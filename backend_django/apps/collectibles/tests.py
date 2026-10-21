# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# reportArgumentType is disabled for the `**self.auth` splat: Django's test client
# forwards unknown kwargs into the WSGI environ, and pyright reads the header string
# as `follow=`/`secure=`. Same note as apps/pos/tests.py.
#
# The same directive, with the same reason, as apps/pos/tests.py, apps/inventory/views.py
# and seed_demo.py: this checker is run by a client whose working directory is outside the
# repo, so it resolves no config and cannot be silenced by pyrightconfig.json, and every
# `Model.objects` access and `self.client.get(...).status_code` here is a false positive on
# valid Django. Django's `manage.py check` and the test run are the authority.

"""Collectibles tests — ledger math on payment posting."""

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase

from apps.pos.models import Customer, SalesTransaction

from .models import CollectibleLedger, CollectiblePayment

User = get_user_model()

PAYMENTS_URL = '/api/v1/ledger-payments/'
LEDGERS_URL = '/api/v1/ledgers/'
LOGIN_URL = '/api/v1/auth/login/'
AGING_URL = '/api/v1/ledgers/aging/'


class CollectiblesTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='collector', email='col@x.com', password='pass12345')
        self.customer = Customer.objects.create(name='Utang Corp')
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.user,
            transaction_no='TRX-TEST-0001',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )

    def test_is_overdue_property(self):
        self.assertFalse(self.ledger.is_overdue)
        self.ledger.due_date = date(2020, 1, 1)
        self.assertTrue(self.ledger.is_overdue)
        self.ledger.balance_due = Decimal('0')
        self.assertFalse(self.ledger.is_overdue)  # paid = never overdue

    def test_payment_records_against_ledger(self):
        payment = CollectiblePayment.objects.create(
            collectible=self.ledger, processed_by=self.user,
            amount_paid=Decimal('200'), payment_method='CASH')
        self.assertEqual(payment.collectible, self.ledger)
        self.ledger.balance_due = self.ledger.balance_due - payment.amount_paid
        self.ledger.status = (
            CollectibleLedger.Status.PARTIAL
            if self.ledger.balance_due > 0
            else CollectibleLedger.Status.PAID)
        self.ledger.save(update_fields=['balance_due', 'status'])
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('300'))
        self.assertEqual(self.ledger.status, CollectibleLedger.Status.PARTIAL)

    def test_full_payment_pays_ledger(self):
        CollectiblePayment.objects.create(
            collectible=self.ledger, processed_by=self.user,
            amount_paid=Decimal('500'), payment_method='GCASH')
        self.ledger.balance_due = Decimal('0')
        self.ledger.status = CollectibleLedger.Status.PAID
        self.ledger.save(update_fields=['balance_due', 'status'])
        self.assertEqual(self.ledger.payments.count(), 1)
        self.assertFalse(self.ledger.is_overdue)


