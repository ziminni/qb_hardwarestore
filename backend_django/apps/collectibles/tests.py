"""Collectibles tests — ledger math on payment posting."""

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.pos.models import Customer, SalesTransaction

from .models import CollectibleLedger, CollectiblePayment

User = get_user_model()


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

