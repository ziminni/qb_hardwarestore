# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests.py: this checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which pyright
# reads as `follow=`.

"""Phase 4 Task 2 — a purchase order is created with its lines, then placed, then received.

There is no `POItem` endpoint, so the lines travel as a nested write on the PO body. What
this file pins, in the order a Stock Manager hits it:

* **Create = DRAFT + lines, atomically.** `created_by` is the CALLER, never the body
  (the same rule the checkout's `cashier` and an adjustment's `user` already follow). An
  inactive supplier, no lines, a qty of 0, a negative cost, an inactive variant or the
  same variant twice are all **400** with a stable code and **no rows**.
* **`status` is action-only.** It is read-only on the serializer, so a `PATCH` cannot
  walk a DRAFT to ORDERED around the audit row, and a non-DRAFT PO refuses edits
  (`PO_LOCKED`) — otherwise lines could be changed after the supplier was told what to
  deliver.
* **Receiving needs an ORDERED purchase order.** A DRAFT one is `PO_NOT_ORDERED`.
* **Cancel only while nothing has arrived** (`PO_HAS_RECEIPTS` otherwise).

The last test is the whole flow in one place: create → place → receive 5 of 10 (PARTIAL)
→ receive 5 (COMPLETE) → 10 units in stock at the PO's cost.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .models import (
    InventoryBatch,
    POItem,
    ProductVariant,
    PurchaseOrder,
    Supplier,
)
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
PO_URL = '/api/v1/purchase-orders/'
RECEIPTS_URL = '/api/v1/goods-receipts/'


class PurchaseOrderTestBase(InventoryTestBase):
    """One Stock Manager, one Cashier, a supplier and a second variant."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.password = get_random_string(16)
        self.stocker = self._make_user('po_stocker', 'Stock Manager')
        self.cashier = self._make_user('po_cashier', 'Cashier')
        self.supplier = Supplier.objects.create(company_name='Cebu Building Supply')
        self.other_supplier = Supplier.objects.create(company_name='Visayas Hardware')
        # A second variant, so "the same variant twice" has a different variant to
        # contrast against.
        self.variant_b = ProductVariant.objects.create(
            product=self.product, variant_name='50kg', base_uom=self.uom,
            min_stock_threshold=Decimal('5'))

    # -- fixture helpers ---------------------------------------------------
    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username, email=f'{username}@example.com',
            password=self.password, full_name=username)
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self, user):
        login = APIClient().post(
            LOGIN_URL, {'username': user.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f'Bearer {login.data["access"]}'}

    def _line(self, variant=None, qty='10', cost='50.00'):
        return {
            'variant': (variant or self.variant).pk,
            'ordered_qty': qty,
            'unit_cost': cost,
        }

    def _body(self, **overrides):
        body = {
            'supplier': self.supplier.pk,
            'expected_delivery': '2026-11-30',
            'notes': 'Deliver to the rear gate.',
            'items': [self._line()],
        }
        body.update(overrides)
        return body

    def _create(self, body=None, user=None):
        return self.client.post(
            PO_URL, body if body is not None else self._body(),
            format='json', **self._auth(user or self.stocker))

    def _action(self, po_id, name, user=None):
        return self.client.post(
            f'{PO_URL}{po_id}/{name}/', {}, format='json',
            **self._auth(user or self.stocker))

    def _place(self, po_id, user=None):
        return self._action(po_id, 'place', user=user)

    def _post_receipt(self, po_id, item_id, qty):
        """POST one goods receipt line. Named for the API call, not the model, so it
        does not shadow `InventoryTestBase._receive` (the ORM fixture helper)."""
        return self.client.post(
            RECEIPTS_URL,
            {'po': po_id, 'items': [{'po_item': item_id, 'qty': str(qty)}]},
            format='json', **self._auth(self.stocker))

    def _process(self, receipt_id):
        return self.client.post(
            f'{RECEIPTS_URL}{receipt_id}/process/', {}, format='json',
            **self._auth(self.stocker))

    def _place_existing(self):
        """An ORDERED PO with one 10-unit line, created through the API."""
        created = self._create()
        self.assertEqual(created.status_code, 201, created.data)
        placed = self._place(created.data['id'])
        self.assertEqual(placed.status_code, 200, placed.data)
        return PurchaseOrder.objects.get(pk=created.data['id'])


class PurchaseOrderCreateTests(PurchaseOrderTestBase):
    def test_create_saves_the_lines_and_starts_draft(self):
        response = self._create()

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'DRAFT')
        self.assertEqual(len(response.data['items']), 1, response.data)
        self.assertEqual(response.data['items'][0]['variant'], self.variant.pk)
        self.assertEqual(response.data['items'][0]['ordered_qty'], '10.00')
        self.assertEqual(response.data['items'][0]['received_qty'], '0.00')

        po = PurchaseOrder.objects.get(pk=response.data['id'])
        self.assertEqual(po.items.count(), 1)
        self.assertEqual(po.status, PurchaseOrder.Status.DRAFT)

    def test_created_by_is_the_caller_even_when_the_body_says_otherwise(self):
        body = self._body(created_by=self.cashier.pk)

        response = self._create(body)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['created_by'], self.stocker.pk)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=response.data['id']).created_by,
            self.stocker)

    def test_an_inactive_supplier_is_refused(self):
        self.supplier.is_active = False
        self.supplier.save(update_fields=['is_active'])

        response = self._create()

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'SUPPLIER_INACTIVE', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_an_empty_order_is_refused(self):
        response = self._create(self._body(items=[]))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_a_zero_ordered_qty_is_refused(self):
        response = self._create(self._body(items=[self._line(qty='0')]))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)
        self.assertEqual(POItem.objects.count(), 0)

    def test_a_negative_unit_cost_is_refused(self):
        response = self._create(self._body(items=[self._line(cost='-1')]))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_the_same_variant_twice_on_one_order_is_refused(self):
        response = self._create(
            self._body(items=[self._line(), self._line(qty='5')]))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_an_inactive_variant_is_refused(self):
        self.variant.is_active = False
        self.variant.save(update_fields=['is_active'])

        response = self._create()

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO', response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_a_cashier_cannot_create_a_purchase_order(self):
        response = self._create(user=self.cashier)

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_two_lines_on_two_variants_are_both_saved(self):
        response = self._create(self._body(items=[
            self._line(),
            self._line(variant=self.variant_b, qty='4', cost='60'),
        ]))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(len(response.data['items']), 2, response.data)
        self.assertEqual(POItem.objects.count(), 2)


