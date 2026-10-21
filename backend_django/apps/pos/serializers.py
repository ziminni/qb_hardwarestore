# pyright: reportAttributeAccessIssue=false
#
# Same directive and reason as apps/pos/models.py and apps/pos/services.py: the checker
# resolves its config from its WORKING DIRECTORY, so no pyrightconfig.json is found, and
# `Model.objects` is a false positive on valid Django without django-stubs.
from rest_framework import serializers
from .models import (
    Quotation, QuotationItem,
    SalesOrder, SalesOrderItem,
    HeldCart, HeldCartItem,
    Customer,
    OfficialReceipt,
    Payment,
    SalesItem,
    SalesTransaction,
    Shift,
)


class CustomerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Customer
        fields = ['id','name','customer_type','contact_details','tin_no','total_credit_limit','is_active','created_at','updated_at']
        read_only_fields = ['id','created_at','updated_at']


class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = ['id','transaction','method','amount_tendered','reference_no','timestamp']
        read_only_fields = ['id','timestamp']


class SalesItemSerializer(serializers.ModelSerializer):
    variant_uom_code = serializers.CharField(source='variant_uom.uom.code', read_only=True)

    class Meta:
        model = SalesItem
        fields = ['id','transaction','variant_uom','variant_uom_code','qty','unit_price','subtotal']
        read_only_fields = ['id','subtotal']


class OfficialReceiptSerializer(serializers.ModelSerializer):
    class Meta:
        model = OfficialReceipt
        fields = ['id','transaction','or_number','terminal_no','printed_at']
        read_only_fields = ['id','printed_at']


class SalesTransactionSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source='customer.name', read_only=True)
    cashier_name = serializers.CharField(source='cashier.full_name', read_only=True)
    items = SalesItemSerializer(many=True, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    receipt = OfficialReceiptSerializer(read_only=True)

    class Meta:
        model = SalesTransaction
        fields = ['id','customer','customer_name','cashier','cashier_name','transaction_no','trans_date','vatable_sales','vat_amount','discount_amount','grand_total','source','original_transaction','status','notes','items','payments','receipt','created_at','updated_at']
        # `cashier` is READ-ONLY because the actor is not the client's to choose. The view
        # already passes `cashier=request.user` into `process_sale`, so a writable
        # `cashier` was demanded by validation and then discarded -- every client had to
        # send a value that had no effect, and a client could have attributed a sale to
        # another cashier. Same invariant as StockAdjustmentSerializer.user (Phase 2),
        # found here by POSTing a valid sale to the endpoint: HTTP 400
        # {"cashier": ["This field is required."]}.
        read_only_fields = ['id','transaction_no','trans_date','created_at','updated_at','cashier']


class ShiftSerializer(serializers.ModelSerializer):
    """Phase 4 (decision 06).

    `cashier` is read-only because the actor is never the client's to choose - the view
    takes `request.user`, the same invariant as SalesTransactionSerializer.cashier.
    `status` and `closed_at` are read-only because only the open/close ACTIONS may move
    them: a writable status would let a client reopen a closed shift, which decision 06
    forbids (OPEN -> CLOSED, never back).

    `z_reading` is derived on read from the shift's own transactions, so a closed shift
    prints identical numbers every time and no second table can drift from the sales.
    """

    cashier_name = serializers.CharField(
        source='cashier.full_name', read_only=True)
    z_reading = serializers.SerializerMethodField()

    class Meta:
        model = Shift
        fields = [
            'id', 'cashier', 'cashier_name', 'status', 'opening_float',
            'closing_count', 'opened_at', 'closed_at', 'notes', 'z_reading',
        ]
        read_only_fields = [
            'id', 'cashier', 'status', 'opened_at', 'closed_at']

    def get_z_reading(self, obj):
        # Imported here, not at module level: services imports these models, and a
        # module-level import in both directions is a cycle waiting for the next edit.
        from .services import compute_z_reading
        return compute_z_reading(obj)


class QuotationItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = QuotationItem
        fields = ['id', 'quotation', 'variant_uom', 'qty', 'unit_price']
        # `quotation` is READ-ONLY: the parent QuotationSerializer.create() sets it. Leaving it
        # writable made it a required field on every nested item, so a legitimate payload was
        # rejected with "quotation: This field is required." - which is what the first GREEN run hit.
        read_only_fields = ['id', 'quotation']


class QuotationSerializer(serializers.ModelSerializer):
    items = QuotationItemSerializer(many=True, required=False)

    class Meta:
        model = Quotation
        fields = [
            'id', 'quotation_no', 'customer', 'status', 'valid_until', 'notes',
            'items', 'created_at', 'updated_at',
        ]
        # quotation_no and created_by are the server's to decide; a client that could set
        # either could forge a number or attribute a quotation to someone else.
        read_only_fields = ['id', 'quotation_no', 'created_at', 'updated_at']

    def create(self, validated_data):
        items = validated_data.pop('items', [])
        quotation = Quotation.objects.create(**validated_data)
        for item in items:
            QuotationItem.objects.create(quotation=quotation, **item)
        return quotation


class SalesOrderItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = SalesOrderItem
        fields = ['id', 'order', 'variant_uom', 'qty', 'unit_price']
        # `order` is read-only for the same reason `quotation` is on the item serializer above:
        # the parent's create() sets it, and leaving it writable makes it REQUIRED on every nested
        # item, rejecting a legitimate payload.
        read_only_fields = ['id', 'order']


class SalesOrderSerializer(serializers.ModelSerializer):
    items = SalesOrderItemSerializer(many=True, required=False)

    class Meta:
        model = SalesOrder
        fields = [
            'id', 'order_no', 'customer', 'quotation', 'status', 'notes',
            'items', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'order_no', 'created_at', 'updated_at']

    def create(self, validated_data):
        items = validated_data.pop('items', [])
        order = SalesOrder.objects.create(**validated_data)
        for item in items:
            SalesOrderItem.objects.create(order=order, **item)
        return order


class HeldCartItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = HeldCartItem
        fields = ['id', 'cart', 'variant_uom', 'qty', 'unit_price']
        read_only_fields = ['id', 'cart']


class HeldCartSerializer(serializers.ModelSerializer):
    items = HeldCartItemSerializer(many=True, required=False)
    customer_name = serializers.CharField(source='customer.name', read_only=True, default=None)
    cashier_name = serializers.CharField(source='cashier.full_name', read_only=True)

    class Meta:
        model = HeldCart
        fields = ['id', 'cashier', 'cashier_name', 'customer', 'customer_name', 'notes', 'items', 'created_at']
        read_only_fields = ['id', 'cashier', 'created_at']

    def create(self, validated_data):
        items_data = validated_data.pop('items', [])
        cart = HeldCart.objects.create(**validated_data)
        for item in items_data:
            HeldCartItem.objects.create(cart=cart, **item)
        return cart
