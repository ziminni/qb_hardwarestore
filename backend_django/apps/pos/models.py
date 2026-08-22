from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class Customer(models.Model):
    class Type(models.TextChoices):
        WALK_IN = 'WALK_IN', 'Walk-in'
        REGULAR = 'REGULAR', 'Regular'
        CONTRACTOR = 'CONTRACTOR', 'Contractor'
        CONSTRUCTION_FIRM = 'CONSTRUCTION_FIRM', 'Construction Firm'

    name = models.CharField(max_length=255, db_index=True)
    customer_type = models.CharField(max_length=20, choices=Type.choices, default=Type.WALK_IN)
    contact_details = models.CharField(max_length=255, blank=True, default='')
    tin_no = models.CharField(max_length=50, blank=True, default='')
    total_credit_limit = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'pos_customer'
        ordering = ['name']

    def __str__(self):
        return self.name


class SalesTransaction(models.Model):
    class Source(models.TextChoices):
        WALK_IN = 'WALK_IN', 'Walk-in'
        REQUISITION = 'REQUISITION', 'Requisition'

    class Status(models.TextChoices):
        COMPLETED = 'COMPLETED', 'Completed'
        VOID = 'VOID', 'Void'
        REFUNDED = 'REFUNDED', 'Refunded'

    customer = models.ForeignKey(Customer, on_delete=models.PROTECT, related_name='transactions')
    cashier = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='pos_transactions')
    transaction_no = models.CharField(max_length=50, unique=True, db_index=True)
    trans_date = models.DateTimeField(auto_now_add=True, db_index=True)
    vatable_sales = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    vat_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    discount_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    grand_total = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    source = models.CharField(max_length=15, choices=Source.choices, default=Source.WALK_IN)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.COMPLETED)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'pos_transaction'
        ordering = ['-trans_date']
        indexes = [models.Index(fields=['-trans_date']), models.Index(fields=['status'])]

    def __str__(self):
        return f'{self.transaction_no} — {self.grand_total}'


class SalesItem(models.Model):
    transaction = models.ForeignKey(SalesTransaction, on_delete=models.CASCADE, related_name='items')
    variant_uom = models.ForeignKey('inventory.VariantUOM', on_delete=models.PROTECT, related_name='sales_items')
    qty = models.DecimalField(max_digits=12, decimal_places=2, validators=[MinValueValidator(0)])
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = 'pos_sales_item'

    def __str__(self):
        return f'{self.transaction.transaction_no} — {self.variant_uom} × {self.qty}'


class Payment(models.Model):
    class Method(models.TextChoices):
        CASH = 'CASH', 'Cash'
        CARD = 'CARD', 'Card'
        GCASH = 'GCASH', 'GCash'
        BANK_TRANSFER = 'BANK_TRANSFER', 'Bank Transfer'

    transaction = models.ForeignKey(SalesTransaction, on_delete=models.CASCADE, related_name='payments')
    method = models.CharField(max_length=15, choices=Method.choices, default=Method.CASH)
    amount_tendered = models.DecimalField(max_digits=12, decimal_places=2)
    reference_no = models.CharField(max_length=100, blank=True, default='')
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pos_payment'

    def __str__(self):
        return f'{self.transaction.transaction_no} — {self.method} {self.amount_tendered}'


class OfficialReceipt(models.Model):
    transaction = models.OneToOneField(SalesTransaction, on_delete=models.PROTECT, related_name='receipt', unique=True)
    or_number = models.CharField(max_length=50, unique=True, db_index=True)
    terminal_no = models.CharField(max_length=20, default='POS-01')
    printed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pos_receipt'
        ordering = ['-printed_at']

    def __str__(self):
        return f'OR #{self.or_number}'
