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


class PurchaseOrderEditLockTests(PurchaseOrderTestBase):
    """The DRAFT-only edit gate decides under the PO row lock (B2).

    `update()` used to ask "is this a DRAFT?" with an unlocked `get_object()` and only
    then hand the write to `perform_update`, so a PATCH that replaces the lines could
    pass the check while `place/` or `cancel/` committed in between — the supplier had
    already been told what to deliver, and the order's lines changed underneath it. The
    status is now read AFTER a `SELECT ... FOR UPDATE` on the order row, and that same
    locked row is the one `super().update()` writes, so the verdict cannot go stale
    before its own write commits.

    What these tests prove deterministically: the lock query is issued, and it is issued
    BEFORE the status decision / the UPDATE statement. What only a real two-connection
    run can prove is that Postgres BLOCKS the loser; a single-threaded test shows the
    ordering, not the blocking.
    """

    def _po_locks(self, queries):
        """Captured statements that row-lock the PURCHASE ORDER table itself.

        The table name is matched with its quotes, so the `FOR UPDATE` on
        `inventory_po_item` (receiving takes that one too) is not counted.
        """
        return [
            q['sql'] for q in queries
            if 'FOR UPDATE' in q['sql'].upper() and '"inventory_po"' in q['sql']
        ]

    def test_the_edit_refusal_is_decided_while_the_po_row_is_locked(self):
        from unittest import mock

        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        from apps.inventory.views import PurchaseOrderLocked as real_refusal

        po = self._place_existing()
        seen = {}

        def probe(instance):
            seen['locks'] = self._po_locks(connection.queries)
            return real_refusal(instance)

        with CaptureQueriesContext(connection), mock.patch(
                'apps.inventory.views.PurchaseOrderLocked', probe):
            response = self.client.patch(
                f'{PO_URL}{po.pk}/', {'notes': 'Too late.'}, format='json',
                **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_LOCKED', response.data)
        self.assertIn('locks', seen, 'the PO_LOCKED gate must be reached at all')
        self.assertTrue(
            seen['locks'],
            'the edit gate must read the status after locking the order row')
        po.refresh_from_db()
        self.assertNotEqual(po.notes, 'Too late.')

    def test_a_draft_edit_locks_the_order_row_before_it_writes(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        created = self._create()

        with CaptureQueriesContext(connection) as captured:
            response = self.client.patch(
                f'{PO_URL}{created.data["id"]}/',
                {'notes': 'Call before delivery.'}, format='json',
                **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        sql = [q['sql'].upper() for q in captured.captured_queries]
        lock_at = next(
            (i for i, s in enumerate(sql)
             if 'FOR UPDATE' in s and '"INVENTORY_PO"' in s), None)
        self.assertIsNotNone(lock_at, 'an edit must lock the order row')
        write_at = next(
            (i for i, s in enumerate(sql)
             if s.startswith('UPDATE "INVENTORY_PO"')), None)
        self.assertIsNotNone(write_at, 'the edit must write the order row')
        self.assertLess(
            int(lock_at), int(write_at),
            'the lock must be taken before the write')

    def test_a_patch_after_place_is_refused_and_the_order_is_unchanged(self):
        po = self._place_existing()

        response = self.client.patch(
            f'{PO_URL}{po.pk}/', {'notes': 'Too late.'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'PO_LOCKED', response.data)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)
        self.assertEqual(po.items.get().ordered_qty, Decimal('10'))


class NoOpPatchWritesNoAuditRowTests(PurchaseOrderTestBase):
    """A PATCH that changes nothing writes no audit row (M3).

    `{"status": "ORDERED"}` on a DRAFT order is a body with only a read-only field, so
    DRF saves nothing — but the view still wrote an `UPDATE` row saying the order was
    edited. The trail has to mean "something changed", otherwise every no-op PATCH a
    screen fires on blur is a fake edit.
    """

    def _update_rows(self):
        return AuditLog.objects.filter(
            action_type=AuditLog.ActionType.UPDATE).count()

    def test_a_read_only_field_patch_writes_no_audit_row(self):
        created = self._create()
        before = self._update_rows()

        response = self.client.patch(
            f'{PO_URL}{created.data["id"]}/', {'status': 'ORDERED'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], 'DRAFT')
        self.assertEqual(
            PurchaseOrder.objects.get(pk=created.data['id']).status,
            PurchaseOrder.Status.DRAFT)
        self.assertEqual(
            self._update_rows(), before,
            'a PATCH that changed nothing must not claim an edit in the trail')

    def test_a_real_edit_still_writes_exactly_one_audit_row(self):
        created = self._create()
        before = self._update_rows()

        response = self.client.patch(
            f'{PO_URL}{created.data["id"]}/',
            {'notes': 'Call before delivery.'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self._update_rows(), before + 1)


class ReceiptProcessRechecksTheOrderTests(PurchaseOrderTestBase):
    """`process/` re-checks the PO status under the PO row lock (B1).

    A receipt recorded while the order was ORDERED, an order cancelled afterwards, and
    then a `process/` call: before the fix `process_goods_receipt` locked the PO row and
    batched anyway — the lock protected the status WRITE, never the DECISION — so
    batches were minted against a CANCELLED order, leaving stock that only a document
    the books call cancelled can explain.
    """

    def test_processing_a_receipt_of_a_since_cancelled_order_is_refused(self):
        from .models import GoodsReceipt

        po = self._place_existing()
        item = po.items.get()
        receipt = self._post_receipt(po.pk, item.pk, '5')
        self.assertEqual(receipt.status_code, 201, receipt.data)

        # The cancel winning the race the row lock now closes: it commits after the
        # receipt's own ORDERED gate was passed, so the receipt exists on a CANCELLED
        # order. Written through the ORM because the API cancel refuses while a receipt
        # exists (the next test) — this is the interleaving, not a reachable sequence.
        PurchaseOrder.objects.filter(pk=po.pk).update(
            status=PurchaseOrder.Status.CANCELLED)

        response = self._process(receipt.data['id'])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data.get('code'), 'PO_NOT_RECEIVABLE', response.data)
        self.assertFalse(
            InventoryBatch.objects.filter(variant=self.variant).exists(),
            'no batch may be minted against a cancelled order')
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal('5'),
                         'the recorded delivery is unchanged, it is just not stocked')
        self.assertIsNone(
            GoodsReceipt.objects.get(pk=receipt.data['id']).processed_at,
            'a refused process/ leaves the receipt unprocessed')

    def test_cancel_is_refused_while_an_unprocessed_receipt_exists(self):
        po = self._place_existing()
        receipt = self._post_receipt(po.pk, po.items.get().pk, '5')
        self.assertEqual(receipt.status_code, 201, receipt.data)

        response = self._action(po.pk, 'cancel')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data.get('code'), 'PO_HAS_RECEIPTS', response.data)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)

    def test_create_takes_the_po_row_lock_before_recording_the_receipt(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        po = self._place_existing()

        with CaptureQueriesContext(connection) as captured:
            response = self._post_receipt(po.pk, po.items.get().pk, '5')

        self.assertEqual(response.status_code, 201, response.data)
        sql = [q['sql'].upper() for q in captured.captured_queries]
        lock_at = next(
            (i for i, s in enumerate(sql)
             if 'FOR UPDATE' in s and '"INVENTORY_PO"' in s), None)
        self.assertIsNotNone(
            lock_at, 'recording a receipt must lock the order row first')
        insert_at = next(
            (i for i, s in enumerate(sql)
             if s.startswith('INSERT INTO "INVENTORY_GOODS_RECEIPT"')), None)
        self.assertIsNotNone(insert_at, 'the receipt row must be written')
        self.assertLess(
            int(lock_at), int(insert_at),
            'the order must be locked before the receipt row exists, so a cancel '
            'either sees the receipt or blocks')
