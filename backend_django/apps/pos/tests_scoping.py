# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# The same directives and reasons as apps/pos/tests.py: this checker runs from a working
# directory outside the repo, so `Model.objects` is a false positive on valid Django, and
# `**auth` splats HTTP_AUTHORIZATION into Django's test client, which forwards unknown
# kwargs into the WSGI environ (pyright reads that string as `follow=`).

"""Phase 2 Task 2 — role-scoped sales, receivables and held-cart access (decision 02).

Two different refusals live here and they must not be confused:

* **role denial** — the caller has no role that may see the resource at all: ``403``.
* **row scoping** — a cashier may see sales, but only their own: a row belonging to
  another till is ``404``, because the API must not confirm that a stranger's sale
  exists.

The ``P2 Ruling`` in ``.superpowers/sdd/audit-remediation/progress.md`` overrides
decision 02's "inventory sees RETURN only": the built Stock Manager Sales tab reads ALL
sales, so ``inventory`` is a sales reader. Only a **cashier-only** user is scoped to their
own rows.

Real JWT logins (no ``force_authenticate``) and a random per-run password: the
permission classes read the authenticated user's GROUP membership, so the login path is
part of what is under test.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import Customer, HeldCart, Payment, SalesItem, SalesTransaction, Shift
from .services import process_sale
from .tests import POSTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
TRANSACTIONS_URL = '/api/v1/transactions/'
DAILY_REPORT_URL = '/api/v1/transactions/daily_report/'
PAYMENTS_URL = '/api/v1/payments/'
RECEIPTS_URL = '/api/v1/receipts/'
CUSTOMERS_URL = '/api/v1/customers/'
HELD_CARTS_URL = '/api/v1/held-carts/'
QUOTATIONS_URL = '/api/v1/quotations/'
SALES_ORDERS_URL = '/api/v1/sales-orders/'


class ScopingTestBase(POSTestBase):
    """One user per role, real JWT logins, and one completed sale rung per cashier."""

    def setUp(self):
        super().setUp()
        # APIClient, not Django's test client: `POSTestBase` inherits `TestCase`, whose
        # client cannot encode `format='json'` (nested held-cart items need a JSON body).
        self.client = APIClient()
        self.password = get_random_string(16)
        self.cashier_a = self._make_user('scope_cashier_a', 'Cashier')
        self.cashier_b = self._make_user('scope_cashier_b', 'Cashier')
        self.manager = self._make_user('scope_manager', 'Store Manager')
        self.stocker = self._make_user('scope_stocker', 'Stock Manager')
        self.foreman = self._make_user('scope_foreman', 'Site Foreman')
        # Deny by default: a user with no role group at all.
        self.nobody = self._make_user('scope_nobody')
        self.txn_a = self._ring_sale(self.cashier_a, 2)  # 20.00
        self.txn_b = self._ring_sale(self.cashier_b, 3)  # 30.00

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
        return {'HTTP_AUTHORIZATION': f"Bearer {login.data['access']}"}

    def _ring_sale(self, cashier, qty):
        Shift.objects.create(cashier=cashier, opening_float=Decimal('5000'))
        return process_sale(
            customer_id=self.customer.id,
            cashier=cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': qty,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal(str(10 * qty))}],
        )

    def _get(self, url, user, params=None):
        return self.client.get(url, params or {}, **self._auth(user))

    def _ids(self, response):
        return [row['id'] for row in response.data['results']]


class TransactionScopingTests(ScopingTestBase):
    """GET /transactions/ (list, detail, daily_report) — own rows for cashier-only."""

    def test_a_cashier_lists_only_their_own_transactions(self):
        response = self._get(TRANSACTIONS_URL, self.cashier_a)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self._ids(response), [self.txn_a.id])

    def test_another_cashiers_transaction_detail_is_404_not_403(self):
        response = self.client.get(
            f'{TRANSACTIONS_URL}{self.txn_b.id}/', **self._auth(self.cashier_a))

        self.assertEqual(
            response.status_code, 404,
            'a row outside the caller\'s scope must not be confirmed to exist')

    def test_a_cashier_reads_their_own_transaction_detail(self):
        response = self.client.get(
            f'{TRANSACTIONS_URL}{self.txn_a.id}/', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['id'], self.txn_a.id)

    def test_manager_and_stocker_see_every_transaction(self):
        for user in (self.manager, self.stocker):
            with self.subTest(role=user.username):
                response = self._get(TRANSACTIONS_URL, user)

                self.assertEqual(response.status_code, 200, response.data)
                self.assertEqual(
                    sorted(self._ids(response)),
                    sorted([self.txn_a.id, self.txn_b.id]))

    def test_the_daily_report_totals_only_the_cashiers_own_sales(self):
        cashier_response = self._get(DAILY_REPORT_URL, self.cashier_a)

        self.assertEqual(cashier_response.status_code, 200, cashier_response.data)
        self.assertEqual(cashier_response.data['count'], 1)
        self.assertEqual(
            Decimal(str(cashier_response.data['total_sales'])), Decimal('20.00'))

        manager_response = self._get(DAILY_REPORT_URL, self.manager)

        self.assertEqual(manager_response.status_code, 200, manager_response.data)
        self.assertEqual(manager_response.data['count'], 2)
        self.assertEqual(
            Decimal(str(manager_response.data['total_sales'])), Decimal('30.00') + Decimal('20.00'))

    def test_foreman_and_groupless_are_refused_sales_reads(self):
        for user in (self.foreman, self.nobody):
            with self.subTest(user=user.username):
                self.assertEqual(
                    self._get(TRANSACTIONS_URL, user).status_code, 403)
                self.assertEqual(
                    self._get(DAILY_REPORT_URL, user).status_code, 403)


class PaymentAndReceiptScopingTests(ScopingTestBase):
    """Payments and receipts follow their transaction's cashier."""

    def test_a_cashier_lists_only_payments_of_their_own_sales(self):
        response = self._get(PAYMENTS_URL, self.cashier_a)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(
            response.data['results'][0]['transaction'], self.txn_a.id)

    def test_another_cashiers_payment_is_404(self):
        other_payment = self.txn_b.payments.first()
        self.assertIsNotNone(other_payment)

        response = self.client.get(
            f'{PAYMENTS_URL}{other_payment.id}/', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 404)

    def test_a_cashier_lists_only_their_own_receipts(self):
        response = self._get(RECEIPTS_URL, self.cashier_a)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['count'], 1)
        self.assertEqual(
            response.data['results'][0]['transaction'], self.txn_a.id)

    def test_manager_and_stocker_read_every_payment_and_receipt(self):
        for user in (self.manager, self.stocker):
            with self.subTest(role=user.username):
                self.assertEqual(
                    self._get(PAYMENTS_URL, user).data['count'], 2)
                self.assertEqual(
                    self._get(RECEIPTS_URL, user).data['count'], 2)

    def test_foreman_and_groupless_cannot_read_payments_or_receipts(self):
        for user in (self.foreman, self.nobody):
            with self.subTest(user=user.username):
                self.assertEqual(self._get(PAYMENTS_URL, user).status_code, 403)
                self.assertEqual(self._get(RECEIPTS_URL, user).status_code, 403)


