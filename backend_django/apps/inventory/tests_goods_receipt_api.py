# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6B.2 T1 — POST /goods-receipts/ carries received quantities.

The process/ endpoint builds batches from POItem.received_qty, which defaults to 0
and has no other API write path. Without a writable `items` payload on receipt
creation, an API-recorded receipt always processes into zero batches.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.inventory.models import POItem, PurchaseOrder, Supplier
from apps.inventory.tests import InventoryTestBase


class GoodsReceiptItemsApiTests(InventoryTestBase):
    def setUp(self):
        super().setUp()
        User = get_user_model()
        receiver_password = get_random_string(16)
        User.objects.create_superuser(
            username='receivermgr', email='r@x.com',
            password=receiver_password)
        self.client = APIClient()
        login = self.client.post('/api/v1/auth/login/', {
            'username': 'receivermgr',
            'password': receiver_password}, format='json')
        token = login.data.get('access') or login.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        supplier = Supplier.objects.create(company_name='Acme Supply')
        self.po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.user)
        self.item = POItem.objects.create(
            po=self.po, variant=self.variant, ordered_qty=Decimal('10'),
            unit_cost=Decimal('50'))

    def _post(self, payload):
        return self.client.post('/api/v1/goods-receipts/', payload,
                                format='json')

    def test_items_set_received_quantities(self):
        response = self._post({
            'po': self.po.id,
            'items': [{'po_item': self.item.id, 'qty': '4'}],
        })

        self.assertEqual(response.status_code, 201, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('4'))

    def test_qty_above_ordered_is_refused(self):
        response = self._post({
            'po': self.po.id,
            'items': [{'po_item': self.item.id, 'qty': '11'}],
        })

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('would exceed', response.data['detail'])
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('0'))

    def test_item_from_another_po_is_refused(self):
        other_supplier = Supplier.objects.create(company_name='Other')
        other_po = PurchaseOrder.objects.create(
            supplier=other_supplier, created_by=self.user)
        other_item = POItem.objects.create(
            po=other_po, variant=self.variant, ordered_qty=Decimal('10'),
            unit_cost=Decimal('50'))

        response = self._post({
            'po': self.po.id,
            'items': [{'po_item': other_item.id, 'qty': '4'}],
        })

        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn('is not on this PO', response.data['detail'])

    def test_no_items_still_records_the_receipt(self):
        response = self._post({'po': self.po.id})

        self.assertEqual(response.status_code, 201, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('0'))



class ReceiptProcessGuardTests(GoodsReceiptItemsApiTests):
    """Fix pass: re-processing, accumulation, closed POs, empty process.

    Inherits the authenticated client plus a PO with one 10-unit item.
    """

    def _post_receipt(self, qty, items=None):
        payload = {'po': self.po.id}
        if items is None:
            items = [{'po_item': self.item.id, 'qty': str(qty)}]
        payload['items'] = items
        return self.client.post('/api/v1/goods-receipts/', payload,
                               format='json')

    def test_reprocessing_a_receipt_is_refused(self):
        first = self._post_receipt('4')
        self.assertEqual(first.status_code, 201, first.data)
        process = self.client.post(
            f"/api/v1/goods-receipts/{first.data['id']}/process/", {},
            format='json')
        self.assertEqual(process.status_code, 200, process.data)
        self.assertEqual(len(process.data), 1)

        again = self.client.post(
            f"/api/v1/goods-receipts/{first.data['id']}/process/", {},
            format='json')

        self.assertEqual(again.status_code, 400, again.data)
        from apps.inventory.models import InventoryBatch
        self.assertEqual(
            InventoryBatch.objects.filter(variant=self.variant).count(), 1)

    def test_a_second_receipt_accumulates_quantities(self):
        self.assertEqual(self._post_receipt('4').status_code, 201)
        response = self._post_receipt('6')

        self.assertEqual(response.status_code, 201, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('10'))

    def test_accumulation_never_exceeds_ordered(self):
        self.assertEqual(self._post_receipt('7').status_code, 201)
        response = self._post_receipt('7')

        self.assertEqual(response.status_code, 400, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('7'))

    def test_receipt_against_a_completed_po_is_refused(self):
        from apps.inventory.models import PurchaseOrder
        self.assertEqual(self._post_receipt('10').status_code, 201)
        po = PurchaseOrder.objects.get(pk=self.po.pk)
        po.status = PurchaseOrder.Status.COMPLETE
        po.save(update_fields=['status'])

        response = self._post_receipt('1')

        self.assertEqual(response.status_code, 400, response.data)

    def test_receipt_against_a_cancelled_po_is_refused(self):
        from apps.inventory.models import PurchaseOrder
        po = PurchaseOrder.objects.get(pk=self.po.pk)
        po.status = PurchaseOrder.Status.CANCELLED
        po.save(update_fields=['status'])

        response = self._post_receipt('1')

        self.assertEqual(response.status_code, 400, response.data)

    def test_processing_an_empty_receipt_leaves_the_po_draft(self):
        from apps.inventory.models import PurchaseOrder
        receipt = self._post_receipt(None, items=[])
        self.assertEqual(receipt.status_code, 201, receipt.data)

        process = self.client.post(
            f"/api/v1/goods-receipts/{receipt.data['id']}/process/", {},
            format='json')

        self.assertEqual(process.status_code, 200, process.data)
        self.assertEqual(process.data, [])
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.po.pk).status,
            PurchaseOrder.Status.DRAFT)


