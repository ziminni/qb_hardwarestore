# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6A.4 — the restock rule's two branches.

Decision 15: original batch when the FK is set, else the newest active batch.
Task 4a pins the precondition first: a sale must persist which batches it drew from,
or the linked branch is unimplementable.
"""
from decimal import Decimal

from apps.pos.tests import POSTestBase
from apps.pos.services import process_return, process_sale
from apps.pos.models import SalesItemDeduction


class SaleDeductionTests(POSTestBase):
    def test_sale_persists_which_batches_it_drew_from(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH', 'amount_tendered': Decimal('70')}])
        rows = list(SalesItemDeduction.objects.filter(
            sales_item__transaction_id=txn.id).order_by('batch__receipt__receive_date'))
        self.assertEqual(
            [(r.batch.current_qty + r.qty, r.qty) for r in rows],
            [(Decimal('5'), Decimal('5')), (Decimal('5'), Decimal('2'))],
            'oldest batch emptied first: 5 from the 40-cost batch, 2 from the 60-cost batch',
        )


class LinkedReturnTests(POSTestBase):
    def _sell_seven(self):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH', 'amount_tendered': Decimal('70')}])

    def _batches(self):
        from apps.inventory.models import InventoryBatch
        return list(InventoryBatch.objects.filter(variant=self.variant)
                    .order_by('receipt__receive_date'))

    def test_linked_return_restocks_the_original_batches(self):
        original = self._sell_seven()

        ret = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            original_transaction_id=original.id)

        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('5'), Decimal('5')))
        self.assertEqual(ret.source, 'RETURN')
        self.assertEqual(ret.original_transaction_id, original.id)
        self.assertEqual(ret.grand_total, Decimal('-70'))

    def test_unlinked_return_increments_the_newest_active_batch(self):
        self._sell_seven()

        ret = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 4,
                         'unit_price': Decimal('10')}])

        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('0'), Decimal('7')))
        self.assertEqual(ret.source, 'RETURN')
        self.assertIsNone(ret.original_transaction_id)
        self.assertEqual(ret.grand_total, Decimal('-40'))


class ReturnEndpointTests(POSTestBase):
    """POST /transactions/ with source=RETURN reaches process_return, not process_sale."""

    def test_a_return_posts_negative_amounts_over_http(self):
        from rest_framework.test import APIClient
        from django.contrib.auth import get_user_model
        manager = get_user_model().objects.create_superuser(
            username='retmgr', email='r@x.com', password='pass12345')
        client = APIClient()
        login = client.post('/api/v1/auth/login/',
                            {'username': 'retmgr', 'password': 'pass12345'},
                            format='json')
        client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

        response = client.post('/api/v1/transactions/', {
            'customer': self.customer.id,
            'source': 'RETURN',
            'items': [{'variant_id': self.vuom.id, 'qty': '2',
                       'unit_price': '10.00'}],
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['source'], 'RETURN')
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('-20.00'))
