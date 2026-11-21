# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
# Without django-stubs the checker cannot model `Model.objects` or `transaction.atomic()`
# as a context manager; both are valid at runtime.
"""Django Admin registration for Inventory models."""

from django.contrib import admin
from django.core.exceptions import ValidationError
from django.db import transaction

from .models import (
    Brand,
    Category,
    GoodsReceipt,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    SellingUnitPriceChange,
    StockAdjustment,
    Supplier,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
)


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ("name", "created_at")
    search_fields = ("name",)


@admin.register(Brand)
class BrandAdmin(admin.ModelAdmin):
    list_display = ("name", "created_at")
    search_fields = ("name",)


@admin.register(UnitOfMeasure)
class UnitOfMeasureAdmin(admin.ModelAdmin):
    # Decision 16: there is no in-app "new unit" screen, so the rare extra unit - and any
    # correction to the whole-number flag - happens here.
    list_display = ("code", "name", "is_whole", "created_at")
    list_editable = ("is_whole",)
    search_fields = ("code", "name")


class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 0
    fields = ("variant_name", "base_uom", "is_active")


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ("base_name", "category", "brand", "is_active")
    list_filter = ("category", "brand", "is_active")
    search_fields = ("base_name",)
    inlines = [ProductVariantInline]


@admin.register(ProductVariant)
class ProductVariantAdmin(admin.ModelAdmin):
    list_display = ("variant_name", "product", "base_uom", "is_active")
    list_filter = ("product__category", "is_active")
    search_fields = ("variant_name", "product__base_name")


@admin.register(VariantUOM)
class VariantUOMAdmin(admin.ModelAdmin):
    list_display = ("variant", "uom", "conversion_factor", "barcode_qr")
    search_fields = ("variant__variant_name", "barcode_qr")

    def save_model(self, request, obj, form, change):
        with transaction.atomic():
            stored = (
                VariantUOM.objects.select_for_update().filter(pk=obj.pk).first()
                if change
                else None
            )
            if change and stored is None:
                raise ValidationError(
                    "This selling unit was removed; reload and retry."
                )
            old_price = stored.default_selling_price if stored else None
            # An unchanged price input from a stale form must not undo a concurrent edit.
            if (
                old_price is not None
                and "default_selling_price" not in form.changed_data
            ):
                obj.default_selling_price = old_price
            super().save_model(request, obj, form, change)
            SellingUnitPriceChange.record(
                unit=obj,
                old_price=old_price,
                new_price=obj.default_selling_price,
                actor=request.user,
                source=SellingUnitPriceChange.Source.ADMIN,
            )


# =========================================================================
# Phase 2 Admin registrations
# =========================================================================


@admin.register(Supplier)
class SupplierAdmin(admin.ModelAdmin):
    list_display = ("company_name", "contact_person", "phone", "is_active")
    search_fields = ("company_name",)
    list_filter = ("is_active",)


class POItemInline(admin.TabularInline):
    model = POItem
    extra = 0


@admin.register(PurchaseOrder)
class PurchaseOrderAdmin(admin.ModelAdmin):
    list_display = ("id", "supplier", "status", "order_date", "expected_delivery")
    list_filter = ("status",)
    search_fields = ("supplier__company_name",)
    inlines = [POItemInline]


@admin.register(GoodsReceipt)
class GoodsReceiptAdmin(admin.ModelAdmin):
    list_display = ("id", "po", "receive_date", "delivery_receipt_no")
    search_fields = ("po__supplier__company_name",)


@admin.register(InventoryBatch)
class InventoryBatchAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "variant",
        "current_qty",
        "batch_selling_price",
        "expiration_date",
    )
    search_fields = ("variant__variant_name",)
    list_filter = ("expiration_date",)


@admin.register(StockAdjustment)
class StockAdjustmentAdmin(admin.ModelAdmin):
    list_display = ("variant", "adjustment_type", "qty_adjusted", "user", "timestamp")
    list_filter = ("adjustment_type",)


@admin.register(SystemAlert)
class SystemAlertAdmin(admin.ModelAdmin):
    list_display = ("alert_type", "variant", "is_resolved", "created_at")
    list_filter = ("alert_type", "is_resolved")