class SplitReceiptLineTests(GoodsReceiptItemsApiTests):
    """Phase 1 task 4 — a receipt batches ONLY the quantities it delivered.

    The bug this pins: `create` accumulates POItem.received_qty across receipts and
    `process_goods_receipt` used to mint a batch from the FULL cumulative figure every
    time. Receipt of 5 then 2 therefore stocked 5 + 7 = 12 units for 7 delivered.
    """

    def _post_receipt(self, qty):
        return self._post({
            'po': self.po.id,
            'items': [{'po_item': self.item.id, 'qty': str(qty)}],
        })

    def _process(self, receipt_id):
        return self.client.post(
            f'/api/v1/goods-receipts/{receipt_id}/process/', {}, format='json')

    def test_split_receipts_batch_only_what_each_delivered(self):
        from apps.inventory.models import InventoryBatch

        first = self._post_receipt('5')
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(self._process(first.data['id']).status_code, 200)

        second = self._post_receipt('2')
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(self._process(second.data['id']).status_code, 200)

        total = sum(
            InventoryBatch.objects
            .filter(variant=self.variant)
            .values_list('initial_qty', flat=True),
            Decimal('0'),
        )
        self.assertEqual(total, Decimal('7'))
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('7'))

    def test_create_records_one_line_per_delivered_entry(self):
        response = self._post_receipt('5')

        self.assertEqual(response.status_code, 201, response.data)
        lines = response.data.get('lines') or []
        self.assertEqual(len(lines), 1, response.data)
        self.assertEqual(lines[0]['qty'], '5.00')
        self.assertEqual(lines[0]['po_item'], self.item.id)
        self.assertEqual(lines[0]['variant'], self.variant.id)
        self.assertEqual(lines[0]['variant_name'], self.variant.variant_name)

    def test_a_second_receipt_records_only_its_own_line(self):
        self.assertEqual(self._post_receipt('5').status_code, 201)
        second = self._post_receipt('2')

        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(len(second.data.get('lines') or []), 1, second.data)
        self.assertEqual(second.data['lines'][0]['qty'], '2.00')

    def test_processing_marks_the_receipt_and_refuses_a_second_process(self):
        first = self._post_receipt('4')
        processed = self._process(first.data['id'])

        self.assertEqual(processed.status_code, 200, processed.data)
        detail = self.client.get(
            f"/api/v1/goods-receipts/{first.data['id']}/")
        self.assertIsNotNone(detail.data.get('processed_at'), detail.data)

        again = self._process(first.data['id'])
        self.assertEqual(again.status_code, 400, again.data)
        self.assertEqual(again.data.get('code'), 'RECEIPT_ALREADY_PROCESSED')
        self.assertEqual(
            again.data.get('detail'),
            f"Goods receipt {first.data['id']} was already processed.")

    def test_zero_qty_entry_creates_no_line(self):
        response = self._post({
            'po': self.po.id,
            'items': [{'po_item': self.item.id, 'qty': '0'}],
        })

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data.get('lines') or [], [])
