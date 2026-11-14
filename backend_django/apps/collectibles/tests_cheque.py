# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/collectibles/tests.py: `Model.objects` and the
# `**self.auth` header splat are false positives on valid Django from a checker whose
# working directory is outside the repo. `reportMissingImports` is off for the same
# reason apps/pos/tests_discount_vat.py turns it off: the checker resolves no environment
# here, so every Django and DRF import reads as unresolved.

"""Phase 4 Task B2 (decision 18) — a cheque tendered against an utang.

The utang payment dialog offers the same methods the till does, so `payment_method`
takes the SHARED codes (`Payment.Method`) and nothing else. Paying by cheque records the
cheque and leaves the debt standing: money that has not cleared is not money received,
so `balance_due` does not move until a Store Manager or Admin clears it
(`POST /api/v1/cheques/{id}/clear/`, pinned in apps/pos/tests_cheque.py).
"""

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.pos.models import Customer, Payment, SalesTransaction

User = get_user_model()

PAYMENTS_URL = '/api/v1/ledger-payments/'
LOGIN_URL = '/api/v1/auth/login/'


class UtangChequeTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.password = get_random_string(16)
        self.user = User.objects.create_user(
            username='chq_collector', email='cc@example.com',
            password=self.password)
        self.user.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.customer = Customer.objects.create(
            name='Utang Corp', customer_type=Customer.Type.REGULAR)
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.user,
            transaction_no='TRX-CHQ-0001',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )

    def _post(self, **body):
        login = self.client.post(
            LOGIN_URL, {'username': 'chq_collector', 'password': self.password},
            format='json')
        auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}
        return self.client.post(PAYMENTS_URL, body, format='json', **auth)

    def _cheque_body(self, **overrides):
        body = {
            'collectible': self.ledger.id,
            'amount_paid': '200.00',
            'payment_method': 'CHEQUE',
            'cheque_number': 'CHQ-9001',
            'bank': 'BPI',
            'cheque_date': '2026-11-25',
        }
        body.update(overrides)
        return body

    def test_a_utang_cheque_is_pending_and_the_debt_stands(self):
        response = self._post(**self._cheque_body())

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body['status'], 'PENDING')
        self.assertEqual(body['amount'], '200.00')
        self.assertEqual(body['cheque_number'], 'CHQ-9001')
        self.assertEqual(body['bank'], 'BPI')
        self.assertEqual(body['cheque_date'], '2026-11-25')
        self.assertEqual(body['ledger'], self.ledger.id)
        self.assertEqual(body['customer_name'], 'Utang Corp')

        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('500.00'),
                         'an uncleared cheque is not money received')
        self.assertFalse(CollectiblePayment.objects.filter(
            collectible=self.ledger).exists())
        cheque = Payment.objects.get(method=Payment.Method.CHEQUE)
        self.assertEqual(cheque.transaction_id, self.txn.id)
        self.assertEqual(cheque.ledger_id, self.ledger.id)

    def test_a_utang_cheque_needs_its_number_bank_and_date(self):
        response = self._post(**self._cheque_body(bank=''))

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'CHEQUE_DETAILS_REQUIRED')
        self.assertFalse(Payment.objects.exists())

    def test_a_utang_cheque_above_the_balance_is_refused(self):
        response = self._post(**self._cheque_body(amount_paid='600.00'))

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'PAYMENT_EXCEEDS_BALANCE')
        self.assertFalse(Payment.objects.exists())
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('500.00'))

    def test_cash_still_moves_the_balance(self):
        response = self._post(
            collectible=self.ledger.id, amount_paid='200.00',
            payment_method='CASH')

        self.assertEqual(response.status_code, 201, response.content)
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('300.00'))
        self.assertEqual(self.ledger.status, CollectibleLedger.Status.PARTIAL)

    def test_the_shared_choices_are_the_contract(self):
        # The utang dialog's methods ARE the till's methods, in one place: the model
        # field declares the shared choices, and a label ('Cash') is still refused.
        self.assertEqual(
            list(CollectiblePayment._meta.get_field('payment_method').choices),
            list(Payment.Method.choices))
        refused = self._post(
            collectible=self.ledger.id, amount_paid='200.00',
            payment_method='Cash')
        self.assertEqual(refused.status_code, 400, refused.content)
        self.assertEqual(refused.json()['code'], 'INVALID_PAYMENT_METHOD')
