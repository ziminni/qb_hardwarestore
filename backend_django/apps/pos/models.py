from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from apps.inventory.models import VariantUOM


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
        # Decision 15: a customer return is a transaction with NEGATIVE amounts, so it nets
        # out of every total that already sums grand_total. The reports need no change for it.
        RETURN = 'RETURN', 'Return'

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
    # PROTECT, so a reversed sale cannot be deleted out from under its return. Nullable
    # because a return is still valid when the original receipt is not to hand - decision
    # 15's restock rule has a branch for exactly that case.
    original_transaction = models.ForeignKey(
        'self', null=True, blank=True, on_delete=models.PROTECT,
        related_name='reversals')
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


class SalesItemDeduction(models.Model):
    """Which batches one sale item drew from, and how much from each.

    Task 6A.4: `allocate_fifo` returns (batch, qty) allocations and `process_sale`
    used to discard them, so a return linked to its original sale could not know
    "the original batch it left from" (decision 15's linked branch). One row per
    batch touched — an item spanning two batches writes two rows.
    """
    sales_item = models.ForeignKey(
        SalesItem, on_delete=models.CASCADE, related_name='deductions')
    batch = models.ForeignKey(
        'inventory.InventoryBatch', on_delete=models.PROTECT, related_name='+')
    qty = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = 'pos_sales_item_deduction'


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


# ---------------------------------------------------------------------------
# Phase 6 task 6A.1 — quotations (decision 05, Sales Stack Reconciliation).
#
# The sales role ships a quotations screen, and the client stack for it
# (sales_module_viewmodel.dart + models/sales_module.dart) had no endpoint to call.
# Decision 05 ruled that quotations get a real backend model rather than being dropped,
# which is what superseded the epic's "no new endpoints, no model or migration changes"
# invariant.
# ---------------------------------------------------------------------------


class Quotation(models.Model):
    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        SENT = 'SENT', 'Sent'
        ACCEPTED = 'ACCEPTED', 'Accepted'
        # The client's canonical enum (SalesQuoteStatus) says `expired`, not `rejected`.
        # Decision 05 made that stack canonical, and a status the client cannot render shows
        # as "Unknown" - avoidable here, unlike the requisition case where `unknown` exists
        # because the server may add statuses the client was never taught.
        EXPIRED = 'EXPIRED', 'Expired'

    quotation_no = models.CharField(max_length=30, unique=True, db_index=True)
    customer = models.ForeignKey(
        Customer, on_delete=models.PROTECT, related_name='quotations')
    status = models.CharField(
        max_length=15, choices=Status.choices, default=Status.DRAFT, db_index=True)
    valid_until = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True, default='')
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'pos_quotation'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.quotation_no} — {self.customer}'

    def save(self, *args, **kwargs):
        # Generated server-side, like Requisition.req_number: a client-supplied number would
        # be a second source of truth for something the server must guarantee is unique.
        if not self.quotation_no:
            from common.numbering import generate_document_number
            self.quotation_no = generate_document_number(Quotation, 'quotation_no', 'QT')
        super().save(*args, **kwargs)


class QuotationItem(models.Model):
    quotation = models.ForeignKey(
        Quotation, on_delete=models.CASCADE, related_name='items')
    variant_uom = models.ForeignKey(
        VariantUOM, on_delete=models.PROTECT, related_name='+')
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = 'pos_quotation_item'

    def __str__(self):
        return f'{self.quotation.quotation_no} — {self.variant_uom} × {self.qty}'


class SalesOrder(models.Model):
    """Phase 6 task 6A.2 (decision 05).

    The second of the two models decision 05 ruled were missing. Like Quotation it is a DOCUMENT,
    not a sale: no stock moves and no money is taken until it is fulfilled, which is why it does not
    touch InventoryBatch or the ledger.
    """

    class Status(models.TextChoices):
        # Matches the client's canonical SalesOrderStatus enum exactly.
        CONFIRMED = 'CONFIRMED', 'Confirmed'
        PROCESSING = 'PROCESSING', 'Processing'
        READY = 'READY', 'Ready'
        COMPLETED = 'COMPLETED', 'Completed'

    order_no = models.CharField(max_length=30, unique=True, db_index=True)
    customer = models.ForeignKey(
        Customer, on_delete=models.PROTECT, related_name='sales_orders')
    # SET_NULL, not PROTECT: an order may outlive the quotation it came from, and losing the order
    # because a quotation was deleted would be the wrong trade. The order stands on its own.
    quotation = models.ForeignKey(
        Quotation, on_delete=models.SET_NULL, null=True, blank=True, related_name='orders')
    status = models.CharField(
        max_length=15, choices=Status.choices, default=Status.CONFIRMED, db_index=True)
    notes = models.TextField(blank=True, default='')
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='+')
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'pos_sales_order'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.order_no} — {self.customer}'

    def save(self, *args, **kwargs):
        if not self.order_no:
            from common.numbering import generate_document_number
            self.order_no = generate_document_number(SalesOrder, 'order_no', 'SO')
        super().save(*args, **kwargs)


class SalesOrderItem(models.Model):
    order = models.ForeignKey(
        SalesOrder, on_delete=models.CASCADE, related_name='items')
    variant_uom = models.ForeignKey(
        VariantUOM, on_delete=models.PROTECT, related_name='+')
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = 'pos_sales_order_item'

    def __str__(self):
        return f'{self.order.order_no} — {self.variant_uom} × {self.qty}'


class HeldCart(models.Model):
    cashier = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name='held_carts')
    customer = models.ForeignKey(
        Customer, on_delete=models.SET_NULL, null=True, blank=True, related_name='held_carts')
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'pos_held_cart'
        ordering = ['-created_at']

    def __str__(self):
        return f'HeldCart {self.id} by {self.cashier}'


class HeldCartItem(models.Model):
    cart = models.ForeignKey(HeldCart, on_delete=models.CASCADE, related_name='items')
    variant_uom = models.ForeignKey(
        'inventory.VariantUOM', on_delete=models.PROTECT, related_name='+')
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = 'pos_held_cart_item'

    def __str__(self):
        return f'HeldCartItem {self.id} — {self.variant_uom} × {self.qty}'
