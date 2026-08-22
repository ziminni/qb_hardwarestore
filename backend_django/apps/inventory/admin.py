"""Django Admin registration for Inventory models."""

from django.contrib import admin

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ('name', 'created_at')
    search_fields = ('name',)


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ('name', 'created_at')
    search_fields = ('name',)


@admin.register(UnitOfMeasure)
class UnitOfMeasureAdmin(admin.ModelAdmin):
    list_display = ('code', 'name', 'created_at')
    search_fields = ('code', 'name')


class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 0
    fields = ('variant_name', 'base_uom', 'is_active')


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ('base_name', 'category', 'brand', 'is_active')
    list_filter = ('category', 'brand', 'is_active')
    search_fields = ('base_name',)
    inlines = [ProductVariantInline]


@admin.register(ProductVariant)
class ProductVariantAdmin(admin.ModelAdmin):
    list_display = ('variant_name', 'product', 'base_uom', 'is_active')
    list_filter = ('product__category', 'is_active')
    search_fields = ('variant_name', 'product__base_name')


@admin.register(VariantUOM)
class VariantUOMAdmin(admin.ModelAdmin):
    list_display = ('variant', 'uom', 'conversion_factor', 'barcode_qr')
    search_fields = ('variant__variant_name', 'barcode_qr')
