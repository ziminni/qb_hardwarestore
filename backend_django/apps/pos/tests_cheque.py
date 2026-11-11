# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/tests_discount_vat.py: the checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django and `**self.auth` splats the Authorization header into the WSGI environ.

"""Phase 4 Task B2 (decision 18) — split tenders and a cheque pending until cleared.

The owner's ruling, enforced here on the server:

* `CHEQUE` is a payment method with a number, a bank and a cheque date, and only a
  NAMED customer may pay by cheque (a walk-in's balance would be owed by nobody);
* a pending cheque does NOT count as paid: its amount posts to the customer's utang
  ledger through the ordinary underpayment path, and the credit-limit rule applies as it
  always did;
* a Store Manager or Admin decides it ONCE: `clear/` applies a ledger payment,
  `bounce/` with a reason leaves the debt standing (`409 CHEQUE_ALREADY_DECIDED` on the
  second attempt);
* change never comes from a cheque - a cheque tendered above what is still owed is
  refused, because the shop would be handing back money it has not received;
* the queue (`GET /cheques/`) is paginated, oldest first, and carries the customer, the
  sale and ledger it belongs to, and who decided it.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.pos.models import Customer, Payment, SalesTransaction
from apps.pos.services import compute_z_reading
from apps.pos.tests import POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
TRANSACTIONS_URL = '/api/v1/transactions/'
CHEQUES_URL = '/api/v1/cheques/'

CASHIER_USERNAME = 'cashier1'
CASHIER_PASSWORD = 'pass12345'  # noqa: S105 # nosemgrep: throwaway test fixture


def _auth(token):
    return {'HTTP_AUTHORIZATION': f'Bearer {token}'}


def cheque_tender(amount, *, number='CHQ-1001', bank='BDO', date='2026-11-20'):
    """One cheque tender, in the shape the till sends inside `payments[]`."""
    return {
        'method': 'CHEQUE',
        'amount_tendered': f'{amount:.2f}',
        'cheque_number': number,
        'bank': bank,
        'cheque_date': date,
    }


class ChequeTestBase(POSTestBase):
    """`POSTestBase` (one selling unit at 10.00) plus a REGULAR customer and logins.

    `POSTestBase.customer` is a WALK_IN record, which is exactly what a cheque must be
    refused for - so the cheque tests use their own named customer and keep the walk-in
    one for the refusal.
    """

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.regular = Customer.objects.create(
            name='Utang Corp', customer_type=Customer.Type.REGULAR)

        manager_password = get_random_string(20)
        self.manager = User.objects.create_user(
            username='chq_manager', email='cm@x.com', password=manager_password,
            full_name='Maria Santos')
        self.manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        self.manager_password = manager_password

        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.manager_auth = _auth(self._token('chq_manager', self.manager_password))

    def _token(self, username, password):
        login = self.client.post(
            LOGIN_URL, {'username': username, 'password': password},
            format='json')
        self.assertEqual(login.status_code, 200, f'{username} must be able to log in')
        return login.json()['access']

    def _ring(self, payments, *, qty=2, customer=None, discount=None):
        body = {
            'customer': self.regular.id if customer is None else customer,
            'source': 'WALK_IN',
            'items': [{'variant_id': self.vuom.id, 'qty': qty}],
            'payments': payments,
        }
        if discount is not None:
            body['discount'] = discount
        return self.client.post(
            TRANSACTIONS_URL, body, format='json', **self.cashier_auth)

    def _cash(self, amount):
        return {'method': 'CASH', 'amount_tendered': f'{amount:.2f}'}

    def _cheque_row(self, txn):
        return Payment.objects.get(transaction=txn, method=Payment.Method.CHEQUE)

    def _decide(self, cheque_id, action, body=None, as_auth=None):
        return self.client.post(
            f'{CHEQUES_URL}{cheque_id}/{action}/', body or {}, format='json',
            **(as_auth or self.manager_auth))

    def _pending_cheque(self, *, cash, cheque, qty=2):
        """Ring a sale whose cheque is pending and return (sale, cheque row, ledger)."""
        response = self._ring([self._cash(cash), cheque_tender(cheque)], qty=qty)
        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()['id'])
        return txn, self._cheque_row(txn), CollectibleLedger.objects.get(
            transaction=txn)


class ChequeTenderTests(ChequeTestBase):
    """What a cheque does to a sale's money."""

    def test_a_pending_cheque_posts_to_the_utang_ledger_instead_of_paying(self):
        txn, cheque, ledger = self._pending_cheque(cash=5, cheque=15)

        self.assertEqual(txn.grand_total, Decimal('20.00'))
        self.assertEqual(ledger.balance_due, Decimal('15.00'),
                         'the shortfall is the full amount the cheque did not pay')
        self.assertEqual(cheque.status, Payment.Status.PENDING)
        self.assertEqual(cheque.ledger_id, ledger.id,
                         'a pending cheque must know which utang it is waiting on')
        self.assertEqual(cheque.cheque_number, 'CHQ-1001')
        self.assertEqual(cheque.bank, 'BDO')
        self.assertEqual(cheque.cheque_date.isoformat(), '2026-11-20')
        self.assertEqual(cheque.decided_by, None)
        self.assertEqual(txn.payments.count(), 2)

    def test_a_cheque_needs_a_named_customer(self):
        response = self._ring(
            [self._cash(5), cheque_tender(15)], customer=self.customer.id)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'CHEQUE_NEEDS_CUSTOMER')
        self.assertEqual(SalesTransaction.objects.count(), 0,
                         'a refused cheque leaves no sale behind')
        self.assertEqual(CollectibleLedger.objects.count(), 0)

    def test_a_cheque_needs_its_number_bank_and_date(self):
        for missing in ('cheque_number', 'bank', 'cheque_date'):
            with self.subTest(missing=missing):
                tender = cheque_tender(15)
                tender[missing] = ''
                response = self._ring([self._cash(5), tender])
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(response.json()['code'], 'CHEQUE_DETAILS_REQUIRED')
        self.assertEqual(Payment.objects.count(), 0)

    def test_a_cheque_cannot_be_tendered_above_what_is_still_owed(self):
        # Change comes from the DRAWER: the shop cannot hand back money it has not
        # received, so cash 20 of a 20.00 sale leaves nothing for a cheque to cover.
        response = self._ring([self._cash(20), cheque_tender(5)])

        self.assertEqual(response.status_code, 400, response.content)
        body = response.json()
        self.assertEqual(body['code'], 'CHEQUE_EXCEEDS_BALANCE')
        self.assertEqual(body['cheque_total'], '5.00')
        self.assertEqual(body['owed'], '0.00')
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_cash_gcash_and_cheque_split_tenders(self):
        response = self._ring([
            self._cash(5),
            {'method': 'GCASH', 'amount_tendered': '5.00', 'reference_no': 'G-77'},
            cheque_tender(10),
        ])

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()['id'])
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('10.00'))
        self.assertEqual(txn.payments.count(), 3)
        self.assertEqual(
            sorted(txn.payments.values_list('method', flat=True)),
            ['CASH', 'CHEQUE', 'GCASH'])
        self.assertEqual(
            self._cheque_row(txn).status, Payment.Status.PENDING)

    def test_a_discount_and_split_tenders_together_use_the_net(self):
        # 2 units at 10.00 = 20.00 gross; 10 percent (the cap) = 2.00 off, net 18.00.
        response = self._ring(
            [self._cash(8), cheque_tender(10)],
            discount={'kind': 'PERCENT', 'value': '10', 'reason': 'Loyal customer'})

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body['grand_total'], '18.00')
        self.assertEqual(body['discount_amount'], '2.00')
        self.assertEqual(body['vatable_sales'], '16.07')
        self.assertEqual(body['vat_amount'], '1.93')
        txn = SalesTransaction.objects.get(pk=body['id'])
        self.assertEqual(
            CollectibleLedger.objects.get(transaction=txn).balance_due,
            Decimal('10.00'), 'the utang is the NET minus the cash taken')

    def test_a_pending_cheque_is_not_cash_in_the_z_reading(self):
        self._pending_cheque(cash=5, cheque=15)

        reading = compute_z_reading(self.shift)

        self.assertEqual(reading['gross_sales'], '20.00')
        self.assertEqual(reading['cash_sales'], '5.00',
                         'only the cash is in the drawer; the cheque is not money yet')
        self.assertEqual(reading['expected_drawer'], '5005.00')


