"""
Inventory Module — Product Catalog tables (Sprint 1).

ERD mapping:
    CATEGORY          → Category
    BRAND             → Brand
    PRODUCT           → Product
    PRODUCT_VARIANT   → ProductVariant
    UNIT_OF_MEASURE   → UnitOfMeasure
    VARIANT_UOM       → VariantUOM

Purchasing / batch / alert tables are added in Sprint 2.
"""

from django.core.validators import MinValueValidator
from django.db import models


class Category(models.Model):
    """Product category (e.g. Paints, Electrical, Plumbing)."""
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
    """Product brand (e.g. Boysen, Omni, National)."""
    name = models.CharField(max_length=100, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'inventory_brand'
        ordering = ['name']

    def __str__(self):
        return self.name


class UnitOfMeasure(models.Model):
    """Unit of measure (e.g. piece, box, kg, meter, liter)."""
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
    """Master product definition (not sellable directly — variants are)."""
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
    """A sellable SKU. Base stock tracked in `base_uom` (smallest unit).

    Alternative selling units (box, bundle) are defined via VariantUOM.
    """
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
    """Alternative selling unit with its own barcode & price.

    conversion_factor = how many base_uom units make this unit.
    e.g. 1 box = 20 pcs → conversion_factor = 20.
    """
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.CASCADE, related_name='selling_uoms')
    uom = models.ForeignKey(
        UnitOfMeasure, on_delete=models.PROTECT, related_name='+')
    barcode_qr = models.CharField(
        max_length=100, blank=True, default='', db_index=True)
    conversion_factor = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(0.01)])
    default_selling_price = models.DecimalField(
        max_digits=12, decimal_places=2,
        validators=[MinValueValidator(0)])
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
