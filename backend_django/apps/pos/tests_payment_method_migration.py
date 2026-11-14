# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""C2 — the data migration that rewrites legacy payment method LABELS to CODES.

The live database carries pre-Phase-1 rows whose `Payment.method` is the label the old
till displayed ('Cash'). `compute_z_reading` keys `by_method` on `'CASH'`, so those
payments were invisible to `cash_sales` and the expected drawer was short.

The migration is imported by module name (its own file IS the contract) and run against
real rows, so the test exercises the same function the migration runner calls.
"""

import importlib
from datetime import date
from decimal import Decimal

from django.apps import apps as django_apps
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils.crypto import get_random_string

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.pos.models import Customer, Payment, SalesTransaction, Shift
from apps.pos.services import compute_z_reading

User = get_user_model()

migration = importlib.import_module(
    'apps.pos.migrations.0010_normalise_payment_methods')


class PaymentMethodNormalisationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='pm_owner', email='pm@example.com',
            password=get_random_string(16))
        self.customer = Customer.objects.create(name='Legacy Corp')
        self.txn = SalesTransaction.objects.create(
            customer=self.customer, cashier=self.user,
            transaction_no='TRX-LEGACY-0001',
            vatable_sales=Decimal('500'), grand_total=Decimal('500'))

    def _payment(self, method, amount='100'):
        return Payment.objects.create(
            transaction=self.txn, method=method,
            amount_tendered=Decimal(amount))

    def _ledger(self):
        return CollectibleLedger.objects.create(
            customer=self.customer, transaction=self.txn,
            original_amount=Decimal('500'), balance_due=Decimal('500'),
            due_date=date.today(), status=CollectibleLedger.Status.OPEN,
        )

    def test_labels_become_codes(self):
        cases = {
            'Cash': 'CASH',
            'Card': 'CARD',
            'GCash': 'GCASH',
            'Bank Transfer': 'BANK_TRANSFER',
            'bank_transfer': 'BANK_TRANSFER',
            'CASH': 'CASH',
        }
        for label in cases:
            self._payment(label)

        migration.normalise_payment_methods(django_apps, None)

        self.assertEqual(
            sorted(Payment.objects.values_list('method', flat=True)),
            sorted(cases.values()))

    def test_collectible_payments_are_normalised_too_and_RETURN_CREDIT_is_left_alone(
            self):
        ledger = self._ledger()
        for method in ('Cash', 'RETURN_CREDIT', 'GCASH'):
            CollectiblePayment.objects.create(
                collectible=ledger, processed_by=self.user,
                amount_paid=Decimal('10'), payment_method=method)

        migration.normalise_payment_methods(django_apps, None)

        self.assertEqual(
            sorted(CollectiblePayment.objects.values_list(
                'payment_method', flat=True)),
            ['CASH', 'GCASH', 'RETURN_CREDIT'])

    def test_an_unknown_method_is_left_as_it_is(self):
        # A method this map does not know is a fact about the data, not a guess to make.
        self._payment('MAYA')

        migration.normalise_payment_methods(django_apps, None)

        self.assertEqual(Payment.objects.get().method, 'MAYA')

    def test_running_it_twice_changes_nothing_further(self):
        self._payment('Cash')

        migration.normalise_payment_methods(django_apps, None)
        migration.normalise_payment_methods(django_apps, None)

        self.assertEqual(Payment.objects.get().method, 'CASH')

    def test_the_z_reading_now_counts_the_money_it_used_to_miss(self):
        # The reason the migration exists: a label-valued payment was absent from
        # cash_sales, so the drawer total was short by money the till took.
        shift = Shift.objects.create(
            cashier=self.user, opening_float=Decimal('1000'))
        self.txn.shift = shift
        self.txn.save(update_fields=['shift'])
        self._payment('Cash', amount='250')

        before = compute_z_reading(shift)
        self.assertEqual(before['cash_sales'], '0.00', 'the defect being fixed')

        migration.normalise_payment_methods(django_apps, None)

        after = compute_z_reading(shift)
        self.assertEqual(after['cash_sales'], '250.00')
        self.assertEqual(after['expected_drawer'], '1250.00')