class ChequeDecisionTests(ChequeTestBase):
    """`clear/` and `bounce/`: Store Manager or Admin, once, locked, audited."""

    def test_clearing_applies_a_ledger_payment(self):
        txn, cheque, ledger = self._pending_cheque(cash=5, cheque=15)

        response = self._decide(cheque.id, 'clear')

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body['status'], 'CLEARED')
        self.assertEqual(body['decided_by'], self.manager.id)
        self.assertIsNotNone(body['decided_at'])
        cheque.refresh_from_db()
        ledger.refresh_from_db()
        self.assertEqual(cheque.status, Payment.Status.CLEARED)
        self.assertEqual(ledger.balance_due, Decimal('0.00'))
        self.assertEqual(ledger.status, CollectibleLedger.Status.PAID)
        payment = CollectiblePayment.objects.get(collectible=ledger)
        self.assertEqual(payment.amount_paid, Decimal('15.00'))
        self.assertEqual(payment.payment_method, Payment.Method.CHEQUE)
        self.assertTrue(
            AuditLog.objects.filter(action_type='CHEQUE_DECISION').exists(),
            'who decided a cheque belongs in the audit trail')
        self.assertIn('CHQ-1001', AuditLog.objects.filter(
            action_type='CHEQUE_DECISION').first().description)

    def test_a_cheque_covering_only_part_of_the_debt_leaves_the_rest_owed(self):
        txn, cheque, ledger = self._pending_cheque(cash=0, cheque=10)

        self.assertEqual(self._decide(cheque.id, 'clear').status_code, 200)

        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('10.00'))
        self.assertEqual(ledger.status, CollectibleLedger.Status.PARTIAL)

    def test_a_cashier_cannot_decide_a_cheque(self):
        txn, cheque, ledger = self._pending_cheque(cash=5, cheque=15)

        response = self._decide(cheque.id, 'clear', as_auth=self.cashier_auth)

        self.assertEqual(response.status_code, 403)
        cheque.refresh_from_db()
        ledger.refresh_from_db()
        self.assertEqual(cheque.status, Payment.Status.PENDING)
        self.assertEqual(ledger.balance_due, Decimal('15.00'))

    def test_a_clear_cannot_be_repeated(self):
        txn, cheque, ledger = self._pending_cheque(cash=5, cheque=15)
        self.assertEqual(self._decide(cheque.id, 'clear').status_code, 200)

        response = self._decide(cheque.id, 'clear')

        self.assertEqual(response.status_code, 409, response.content)
        self.assertEqual(response.json()['code'], 'CHEQUE_ALREADY_DECIDED')
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('0.00'),
                         'a second clear must not pay the ledger twice')
        self.assertEqual(CollectiblePayment.objects.filter(
            collectible=ledger).count(), 1)

    def test_a_bounce_keeps_the_debt_and_needs_a_reason(self):
        txn, cheque, ledger = self._pending_cheque(cash=5, cheque=15)

        without_reason = self._decide(cheque.id, 'bounce')
        self.assertEqual(without_reason.status_code, 400, without_reason.content)
        self.assertEqual(
            without_reason.json()['code'], 'CHEQUE_REASON_REQUIRED')

        bounced = self._decide(
            cheque.id, 'bounce', {'reason': 'Insufficient funds'})
        self.assertEqual(bounced.status_code, 200, bounced.content)
        self.assertEqual(bounced.json()['status'], 'BOUNCED')
        self.assertEqual(
            bounced.json()['decision_reason'], 'Insufficient funds')
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('15.00'),
                         'a bounced cheque leaves the customer owing')
        self.assertFalse(CollectiblePayment.objects.filter(
            collectible=ledger).exists())

        cleared_after = self._decide(cheque.id, 'clear')
        self.assertEqual(cleared_after.status_code, 409)
        self.assertEqual(
            cleared_after.json()['code'], 'CHEQUE_ALREADY_DECIDED')

    def test_a_non_cheque_payment_is_not_in_the_queue(self):
        self._ring([self._cash(20)])

        response = self.client.get(CHEQUES_URL, **self.manager_auth)

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()['results'], [])


