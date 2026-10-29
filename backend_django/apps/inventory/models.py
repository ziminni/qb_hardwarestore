# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIncompatibleMethodOverride=false
#
# Same directive and reason as apps/pos/models.py: the checker resolves its config from
# its WORKING DIRECTORY and does not run inside this repo here, so pyrightconfig.json is
# not found and this travels with the file. Without django-stubs every
# `Model.objects`, FK-attribute read (`self.po_item.variant`) and
# `BooleanField(default=True)` is a false positive on valid Django, and so is an
# `__str__` whose return type pyright reads off a `CharField`. Django's own
# `manage.py check` and the test run remain the authority.
"""Inventory Module — Product Catalog, Purchasing & Stock (Phase 2).

ERD mapping:
    CATEGORY          → Category
    BRAND             → Brand
    PRODUCT           → Product
    PRODUCT_VARIANT   → ProductVariant
    UNIT_OF_MEASURE   → UnitOfMeasure
    VARIANT_UOM       → VariantUOM
    SUPPLIER          → Supplier
    PURCHASE_ORDER    → PurchaseOrder
    PO_ITEM           → POItem
    GOODS_RECEIPT     → GoodsReceipt
    GOODS_RECEIPT_ITEM → GoodsReceiptItem
    INVENTORY_BATCH   → InventoryBatch
    STOCK_ADJUSTMENT  → StockAdjustment
    SYSTEM_ALERT      → SystemAlert
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models, transaction
from django.db.models.functions import Upper


# =========================================================================
# Selling-unit codes  (Phase 6, decisions 11/12/16)
# =========================================================================

def gs1_check_digit(digits: str) -> int:
    """The GS1 mod-10 check digit for `digits` (weights 3,1,3,1… from the RIGHTMOST).

    One function for both code kinds: it validates a factory EAN (`4800016123450`) and
    it derives an internal code from a selling unit's id, so the printed label and the
    scan agree on the same arithmetic.
    """
    total = sum(
        int(char) * (3 if position % 2 == 0 else 1)
        for position, char in enumerate(reversed(digits)))
    return (10 - total % 10) % 10


def derived_code(pk: int) -> str:
    """This shop's own code for a selling unit: `QB{id:06}-{check}`, e.g. QB000013-0.

    Derived, never random: unique by construction (ids are unique) and recomputable
    during an audit. The `QB` prefix is reserved so nobody can hand-type a code that a
    future unit will be given automatically.
    """
    digits = f'{pk:06d}'
    return f'QB{digits}-{gs1_check_digit(digits)}'


def normalise_barcode(value) -> str:
    """Trim + upper — the single normalisation the API, the seed and the till share.

    `'  qb000013-0 '` and `'QB000013-0'` are the same code, so the stored value and a
    scanned value compare equal without either side guessing.
    """
    return (value or '').strip().upper()


# =========================================================================
# Catalog master data  (Phase 1)
# =========================================================================

class Category(models.Model):
    name = models.CharField(max_length=100, unique=True, db_index=True)
    # Phase 4 Task 1: the archive replaces the DELETE a clerk wanted. A category is
    # PROTECT-referenced by its products, so deleting it was a 500, and deleting the
    # products first would have erased their sales history. Archiving hides the category
    # from the "new product" picker and leaves its products SELLABLE - the till prices a
    # line from the selling unit, never from the category.
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_category'
        verbose_name_plural = 'categories'
        ordering = ['name']

    def __str__(self):
        return self.name


class Brand(models.Model):
    name = models.CharField(max_length=100, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_brand'
        ordering = ['name']

    def __str__(self):
        return self.name


class UnitOfMeasure(models.Model):
    code = models.CharField(max_length=20, unique=True, db_index=True)
    name = models.CharField(max_length=50)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_uom'
        verbose_name = 'unit of measure'
        verbose_name_plural = 'units of measure'
        ordering = ['code']

    def __str__(self):
        return f'{self.code} ({self.name})'


class Product(models.Model):
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name='products')
    brand = models.ForeignKey(
        Brand, on_delete=models.PROTECT, related_name='products')
    base_name = models.CharField(max_length=255, db_index=True)
    description = models.TextField(blank=True, default='')
    image_url = models.URLField(blank=True, default='')
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_product'
        ordering = ['base_name']
        indexes = [
            models.Index(fields=['category', 'is_active']),
            models.Index(fields=['brand']),
        ]

    def __str__(self):
        return self.base_name


class ProductVariant(models.Model):
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name='variants')
    variant_name = models.CharField(max_length=255, db_index=True)
    base_uom = models.ForeignKey(
        UnitOfMeasure, on_delete=models.PROTECT, related_name='+',
        help_text='Smallest divisible unit for stock tracking.')
    min_stock_threshold = models.DecimalField(
        max_digits=12, decimal_places=2, default=0,
        validators=[MinValueValidator(0)])
    max_stock_level = models.DecimalField(
        max_digits=12, decimal_places=2, default=0,
        validators=[MinValueValidator(0)])
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_product_variant'
        ordering = ['product__base_name', 'variant_name']
        indexes = [models.Index(fields=['product', 'is_active'])]

    def __str__(self):
        return f'{self.product.base_name} — {self.variant_name}'


class VariantUOM(models.Model):
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.CASCADE, related_name='selling_uoms')
    uom = models.ForeignKey(
        UnitOfMeasure, on_delete=models.PROTECT, related_name='+')
    barcode_qr = models.CharField(
        max_length=100, blank=True, default='', db_index=True)
    conversion_factor = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))])
    default_selling_price = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_variant_uom'
        verbose_name = 'variant UOM'
        verbose_name_plural = 'variant UOMs'
        ordering = ['variant', 'uom']
        constraints = [
            models.UniqueConstraint(
                fields=['variant', 'uom'], name='uq_variant_uom'),
            # Phase 6 (decision 11): one scannable code per selling unit, compared
            # case-insensitively because every write normalises to upper. Blanks are left
            # out of the condition so the constraint never blocks a row that has no code
            # yet - `save()` gives it one straight away (decision 16).
            models.UniqueConstraint(
                Upper('barcode_qr'), condition=~models.Q(barcode_qr=''),
                name='uniq_variantuom_barcode'),
        ]

    def __str__(self):
        return f'{self.variant} @ {self.uom.code} (×{self.conversion_factor})'
# =========================================================================
# Purchasing & Stock  (Phase 2)
# =========================================================================


class Supplier(models.Model):
    company_name = models.CharField(max_length=255, db_index=True)
    contact_person = models.CharField(max_length=255, blank=True, default='')
    phone = models.CharField(max_length=50, blank=True, default='')
    email = models.EmailField(blank=True, default='')
    address = models.TextField(blank=True, default='')
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_supplier'
        ordering = ['company_name']

    def __str__(self):
        return self.company_name


class PurchaseOrder(models.Model):

    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        ORDERED = 'ORDERED', 'Ordered'
        PARTIAL = 'PARTIAL', 'Partially Received'
        COMPLETE = 'COMPLETE', 'Complete'
        CANCELLED = 'CANCELLED', 'Cancelled'

    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name='purchase_orders')
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    order_date = models.DateField(auto_now_add=True)
    expected_delivery = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.DRAFT, db_index=True)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_po'
        ordering = ['-order_date']
        indexes = [
            models.Index(fields=['supplier', '-order_date']),
            models.Index(fields=['status']),
        ]

    def __str__(self):
        return f'PO #{self.pk} — {self.supplier.company_name}'


class POItem(models.Model):
    po = models.ForeignKey(
        PurchaseOrder, on_delete=models.CASCADE, related_name='items')
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name='po_items')
    ordered_qty = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))])
    unit_cost = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    received_qty = models.DecimalField(
        max_digits=12, decimal_places=2, default=0,
        validators=[MinValueValidator(Decimal('0'))])

    class Meta:
        db_table = 'inventory_po_item'

    def __str__(self):
        return f'{self.variant} × {self.ordered_qty} @ {self.unit_cost}'


class GoodsReceipt(models.Model):
    po = models.ForeignKey(
        PurchaseOrder, on_delete=models.PROTECT, related_name='receipts')
    received_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    receive_date = models.DateField(auto_now_add=True)
    delivery_receipt_no = models.CharField(max_length=100, blank=True, default='')
    notes = models.TextField(blank=True, default='')
    # Set by process_goods_receipt, inside the same transaction that mints the
    # batches. NULL = never processed. This is the double-process guard: it lives
    # on the row that is locked, so two concurrent process/ calls cannot both pass
    # it (the previous guard read `batches.exists()` outside any lock).
    processed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'inventory_goods_receipt'
        ordering = ['-receive_date']

    def __str__(self):
        return f'GR #{self.pk} ← PO #{self.po_id} ({self.receive_date})'


class GoodsReceiptItem(models.Model):
    """One delivered quantity on ONE goods receipt (decision 09 item 4).

    `POItem.received_qty` is a running total across every receipt of the PO, so it
    cannot answer "what did THIS delivery contain". Before this table existed the
    process step minted a batch from the running total on every receipt, which
    stocked 12 units for two deliveries of 5 and 2. A batch is now built from these
    lines, and `received_qty` stays what it always was: the cap the next delivery is
    checked against.
    """

    receipt = models.ForeignKey(
        GoodsReceipt, on_delete=models.CASCADE, related_name='lines')
    # PROTECT: a line is stock evidence, so a PO item that has been delivered
    # cannot be deleted out from under the batches it explains.
    po_item = models.ForeignKey(
        POItem, on_delete=models.PROTECT, related_name='receipt_lines')
    qty = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))])

    class Meta:
        db_table = 'inventory_goods_receipt_item'
        ordering = ['id']

    def __str__(self):
        return f'GR #{self.receipt_id} line: {self.po_item.variant} × {self.qty}'


class InventoryBatch(models.Model):
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name='batches')
    receipt = models.ForeignKey(
        GoodsReceipt, on_delete=models.PROTECT, related_name='batches')
    initial_qty = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    current_qty = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    unit_cost_landed = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    markup_percentage = models.DecimalField(
        max_digits=5, decimal_places=2, default=0,
        validators=[MinValueValidator(Decimal('0'))])
    batch_selling_price = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(Decimal('0'))])
    expiration_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'inventory_batch'
        ordering = ['receipt__receive_date']
        indexes = [models.Index(fields=['variant', 'current_qty'])]

    def __str__(self):
        return f'Batch #{self.pk} — {self.variant} ({self.current_qty} left)'


class StockAdjustment(models.Model):

    class AdjustmentType(models.TextChoices):
        SHRINKAGE = 'SHRINKAGE', 'Shrinkage / Loss'
        DAMAGE = 'DAMAGE', 'Damaged'
        CORRECTION = 'CORRECTION', 'Count Correction'
        RETURN = 'RETURN', 'Return to Supplier'

    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name='adjustments')
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    adjustment_type = models.CharField(max_length=15, choices=AdjustmentType.choices)
    qty_adjusted = models.DecimalField(max_digits=12, decimal_places=2)
    remarks = models.TextField(blank=True, default='')
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = 'inventory_stock_adjustment'
        ordering = ['-timestamp']

    def __str__(self):
        return f'{self.adjustment_type}: {self.variant} {self.qty_adjusted:+}'


class SystemAlert(models.Model):

    class AlertType(models.TextChoices):
        LOW_STOCK = 'LOW_STOCK', 'Low Stock'
        OUT_OF_STOCK = 'OUT_OF_STOCK', 'Out of Stock'
        EXPIRING = 'EXPIRING', 'Expiring Batch'

    alert_type = models.CharField(max_length=15, choices=AlertType.choices)
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.CASCADE, related_name='alerts')
    message = models.TextField()
    is_resolved = models.BooleanField(default=False, db_index=True)
    # Decision 06 (Phase 2): resolving an alert is a named act. Without these two columns
    # the API could say "resolved" but not "by whom, when", and a second resolve would
    # have silently overwritten the first resolver.
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='+')
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'inventory_system_alert'
        ordering = ['-created_at']
        indexes = [models.Index(fields=['is_resolved', '-created_at'])]

    def __str__(self):
        return f'[{self.alert_type}] {self.variant}'
