# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests_catalog_writes.py: this checker
# runs from a working directory outside the repo, so `Model.objects` is a false positive
# on valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which
# pyright reads as `follow=`.

"""Stock evidence is append-only — a goods receipt and a stock adjustment.

Both rows are the SAME KIND of record a sale is: by the time the row exists, the stock
has already moved. `apply_stock_adjustment` deducts through FIFO (or reopens the newest
batch) inside the POST that creates the row, and `process/` mints the batches from a
receipt's lines. So editing `qty_adjusted` afterwards re-writes what the ledger says
moved without moving anything, and deleting either row erases the only evidence that it
did move. That is the Phase 2 defect ("editable sales") in a stock costume.

The refusal is **405 for every role, Admin included**, and it is a 405 rather than a 403
or a 400 on purpose: the verb does not exist on these resources, the same way it does not
exist on `/transactions/{id}/` or `/collectible-payments/{id}/`.

**The documented cost.** A mistaken UNPROCESSED receipt cannot be withdrawn either: no
header edit, no delete. It is left unprocessed (it minted no batches, moved no stock and
its `received_qty` is the only trace), and the correction is another business event, not
an edit of a past one. A processed receipt is stock on the shelf and must be corrected by
an adjustment. Both halves of that sentence are pinned below, so the trade-off cannot be
quietly reversed.

Real JWT logins (no ``force_authenticate``): the permission classes read GROUP membership,
so the login path is part of what is under test.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    PurchaseOrder,
    StockAdjustment,
    Supplier,
)
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
ADJUSTMENTS_URL = '/api/v1/adjustments/'
RECEIPTS_URL = '/api/v1/goods-receipts/'


class StockRecordTestBase(InventoryTestBase):
    """One user per role, real logins, and a PLACED purchase order to receive against."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.password = get_random_string(16)
        self.stocker = self._make_user('rec_stocker', 'Stock Manager')
        self.admin = self._make_user('rec_admin', 'Admin')
        self.cashier = self._make_user('rec_cashier', 'Cashier')
        self.supplier = Supplier.objects.create(company_name='Acme Supply')
        # ORDERED, because only an ORDERED/PARTIAL order can receive (Task 4.2).
        self.po = PurchaseOrder.objects.create(
            supplier=self.supplier, created_by=self.stocker,
            status=PurchaseOrder.Status.ORDERED)
        self.item = POItem.objects.create(
            po=self.po, variant=self.variant, ordered_qty=Decimal('20'),
            unit_cost=Decimal('50'))

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

    def _post_receipt(self, qty='10', user=None):
        """Record a receipt carrying one delivered line; UNPROCESSED unless the caller
        processes it."""
        response = self.client.post(
            RECEIPTS_URL,
            {'po': self.po.pk, 'delivery_receipt_no': 'DR-0001',
             'notes': 'as delivered',
             'items': [{'po_item': self.item.pk, 'qty': qty}]},
            format='json', **self._auth(user or self.stocker))
        self.assertEqual(response.status_code, 201, response.data)
        return GoodsReceipt.objects.get(pk=response.data['id'])

    def _processed_receipt(self, qty='10'):
        """A receipt that stocked the rack: 10 units are now in one batch."""
        receipt = self._post_receipt(qty=qty)
        ok = self.client.post(
            f'{RECEIPTS_URL}{receipt.pk}/process/', {}, format='json',
            **self._auth(self.stocker))
        self.assertEqual(ok.status_code, 200, ok.data)
        receipt.refresh_from_db()
        return receipt

    def _post_adjustment(self, qty='-2', adjustment_type='SHRINKAGE'):
        response = self.client.post(
            ADJUSTMENTS_URL,
            {'variant': self.variant.pk, 'adjustment_type': adjustment_type,
             'qty_adjusted': qty, 'remarks': 'damaged bag'},
            format='json', **self._auth(self.stocker))
        self.assertEqual(response.status_code, 201, response.data)
        return StockAdjustment.objects.get(pk=response.data['id'])

    def _batch_qty(self):
        return sum(
            InventoryBatch.objects.filter(variant=self.variant)
            .values_list('current_qty', flat=True))


class AdjustmentIsAppendOnlyTests(StockRecordTestBase):
    """`PATCH`/`PUT`/`DELETE /adjustments/{id}/` are 405, and nothing moves."""

    def setUp(self):
        super().setUp()
        self._processed_receipt('10')     # 10 in stock
        self.adjustment = self._post_adjustment('-2')  # 8 in stock, ledger says -2

    def test_patch_qty_is_refused_and_moves_no_stock(self):
        qty_before = self._batch_qty()
        self.assertEqual(qty_before, Decimal('8'))

        for method in ('patch', 'put'):
            with self.subTest(method=method):
                response = getattr(self.client, method)(
                    f'{ADJUSTMENTS_URL}{self.adjustment.pk}/',
                    {'qty_adjusted': '-1'}, format='json',
                    **self._auth(self.stocker))

                self.assertEqual(
                    response.status_code, 405,
                    f'{method.upper()} /adjustments/ must be refused: '
                    f'{response.data}')

        self.adjustment.refresh_from_db()
        self.assertEqual(self.adjustment.qty_adjusted, Decimal('-2'))
        self.assertEqual(self.adjustment.remarks, 'damaged bag')
        self.assertEqual(self._batch_qty(), qty_before)

    def test_delete_is_refused_and_the_row_survives(self):
        response = self.client.delete(
            f'{ADJUSTMENTS_URL}{self.adjustment.pk}/', **self._auth(self.stocker))

        self.assertEqual(
            response.status_code, 405,
            f'DELETE /adjustments/ must be refused: {response.data}')
        self.assertTrue(
            StockAdjustment.objects.filter(pk=self.adjustment.pk).exists())
        self.assertEqual(self._batch_qty(), Decimal('8'))

    def test_a_cashier_is_refused_too(self):
        # 403 (not the inventory role) is still a refusal; pinned so a later permission
        # change cannot quietly open the verb.
        response = self.client.patch(
            f'{ADJUSTMENTS_URL}{self.adjustment.pk}/',
            {'qty_adjusted': '-1'}, format='json', **self._auth(self.cashier))

        self.assertEqual(response.status_code, 403, response.data)
        self.adjustment.refresh_from_db()
        self.assertEqual(self.adjustment.qty_adjusted, Decimal('-2'))