class HeldCartAccessTests(ScopingTestBase):
    """Held carts are store-wide among POS roles — and closed to every other role."""

    def _hold(self, user, qty=2):
        response = self.client.post(
            HELD_CARTS_URL,
            {'notes': 'parked', 'items': [
                {'variant_uom': self.vuom.id, 'qty': str(qty),
                 'unit_price': '10.00'}]},
            format='json', **self._auth(user))
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def test_inventory_and_foreman_are_refused_held_carts(self):
        cart = self._hold(self.cashier_a)

        for user in (self.stocker, self.foreman, self.nobody):
            with self.subTest(user=user.username):
                self.assertEqual(
                    self._get(HELD_CARTS_URL, user).status_code, 403)
                self.assertEqual(
                    self.client.get(f'{HELD_CARTS_URL}{cart["id"]}/',
                                    **self._auth(user)).status_code, 403)

    def test_a_second_cashier_can_see_and_complete_a_parked_cart(self):
        cart = self._hold(self.cashier_a)

        seen = self.client.get(
            f'{HELD_CARTS_URL}{cart["id"]}/', **self._auth(self.cashier_b))
        self.assertEqual(seen.status_code, 200, seen.data)

        completed = self.client.post(
            f'{HELD_CARTS_URL}{cart["id"]}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '20.00'}]},
            format='json', **self._auth(self.cashier_b))

        self.assertEqual(completed.status_code, 201, completed.data)
        self.assertFalse(HeldCart.objects.filter(pk=cart['id']).exists())
        # The sale belongs to the cashier who actually took the money.
        self.assertEqual(completed.data['cashier'], self.cashier_b.id)

    def test_a_manager_may_read_held_carts(self):
        cart = self._hold(self.cashier_a)

        response = self._get(HELD_CARTS_URL, self.manager)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(self._ids(response), [cart['id']])


