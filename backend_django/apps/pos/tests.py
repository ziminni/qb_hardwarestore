"""POS app tests — process_sale, FIFO deduction, receipts, underpayment."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
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
            # nosemgrep: the hardcoded-password rule fires on a test fixture. This
            # password authenticates nothing: it exists only in the throwaway test
            # database and is posted straight back to the login endpoint below.
            # It appears nowhere in the app, and it is the established fixture in all
            # five test modules. Indirection would only make the login unreadable.
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



TRANSACTIONS_URL = '/api/v1/transactions/'
LOGIN_URL = '/api/v1/auth/login/'


class CheckoutApiTests(POSTestBase):
    """Phase 3 Task 2 (decision 06, section 3) - the failure contract.

    `process_sale` reaches `allocate_fifo`, which raises ValueError when stock is
    short. Nothing catches it and no DRF EXCEPTION_HANDLER is configured, so the
    most common expected failure - a cashier asking for more than is on the shelf -
    came back as HTTP 500. Decision 06 calls that "an expected outcome, not a
    crash" and requires distinct UI treatment, which a 500 cannot give: the client
    cannot tell it apart from the server being broken.

    Contract under test: HTTP 400 with a stable machine-readable code.
    """

    def setUp(self):
        super().setUp()
        # Roles are Django Groups, not a field on the user (see permissions.ROLE_CASHIER
        # and User.role_names). Without this the endpoint answers 403 before the code
        # under test runs, and the test would "fail" for the wrong reason.
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'cashier1', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200, 'the cashier must be able to log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def test_the_fixture_can_actually_reach_the_view(self):
        # A guard on the harness itself: if this 403s, every other assertion in this
        # class is testing the permission layer rather than the failure contract.
        self.assertNotEqual(self._post(1).status_code, 403)

    def _payload(self, qty):
        # Stock on hand is 10 (two batches of 5). `variant_id` is a VariantUOM id,
        # which is what the API resolves it as - see Task 1.
        return {
            'customer': self.customer.id,
            'source': 'WALK_IN',
            'items': [{'variant_id': self.vuom.id, 'qty': qty,
                       'unit_price': '10.00'}],
            'payments': [{'method': 'CASH', 'amount_tendered': '100.00'}],
        }

    def _post(self, qty):
        return self.client.post(
            TRANSACTIONS_URL, data=self._payload(qty),
            content_type='application/json', **self.auth)

    def test_insufficient_stock_is_a_400_with_a_stable_code(self):
        # 10 on hand; ask for 11.
        response = self._post(11)
        self.assertEqual(
            response.status_code, 400,
            'insufficient stock is an expected outcome and must not be a 500')
        body = response.json()
        self.assertEqual(body['code'], 'INSUFFICIENT_STOCK')
        self.assertIn('shortfall', body, 'the client needs the shortfall to explain it')

    def test_a_rejected_sale_rolls_back_entirely(self):
        # transaction.atomic() means a failure leaves NOTHING behind: the client is
        # allowed to keep its cart precisely because the server state is unchanged.
        txns_before = SalesTransaction.objects.count()
        self._post(11)
        self.assertEqual(SalesTransaction.objects.count(), txns_before)
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(Payment.objects.exists())
        self.assertEqual(
            sum(self.variant.batches.values_list('current_qty', flat=True)),
            Decimal('10'),
            'a rejected sale must not have moved any stock')

    def test_a_valid_sale_still_returns_201_with_the_finished_transaction(self):
        # Decision 06 section 1: the response IS the finished transaction, so the
        # receipt screen needs no second fetch.
        response = self._post(2)
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertIn('items', body)
        self.assertIn('payments', body)
        self.assertIn('receipt', body)
        self.assertEqual(body['grand_total'], '20.00')