class LedgerApiCustomerNameTests(TestCase):
    """Phase 4 — decision 14 correction 3.

    `Customer` has no `full_name` field. The project's `User` does, and that one wrong
    assumption was copied across, breaking the utang surface in two ways that reading
    the code does not reveal:

      * `apps/collectibles/views.py:59` reads `entry.customer.full_name` directly, so
        `GET /api/v1/ledgers/aging/` raises AttributeError -> **HTTP 500**.
      * `CollectibleLedgerSerializer.customer_name` sources `customer.full_name`, and
        DRF swallows the AttributeError for a ReadOnlyField, so every ledger row comes
        back 200 with `customer_name: null`. **That one is worse: it looks fine.**

    Both were confirmed live against the running server before the fix. These tests are
    the regression that keeps them fixed, and they are the reason Task 1 comes first —
    the utang panel cannot show a balance until this works.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            # The same fixture string as every other backend test module: a throwaway
            # per-run database, and the login below must POST this exact value.
            username='arclerk', email='ar@x.com', password='pass12345')  # nosemgrep
        self.customer = Customer.objects.create(
            name='Utang Corp', customer_type=Customer.Type.REGULAR)
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.user,
            transaction_no='TRX-TEST-0002',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )
        login = self.client.post(
            LOGIN_URL,
            {'username': 'arclerk', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200, 'the clerk must be able to log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def test_aging_report_does_not_crash(self):
        # Was HTTP 500 AttributeError: 'Customer' object has no attribute 'full_name'.
        response = self.client.get(
            AGING_URL, **self.auth)  # pyright: ignore[reportArgumentType]
        self.assertEqual(
            response.status_code, 200,
            'the aging report is what makes "charge it to my account" meaningful')
        body = response.json()
        self.assertEqual(body['total_customers'], 1)
        self.assertEqual(body['groups'][0]['customer_name'], 'Utang Corp')

    def test_a_ledger_row_carries_its_customers_name(self):
        # Was a silent null: the key existed, so nothing complained and the panel would
        # have shown an anonymous receivable.
        response = self.client.get(
            LEDGERS_URL, **self.auth)  # pyright: ignore[reportArgumentType]
        self.assertEqual(response.status_code, 200)
        rows = response.json()['results']
        self.assertEqual(len(rows), 1)
        self.assertEqual(
            rows[0]['customer_name'], 'Utang Corp',
            'a null name makes every receivable anonymous')

    def test_ledgers_can_be_filtered_to_one_customer(self):
        # Phase 4's panel needs one customer's balance, so the `customer` query param is
        # part of the contract, not an incidental extra.
        other = Customer.objects.create(name='Someone Else')
        other_txn = SalesTransaction.objects.create(
            customer=other, cashier=self.user,
            transaction_no='TRX-TEST-0003',
            vatable_sales=Decimal('50'), grand_total=Decimal('50'))
        CollectibleLedger.objects.create(
            customer=other, transaction=other_txn,
            original_amount=Decimal('50'), balance_due=Decimal('50'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN)

        response = self.client.get(
            f'{LEDGERS_URL}?customer={self.customer.id}',
            **self.auth)  # pyright: ignore[reportArgumentType]
        self.assertEqual(response.status_code, 200)
        rows = response.json()['results']
        self.assertEqual(len(rows), 1, 'the filter must actually narrow')
        self.assertEqual(rows[0]['customer_name'], 'Utang Corp')



class LedgerPaymentApiTests(TestCase):
    """Posting a payment must MOVE THE LEDGER - through the ENDPOINT.

    The two payment tests above create the CollectiblePayment and then perform
    the balance arithmetic THEMSELVES, asserting that the test can subtract.
    They passed for as long as `perform_create` only saved the payment and left
    `balance_due` alone, so a customer who had paid in full still read as owing
    the full amount, and the aging report, the till's utang panel and the
    receivables screen all repeated that number.

    These go through POST /api/v1/ledger-payments/, which is where the
    calculation has to happen for any of those consumers to be right.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            username='armgr', email='am@x.com', password='pass12345')  # nosemgrep
        self.customer = Customer.objects.create(
            name='Utang Corp', customer_type=Customer.Type.REGULAR)
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.user,
            transaction_no='TRX-TEST-0003',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )
        # Posting a payment is IsPOSOrReadOnly, so the actor needs a POS role -
        # the same fixture every other POS-role test uses.
        self.user.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'armgr', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _pay(self, amount):
        return self.client.post(
            PAYMENTS_URL,
            {'collectible': self.ledger.pk, 'amount_paid': str(amount),
             'payment_method': 'CASH'},
            content_type='application/json', **self.auth)

    def test_a_partial_payment_lowers_the_balance_and_marks_it_partial(self):
        response = self._pay('200')

        self.assertEqual(response.status_code, 201, response.content)
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('300'))
        self.assertEqual(self.ledger.status, CollectibleLedger.Status.PARTIAL)

    def test_a_full_payment_clears_the_balance_and_marks_it_paid(self):
        response = self._pay('500')

        self.assertEqual(response.status_code, 201, response.content)
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('0'))
        self.assertEqual(self.ledger.status, CollectibleLedger.Status.PAID)
        self.assertFalse(self.ledger.is_overdue)

    def test_the_payment_is_attributed_to_the_logged_in_user(self):
        # `processed_by` is read-only, so the server assigns the actor rather than
        # trusting the client - the audit trail names who really took the money.
        response = self._pay('100')

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(
            CollectiblePayment.objects.get().processed_by_id, self.user.pk)

    def test_an_overpayment_is_refused_and_writes_nothing(self):
        response = self._pay('600')

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'PAYMENT_EXCEEDS_BALANCE')
        self.assertEqual(response.json()['balance_due'], '500.00')
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('500'))
        self.assertEqual(self.ledger.status, CollectibleLedger.Status.OPEN)
        self.assertEqual(self.ledger.payments.count(), 0)

    def test_the_ledger_endpoint_reflects_the_payment_it_recorded(self):
        # The consumer-facing proof: what the receivables screen reads.
        self._pay('200')

        response = self.client.get(
            LEDGERS_URL, **self.auth)  # nosemgrep
        self.assertEqual(response.status_code, 200, response.content)
        row = next(r for r in response.json()['results']
                   if r['id'] == self.ledger.pk)
        self.assertEqual(row['balance_due'], '300.00')
