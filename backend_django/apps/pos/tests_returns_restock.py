# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6A.4 — the restock rule's two branches.

Decision 15: original batch when the FK is set, else the newest active batch.
Task 4a pins the precondition first: a sale must persist which batches it drew from,
or the linked branch is unimplementable.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group

from apps.pos.tests import POSTestBase
from apps.pos.exceptions import ReturnError
from apps.pos.services import process_return, process_sale
from apps.pos.models import SalesItemDeduction, SalesTransaction, Shift

User = get_user_model()

# Phase 3 task 2 (decision 05): every return now needs a reason, and an UNLINKED return
# is a manager's alone. The literal below is what a clerk would type; it is test data.
RETURN_REASON = 'customer brought the bags back'


def make_manager_with_shift(username='ret_unlinked_mgr'):
    """A Store Manager who may post an UNLINKED return, with an open shift.

    Both halves are new in Phase 3: decision 05 bounds the till to linked returns, and
    the shift gate now applies to refunds as it does to sales (a refund is money out of
    a drawer, and a drawer is a shift).
    """
    manager = User.objects.create_user(
        username=username, email=f'{username}@x.com', password='pass12345')
    manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
    Shift.objects.create(cashier=manager, opening_float=Decimal('5000'))
    return manager


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
            original_transaction_id=original.id,
            reason=RETURN_REASON)

        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('5'), Decimal('5')))
        self.assertEqual(ret.source, 'RETURN')
        self.assertEqual(ret.original_transaction_id, original.id)
        self.assertEqual(ret.grand_total, Decimal('-70'))

    def test_unlinked_return_increments_the_newest_active_batch(self):
        self._sell_seven()
        # Phase 3 task 2: only a Store Manager / Admin may post an unlinked return.
        manager = make_manager_with_shift()

        ret = process_return(
            customer_id=self.customer.id,
            cashier=manager,
            items_data=[{'variant_id': self.vuom.id, 'qty': 4,
                         'unit_price': Decimal('10')}],
            reason=RETURN_REASON)

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
        # Phase 3 task 2 (decision 05): a return needs an open shift, and this one is
        # UNLINKED, which only a manager may post - hence the superuser above.
        Shift.objects.create(cashier=manager, opening_float=Decimal('5000'))
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
            'reason': RETURN_REASON,
        }, format='json')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['source'], 'RETURN')
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('-20.00'))


class ReturnGuardTests(POSTestBase):
    """Validity holes the first pass left: repeats, signs, methods, states."""

    def _sell_seven(self):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH', 'amount_tendered': Decimal('70')}])

    def _return(self, qty, original_id, unit_price=Decimal('10'),
                method='CASH'):
        """Post a linked return. `unit_price` is still accepted by the service signature
        (older callers pass it) but is IGNORED since decision 01 - see
        `test_a_client_return_price_is_ignored`.
        """
        return process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': qty,
                         'unit_price': unit_price}],
            original_transaction_id=original_id,
            payment_method=method,
            reason=RETURN_REASON)

    def _batches(self):
        from apps.inventory.models import InventoryBatch
        return list(InventoryBatch.objects.filter(variant=self.variant)
                    .order_by('receipt__receive_date'))

    def test_a_second_linked_return_is_refused(self):
        original = self._sell_seven()
        self._return(Decimal('7'), original.id)

        with self.assertRaises(ReturnError):
            self._return(Decimal('7'), original.id)
        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('5'), Decimal('5')))

    def test_partial_then_remainder_is_allowed_but_a_third_is_not(self):
        original = self._sell_seven()
        self._return(Decimal('3'), original.id)
        self._return(Decimal('4'), original.id)

        with self.assertRaises(ReturnError):
            self._return(Decimal('1'), original.id)
        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('5'), Decimal('5')))

    def test_two_lines_share_one_accounting_not_two(self):
        original = self._sell_seven()

        process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 4,
                         'unit_price': Decimal('10')},
                        {'variant_id': self.vuom.id, 'qty': 3,
                         'unit_price': Decimal('10')}],
            original_transaction_id=original.id,
            reason=RETURN_REASON)

        oldest, newest = self._batches()
        self.assertEqual((oldest.current_qty, newest.current_qty),
                         (Decimal('5'), Decimal('5')),
                         'row caps are per call, not per line: oldest takes 5, not 7')

    def test_a_client_return_price_is_ignored(self):
        # REWRITTEN by phase 1 task 1 (decision 01). This used to assert that a NEGATIVE
        # client `unit_price` raised ReturnError - a guard that only worked because the
        # client's price was believed in the first place. The server now prices the
        # refund from the original sale line, so there is nothing left to validate: a
        # forged price (negative, zero or inflated) is simply not input.
        original = self._sell_seven()

        ret = self._return(Decimal('2'), original.id,
                           unit_price=Decimal('-10'))

        self.assertEqual(ret.grand_total, Decimal('-20'),
                         'refund is 2 x the ORIGINAL line price, not the forged sign')
        self.assertEqual(ret.items.get().unit_price, Decimal('10'))

    def test_unknown_payment_method_is_refused(self):
        original = self._sell_seven()

        with self.assertRaises(ReturnError):
            self._return(Decimal('2'), original.id, method='BARTER')

    def test_return_against_a_voided_original_is_refused(self):
        original = self._sell_seven()
        original.status = 'VOID'
        original.save(update_fields=['status'])

        with self.assertRaises(ReturnError):
            self._return(Decimal('2'), original.id)

    def test_restock_takes_row_locks_like_fifo(self):
        from django.test.utils import CaptureQueriesContext
        from django.db import connection
        original = self._sell_seven()

        with CaptureQueriesContext(connection) as ctx:
            self._return(Decimal('2'), original.id)

        self.assertTrue(
            any('FOR UPDATE' in q['sql'] for q in ctx.captured_queries),
            'restock reads its rows locked, matching allocate_fifo discipline')

    def test_endpoint_maps_return_errors_to_400(self):
        # UPDATED by phase 1 task 1 (decision 01): this used to provoke the 400 with a
        # NEGATIVE client `unit_price`, and a client price is now ignored entirely, so
        # that request would legitimately return 201. The refusal under test - a return
        # against its own original must map to a stable code, not a 500 - is provoked
        # with a real violation instead: returning more than the original sale drew.
        from rest_framework.test import APIClient
        from django.contrib.auth import get_user_model
        retmgr2 = get_user_model().objects.create_superuser(
            username='retmgr2', email='r2@x.com', password='pass12345')
        Shift.objects.create(cashier=retmgr2, opening_float=Decimal('5000'))
        client = APIClient()
        login = client.post('/api/v1/auth/login/',
                            {'username': 'retmgr2', 'password': 'pass12345'},
                            format='json')
        client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        original = self._sell_seven()   # 7 on the shelf, 7 sold

        response = client.post('/api/v1/transactions/', {
            'customer': self.customer.id,
            'source': 'RETURN',
            'original_transaction': original.id,
            'items': [{'variant_id': self.vuom.id, 'qty': '10'}],
            'reason': RETURN_REASON,
        }, format='json')

        self.assertEqual(response.status_code, 400, response.data)
        # UPDATED by phase 3 task 2: the over-draw refusal has its own stable code now
        # (decision 05), which is what lets the till say how many are left. A NARROWER
        # assertion than the old catch-all `INVALID_RETURN`, not a weaker one.
        self.assertEqual(response.data['code'], 'RETURN_QTY_EXCEEDED')
        self.assertFalse(
            SalesTransaction.objects.filter(
                source=SalesTransaction.Source.RETURN).exists(),
            'a refused return must not be recorded')