class CustomerAccessTests(ScopingTestBase):
    """Customer reads need a sales role; the credit limit is manager-only money."""

    def test_foreman_and_groupless_cannot_read_customers(self):
        for user in (self.foreman, self.nobody):
            with self.subTest(user=user.username):
                self.assertEqual(self._get(CUSTOMERS_URL, user).status_code, 403)

    def test_cashier_manager_and_stocker_can_read_customers(self):
        for user in (self.cashier_a, self.manager, self.stocker):
            with self.subTest(role=user.username):
                self.assertEqual(
                    self._get(CUSTOMERS_URL, user).status_code, 200)

    def test_a_cashier_cannot_create_a_customer_with_a_credit_limit(self):
        response = self.client.post(
            CUSTOMERS_URL,
            {'name': 'Limit Raiser', 'total_credit_limit': '999999.00'},
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['code'], 'CREDIT_LIMIT_FORBIDDEN')
        self.assertTrue(response.data['detail'])
        self.assertFalse(Customer.objects.filter(name='Limit Raiser').exists())

    def test_a_cashier_can_still_create_a_customer_without_a_credit_limit(self):
        response = self.client.post(
            CUSTOMERS_URL, {'name': 'Plain Walk-in'},
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertIsNone(response.data['total_credit_limit'])

    def test_a_cashier_cannot_raise_an_existing_credit_limit(self):
        response = self.client.patch(
            f'{CUSTOMERS_URL}{self.customer.id}/',
            {'total_credit_limit': '50000.00'},
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data['code'], 'CREDIT_LIMIT_FORBIDDEN')
        self.customer.refresh_from_db()
        self.assertIsNone(self.customer.total_credit_limit)

    def test_a_manager_may_set_and_change_a_credit_limit(self):
        created = self.client.post(
            CUSTOMERS_URL,
            {'name': 'Contractor Account', 'total_credit_limit': '25000.00'},
            format='json', **self._auth(self.manager))
        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(Decimal(created.data['total_credit_limit']), Decimal('25000.00'))

        patched = self.client.patch(
            f'{CUSTOMERS_URL}{created.data["id"]}/',
            {'total_credit_limit': '30000.00'},
            format='json', **self._auth(self.manager))
        self.assertEqual(patched.status_code, 200, patched.data)
        self.assertEqual(Decimal(patched.data['total_credit_limit']), Decimal('30000.00'))

    def test_only_a_manager_may_delete_a_customer(self):
        response = self.client.delete(
            f'{CUSTOMERS_URL}{self.customer.id}/', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 403)
        self.assertTrue(Customer.objects.filter(pk=self.customer.id).exists())

    def test_deleting_a_customer_with_sales_is_a_409(self):
        response = self.client.delete(
            f'{CUSTOMERS_URL}{self.customer.id}/', **self._auth(self.manager))

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data['code'], 'CUSTOMER_IN_USE')
        self.assertTrue(Customer.objects.filter(pk=self.customer.id).exists())

    def test_a_manager_may_delete_an_unused_customer(self):
        unused = Customer.objects.create(name='Never Bought')

        response = self.client.delete(
            f'{CUSTOMERS_URL}{unused.id}/', **self._auth(self.manager))

        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(Customer.objects.filter(pk=unused.id).exists())


