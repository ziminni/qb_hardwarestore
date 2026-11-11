# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/pos/tests_returns_policy.py: this checker runs
# from a working directory outside the repo, so `Model.objects` is a false positive on
# valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client's environ.

"""Phase 1d Task 2 — the server refuses a fractional quantity on a whole unit.

Decision 16 put the whole-number flag on `UnitOfMeasure` and ruled that every write path
carrying a quantity refuses a fraction for a whole unit with ONE stable code,
`WHOLE_UNIT_QUANTITY`, and writes nothing at all: no sale, no stock movement, no ledger,
no audit row, no parked cart, no document. A measured unit (KG) keeps taking two decimal
places, and a whole quantity sent as "2.00" is still a whole number.

The last three paths (purchase order, goods receipt, stock adjustment) are counted in the
variant's BASE unit, so a kg-based product still accepts 2.5 while a bag-based one does
not. The CPMS import is covered in `apps/integration/tests_import.py` (its own fixtures),
and the release rounding in `apps/requisitions/tests_releasable.py`.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.users.models import AuditLog

from .models import (
    Customer,
    HeldCart,
    HeldCartItem,
    Quotation,
    QuotationItem,
    SalesItem,
    SalesOrder,
    SalesOrderItem,
    SalesTransaction,
    Shift,
)

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
TRANSACTIONS_URL = '/api/v1/transactions/'
HELD_CARTS_URL = '/api/v1/held-carts/'
QUOTATIONS_URL = '/api/v1/quotations/'
SALES_ORDERS_URL = '/api/v1/sales-orders/'
PURCHASE_ORDERS_URL = '/api/v1/purchase-orders/'
GOODS_RECEIPTS_URL = '/api/v1/goods-receipts/'
ADJUSTMENTS_URL = '/api/v1/adjustments/'

CODE = 'WHOLE_UNIT_QUANTITY'


class WholeUnitBase(TestCase):
    """One whole unit (BAG) and one measured unit (KG), 500 base units of each in stock."""

    def setUp(self):
        self.client = APIClient()
        # Random per run, like `tests_scoping.py`: the value authenticates nothing outside
        # this throwaway test database.
        self.password = get_random_string(16)
        # A superuser keeps this suite about the RULE; the role wiring of each endpoint
        # is pinned by its own suite, and `RoleRequired` lets a superuser through.
        self.user = User.objects.create_superuser(
            username='wu_admin', email='wu@x.com', password=self.password)
        self.shift = Shift.objects.create(
            cashier=self.user, opening_float=Decimal('5000'))
        self.customer = Customer.objects.create(
            name='Dela Cruz Construction',
            customer_type=Customer.Type.CONTRACTOR)
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        # get_or_create on the canonical codes: migration 0008 puts these rows in every
        # database, so creating them here would collide with it.
        self.uom_bag, _ = UnitOfMeasure.objects.get_or_create(
            code='BAG', defaults={'name': 'Bag', 'is_whole': True})
        self.uom_kg, _ = UnitOfMeasure.objects.get_or_create(
            code='KG', defaults={'name': 'Kilogram', 'is_whole': False})
        self.variant_bag = self._variant(category, brand, 'Portland Cement', self.uom_bag)
        self.vuom_bag = self._vuom(self.variant_bag, self.uom_bag, '10')
        self.variant_kg = self._variant(category, brand, 'Washed Sand', self.uom_kg)
        self.vuom_kg = self._vuom(self.variant_kg, self.uom_kg, '5')
        self._receive(self.variant_bag, '500')
        self._receive(self.variant_kg, '500')

    # -- fixture helpers ---------------------------------------------------
    def _variant(self, category, brand, name, uom, variant_name='standard'):
        product = Product.objects.create(
            category=category, brand=brand, base_name=name)
        return ProductVariant.objects.create(
            product=product, variant_name=variant_name, base_uom=uom)

    def _vuom(self, variant, uom, price):
        return VariantUOM.objects.create(
            variant=variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal(price))

    def _receive(self, variant, qty, cost='5'):
        supplier, _ = Supplier.objects.get_or_create(company_name='Acme Supply')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.user,
            status=PurchaseOrder.Status.ORDERED)
        item = POItem.objects.create(
            po=po, variant=variant, ordered_qty=Decimal(qty),
            unit_cost=Decimal(cost), received_qty=Decimal(qty))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        process_goods_receipt(receipt=receipt, user=self.user)
        return po, item

    def _login(self):
        res = self.client.post(
            LOGIN_URL, {'username': self.user.username, 'password': self.password},
            format='json')
        self.assertEqual(res.status_code, 200, res.data)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {res.data["access"]}')

    # -- shared assertions -------------------------------------------------
    def _rows(self):
        """Every row a refused write could leave behind, as one comparable tuple."""
        return (
            SalesTransaction.objects.count(),
            SalesItem.objects.count(),
            HeldCart.objects.count(),
            HeldCartItem.objects.count(),
            Quotation.objects.count(),
            QuotationItem.objects.count(),
            SalesOrder.objects.count(),
            SalesOrderItem.objects.count(),
            PurchaseOrder.objects.count(),
            POItem.objects.count(),
            GoodsReceipt.objects.count(),
            GoodsReceiptItem.objects.count(),
            StockAdjustment.objects.count(),
            AuditLog.objects.count(),
            sum(InventoryBatch.objects.values_list('current_qty', flat=True),
                Decimal('0')),
        )

    def _assert_refused(self, response, before):
        """400 with the stable code, and not one row or batch moved."""
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), CODE, response.data)
        detail = response.data.get('detail') or ''
        self.assertIn('whole', detail.lower(), response.data)
        self.assertEqual(self._rows(), before,
                         'a refused whole-unit quantity must write nothing')


class SaleTests(WholeUnitBase):
    """`process_sale` -> `_validated_sale_lines`, the one validator the till shares."""

    def setUp(self):
        super().setUp()
        self._login()

    def _post(self, vuom, qty):
        return self.client.post(TRANSACTIONS_URL, {
            'customer': self.customer.id,
            'items': [{'variant_id': vuom.id, 'qty': qty}],
            'payments': [{'method': 'CASH', 'amount_tendered': '1000'}],
        }, format='json')

    def test_a_fractional_quantity_on_a_whole_unit_is_refused(self):
        before = self._rows()

        response = self._post(self.vuom_bag, '1.5')

        self._assert_refused(response, before)

    def test_the_detail_names_the_line_the_product_and_the_unit(self):
        response = self._post(self.vuom_bag, '1.5')

        detail = response.data['detail']
        self.assertIn('Line 1', detail, detail)
        self.assertIn('Portland Cement', detail, detail)
        self.assertIn('BAG', detail, detail)

    def test_a_whole_quantity_sent_as_two_decimals_passes(self):
        response = self._post(self.vuom_bag, '2.00')

        self.assertEqual(response.status_code, 201, response.data)

    def test_a_measured_unit_still_accepts_two_decimal_places(self):
        response = self._post(self.vuom_kg, '2.50')

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(SalesTransaction.objects.get().items.get().qty,
                         Decimal('2.50'))


class HeldCartTests(WholeUnitBase):
    """Parking a cart refuses before the cart row exists; completing one goes through
    `process_sale`, so the same validator answers."""

    def setUp(self):
        super().setUp()
        self._login()

    def _hold(self, vuom, qty):
        return self.client.post(HELD_CARTS_URL, {
            'notes': 'test hold',
            'customer': self.customer.id,
            'items': [{'variant_uom': vuom.id, 'qty': qty, 'unit_price': '10.00'}],
        }, format='json')

    def test_holding_a_fractional_whole_unit_writes_no_cart(self):
        before = self._rows()

        response = self._hold(self.vuom_bag, '1.5')

        self._assert_refused(response, before)

    def test_holding_a_whole_quantity_sent_as_two_decimals_passes(self):
        self.assertEqual(self._hold(self.vuom_bag, '2.00').status_code, 201)

    def test_holding_a_measured_unit_accepts_two_decimal_places(self):
        self.assertEqual(self._hold(self.vuom_kg, '2.50').status_code, 201)

    def test_completing_a_cart_holding_a_fraction_rings_nothing(self):
        # Written straight through the ORM: the refusal at COMPLETE has to stand on its
        # own, because a cart can already be on the shelf from before this rule.
        cart = HeldCart.objects.create(cashier=self.user, customer=self.customer)
        HeldCartItem.objects.create(
            cart=cart, variant_uom=self.vuom_bag, qty=Decimal('1.50'),
            unit_price=Decimal('10'))
        before = self._rows()

        response = self.client.post(
            f'{HELD_CARTS_URL}{cart.pk}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '1000'}]},
            format='json')

        self._assert_refused(response, before)
        self.assertTrue(HeldCart.objects.filter(pk=cart.pk).exists(),
                        'a refused completion keeps the cart')


class ReturnTests(WholeUnitBase):
    """`process_return` shares `_validated_sale_lines`, so one check covers both."""

    def setUp(self):
        super().setUp()
        self._login()

    def _sell(self, vuom, qty='10'):
        response = self.client.post(TRANSACTIONS_URL, {
            'customer': self.customer.id,
            'items': [{'variant_id': vuom.id, 'qty': qty}],
            'payments': [{'method': 'CASH', 'amount_tendered': '1000'}],
        }, format='json')
        self.assertEqual(response.status_code, 201, response.data)
        return SalesTransaction.objects.get(pk=response.data['id'])

    def test_a_fractional_return_on_a_whole_unit_is_refused(self):
        original = self._sell(self.vuom_bag)
        before = self._rows()

        response = self.client.post(TRANSACTIONS_URL, {
            'customer': self.customer.id,
            'source': 'RETURN',
            'original_transaction': original.id,
            'reason': 'damaged packaging',
            'items': [{'variant_id': self.vuom_bag.id, 'qty': '1.5'}],
            'payment_method': 'CASH',
        }, format='json')

        self._assert_refused(response, before)


class QuotationTests(WholeUnitBase):
    def setUp(self):
        super().setUp()
        self._login()

    def _post(self, vuom, qty):
        return self.client.post(QUOTATIONS_URL, {
            'customer': self.customer.id,
            'items': [{'variant_uom': vuom.id, 'qty': qty, 'unit_price': '10.00'}],
        }, format='json')

    def test_a_fractional_quote_on_a_whole_unit_is_refused(self):
        before = self._rows()

        response = self._post(self.vuom_bag, '1.5')

        self._assert_refused(response, before)

    def test_a_whole_quantity_sent_as_two_decimals_passes(self):
        self.assertEqual(self._post(self.vuom_bag, '2.00').status_code, 201)

    def test_a_measured_unit_accepts_two_decimal_places(self):
        self.assertEqual(self._post(self.vuom_kg, '2.50').status_code, 201)


class SalesOrderTests(WholeUnitBase):
    def setUp(self):
        super().setUp()
        self._login()

    def _post(self, vuom, qty):
        return self.client.post(SALES_ORDERS_URL, {
            'customer': self.customer.id,
            'items': [{'variant_uom': vuom.id, 'qty': qty, 'unit_price': '10.00'}],
        }, format='json')

    def test_a_fractional_order_on_a_whole_unit_is_refused(self):
        before = self._rows()

        response = self._post(self.vuom_bag, '1.5')

        self._assert_refused(response, before)

    def test_a_whole_quantity_sent_as_two_decimals_passes(self):
        self.assertEqual(self._post(self.vuom_bag, '2.00').status_code, 201)

    def test_a_measured_unit_accepts_two_decimal_places(self):
        self.assertEqual(self._post(self.vuom_kg, '2.50').status_code, 201)


class StockCountedInBaseUnitsTests(WholeUnitBase):
    """Purchase order, goods receipt and adjustment count the variant's BASE unit, so a
    kg product still takes 2.5 while a bag product takes whole bags only."""

    def setUp(self):
        super().setUp()
        self._login()
        self.supplier = Supplier.objects.create(company_name='Cebu Building Supply')

    def _po(self, variant, qty):
        return self.client.post(PURCHASE_ORDERS_URL, {
            'supplier': self.supplier.pk,
            'items': [{'variant': variant.pk, 'ordered_qty': qty,
                       'unit_cost': '5.00'}],
        }, format='json')

    def test_a_fractional_ordered_quantity_on_a_whole_base_unit_is_refused(self):
        before = self._rows()

        response = self._po(self.variant_bag, '1.5')

        self._assert_refused(response, before)

    def test_a_kg_product_accepts_a_fractional_ordered_quantity(self):
        self.assertEqual(self._po(self.variant_kg, '2.50').status_code, 201)

    def _receipt(self, po_item, qty):
        return self.client.post(GOODS_RECEIPTS_URL, {
            'po': po_item.po_id,
            'items': [{'po_item': po_item.pk, 'qty': qty}],
        }, format='json')

    def _ordered_item(self, variant, qty='10'):
        po = PurchaseOrder.objects.create(
            supplier=self.supplier, created_by=self.user,
            status=PurchaseOrder.Status.ORDERED)
        return POItem.objects.create(
            po=po, variant=variant, ordered_qty=Decimal(qty),
            unit_cost=Decimal('5'), received_qty=Decimal('0'))

    def test_a_fractional_receipt_on_a_whole_base_unit_is_refused(self):
        item = self._ordered_item(self.variant_bag)
        before = self._rows()
        batches_before = InventoryBatch.objects.filter(
            variant=self.variant_bag).count()

        response = self._receipt(item, '1.5')

        self._assert_refused(response, before)
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal('0'))
        self.assertEqual(InventoryBatch.objects.filter(
            variant=self.variant_bag).count(), batches_before,
            'a refused delivery stocks nothing')

    def test_a_kg_product_accepts_a_fractional_receipt(self):
        item = self._ordered_item(self.variant_kg)

        self.assertEqual(self._receipt(item, '2.50').status_code, 201)

    def _adjust(self, variant, qty):
        return self.client.post(ADJUSTMENTS_URL, {
            'variant': variant.pk,
            'adjustment_type': StockAdjustment.AdjustmentType.CORRECTION,
            'qty_adjusted': qty,
        }, format='json')

    def test_a_fractional_adjustment_on_a_whole_base_unit_is_refused(self):
        before = self._rows()

        response = self._adjust(self.variant_bag, '1.5')

        self._assert_refused(response, before)

    def test_a_kg_product_accepts_a_fractional_adjustment(self):
        self.assertEqual(self._adjust(self.variant_kg, '2.50').status_code, 201)
