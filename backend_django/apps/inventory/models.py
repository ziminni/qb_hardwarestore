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
    INVENTORY_BATCH   → InventoryBatch
    STOCK_ADJUSTMENT  → StockAdjustment
    SYSTEM_ALERT      → SystemAlert
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models, transaction


# =========================================================================
# Catalog master data  (Phase 1)
# =========================================================================

class Category(models.Model):
    name = models.CharField(max_length=100, unique=True, db_index=True)
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
                fields=['variant', 'uom'], name='uq_variant_uom')]

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
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'inventory_goods_receipt'
        ordering = ['-receive_date']

    def __str__(self):
        return f'GR #{self.pk} ← PO #{self.po_id} ({self.receive_date})'
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
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'inventory_system_alert'
        ordering = ['-created_at']
        indexes = [models.Index(fields=['is_resolved', '-created_at'])]

    def __str__(self):
        return f'[{self.alert_type}] {self.variant}'