class QuotationAndOrderReadAccessTests(ScopingTestBase):
    """Quotations and sales orders are sales surfaces: sales readers only."""

    def test_foreman_and_groupless_cannot_read_quotations_or_orders(self):
        for user in (self.foreman, self.nobody):
            for url in (QUOTATIONS_URL, SALES_ORDERS_URL):
                with self.subTest(user=user.username, url=url):
                    self.assertEqual(self._get(url, user).status_code, 403)

    def test_cashier_manager_and_stocker_can_read_quotations_and_orders(self):
        for user in (self.cashier_a, self.manager, self.stocker):
            for url in (QUOTATIONS_URL, SALES_ORDERS_URL):
                with self.subTest(role=user.username, url=url):
                    self.assertEqual(self._get(url, user).status_code, 200)


class SalesImmutabilityTests(ScopingTestBase):
    """A completed sale is a financial record: written once, never edited or deleted.

    `SalesTransactionViewSet` inherited `ModelViewSet`, so PATCH/PUT rewrote
    `grand_total`, `customer`, `status`, `notes` or `original_transaction` after the
    receipt was printed, and DELETE removed the sale with its items and payments in one
    cascade. The endpoint now routes only `get`/`head`/`options`/`post`: ringing and
    reading a sale stay, mutating it answers **405** for every role, an admin included —
    a correction is a return transaction, never an edit of the original.
    """

    def setUp(self):
        super().setUp()
        self.admin = self._make_user('scope_admin', 'Admin')

    def _detail_url(self, transaction):
        return f'{TRANSACTIONS_URL}{transaction.id}/'

    def test_a_cashier_cannot_patch_a_completed_sale(self):
        response = self.client.patch(
            self._detail_url(self.txn_a), {'grand_total': '0.01'},
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 405, response.data)
        self.txn_a.refresh_from_db()
        self.assertEqual(self.txn_a.grand_total, Decimal('20.00'))

    def test_a_cashier_cannot_put_a_completed_sale(self):
        before = self.txn_a.grand_total

        response = self.client.put(
            self._detail_url(self.txn_a), {'grand_total': '0.01'},
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 405, response.data)
        self.txn_a.refresh_from_db()
        self.assertEqual(self.txn_a.grand_total, before)

    def test_nobody_can_delete_a_completed_sale(self):
        items = self.txn_a.items.count()
        payments = self.txn_a.payments.count()
        self.assertEqual(items, 1)
        self.assertEqual(payments, 1)

        response = self.client.delete(
            self._detail_url(self.txn_a), **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 405, response.data)
        self.assertTrue(
            SalesTransaction.objects.filter(pk=self.txn_a.pk).exists(),
            'the sale, its items and its payments must survive a DELETE')
        self.assertEqual(
            SalesItem.objects.filter(transaction_id=self.txn_a.pk).count(), items)
        self.assertEqual(
            Payment.objects.filter(transaction_id=self.txn_a.pk).count(), payments)

    def test_an_admin_and_a_manager_cannot_mutate_a_sale_either(self):
        for user in (self.admin, self.manager):
            url = self._detail_url(self.txn_a)
            auth = self._auth(user)

            patched = self.client.patch(
                url, {'grand_total': '0.01'}, format='json', **auth)
            self.assertEqual(patched.status_code, 405, patched.data)

            replaced = self.client.put(
                url, {'grand_total': '0.01'}, format='json', **auth)
            self.assertEqual(replaced.status_code, 405, replaced.data)

            deleted = self.client.delete(url, **auth)
            self.assertEqual(deleted.status_code, 405, deleted.data)

        self.txn_a.refresh_from_db()
        self.assertEqual(self.txn_a.grand_total, Decimal('20.00'))
        self.assertTrue(SalesTransaction.objects.filter(pk=self.txn_a.pk).exists())


