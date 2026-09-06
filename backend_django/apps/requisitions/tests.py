"""Requisitions tests — approval flow, tokens, material release."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand, Category, GoodsReceipt, Product, ProductVariant, PurchaseOrder,
    POItem, Supplier, UnitOfMeasure, VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.models import Customer, SalesTransaction

from .models import MaterialToken, Project, Requisition, RequisitionItem
from .services import (
    approve_requisition, reject_requisition, release_materials,
    submit_requisition, verify_token,
)

User = get_user_model()


class RequisitionTestBase(TestCase):
    def setUp(self):
        self.manager = User.objects.create_user(
            username='manager1', email='m@x.com', password='pass12345')
        self.foreman = User.objects.create_user(
            username='foreman1', email='f@x.com', password='pass12345')
        self.cashier = User.objects.create_user(
            username='cashier1', email='c@x.com', password='pass12345')
        self.customer = Customer.objects.create(name='Builder Corp')
        self.project = Project.objects.create(
            name='House Build', customer=self.customer)
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('100'),
            unit_cost=Decimal('40'), received_qty=Decimal('100'))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

        self.requisition = Requisition.objects.create(
            project=self.project, requested_by=self.foreman)
        self.req_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant=self.variant,
            quantity=Decimal('10'))


class RequisitionFlowTests(RequisitionTestBase):
    def test_full_flow_submit_approve_release(self):
        submit_requisition(requisition=self.requisition)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.SUBMITTED)

        token = approve_requisition(
            requisition=self.requisition, approver=self.manager)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.APPROVED)
        self.assertEqual(self.requisition.approved_by, self.manager)
        self.assertEqual(token.requisition, self.requisition)

        # Token verify shows remaining qty before release
        info = verify_token(token_value=str(token.token))
        self.assertEqual(info['items'][0]['remaining'], '10.00')

        result = release_materials(
            token_value=str(token.token), cashier=self.cashier)

        # Stock deducted via FIFO
        total = sum(self.variant.batches.values_list(
            'current_qty', flat=True))
        self.assertEqual(total, Decimal('90'))
        # Sales transaction created with requisition source
        txn = SalesTransaction.objects.get(id=result['transaction_id'])
        self.assertEqual(txn.source, SalesTransaction.Source.REQUISITION)
        self.assertEqual(txn.grand_total, Decimal('100'))
        # Ledger posted for the construction firm
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('100'))
        # Token consumed, requisition released
        token.refresh_from_db()
        self.assertTrue(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)

    def test_cannot_approve_draft_requisition(self):
        with self.assertRaises(ValueError):
            approve_requisition(
                requisition=self.requisition, approver=self.manager)

    def test_cannot_submit_twice(self):
        submit_requisition(requisition=self.requisition)
        with self.assertRaises(ValueError):
            submit_requisition(requisition=self.requisition)

    def test_reject_sets_status(self):
        submit_requisition(requisition=self.requisition)
        reject_requisition(requisition=self.requisition, approver=self.manager)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.REJECTED)

    def test_token_cannot_be_used_twice(self):
        submit_requisition(requisition=self.requisition)
        token = approve_requisition(
            requisition=self.requisition, approver=self.manager)
        release_materials(token_value=str(token.token), cashier=self.cashier)
        with self.assertRaises(ValueError):
            release_materials(token_value=str(token.token),
                              cashier=self.cashier)

    def test_invalid_token_rejected(self):
        with self.assertRaises(ValueError):
            verify_token(token_value='not-a-uuid')

