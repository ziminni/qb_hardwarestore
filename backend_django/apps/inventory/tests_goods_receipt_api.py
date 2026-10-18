# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6B.2 T1 — POST /goods-receipts/ carries received quantities.

The process/ endpoint builds batches from POItem.received_qty, which defaults to 0
and has no other API write path. Without a writable `items` payload on receipt
creation, an API-recorded receipt always processes into zero batches.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from rest_framework.test import APIClient

from apps.inventory.tests import InventoryTestBase
from apps.inventory.models import POItem, PurchaseOrder, Supplier


class GoodsReceiptItemsApiTests(InventoryTestBase):
    def setUp(self):
        super().setUp()
        User = get_user_model()
        User.objects.create_superuser(
            username='receivermgr', email='r@x.com', password='pass12345')
        self.client = APIClient()
        login = self.client.post('/api/v1/auth/login/', {
            'username': 'receivermgr', 'password': 'pass12345'}, format='json')
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

    def _receive(self, qty, items=None):
        payload = {'po': self.po.id}
        if items is None:
            items = [{'po_item': self.item.id, 'qty': str(qty)}]
        payload['items'] = items
        return self.client.post('/api/v1/goods-receipts/', payload,
                               format='json')

    def test_reprocessing_a_receipt_is_refused(self):
        first = self._receive('4')
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
        self.assertEqual(self._receive('4').status_code, 201)
        response = self._receive('6')

        self.assertEqual(response.status_code, 201, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('10'))

    def test_accumulation_never_exceeds_ordered(self):
        self.assertEqual(self._receive('7').status_code, 201)
        response = self._receive('7')

        self.assertEqual(response.status_code, 400, response.data)
        self.item.refresh_from_db()
        self.assertEqual(self.item.received_qty, Decimal('7'))

    def test_receipt_against_a_completed_po_is_refused(self):
        from apps.inventory.models import PurchaseOrder
        self.assertEqual(self._receive('10').status_code, 201)
        po = PurchaseOrder.objects.get(pk=self.po.pk)
        po.status = PurchaseOrder.Status.COMPLETE
        po.save(update_fields=['status'])

        response = self._receive('1')

        self.assertEqual(response.status_code, 400, response.data)

    def test_receipt_against_a_cancelled_po_is_refused(self):
        from apps.inventory.models import PurchaseOrder
        po = PurchaseOrder.objects.get(pk=self.po.pk)
        po.status = PurchaseOrder.Status.CANCELLED
        po.save(update_fields=['status'])

        response = self._receive('1')

        self.assertEqual(response.status_code, 400, response.data)

    def test_processing_an_empty_receipt_leaves_the_po_draft(self):
        from apps.inventory.models import PurchaseOrder
        receipt = self._receive(None, items=[])
        self.assertEqual(receipt.status_code, 201, receipt.data)

        process = self.client.post(
            f"/api/v1/goods-receipts/{receipt.data['id']}/process/", {},
            format='json')

        self.assertEqual(process.status_code, 200, process.data)
        self.assertEqual(process.data, [])
        self.assertEqual(
            PurchaseOrder.objects.get(pk=self.po.pk).status,
            PurchaseOrder.Status.DRAFT)
