"""Inventory app — serializers for product catalog (Sprint 1)."""

from rest_framework import serializers

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
    Supplier,
    PurchaseOrder,
    POItem,
    GoodsReceipt,
    InventoryBatch,
    StockAdjustment,
    SystemAlert,
)


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ['id', 'name', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ['id', 'name', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class UnitOfMeasureSerializer(serializers.ModelSerializer):
    class Meta:
        model = UnitOfMeasure
        fields = ['id', 'code', 'name', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']


class VariantUOMSerializer(serializers.ModelSerializer):
    uom_code = serializers.CharField(source='uom.code', read_only=True)
    uom_name = serializers.CharField(source='uom.name', read_only=True)

    class Meta:
        model = VariantUOM
        fields = [
            'id', 'variant', 'uom', 'uom_code', 'uom_name',
            'barcode_qr', 'conversion_factor', 'default_selling_price',
        ]
        read_only_fields = ['id']


class ProductVariantSerializer(serializers.ModelSerializer):
    base_uom_code = serializers.CharField(
        source='base_uom.code', read_only=True)
    selling_uoms = VariantUOMSerializer(many=True, read_only=True)

    class Meta:
        model = ProductVariant
        fields = [
            'id', 'product', 'variant_name', 'base_uom',
            'base_uom_code', 'min_stock_threshold', 'max_stock_level',
            'is_active', 'selling_uoms', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class ProductSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(
        source='category.name', read_only=True)
    brand_name = serializers.CharField(
        source='brand.name', read_only=True)
    variants = ProductVariantSerializer(many=True, read_only=True)

    class Meta:
        model = Product
        fields = [
            'id', 'category', 'category_name', 'brand', 'brand_name',
            'base_name', 'description', 'image_url', 'is_active',
            'variants', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']
class SupplierSerializer(serializers.ModelSerializer):
    class Meta:
        model = Supplier
        fields = ['id','company_name','contact_person','phone','email','address','is_active','created_at','updated_at']
        read_only_fields = ['id','created_at','updated_at']


class POItemSerializer(serializers.ModelSerializer):
    variant_name = serializers.CharField(source='variant.variant_name', read_only=True)
    class Meta:
        model = POItem
        fields = ['id','po','variant','variant_name','ordered_qty','unit_cost','received_qty']
        read_only_fields = ['id']


class PurchaseOrderSerializer(serializers.ModelSerializer):
    items = POItemSerializer(many=True, read_only=True)
    created_by_name = serializers.CharField(source='created_by.full_name', read_only=True)
    class Meta:
        model = PurchaseOrder
        fields = ['id','supplier','created_by','created_by_name','order_date','expected_delivery','status','notes','items','created_at','updated_at']
        read_only_fields = ['id','order_date','created_at','updated_at']
class InventoryBatchSerializer(serializers.ModelSerializer):
    class Meta:
        model = InventoryBatch
        fields = ['id','variant','receipt','initial_qty','current_qty','unit_cost_landed','markup_percentage','batch_selling_price','expiration_date','created_at']
        read_only_fields = ['id','created_at']


class GoodsReceiptSerializer(serializers.ModelSerializer):
    batches = InventoryBatchSerializer(many=True, read_only=True)
    received_by_name = serializers.CharField(source='received_by.full_name', read_only=True)
    class Meta:
        model = GoodsReceipt
        fields = ['id','po','received_by','received_by_name','receive_date','delivery_receipt_no','notes','batches','created_at']
        read_only_fields = ['id','receive_date','created_at']


class StockAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockAdjustment
        fields = ['id','variant','user','adjustment_type','qty_adjusted','remarks','timestamp']
        read_only_fields = ['id','timestamp']


class SystemAlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = SystemAlert
        fields = ['id','alert_type','variant','message','is_resolved','created_at']
        read_only_fields = ['id','created_at']