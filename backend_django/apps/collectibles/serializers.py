"""Serializers for Collectibles (Accounts Receivable) module."""

from rest_framework import serializers

from .models import CollectibleLedger, CollectiblePayment


class CollectiblePaymentSerializer(serializers.ModelSerializer):
    """Payment posted against a collectible ledger."""

    processed_by_name = serializers.ReadOnlyField(
        source='processed_by.full_name',
    )

    class Meta:
        model = CollectiblePayment
        fields = [
            'id',
            'collectible',
            'processed_by',
            'processed_by_name',
            'amount_paid',
            'payment_method',
            'payment_date',
            'official_receipt_no',
        ]
        read_only_fields = [
            'id',
            'payment_date',
        ]


class CollectibleLedgerSerializer(serializers.ModelSerializer):
    """Collectible ledger entry with nested recent payments."""

    # `Customer` has no `full_name` — the project's `User` does, and that one wrong
    # assumption was copied across. DRF swallows the AttributeError for a ReadOnlyField
    # and skips the field entirely, so this key was SILENTLY ABSENT from every ledger row
    # rather than present-and-null: a client reading `json['customer_name']` got a
    # KeyError and one reading `.get(...)` got None, with the response still a 200.
    customer_name = serializers.ReadOnlyField(source='customer.name')
    transaction_no = serializers.ReadOnlyField(source='transaction.transaction_no')
    is_overdue = serializers.ReadOnlyField()
    recent_payments = CollectiblePaymentSerializer(
        source='payments',
        many=True,
        read_only=True,
    )

    class Meta:
        model = CollectibleLedger
        fields = [
            'id',
            'customer',
            'customer_name',
            'transaction',
            'transaction_no',
            'original_amount',
            'balance_due',
            'due_date',
            'status',
            'is_overdue',
            'created_at',
            'updated_at',
            'recent_payments',
        ]
        read_only_fields = [
            'id',
            'created_at',
            'updated_at',
        ]

    def get_recent_payments(self, obj):
        """Return the 10 most recent payments for this ledger."""
        payments = obj.payments.order_by('-payment_date')[:10]
        return CollectiblePaymentSerializer(payments, many=True).data
