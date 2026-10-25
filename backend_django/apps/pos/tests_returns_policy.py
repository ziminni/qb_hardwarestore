# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/pos/tests_scoping.py: this checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into Django's test client, which
# forwards unknown kwargs into the WSGI environ.

"""Phase 3 Task 2 — the cashier returns policy (decision 05).

Every refusal below is a stable `{code, detail}` 4xx and writes nothing: no RETURN row,
no receipt, no stock movement, no audit row. The money half is DEBT FIRST — a return
against a credit sale reduces what the customer still owes before a single peso leaves
the drawer, so the Z-reading's `cash_refunds` is only the cash EXCESS.

Real JWT logins (the permission classes read GROUP membership, so the login path is part
of what is under test), an open shift per user, and a REGULAR customer who is allowed to
owe — the walk-in placeholder may not (decision 14).
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connection
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.inventory.models import (
    Brand, Category, GoodsReceipt, POItem, Product, ProductVariant, PurchaseOrder,
    Supplier, UnitOfMeasure, VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.users.models import AuditLog

from .models import (
    Customer, OfficialReceipt, Payment, SalesItem, SalesItemDeduction,
    SalesTransaction, Shift,
)
from .services import process_sale

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
TRANSACTIONS_URL = '/api/v1/transactions/'
SHIFTS_URL = '/api/v1/shifts/'
# Random per run, like `tests_scoping.py`: a literal would trip the hardcoded-password
# rule, and the value authenticates nothing outside the throwaway test database.


class ReturnsPolicyBase(TestCase):
    """500 base units on the shelf, price 10.00, one user per role, shifts open."""

    def setUp(self):
        self.client = APIClient()
        self.password = get_random_string(16)
        self.cashier = self._make_user('ret_cashier', 'Cashier')
        self.other_cashier = self._make_user('ret_cashier_b', 'Cashier')
        self.manager = self._make_user('ret_manager', 'Store Manager')
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal('5000'))
        self.other_shift = Shift.objects.create(
            cashier=self.other_cashier, opening_float=Decimal('5000'))
        self.manager_shift = Shift.objects.create(
            cashier=self.manager, opening_float=Decimal('5000'))

        # A customer who MAY owe (decision 14 refuses utang on the walk-in placeholder).
        self.customer = Customer.objects.create(
            name='Dela Cruz Construction',
            customer_type=Customer.Type.CONTRACTOR)

        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        self.vuom = VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.cashier,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('500'),
            unit_cost=Decimal('5'), received_qty=Decimal('500'))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.cashier)
        process_goods_receipt(receipt=receipt, user=self.cashier)

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

    def _sell(self, qty=10, paid=None, cashier=None, customer=None):
        qty = Decimal(str(qty))
        if paid is None:
            paid = qty * Decimal('10')
        return process_sale(
            customer_id=(customer or self.customer).id,
            cashier=cashier or self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': qty}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal(str(paid))}],
        )

    def _return_url(self):
        return TRANSACTIONS_URL

    def _post_return(self, *, original=None, qty=1, reason='damaged packaging',
                     user=None, method='CASH', payload_extra=None):
        body = {
            'customer': self.customer.id,
            'source': 'RETURN',
            'items': [{'variant_id': self.vuom.id, 'qty': str(qty)}],
            'payment_method': method,
        }
        if original is not None:
            body['original_transaction'] = original.id
        if reason is not None:
            body['reason'] = reason
        body.update(payload_extra or {})
        return self.client.post(
            self._return_url(), body, format='json',
            **self._auth(user or self.cashier))

    def _return_count(self):
        return SalesTransaction.objects.filter(
            source=SalesTransaction.Source.RETURN).count()

    def _stock(self):
        from apps.inventory.models import InventoryBatch
        return sum(InventoryBatch.objects.filter(variant=self.variant)
                   .values_list('current_qty', flat=True), Decimal('0'))

    def _refused(self, response, code, http_status=400):
        """Every refusal: the stable code, the status, and NOTHING written."""
        returns_before = self._return_count()
        self.assertEqual(response.status_code, http_status, response.data)
        self.assertEqual(response.data['code'], code, response.data)
        self.assertIn('detail', response.data)
        self.assertEqual(self._return_count(), returns_before,
                         'a refused return must not be recorded')


class ShiftGateTests(ReturnsPolicyBase):
    """Decision 05: a cashier with an OPEN shift. No shift, no refund."""

    def test_a_return_without_an_open_shift_is_refused_before_any_write(self):
        original = self._sell(10, 100)
        Shift.objects.filter(cashier=self.cashier).update(
            status=Shift.Status.CLOSED)
        stock_before = self._stock()
        payments_before = Payment.objects.count()

        response = self._post_return(original=original, qty=2)

        self._refused(response, 'NO_OPEN_SHIFT')
        self.assertEqual(self._stock(), stock_before,
                         'a refused return restocks nothing')
        self.assertEqual(Payment.objects.count(), payments_before)
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.RETURN).count(), 0,
            'a refused return writes no audit row')

    def test_a_return_records_the_cashiers_open_shift(self):
        original = self._sell(10, 100)

        response = self._post_return(original=original, qty=2)

        self.assertEqual(response.status_code, 201, response.data)
        txn = SalesTransaction.objects.get(pk=response.data['id'])
        self.assertEqual(txn.shift, self.shift)


class LinkedAndReasonTests(ReturnsPolicyBase):
    """Decision 05: cashiers return LINKED, every return carries a REASON."""

    def test_a_cashier_cannot_post_an_unlinked_return(self):
        response = self._post_return(original=None, qty=2)

        self._refused(response, 'UNLINKED_RETURN_FORBIDDEN', http_status=403)

    def test_a_manager_may_post_an_unlinked_return_with_a_reason(self):
        response = self._post_return(
            original=None, qty=2, user=self.manager,
            reason='no receipt, customer brought the bag back')

        self.assertEqual(response.status_code, 201, response.data)
        txn = SalesTransaction.objects.get(pk=response.data['id'])
        self.assertIsNone(txn.original_transaction)
        self.assertEqual(txn.notes, 'no receipt, customer brought the bag back')

    def test_a_return_without_a_reason_is_refused(self):
        original = self._sell(10, 100)

        response = self._post_return(original=original, qty=2, reason=None)

        self._refused(response, 'RETURN_REASON_REQUIRED')

    def test_a_blank_reason_is_refused(self):
        original = self._sell(10, 100)

        response = self._post_return(original=original, qty=2, reason='   ')

        self._refused(response, 'RETURN_REASON_REQUIRED')

    def test_an_over_long_reason_is_refused(self):
        original = self._sell(10, 100)

        response = self._post_return(
            original=original, qty=2, reason='x' * 256)

        self._refused(response, 'RETURN_REASON_REQUIRED')

    def test_the_reason_is_stored_on_the_return(self):
        original = self._sell(10, 100)

        response = self._post_return(
            original=original, qty=2, reason='cracked bags')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['notes'], 'cracked bags')


class OriginalEligibilityTests(ReturnsPolicyBase):
    """A requisition release, a return, and a void sale are all unreversible."""

    def test_a_requisition_release_cannot_be_returned(self):
        release = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no='TRX-RELEASE-1',
            source=SalesTransaction.Source.REQUISITION,
            grand_total=Decimal('100'),
        )
        SalesItem.objects.create(
            transaction=release, variant_uom=self.vuom, qty=Decimal('10'),
            unit_price=Decimal('10'), subtotal=Decimal('100'))

        response = self._post_return(original=release, qty=2)

        self._refused(response, 'RELEASE_NOT_RETURNABLE')

    def test_a_return_cannot_reverse_another_return(self):
        original = self._sell(10, 100)
        first = self._post_return(original=original, qty=2)
        self.assertEqual(first.status_code, 201, first.data)
        first_txn = SalesTransaction.objects.get(pk=first.data['id'])

        response = self._post_return(original=first_txn, qty=1)

        self._refused(response, 'RETURN_OF_RETURN')

    def test_a_non_completed_original_is_refused(self):
        original = self._sell(10, 100)
        SalesTransaction.objects.filter(pk=original.pk).update(
            status=SalesTransaction.Status.VOID)

        response = self._post_return(original=original, qty=2)

        self._refused(response, 'ORIGINAL_NOT_COMPLETED')


class QtyCapTests(ReturnsPolicyBase):
    """The cap is by SELLING UNIT against what the original SOLD (decision 05)."""

    def test_a_return_above_the_sold_quantity_is_refused_with_the_numbers(self):
        original = self._sell(10, 100)

        response = self._post_return(original=original, qty=11)

        self._refused(response, 'RETURN_QTY_EXCEEDED')
        self.assertEqual(response.data['variant_uom'], self.vuom.id)
        self.assertEqual(response.data['sold'], '10.00')
        self.assertEqual(response.data['already_returned'], '0.00')
        self.assertEqual(response.data['requested'], '11.00')

    def test_a_second_return_cannot_exceed_what_is_left(self):
        original = self._sell(10, 100)
        first = self._post_return(original=original, qty=6)
        self.assertEqual(first.status_code, 201, first.data)

        response = self._post_return(original=original, qty=5)

        self._refused(response, 'RETURN_QTY_EXCEEDED')
        self.assertEqual(response.data['already_returned'], '6.00')
        self.assertEqual(response.data['requested'], '5.00')

    def test_returning_exactly_the_remaining_quantity_is_allowed(self):
        original = self._sell(10, 100)
        self.assertEqual(
            self._post_return(original=original, qty=6).status_code, 201)

        response = self._post_return(original=original, qty=4)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(SalesTransaction.objects.filter(
            source=SalesTransaction.Source.RETURN).count(), 2)

    def test_the_cap_applies_to_a_sale_with_no_deduction_rows(self):
        # Pre-linkage history: the sale never recorded which batches it drew from, so the
        # only cap that used to exist (the deduction rows) was blind here.
        original = self._sell(10, 100)
        SalesItemDeduction.objects.filter(
            sales_item__transaction=original).delete()
        self.assertFalse(
            SalesItemDeduction.objects.filter(
                sales_item__transaction=original).exists())

        response = self._post_return(original=original, qty=11)

        self._refused(response, 'RETURN_QTY_EXCEEDED')
        self.assertEqual(response.data['sold'], '10.00')

    def test_the_cap_counts_two_lines_of_the_same_unit_in_one_request(self):
        original = self._sell(10, 100)

        response = self.client.post(
            TRANSACTIONS_URL,
            {'customer': self.customer.id, 'source': 'RETURN',
             'original_transaction': original.id,
             'payment_method': 'CASH', 'reason': 'two lines',
             'items': [{'variant_id': self.vuom.id, 'qty': '6'},
                       {'variant_id': self.vuom.id, 'qty': '6'}]},
            format='json', **self._auth(self.cashier))

        self._refused(response, 'RETURN_QTY_EXCEEDED')
        self.assertEqual(response.data['requested'], '12.00')

    def test_the_original_row_is_locked_before_the_cap_is_read(self):
        original = self._sell(10, 100)

        with CaptureQueriesContext(connection) as ctx:
            response = self._post_return(original=original, qty=1)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(
            any('pos_transaction' in q['sql'] and 'FOR UPDATE' in q['sql']
                for q in ctx.captured_queries),
            'concurrent returns must serialize on the original transaction row')


class DebtFirstTests(ReturnsPolicyBase):
    """Decision 05: return value reduces the debt first; only the excess is refunded."""

    def _credit_sale(self, total=Decimal('1000'), paid=Decimal('400')):
        """A credit sale: total sold, `paid` cash taken, the rest posted to utang."""
        txn = self._sell(qty=total / Decimal('10'), paid=paid)
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, total - paid)
        return txn, ledger

    def test_credit_sale_return_of_800_against_600_owed_refunds_only_200(self):
        original, ledger = self._credit_sale()          # 1000, 600 owed

        response = self._post_return(original=original, qty=80)  # value 800

        self.assertEqual(response.status_code, 201, response.data)
        ret = SalesTransaction.objects.get(pk=response.data['id'])

        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('0'))
        self.assertEqual(ledger.status, CollectibleLedger.Status.PAID)

        credit = CollectiblePayment.objects.get(collectible=ledger)
        self.assertEqual(credit.amount_paid, Decimal('600'))
        self.assertEqual(credit.payment_method, 'RETURN_CREDIT')
        self.assertEqual(credit.official_receipt_no, ret.transaction_no)
        self.assertEqual(credit.processed_by, self.cashier)

        payment = Payment.objects.get(transaction=ret)
        self.assertEqual(payment.method, Payment.Method.CASH)
        self.assertEqual(payment.amount_tendered, Decimal('-200.00'),
                         'only the EXCESS leaves the drawer')

        summary = response.data['refund_summary']
        self.assertEqual(summary['return_value'], '800.00')
        self.assertEqual(summary['debt_reduced'], '600.00')
        self.assertEqual(summary['cash_refund'], '200.00')
        self.assertEqual(summary['refund_method'], 'CASH')
        self.assertEqual(summary['ledger_id'], ledger.id)
        self.assertEqual(summary['ledger_balance'], '0.00')

        # The drawer only ever paid out the excess.
        resp = self.client.post(
            f'{SHIFTS_URL}{self.shift.id}/close/', {'closing_count': '5200.00'},
            format='json', **self._auth(self.cashier))
        self.assertEqual(resp.status_code, 200, resp.data)
        z = resp.data['z_reading']
        self.assertEqual(Decimal(z['cash_refunds']), Decimal('200.00'))
        self.assertEqual(Decimal(z['cash_sales']), Decimal('400.00'))
        self.assertEqual(Decimal(z['gross_sales']), Decimal('200.00'),
                         '1000 sold less the 800 returned')
        self.assertEqual(Decimal(z['expected_drawer']), Decimal('5200.00'))

    def test_a_return_smaller_than_the_debt_writes_no_payment_row(self):
        original, ledger = self._credit_sale()      # 600 owed

        response = self._post_return(original=original, qty=20)  # value 200

        self.assertEqual(response.status_code, 201, response.data)
        ret = SalesTransaction.objects.get(pk=response.data['id'])
        self.assertFalse(Payment.objects.filter(transaction=ret).exists(),
                         'nothing leaves the drawer when the debt absorbs it all')
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('400'))
        self.assertEqual(ledger.status, CollectibleLedger.Status.PARTIAL)
        self.assertEqual(
            response.data['refund_summary']['cash_refund'], '0.00')
        self.assertEqual(
            response.data['refund_summary']['debt_reduced'], '200.00')

    def test_a_full_paid_sale_return_refunds_the_whole_value(self):
        original = self._sell(qty=10, paid=Decimal('100'))

        response = self._post_return(original=original, qty=2)

        self.assertEqual(response.status_code, 201, response.data)
        ret = SalesTransaction.objects.get(pk=response.data['id'])
        payment = Payment.objects.get(transaction=ret)
        self.assertEqual(payment.amount_tendered, Decimal('-20.00'))
        self.assertIn('refund_summary', response.data)
        self.assertEqual(
            response.data['refund_summary'],
            {'return_value': '20.00', 'debt_reduced': '0.00',
             'cash_refund': '20.00', 'refund_method': 'CASH',
             'ledger_id': None, 'ledger_balance': None},
            'a cash sale has nothing to reduce: the whole value is refunded')

    def test_the_ledger_row_is_locked_before_it_is_reduced(self):
        original, _ = self._credit_sale()

        with CaptureQueriesContext(connection) as ctx:
            response = self._post_return(original=original, qty=80)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(
            any('collectibles_ledger' in q['sql'] and 'FOR UPDATE' in q['sql']
                for q in ctx.captured_queries),
            'two returns must not both read the same stale balance')

    def test_a_non_cash_excess_is_refunded_in_the_requested_method(self):
        original = self._sell(qty=10, paid=Decimal('100'))

        response = self._post_return(original=original, qty=2, method='GCASH')

        self.assertEqual(response.status_code, 201, response.data)
        ret = SalesTransaction.objects.get(pk=response.data['id'])
        self.assertEqual(
            Payment.objects.get(transaction=ret).method, Payment.Method.GCASH)


class AuditRowTests(ReturnsPolicyBase):
    def test_exactly_one_return_audit_row_names_the_original_and_the_money(self):
        original = self._sell(qty=100, paid=Decimal('400'))   # 600 owed

        response = self._post_return(original=original, qty=80)

        self.assertEqual(response.status_code, 201, response.data)
        rows = list(AuditLog.objects.filter(
            action_type=AuditLog.ActionType.RETURN))
        self.assertEqual(len(rows), 1, 'one return event, one audit row')
        txn = SalesTransaction.objects.get(pk=response.data['id'])
        description = rows[0].description
        self.assertIn(txn.transaction_no, description)
        self.assertIn(original.transaction_no, description)
        self.assertIn('600.00', description, 'the debt reduced')
        self.assertIn('200.00', description, 'the cash refunded')


class ReturnLookupTests(ReturnsPolicyBase):
    """The till searches by transaction or receipt number; `returnable/` gates the form."""

    def _sale_with_or(self, cashier, qty=4):
        txn = self._sell(qty=qty, cashier=cashier)
        return txn, OfficialReceipt.objects.get(transaction=txn).or_number

    def _get(self, url, user, params=None):
        return self.client.get(url, params or {}, **self._auth(user))

    def test_q_matches_the_transaction_number_exactly(self):
        txn, _ = self._sale_with_or(self.cashier)

        response = self._get(TRANSACTIONS_URL, self.cashier,
                             {'q': txn.transaction_no})

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([r['id'] for r in response.data['results']], [txn.id])

    def test_q_matches_the_receipt_number_exactly(self):
        txn, or_number = self._sale_with_or(self.cashier)

        response = self._get(TRANSACTIONS_URL, self.cashier, {'q': or_number})

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([r['id'] for r in response.data['results']], [txn.id])

    def test_q_does_not_reach_another_cashiers_sale(self):
        other, other_or = self._sale_with_or(self.other_cashier)

        by_number = self._get(TRANSACTIONS_URL, self.cashier,
                              {'q': other.transaction_no})
        by_receipt = self._get(TRANSACTIONS_URL, self.cashier,
                               {'q': other_or})

        self.assertEqual(by_number.status_code, 200, by_number.data)
        self.assertEqual(by_number.data['results'], [])
        self.assertEqual(by_receipt.data['results'], [])

    def test_q_is_an_exact_match_not_a_substring(self):
        txn, _ = self._sale_with_or(self.cashier)

        response = self._get(TRANSACTIONS_URL, self.cashier,
                             {'q': txn.transaction_no[:-1]})

        self.assertEqual(response.data['results'], [])

    def test_a_manager_q_sees_every_till(self):
        own, _ = self._sale_with_or(self.cashier)
        other, _ = self._sale_with_or(self.other_cashier)

        ids = {
            row['id'] for row in self._get(
                TRANSACTIONS_URL, self.manager,
                {'q': own.transaction_no}).data['results']}
        self.assertEqual(ids, {own.id})

    def test_returnable_lists_what_is_left_and_the_open_debt(self):
        original = self._sell(qty=100, paid=Decimal('400'))     # 600 owed
        self.assertEqual(
            self._post_return(original=original, qty=30).status_code, 201)

        response = self._get(
            f'{TRANSACTIONS_URL}{original.id}/returnable/', self.cashier)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['transaction_no'], original.transaction_no)
        self.assertTrue(response.data['returnable'])
        self.assertIsNone(response.data['reason_if_not'])
        self.assertEqual(response.data['source'], 'WALK_IN')
        self.assertEqual(response.data['customer'], self.customer.name)
        # 600 was owed; the 30-bag return (300.00) settled half of it DEBT FIRST, so
        # nothing left the drawer and the receivable is what is left.
        self.assertEqual(response.data['open_debt'], '300.00')
        line = response.data['lines'][0]
        self.assertEqual(line['variant_uom'], self.vuom.id)
        self.assertEqual(line['sold_qty'], '100.00')
        self.assertEqual(line['returned_qty'], '30.00')
        self.assertEqual(line['remaining_qty'], '70.00')
        self.assertEqual(line['unit_price'], '10.00')
        self.assertEqual(line['uom'], 'BAG')
        self.assertIn('Portland Cement', line['name'])

    def test_returnable_on_another_cashiers_sale_is_404(self):
        other, _ = self._sale_with_or(self.other_cashier)

        response = self._get(
            f'{TRANSACTIONS_URL}{other.id}/returnable/', self.cashier)

        # Asserted without `response.data` in the message: before the action exists the
        # router answers Django's plain 404, which has no DRF payload to print.
        self.assertEqual(response.status_code, 404)

    def test_returnable_marks_a_requisition_release_and_a_return(self):
        release = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no='TRX-RELEASE-2',
            source=SalesTransaction.Source.REQUISITION,
            grand_total=Decimal('100'))
        SalesItem.objects.create(
            transaction=release, variant_uom=self.vuom, qty=Decimal('10'),
            unit_price=Decimal('10'), subtotal=Decimal('100'))
        original = self._sell(qty=2, paid=Decimal('20'))
        posted = self._post_return(original=original, qty=1, reason='one bag back')
        self.assertEqual(posted.status_code, 201, posted.data)
        ret = SalesTransaction.objects.get(pk=posted.data['id'])

        not_a_sale = self._get(
            f'{TRANSACTIONS_URL}{release.id}/returnable/', self.cashier)
        a_return = self._get(
            f'{TRANSACTIONS_URL}{ret.id}/returnable/', self.cashier)

        self.assertEqual(not_a_sale.status_code, 200)
        self.assertFalse(not_a_sale.data['returnable'])
        self.assertEqual(not_a_sale.data['reason_if_not'], 'RELEASE_NOT_RETURNABLE')
        self.assertFalse(a_return.data['returnable'])
        self.assertEqual(a_return.data['reason_if_not'], 'RETURN_OF_RETURN')
