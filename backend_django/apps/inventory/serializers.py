"""Inventory app — serializers for product catalog (Sprint 1)."""

from rest_framework import serializers

from .models import (
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
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
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


class GoodsReceiptItemSerializer(serializers.ModelSerializer):
    """One delivered line. Read-only: lines are created by the receipt POST itself.

    `variant`/`variant_name` are here because a receiving screen has to label the line
    without a second request per po_item, and the po_item id alone does not say what was
    delivered. `qty` is the quantity THIS receipt delivered, not the running total.
    """

    variant = serializers.IntegerField(source='po_item.variant_id', read_only=True)
    variant_name = serializers.CharField(
        source='po_item.variant.variant_name', read_only=True)

    class Meta:
        model = GoodsReceiptItem
        fields = ['id', 'po_item', 'variant', 'variant_name', 'qty']
        read_only_fields = fields


class GoodsReceiptSerializer(serializers.ModelSerializer):
    batches = InventoryBatchSerializer(many=True, read_only=True)
    lines = GoodsReceiptItemSerializer(many=True, read_only=True)
    received_by_name = serializers.CharField(source='received_by.full_name', read_only=True)
    class Meta:
        model = GoodsReceipt
        fields = ['id','po','received_by','received_by_name','receive_date','delivery_receipt_no','notes','lines','batches','processed_at','created_at']
        # `received_by` is READ-ONLY: the actor is not the client's to choose. The viewset
        # already passes `request.user` into creation, so a writable `received_by` was
        # demanded by validation and then had to be sent — every client had to supply a
        # value that means nothing. Same invariant as the checkout's `cashier` field.
        # `processed_at` is read-only for the same reason the timestamp is: the server's
        # process/ call sets it, and a client-writable one would let a caller mark a
        # receipt done (or un-done) without any stock moving.
        read_only_fields = ['id','received_by','receive_date','processed_at','created_at']


class StockAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockAdjustment
        fields = ['id','variant','user','adjustment_type','qty_adjusted','remarks','timestamp']
        # `user` is READ-ONLY because the actor is never the client's to choose.
        # StockAdjustmentViewSet.perform_create already does
        # `serializer.save(user=self.request.user)`, so a writable `user` was
        # both demanded by validation and then discarded -- every client was
        # forced to send a value that had no effect, and a client could have
        # attributed an adjustment to somebody else. Found by POSTing this
        # endpoint's real body to the running server: HTTP 400
        # {"user":["This field is required."]}.
        read_only_fields = ['id','timestamp','user']

    def validate_qty_adjusted(self, value):
        # A zero adjustment is not a correction, it is a no-op with a receipt: a
        # StockAdjustment row is the stock ledger's evidence that quantity moved, so a row
        # that moved nothing is a false record. Refused HERE rather than in the service
        # because it is a payload fact (sign is meaningful, magnitude must be non-zero)
        # and DRF turns it into the same 400 the other validation errors use.
        if value == 0:
            raise serializers.ValidationError(
                'qty_adjusted must not be 0: an adjustment records stock that moved, '
                'and use a negative value for a removal.')
        return value


class SystemAlertSerializer(serializers.ModelSerializer):
    """An alert raised by the system, plus who cleared it and when.

    `resolved_by_name` is derived rather than stored (expressive-dev rule: one home per
    fact) and prefers the human `full_name`, falling back to the username because a
    seeded account may have a blank full name.
    """

    resolved_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SystemAlert
        # Every field is read-only: alerts are system-generated and the only write the
        # API accepts is POST /alerts/{id}/resolve/ (decision 06), which sets the trail
        # from `request.user` and the server clock - never from the payload.
        fields = [
            'id', 'alert_type', 'variant', 'message', 'is_resolved',
            'resolved_by', 'resolved_by_name', 'resolved_at', 'created_at',
        ]
        read_only_fields = fields

    def get_resolved_by_name(self, alert):
        resolver = alert.resolved_by
        if resolver is None:
            return None
        return resolver.full_name or resolver.username

