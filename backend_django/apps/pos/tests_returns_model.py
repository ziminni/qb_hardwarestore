"""Phase 6 task 6A.3 — the return's shape on SalesTransaction.

Decision 15 (Customer Returns) ruled a customer return is a SalesTransaction with source='RETURN' and
NEGATIVE amounts, plus an optional original_transaction FK. These tests pin the SHAPE only; the restock
behaviour (original batch when linked, else the newest active) is task 6A.4.
"""
from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.pos.models import Customer, SalesTransaction

User = get_user_model()


class ReturnModelShapeTests(TestCase):
    def test_source_gains_a_return_member(self):
        self.assertEqual(
            [value for value, _ in SalesTransaction.Source.choices],
            ['WALK_IN', 'REQUISITION', 'RETURN'],
        )

    def test_a_transaction_can_link_to_the_sale_it_reverses(self):
        field = SalesTransaction._meta.get_field('original_transaction')
        self.assertTrue(field.null, 'a return need not know its original sale')
        self.assertEqual(field.remote_field.on_delete.__name__, 'PROTECT',
                         'a reversed sale must not be deletable out from under its return')
        self.assertEqual(field.related_model, SalesTransaction,
                         'the link is to another transaction, not to a sale document')

    def test_an_ordinary_sale_has_no_original_transaction(self):
        user = User.objects.create_superuser(username='r1', email='r@x.com', password='pass12345')
        customer = Customer.objects.create(name='Dela Cruz Construction')
        sale = SalesTransaction.objects.create(
            customer=customer, cashier=user, transaction_no='TXN-RET-1')
        self.assertIsNone(sale.original_transaction)