class ChequeQueueTests(ChequeTestBase):
    """`GET /cheques/` — paginated, oldest first, filterable by status."""

    def test_the_queue_lists_cheques_oldest_first_and_filters_by_status(self):
        _, older, _ = self._pending_cheque(cash=5, cheque=15)
        # A second, later cheque on its own sale.
        response = self._ring(
            [self._cash(5), cheque_tender(15, number='CHQ-2002',
                                          date='2026-12-01')])
        self.assertEqual(response.status_code, 201, response.content)
        newer = self._cheque_row(
            SalesTransaction.objects.get(pk=response.json()['id']))
        self.assertEqual(
            self._decide(older.id, 'bounce', {'reason': 'Closed account'}
                         ).status_code, 200)

        pending = self.client.get(
            f'{CHEQUES_URL}?status=PENDING', **self.manager_auth)

        self.assertEqual(pending.status_code, 200, pending.content)
        body = pending.json()
        self.assertIn('results', body, 'the queue is paginated')
        self.assertEqual([row['id'] for row in body['results']], [newer.id])
        row = body['results'][0]
        self.assertEqual(row['status'], 'PENDING')
        self.assertEqual(row['cheque_number'], 'CHQ-2002')
        self.assertEqual(row['bank'], 'BDO')
        self.assertEqual(row['cheque_date'], '2026-12-01')
        self.assertEqual(row['amount'], '15.00')
        self.assertEqual(row['customer_name'], 'Utang Corp')
        self.assertEqual(row['transaction_no'], newer.transaction.transaction_no)
        self.assertEqual(row['ledger'], newer.ledger_id)
        self.assertEqual(row['decided_by'], None)

    def test_the_queue_is_oldest_first(self):
        _, first, _ = self._pending_cheque(cash=5, cheque=15)
        response = self._ring(
            [self._cash(5), cheque_tender(15, number='CHQ-3003',
                                          date='2026-10-01')])
        later_id = self._cheque_row(
            SalesTransaction.objects.get(pk=response.json()['id'])).id

        body = self.client.get(
            f'{CHEQUES_URL}?status=PENDING', **self.manager_auth).json()

        self.assertEqual(
            [row['id'] for row in body['results']], [later_id, first.id],
            'cheque date, not arrival order: the oldest money to chase comes first')

    def test_a_cashier_cannot_read_the_cheque_queue(self):
        self.assertEqual(
            self.client.get(CHEQUES_URL, **self.cashier_auth).status_code, 403)
