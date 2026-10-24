# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""C2 — payment method codes on the wire, labels only in the database's past.

Two defects, one cause: `Payment.method` was a code, but nothing stopped a CLIENT from
posting the label it displays.

* `POST /api/v1/ledger-payments/` accepted `payment_method` as free text, so the
  receivables screens could record a payment as `'Cash'` or even `'RETURN_CREDIT'` — the
  latter being the server's own marker for "this debt was settled by a return", which a
  client must never be able to forge.
* The live database already carries pre-Phase-1 rows whose method is a label
  (`'Cash'`), which `compute_z_reading` silently MISSES: it keys `by_method` on
  `'CASH'`, so those payments are absent from `cash_sales` and the expected drawer.

The ledger-payment refusals are pinned here; the data normalisation is pinned in
`tests_payment_method_migration.py`.
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


class LedgerPaymentMethodTests(TestCase):
    """The ledger-payment create path takes CODES only (CASH/CARD/GCASH/BANK_TRANSFER)."""

    def setUp(self):
        self.client = APIClient()
        self.password = get_random_string(16)
        self.cashier = User.objects.create_user(
            username='pm_cashier', email='pm@example.com',
            password=self.password)
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.customer = Customer.objects.create(
            name='Utang Corp', customer_type=Customer.Type.REGULAR)
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no='TRX-PM-0001',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))
        self.ledger = CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )

    def _pay(self, method):
        login = APIClient().post(
            LOGIN_URL,
            {'username': self.cashier.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return self.client.post(
            PAYMENTS_URL,
            {'collectible': self.ledger.pk, 'amount_paid': '200',
             'payment_method': method},
            format='json',
            HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    def test_a_wire_code_is_accepted(self):
        response = self._pay(Payment.Method.CASH)

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(CollectiblePayment.objects.get().payment_method, 'CASH')

    def test_a_display_label_is_refused(self):
        # The same seam as the till's: 'Cash' is what the screen shows, 'CASH' is what
        # the books hold. A label reaching the ledger makes the receivable's method
        # unreadable by every consumer that branches on the code.
        response = self._pay('Cash')

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'INVALID_PAYMENT_METHOD')
        self.assertEqual(CollectiblePayment.objects.count(), 0)
        self.ledger.refresh_from_db()
        self.assertEqual(self.ledger.balance_due, Decimal('500'))

    def test_return_credit_is_server_only(self):
        # `process_return` writes RETURN_CREDIT itself to explain a debt settled by
        # goods coming back. A client that can post it can erase a receivable with no
        # money and no goods.
        response = self._pay('RETURN_CREDIT')

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'INVALID_PAYMENT_METHOD')
        self.assertEqual(CollectiblePayment.objects.count(), 0)

    def test_every_offered_code_is_accepted(self):
        for method in ('CASH', 'CARD', 'GCASH', 'BANK_TRANSFER'):
            with self.subTest(method=method):
                CollectiblePayment.objects.all().delete()
                self.ledger.refresh_from_db()
                self.ledger.balance_due = Decimal('500')
                self.ledger.status = CollectibleLedger.Status.OPEN
                self.ledger.save(update_fields=['balance_due', 'status'])

                response = self._pay(method)

                self.assertEqual(response.status_code, 201, response.content)
                self.assertEqual(
                    CollectiblePayment.objects.get().payment_method, method)