class PurchaseOrderStatusTests(PurchaseOrderTestBase):
    def test_status_is_read_only_on_the_serializer(self):
        po = self._place_existing()

        response = self.client.patch(
            f'{PO_URL}{po.pk}/', {'status': 'COMPLETE'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_LOCKED', response.data)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)

    def test_place_moves_a_draft_to_ordered_and_is_audited(self):
        created = self._create()
        self.assertEqual(created.data['status'], 'DRAFT')

        response = self._place(created.data['id'])

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'ORDERED')
        self.assertEqual(
            PurchaseOrder.objects.get(pk=created.data['id']).status,
            PurchaseOrder.Status.ORDERED)
        rows = AuditLog.objects.filter(action_type='UPDATE')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))
        self.assertIn(f'#{created.data["id"]}', rows.get().description)
        self.assertIn('placed', rows.get().description)

    def test_placing_a_non_draft_order_is_refused(self):
        po = self._place_existing()

        response = self._place(po.pk)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO_STATE', response.data)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)

    def test_cancelling_an_ordered_unreceived_order_works_and_is_audited(self):
        po = self._place_existing()

        response = self._action(po.pk, 'cancel')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'CANCELLED')
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.CANCELLED)
        rows = AuditLog.objects.filter(action_type='UPDATE')
        self.assertEqual(rows.count(), 2, list(rows.values_list('description', flat=True)))

    def test_cancelling_a_draft_order_works(self):
        created = self._create()

        response = self._action(created.data['id'], 'cancel')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'CANCELLED')

    def test_cancelling_an_order_with_receipts_is_refused(self):
        po = self._place_existing()
        receipt = self._post_receipt(po.pk, po.items.get().pk, '4')
        self.assertEqual(receipt.status_code, 201, receipt.data)
        self.assertEqual(self._process(receipt.data['id']).status_code, 200)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.PARTIAL)

        response = self._action(po.pk, 'cancel')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_HAS_RECEIPTS', response.data)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.PARTIAL)

    def test_cancelling_a_cancelled_order_is_refused(self):
        created = self._create()
        self.assertEqual(self._action(created.data['id'], 'cancel').status_code, 200)

        response = self._action(created.data['id'], 'cancel')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_PO_STATE', response.data)

    def test_a_cashier_cannot_place_or_cancel(self):
        created = self._create()

        placed = self._place(created.data['id'], user=self.cashier)
        cancelled = self._action(created.data['id'], 'cancel', user=self.cashier)

        self.assertEqual(placed.status_code, 403, placed.data)
        self.assertEqual(cancelled.status_code, 403, cancelled.data)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=created.data['id']).status,
            PurchaseOrder.Status.DRAFT)


