from rest_framework import serializers
from .models import Customer, SalesTransaction, SalesItem, Payment, OfficialReceipt


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
        fields = ['id','customer','customer_name','cashier','cashier_name','transaction_no','trans_date','vatable_sales','vat_amount','discount_amount','grand_total','source','status','notes','items','payments','receipt','created_at','updated_at']
        read_only_fields = ['id','transaction_no','trans_date','created_at','updated_at']