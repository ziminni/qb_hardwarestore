from django.contrib import admin

from .models import CollectibleLedger, CollectiblePayment


@admin.register(CollectibleLedger)
class CollectibleLedgerAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'customer', 'transaction', 'original_amount',
        'balance_due', 'due_date', 'status', 'is_overdue',
    ]
    list_filter = ['status', 'due_date']
    search_fields = ['customer__full_name', 'id']
    readonly_fields = ['created_at', 'updated_at']


@admin.register(CollectiblePayment)
class CollectiblePaymentAdmin(admin.ModelAdmin):
    list_display = [
        'id', 'collectible', 'amount_paid', 'payment_method',
        'payment_date', 'official_receipt_no',
    ]
    list_filter = ['payment_method', 'payment_date']
    search_fields = ['collectible__id', 'official_receipt_no']