class PurchaseOrderEditTests(PurchaseOrderTestBase):
    def test_a_draft_can_be_edited(self):
        created = self._create()

        response = self.client.patch(
            f'{PO_URL}{created.data["id"]}/',
            {'notes': 'Call before delivery.'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['notes'], 'Call before delivery.')

    def test_a_draft_line_can_be_replaced_wholesale(self):
        created = self._create()

        response = self.client.patch(
            f'{PO_URL}{created.data["id"]}/',
            {'items': [self._line(variant=self.variant_b, qty='7', cost='61')]},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        po = PurchaseOrder.objects.get(pk=created.data['id'])
        self.assertEqual(po.items.count(), 1, 'the old line must be replaced, not kept')
        line = po.items.get()
        self.assertEqual(line.variant, self.variant_b)
        self.assertEqual(line.ordered_qty, Decimal('7'))

    def test_an_ordered_order_is_locked_against_edits(self):
        po = self._place_existing()

        response = self.client.patch(
            f'{PO_URL}{po.pk}/', {'notes': 'Too late.'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_LOCKED', response.data)
        po.refresh_from_db()
        self.assertNotEqual(po.notes, 'Too late.')

    def test_an_ordered_order_cannot_have_its_lines_replaced(self):
        po = self._place_existing()

        response = self.client.patch(
            f'{PO_URL}{po.pk}/',
            {'items': [self._line(qty='99')]}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_LOCKED', response.data)
        self.assertEqual(po.items.get().ordered_qty, Decimal('10'))


class PurchaseOrderReceivingTests(PurchaseOrderTestBase):
    def test_a_draft_order_cannot_be_received(self):
        created = self._create()
        po = PurchaseOrder.objects.get(pk=created.data['id'])
        item = po.items.get()

        response = self._post_receipt(po.pk, item.pk, '4')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_NOT_ORDERED', response.data)
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal('0'))

    def test_a_completed_order_refusal_carries_a_stable_code(self):
        po = self._place_existing()
        receipt = self._post_receipt(po.pk, po.items.get().pk, '10')
        self.assertEqual(self._process(receipt.data['id']).status_code, 200)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.COMPLETE)

        response = self._post_receipt(po.pk, po.items.get().pk, '1')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_NOT_RECEIVABLE', response.data)

    def test_a_cancelled_order_refusal_carries_a_stable_code(self):
        created = self._create()
        self.assertEqual(self._action(created.data['id'], 'cancel').status_code, 200)
        po = PurchaseOrder.objects.get(pk=created.data['id'])

        response = self._post_receipt(po.pk, po.items.get().pk, '1')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_NOT_RECEIVABLE', response.data)


class PurchaseOrderFullFlowTests(PurchaseOrderTestBase):
    """Create → place → receive part → receive the rest → stock, at the PO's cost."""

    def test_the_whole_purchase_flow(self):
        created = self._create(self._body(items=[self._line(qty='10', cost='50')]))
        self.assertEqual(created.status_code, 201, created.data)
        po_id = created.data['id']
        item_id = created.data['items'][0]['id']

        self.assertEqual(self._place(po_id).status_code, 200)

        first = self._post_receipt(po_id, item_id, '5')
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(self._process(first.data['id']).status_code, 200)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=po_id).status,
            PurchaseOrder.Status.PARTIAL)

        second = self._post_receipt(po_id, item_id, '5')
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(self._process(second.data['id']).status_code, 200)
        self.assertEqual(
            PurchaseOrder.objects.get(pk=po_id).status,
            PurchaseOrder.Status.COMPLETE)

        batches = InventoryBatch.objects.filter(variant=self.variant)
        self.assertEqual(batches.count(), 2)
        self.assertEqual(
            sum(b.current_qty for b in batches), Decimal('10'))
        self.assertEqual(
            {b.unit_cost_landed for b in batches}, {Decimal('50')})