class ReturnScopeTests(ScopingTestBase):
    """A cashier reverses only a sale THEY rang (review F4).

    `POST /transactions/` with `source=RETURN` handed `request.data['original_transaction']`
    straight to `process_return`, which does `SalesTransaction.objects.get(pk=...)` with
    no scope at all: cashier A could reverse cashier B's sale, restock B's stock and
    refund money out of a drawer that never took it. The original is now resolved through
    the caller's own scoped queryset, so another till's sale is a **404** ("hidden ≠
    forbidden") and nothing is written — no RETURN row, no stock movement. Manager and
    admin keep the whole store and are unchanged.
    """

    def _batches(self):
        from apps.inventory.models import InventoryBatch
        return list(
            InventoryBatch.objects.filter(variant=self.variant)
            .order_by('pk').values_list('pk', 'current_qty'))

    def _open_shift(self, user):
        """Phase 3 task 2 (decision 05): a refund needs an open shift, whatever the role.

        A refund is money out of a drawer and a drawer is a shift; recording one outside
        a shift leaves the Z-reading's expected drawer too high by the amount paid out.
        """
        return Shift.objects.create(
            cashier=user, opening_float=Decimal('5000'))

    def _return_payload(self, original):
        return {
            'customer': self.customer.id,
            'source': 'RETURN',
            'original_transaction': original.id,
            'items': [{'variant_id': self.vuom.id, 'qty': 1}],
            'payment_method': 'CASH',
            # Phase 3 task 2: mandatory on every return, stored in `notes`.
            'reason': 'one bag back',
        }

    def _returns_posted(self):
        return SalesTransaction.objects.filter(
            source=SalesTransaction.Source.RETURN).count()

    def test_a_cashier_cannot_reverse_another_cashiers_sale(self):
        stock_before = self._batches()
        returns_before = self._returns_posted()

        response = self.client.post(
            TRANSACTIONS_URL, self._return_payload(self.txn_b),
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 404, response.data)
        self.assertEqual(self._returns_posted(), returns_before)
        self.assertEqual(self._batches(), stock_before)

    def test_a_cashier_can_return_their_own_sale(self):
        response = self.client.post(
            TRANSACTIONS_URL, self._return_payload(self.txn_a),
            format='json', **self._auth(self.cashier_a))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['source'], 'RETURN')
        self.assertEqual(response.data['original_transaction'], self.txn_a.id)

    def test_a_manager_can_return_any_cashiers_sale(self):
        # The manager needs an open shift of their own (decision 05): the return is
        # recorded against the shift that paid it out, not the sale's shift.
        self._open_shift(self.manager)

        response = self.client.post(
            TRANSACTIONS_URL, self._return_payload(self.txn_b),
            format='json', **self._auth(self.manager))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['original_transaction'], self.txn_b.id)


class DenyByDefaultTests(TestCase):
    """Every refusal above is a role refusal, not a login refusal."""

    def test_a_groupless_authenticated_user_is_403_not_401(self):
        password = get_random_string(16)
        user = User.objects.create_user(
            username='scope_groupless', email='g@example.com', password=password)
        login = APIClient().post(
            LOGIN_URL, {'username': user.username, 'password': password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        auth = {'HTTP_AUTHORIZATION': f"Bearer {login.data['access']}"}

        response = APIClient().get(TRANSACTIONS_URL, **auth)

        self.assertEqual(response.status_code, 403)
        self.assertTrue(user.is_authenticated)
