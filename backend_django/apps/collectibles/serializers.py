"""Serializers for Collectibles (Accounts Receivable) module."""

from rest_framework import serializers

from .models import CollectibleLedger, CollectiblePayment


class CollectiblePaymentSerializer(serializers.ModelSerializer):
    """Payment posted against a collectible ledger.

    Phase 4 task B2 (decision 18): the utang dialog offers the same tenders the till does,
    including a cheque. The cheque's three facts are WRITE-ONLY here because they are not
    columns of `CollectiblePayment` - a pending cheque is a row on `pos.Payment` (the
    cheque queue reads that one table), and this serializer only carries them in for the
    create path.
    """

    processed_by_name = serializers.ReadOnlyField(
        source='processed_by.full_name',
    )
    payment_method = serializers.CharField(max_length=50)
    cheque_number = serializers.CharField(
        required=False, allow_blank=True, write_only=True)
    bank = serializers.CharField(
        required=False, allow_blank=True, write_only=True)
    cheque_date = serializers.DateField(
        required=False, allow_null=True, write_only=True)

    class Meta:
        model = CollectiblePayment
        fields = [
            'id',
            'collectible',
            'processed_by',
            'processed_by_name',
            'amount_paid',
            'payment_method',
            'cheque_number',
            'bank',
            'cheque_date',
            'payment_date',
            'official_receipt_no',
        ]
        read_only_fields = [
            'id',
            'payment_date',
            # `processed_by` is required from the client and then OVERWRITTEN by
            # perform_create with the logged-in user. Demanding a value that is
            # discarded makes the client supply a lie and fails a request for
            # omitting it - the same class as the checkout's `cashier` field.
            'processed_by',
        ]

    def validate_payment_method(self, value):
        """Accept the four tender CODES, nothing else (C2, 2026-10-24).

        `payment_method` used to be free text, so a client could post the label it shows
        ('Cash') or the server's own `RETURN_CREDIT` marker. Both are refused here, BEFORE
        `perform_create` moves a balance: the allowed set is `Payment.Method` — the same
        home the till's checkout validation reads — so a code the server starts taking is
        taken here too, with no second list to keep in step.

        A refusal writes nothing: the exception is raised during validation, which is
        before the atomic block that saves the payment and moves `balance_due`.
        """
        from apps.pos.exceptions import InvalidPaymentMethod
        from apps.pos.models import Payment

        if value not in dict(Payment.Method.choices):
            raise InvalidPaymentMethod(value)
        return value

    def validate(self, attrs):
        """A cheque must carry the three facts the shop would collect on.

        Checked at validation time, before `perform_create` writes or moves anything, and
        with the till's own exception so both screens show the same sentence and the same
        `CHEQUE_DETAILS_REQUIRED` code.
        """
        from apps.pos.exceptions import ChequeDetailsRequired
        from apps.pos.models import Payment

        if attrs.get('payment_method') != Payment.Method.CHEQUE:
            return attrs
        missing = [
            label for field, label in (
                ('cheque_number', 'cheque number'), ('bank', 'bank'),
                ('cheque_date', 'cheque date'))
            if not attrs.get(field)
        ]
        if missing:
            raise ChequeDetailsRequired(missing)
        return attrs


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
    project_name = serializers.SerializerMethodField()
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
            'project_name',
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

    def get_project_name(self, obj):
        """The project this utang belongs to, or None for a counter sale (decision 03).

        A method field, not `ReadOnlyField(source='project.name')`: with no project the
        dotted source raises and DRF drops the key from the row entirely - the same
        silent-absence bug `customer_name` had above, one field over. A counter sale has
        to answer `null` here, not nothing.
        """
        return obj.project.name if obj.project_id else None