class GoodsReceiptIsAppendOnlyTests(StockRecordTestBase):
    """`PUT`/`PATCH`/`DELETE /goods-receipts/{id}/` are 405, processed or not."""

    WRITE_BODY = {'delivery_receipt_no': 'DR-FORGED', 'notes': 'edited after the fact'}

    def _assert_all_verbs_refused(self, receipt, user):
        for method in ('patch', 'put'):
            with self.subTest(method=method):
                response = getattr(self.client, method)(
                    f'{RECEIPTS_URL}{receipt.pk}/', self.WRITE_BODY,
                    format='json', **self._auth(user))
                self.assertEqual(
                    response.status_code, 405,
                    f'{method.upper()} /goods-receipts/ must be refused: '
                    f'{response.data}')
        response = self.client.delete(
            f'{RECEIPTS_URL}{receipt.pk}/', **self._auth(user))
        self.assertEqual(
            response.status_code, 405,
            f'DELETE /goods-receipts/ must be refused: {response.data}')

    def test_a_processed_receipt_cannot_be_edited_or_deleted(self):
        receipt = self._processed_receipt('10')
        batches_before = list(
            InventoryBatch.objects.filter(receipt=receipt)
            .values_list('pk', 'current_qty', 'initial_qty'))

        self._assert_all_verbs_refused(receipt, self.stocker)

        receipt.refresh_from_db()
        self.assertEqual(receipt.delivery_receipt_no, 'DR-0001')
        self.assertEqual(receipt.notes, 'as delivered')
        self.assertIsNotNone(receipt.processed_at)
        self.assertEqual(receipt.lines.count(), 1)
        self.assertEqual(
            list(InventoryBatch.objects.filter(receipt=receipt)
                 .values_list('pk', 'current_qty', 'initial_qty')),
            batches_before)

    def test_an_unprocessed_receipt_is_left_unprocessed_rather_than_withdrawn(self):
        """The documented trade-off: a mistake is corrected FORWARD, not by editing.

        No header edit, no delete. The row stays, `processed_at` stays NULL, and nothing
        was stocked — which is what makes the un-withdrawable row harmless.
        """
        receipt = self._post_receipt('10')
        self.item.refresh_from_db()
        received_before = self.item.received_qty
        self.assertEqual(received_before, Decimal('10'))

        self._assert_all_verbs_refused(receipt, self.stocker)

        receipt.refresh_from_db()
        self.assertIsNone(receipt.processed_at)
        self.assertEqual(receipt.delivery_receipt_no, 'DR-0001')
        self.assertEqual(receipt.notes, 'as delivered')
        self.assertEqual(receipt.lines.count(), 1)
        self.assertFalse(InventoryBatch.objects.filter(receipt=receipt).exists())
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, received_before)

    def test_an_admin_is_refused_too(self):
        receipt = self._post_receipt('10')

        self._assert_all_verbs_refused(receipt, self.admin)

        self.assertTrue(GoodsReceipt.objects.filter(pk=receipt.pk).exists())


class StockRecordWritesStillWorkTests(StockRecordTestBase):
    """The 405s must not have eaten the writes that ARE the API.

    `http_method_names` that drops PUT/PATCH/DELETE still has to keep `post`, because the
    collection POST is the adjustment and `process/` is an action POST.
    """

    def test_create_then_read_an_adjustment(self):
        self._processed_receipt('10')

        created = self._post_adjustment('-2')

        self.assertEqual(created.qty_adjusted, Decimal('-2'))
        self.assertEqual(self._batch_qty(), Decimal('8'))
        listing = self.client.get(ADJUSTMENTS_URL, **self._auth(self.stocker))
        self.assertEqual(listing.status_code, 200, listing.data)
        self.assertEqual(listing.data['results'][0]['id'], created.pk)

    def test_create_then_process_a_receipt(self):
        receipt = self._processed_receipt('10')

        self.assertIsNotNone(receipt.processed_at)
        self.assertEqual(self._batch_qty(), Decimal('10'))
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('10'))
        detail = self.client.get(
            f'{RECEIPTS_URL}{receipt.pk}/', **self._auth(self.stocker))
        self.assertEqual(detail.status_code, 200, detail.data)
