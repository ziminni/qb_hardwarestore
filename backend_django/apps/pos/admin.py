from django.contrib import admin
from .models import Customer, SalesTransaction, SalesItem, Payment, OfficialReceipt

@admin.register(Customer)
class CustomerAdmin(admin.ModelAdmin):
    list_display = ('name','customer_type','tin_no','is_active')
    list_filter = ('customer_type','is_active')
    search_fields = ('name','tin_no')

class SalesItemInline(admin.TabularInline):
    model = SalesItem
    extra = 0

class PaymentInline(admin.TabularInline):
    model = Payment
    extra = 0

@admin.register(SalesTransaction)
class SalesTransactionAdmin(admin.ModelAdmin):
    list_display = ('transaction_no','customer','cashier','grand_total','status','trans_date')
    list_filter = ('status','source','trans_date')
    search_fields = ('transaction_no','customer__name')
    inlines = [SalesItemInline, PaymentInline]

@admin.register(OfficialReceipt)
class OfficialReceiptAdmin(admin.ModelAdmin):
    list_display = ('or_number','transaction','terminal_no','printed_at')
    search_fields = ('or_number',)
