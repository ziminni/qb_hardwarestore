# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests.py: without django-stubs every
# `Model.objects` is a false positive on valid Django, and the checker does not find this
# repo's pyrightconfig.json from its own working directory, so the directive travels with
# the file. `manage.py test` remains the authority on what these tests prove.
"""Inventory app tests — goods receipts, FIFO allocation, adjustments."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from .models import (
    Brand, Category, GoodsReceipt, InventoryBatch, Product, ProductVariant,
    PurchaseOrder, POItem, StockAdjustment, Supplier, UnitOfMeasure,
)
from .services import (
    allocate_fifo, apply_stock_adjustment, process_goods_receipt,
)

User = get_user_model()


class InventoryTestBase(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='stocker', email='s@x.com', password='pass12345',
            full_name='Stock Manager',
        )
        self.category = Category.objects.create(name='Cement')
        self.brand = Brand.objects.create(name='Rhino')
        self.uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        self.product = Product.objects.create(
            category=self.category, brand=self.brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=self.product, variant_name='40kg',
            base_uom=self.uom, min_stock_threshold=Decimal('5'),
        )

    def _receive(self, qty, unit_cost='50.00'):
        supplier = Supplier.objects.create(company_name='Acme Supply')
        po = PurchaseOrder.objects.create(supplier=supplier, created_by=self.user)
        item = POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal(qty),
            unit_cost=Decimal(unit_cost), received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        return po, item, receipt


class GoodsReceiptTests(InventoryTestBase):
    def test_process_creates_batches_and_completes_po(self):
        po, item, receipt = self._receive('10')
        batches = process_goods_receipt(receipt=receipt, user=self.user)
        self.assertEqual(len(batches), 1)
        self.assertEqual(batches[0].initial_qty, Decimal('10'))
        self.assertEqual(batches[0].current_qty, Decimal('10'))
        self.assertEqual(batches[0].unit_cost_landed, Decimal('50'))
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.COMPLETE)

    def test_partial_receipt_marks_po_partial(self):
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(supplier=supplier, created_by=self.user)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('10'),
            unit_cost=Decimal('50'), received_qty=Decimal('10'))
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('5'),
            unit_cost=Decimal('50'), received_qty=Decimal('0'))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        process_goods_receipt(receipt=receipt, user=self.user)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.PARTIAL)


class LegacyGoodsReceiptDeltaTests(InventoryTestBase):
    """The no-`lines` path stocks the DELTA, not the PO's running total.

    A receipt with no lines is the pre-`GoodsReceiptItem` shape, and it is still the
    shape `seed_demo` and the fixtures write: it can only look at
    `POItem.received_qty`, which is the total across EVERY receipt of the PO. So the
    quantity to batch is `received_qty` minus whatever this PO already put into stock
    for that variant. Without that subtraction a second legacy receipt on the same PO
    restocks the whole total (7 received, 4 already batched, 7 more batched = 11 units
    of stock out of 7 delivered).
    """

    def _legacy_po(self, received_qty):
        """A PO with ONE item whose received_qty is set directly (no delivery lines)."""
        supplier = Supplier.objects.create(company_name='Acme Supply')
        po = PurchaseOrder.objects.create(supplier=supplier, created_by=self.user)
        item = POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('10'),
            unit_cost=Decimal('50'), received_qty=Decimal(received_qty))
        return po, item

    def _legacy_receipt(self, po):
        return GoodsReceipt.objects.create(po=po, received_by=self.user)

    def _total_stock(self):
        return sum(
            InventoryBatch.objects.filter(variant=self.variant)
            .values_list('current_qty', flat=True),
            Decimal('0'))

    def test_a_second_legacy_receipt_batches_only_the_new_delta(self):
        po, item = self._legacy_po('4')
        first = self._legacy_receipt(po)

        first_batches = process_goods_receipt(receipt=first, user=self.user)

        self.assertEqual([b.initial_qty for b in first_batches], [Decimal('4')])
        self.assertEqual(self._total_stock(), Decimal('4'))

        # The next delivery lands on the same PO item: received_qty is now 7, and the
        # 4 already in stock must NOT be batched again.
        item.received_qty = Decimal('7')
        item.save(update_fields=['received_qty'])
        second = self._legacy_receipt(po)

        second_batches = process_goods_receipt(receipt=second, user=self.user)

        self.assertEqual([b.initial_qty for b in second_batches], [Decimal('3')],
                         'the second receipt stocks the delta (7 - 4), not the total')
        self.assertEqual(self._total_stock(), Decimal('7'),
                         '7 delivered in total, not 11')
        self.assertEqual(
            InventoryBatch.objects.filter(variant=self.variant).count(), 2,
            'two receipts, two batches')

    def test_a_legacy_receipt_with_nothing_new_stocks_nothing_and_is_consumed(self):
        po, item = self._legacy_po('4')
        process_goods_receipt(receipt=self._legacy_receipt(po), user=self.user)

        # received_qty did NOT move: there is nothing new to stock, so the answer is []
        # and no batch is minted - but the receipt HAS been consumed (processed_at), so
        # a stray retry is refused rather than re-examined.
        second = self._legacy_receipt(po)
        batches = process_goods_receipt(receipt=second, user=self.user)

        self.assertEqual(batches, [])
        self.assertEqual(InventoryBatch.objects.filter(
            variant=self.variant).count(), 1, 'no double-batch for a no-op receipt')
        self.assertEqual(self._total_stock(), Decimal('4'))
        second.refresh_from_db()
        self.assertIsNotNone(second.processed_at,
                             'a consumed receipt must stay decided')


class FifoAllocationTests(InventoryTestBase):
    def test_allocates_oldest_batch_first(self):
        _, _, r1 = self._receive('5', '40.00')
        _, _, r2 = self._receive('5', '60.00')
        process_goods_receipt(receipt=r1, user=self.user)
        process_goods_receipt(receipt=r2, user=self.user)

        allocs = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal('7'))
        self.assertEqual(len(allocs), 2)
        # Oldest (cost 40) fully consumed first
        self.assertEqual(allocs[0][1], Decimal('5'))
        self.assertEqual(allocs[1][1], Decimal('2'))
        qtys = list(InventoryBatch.objects.filter(
            variant=self.variant).order_by('unit_cost_landed')
            .values_list('current_qty', flat=True))
        self.assertEqual(qtys, [Decimal('0'), Decimal('3')])

    def test_insufficient_stock_raises(self):
        _, _, receipt = self._receive('5')
        process_goods_receipt(receipt=receipt, user=self.user)
        with self.assertRaises(ValueError):
            allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal('999'))


class StockAdjustmentTests(InventoryTestBase):
    def test_negative_adjustment_deducts_stock(self):
        _, _, receipt = self._receive('10')
        process_goods_receipt(receipt=receipt, user=self.user)
        adj = StockAdjustment.objects.create(
            variant=self.variant, user=self.user,
            adjustment_type=StockAdjustment.AdjustmentType.DAMAGE,
            qty_adjusted=Decimal('-2'),
        )
        apply_stock_adjustment(adjustment=adj)
        total = sum(InventoryBatch.objects.filter(
            variant=self.variant).values_list('current_qty', flat=True))
        self.assertEqual(total, Decimal('8'))

    def test_low_stock_alert_generated(self):
        _, _, receipt = self._receive('10')
        process_goods_receipt(receipt=receipt, user=self.user)
        adj = StockAdjustment.objects.create(
            variant=self.variant, user=self.user,
            adjustment_type=StockAdjustment.AdjustmentType.SHRINKAGE,
            qty_adjusted=Decimal('-8'),  # leaves 3 < threshold 5
        )
        apply_stock_adjustment(adjustment=adj)
        self.assertTrue(self.variant.alerts.filter(
            alert_type='LOW_STOCK').exists())

