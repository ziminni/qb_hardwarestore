"""POS app tests — process_sale, FIFO deduction, receipts, underpayment."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand, Category, GoodsReceipt, Product, ProductVariant, PurchaseOrder,
    POItem, Supplier, UnitOfMeasure, VariantUOM,
)
from apps.inventory.services import process_goods_receipt

from .models import Customer, OfficialReceipt, Payment, SalesTransaction
from .services import process_sale

User = get_user_model()


class POSTestBase(TestCase):
    def setUp(self):
        self.cashier = User.objects.create_user(
            username='cashier1', email='c@x.com', password='pass12345',
            full_name='Cashy Ir',
        )
        self.customer = Customer.objects.create(name='Juan Dela Cruz')
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
        # Two stock batches: 5 @ 40 (oldest) + 5 @ 60
        supplier = Supplier.objects.create(company_name='Acme')
        for cost, qty in (('40.00', '5'), ('60.00', '5')):
            po = PurchaseOrder.objects.create(
                supplier=supplier, created_by=self.cashier)
            POItem.objects.create(
                po=po, variant=self.variant, ordered_qty=Decimal(qty),
                unit_cost=Decimal(cost), received_qty=Decimal(qty))
            receipt = GoodsReceipt.objects.create(po=po, received_by=self.cashier)
            process_goods_receipt(receipt=receipt, user=self.cashier)


class ProcessSaleTests(POSTestBase):
    def test_sale_deducts_stock_fifo_and_creates_receipt(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('70')}],
        )
        self.assertEqual(txn.grand_total, Decimal('70'))
        self.assertEqual(txn.items.count(), 1)
        self.assertTrue(Payment.objects.filter(transaction=txn).exists())
        self.assertTrue(OfficialReceipt.objects.filter(transaction=txn).exists())
        # FIFO: oldest 5 gone, 3 remain of newest
        qtys = sorted(self.variant.batches.values_list(
            'current_qty', flat=True))
        self.assertEqual(qtys, [Decimal('0'), Decimal('3')])

    def test_underpaid_walk_in_posts_to_collectibles(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 10,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('60')}],  # 40 short
        )
        self.assertEqual(txn.grand_total, Decimal('100'))
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('40'))
        self.assertEqual(ledger.status, CollectibleLedger.Status.OPEN)

    def test_fully_paid_sale_creates_no_ledger(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 2,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('20')}],
        )
        self.assertFalse(
            CollectibleLedger.objects.filter(transaction=txn).exists())

