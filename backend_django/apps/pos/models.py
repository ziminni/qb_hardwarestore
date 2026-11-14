# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIncompatibleMethodOverride=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/services.py, apps/pos/tests.py and seed_demo.py:
# the checker resolves its config from its WORKING DIRECTORY and does not run inside this
# repo here, so pyrightconfig.json is not found and this travels with the file. Without
# django-stubs every `Model.objects`, FK-attribute read (`self.customer.name`) and
# `BooleanField(default=True)` is a false positive on valid Django. Django's own
# `manage.py check` and the test run remain the authority.

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import IntegrityError, models

from apps.inventory.models import VariantUOM


class Customer(models.Model):
    class Type(models.TextChoices):
        WALK_IN = "WALK_IN", "Walk-in"
        REGULAR = "REGULAR", "Regular"
        CONTRACTOR = "CONTRACTOR", "Contractor"
        CONSTRUCTION_FIRM = "CONSTRUCTION_FIRM", "Construction Firm"

    name = models.CharField(max_length=255, db_index=True)
    customer_type = models.CharField(
        max_length=20, choices=Type.choices, default=Type.WALK_IN
    )
    contact_details = models.CharField(max_length=255, blank=True, default="")
    tin_no = models.CharField(max_length=50, blank=True, default="")
    # Decision 08: NULL means UNLIMITED credit, 0 means NO credit at all. The field
    # used to default to 0 on every row and nothing ever set it, so hard-blocking 0
    # would have refused utang at the till for every existing customer - which is why
    # it is nullable and the data migration turns those legacy zeros into NULL.
    total_credit_limit = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        null=True,
        blank=True,
        default=None,
        help_text="NULL = unlimited, 0 = no credit allowed.",
    )
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_customer"
        ordering = ["name"]

    def __str__(self):
        return self.name


class SalesTransaction(models.Model):
    class Source(models.TextChoices):
        WALK_IN = "WALK_IN", "Walk-in"
        REQUISITION = "REQUISITION", "Requisition"
        # Decision 15: a customer return is a transaction with NEGATIVE amounts, so it nets
        # out of every total that already sums grand_total. The reports need no change for it.
        RETURN = "RETURN", "Return"

    class Status(models.TextChoices):
        COMPLETED = "COMPLETED", "Completed"
        VOID = "VOID", "Void"
        REFUNDED = "REFUNDED", "Refunded"

    customer = models.ForeignKey(
        Customer, on_delete=models.PROTECT, related_name="transactions"
    )
    cashier = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="pos_transactions",
    )
    transaction_no = models.CharField(max_length=50, unique=True, db_index=True)
    trans_date = models.DateTimeField(auto_now_add=True, db_index=True)
    vatable_sales = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    vat_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    discount_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Phase 4 task B1 (decision 18): WHY the discount was given. A discount without a
    # reason is money leaving the shop with no explanation, so `process_sale` refuses
    # one; storing the sentence on the row is the same rule `notes` carries for a return.
    discount_reason = models.CharField(max_length=255, blank=True, default="")
    # Whether the store was VAT-registered when this row was written. Stored, not read
    # from the settings on the fly: a receipt reprinted after the Admin turns VAT off
    # must still say what it said when the money was taken.
    vat_registered = models.BooleanField(default=True)
    # The RATE that was in force when this row was written, for the same reason as the
    # flag above: a return books its VAT at the rate its sale was rung at, so a later
    # settings change cannot make a refund disagree with the receipt in the customer's
    # hand. NULL on rows written before Phase 4, which booked no VAT at all - a NULL rate
    # is read as 0.00 percent, so such a row keeps claiming what its receipt showed.
    vat_rate = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True, default=None
    )
    grand_total = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Phase 5 task B3 (decision 18): the delivery charge the customer paid ON TOP of the
    # goods, VAT-inclusive and priced from no stock. Persisted on the sale (not only on
    # the `Delivery` row) because the receipt, the Z-reading and the return arithmetic
    # all read the SALE: `grand_total` includes it, `discount_amount` never does, and a
    # return refunds the goods share only. Default 0 so every row written before this
    # column behaves exactly as it did.
    delivery_fee = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # QA High (Phase 4 close): the change the cashier handed back, in pesos. It comes
    # out of the DRAWER, so the Z-reading subtracts it from the cash tendered - without
    # this column an overpaid sale made the expected drawer look richer than the till
    # by every centavo of change. Derived by `process_sale` from the tenders the server
    # itself stored (never sent by the client), and left at 0 on a return.
    change_given = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    source = models.CharField(
        max_length=15, choices=Source.choices, default=Source.WALK_IN
    )
    # PROTECT, so a reversed sale cannot be deleted out from under its return. Nullable
    # because a return is still valid when the original receipt is not to hand - decision
    # 15's restock rule has a branch for exactly that case.
    original_transaction = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="reversals",
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.COMPLETED
    )
    notes = models.TextField(blank=True, default="")
    # Decision 09 item 2: the client's retry token for THIS checkout attempt, scoped per
    # cashier. Nullable because a client may send no header at all - and then the sale is
    # simply not retry-protected, which is the old behaviour, not an error.
    idempotency_key = models.CharField(max_length=64, null=True, blank=True)
    # The canonical hash of the request body that carried that key. Without it "same key,
    # different cart" is invisible: the server could only replay a sale it has no reason
    # to believe is the same one. Empty (not null) when no key was sent, so the column has
    # one representation of "nothing hashed here".
    request_hash = models.CharField(max_length=64, blank=True, default="")
    # Phase 4 (decision 06): which shift this sale was rung during. SET_NULL, not
    # PROTECT: a shift is a reporting period, and deleting one must not be blocked by
    # - or destroy - the sale history inside it. Nullable so the rows that predate the
    # shift gate stay valid rather than needing a backfill that would be a guess.
    shift = models.ForeignKey(
        "Shift",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_transaction"
        ordering = ["-trans_date"]
        indexes = [
            models.Index(fields=["-trans_date"]),
            models.Index(fields=["status"]),
        ]
        constraints = [
            # Enforced by the DATABASE, not by a view-level lookup: two concurrent retries
            # both read "no such key" and both insert. The unique index is what makes the
            # loser raise IntegrityError, which the view turns into a replay (200) rather
            # than a second sale. Scoped to the cashier so two tills may each use "1".
            models.UniqueConstraint(
                fields=["cashier", "idempotency_key"],
                condition=models.Q(idempotency_key__isnull=False),
                name="uniq_pos_transaction_cashier_idempotency_key",
            ),
        ]

    def __str__(self):
        return f"{self.transaction_no} — {self.grand_total}"


class SalesItem(models.Model):
    transaction = models.ForeignKey(
        SalesTransaction, on_delete=models.CASCADE, related_name="items"
    )
    variant_uom = models.ForeignKey(
        "inventory.VariantUOM", on_delete=models.PROTECT, related_name="sales_items"
    )
    qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(0)]
    )
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    subtotal = models.DecimalField(max_digits=12, decimal_places=2)
    # Phase 7 B1 (decision 19 #3): the order line a fulfilment sale line was rung from,
    # which is what makes "fulfilled vs remaining" arithmetically checkable. NULL for
    # every ordinary till sale; a fulfilment (B4) sets it, and a return against that sale
    # copies nothing - a return is its own line.
    order_line = models.ForeignKey(
        "SalesOrderItem",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="sale_items",
    )

    class Meta:
        db_table = "pos_sales_item"

    def __str__(self):
        return f"{self.transaction.transaction_no} — {self.variant_uom} × {self.qty}"


class SalesItemDeduction(models.Model):
    """Which batches one sale item drew from, and how much from each.

    Task 6A.4: `allocate_fifo` returns (batch, qty) allocations and `process_sale`
    used to discard them, so a return linked to its original sale could not know
    "the original batch it left from" (decision 15's linked branch). One row per
    batch touched — an item spanning two batches writes two rows.
    """

    sales_item = models.ForeignKey(
        SalesItem, on_delete=models.CASCADE, related_name="deductions"
    )
    batch = models.ForeignKey(
        "inventory.InventoryBatch", on_delete=models.PROTECT, related_name="+"
    )
    qty = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = "pos_sales_item_deduction"


class Payment(models.Model):
    class Method(models.TextChoices):
        CASH = "CASH", "Cash"
        CARD = "CARD", "Card"
        GCASH = "GCASH", "GCash"
        BANK_TRANSFER = "BANK_TRANSFER", "Bank Transfer"
        # Phase 4 task B2 (decision 18): a post-dated cheque. The shop does not have the
        # money yet, so this method is the one tender whose row starts PENDING.
        CHEQUE = "CHEQUE", "Cheque"

    class Status(models.TextChoices):
        # The cheque lifecycle. Every other method is CLEARED on creation - cash in the
        # drawer is money received, and pretending otherwise would make the drawer count
        # wrong. PENDING is money owed until a Store Manager or Admin decides it.
        PENDING = "PENDING", "Pending"
        CLEARED = "CLEARED", "Cleared"
        BOUNCED = "BOUNCED", "Bounced"

    transaction = models.ForeignKey(
        SalesTransaction, on_delete=models.CASCADE, related_name="payments"
    )
    method = models.CharField(
        max_length=15, choices=Method.choices, default=Method.CASH
    )
    amount_tendered = models.DecimalField(max_digits=12, decimal_places=2)
    reference_no = models.CharField(max_length=100, blank=True, default="")
    # Phase 4 task B2: PENDING/CLEARED/BOUNCED. Default CLEARED is what every existing row
    # was - money already taken - so the column needs no separate backfill.
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.CLEARED, db_index=True
    )
    cheque_number = models.CharField(max_length=50, blank=True, default="")
    bank = models.CharField(max_length=100, blank=True, default="")
    # Nullable: a cheque date is a fact about the cheque, and there is no honest default
    # for a tender that is not a cheque at all.
    cheque_date = models.DateField(null=True, blank=True)
    # The utang this pending cheque is waiting on. PROTECT: deleting a ledger that a
    # cheque answers for would erase what the cheque was for. Nullable because a tender
    # that is not a cheque owes nothing.
    ledger = models.ForeignKey(
        "collectibles.CollectibleLedger",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="cheques",
    )
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="cheque_decisions",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    # Why a cheque bounced. Empty for a cleared one: the interesting sentence is the
    # bank's refusal.
    decision_reason = models.CharField(max_length=255, blank=True, default="")
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "pos_payment"

    def __str__(self):
        return (
            f"{self.transaction.transaction_no} — {self.method} {self.amount_tendered}"
        )


class OfficialReceipt(models.Model):
    transaction = models.OneToOneField(
        SalesTransaction, on_delete=models.PROTECT, related_name="receipt", unique=True
    )
    or_number = models.CharField(max_length=50, unique=True, db_index=True)
    terminal_no = models.CharField(max_length=20, default="POS-01")
    printed_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "pos_receipt"
        ordering = ["-printed_at"]

    def __str__(self):
        return f"OR #{self.or_number}"


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
        DRAFT = "DRAFT", "Draft"
        SENT = "SENT", "Sent"
        ACCEPTED = "ACCEPTED", "Accepted"
        # The client's canonical enum (SalesQuoteStatus) says `expired`, not `rejected`.
        # Decision 05 made that stack canonical, and a status the client cannot render shows
        # as "Unknown" - avoidable here, unlike the requisition case where `unknown` exists
        # because the server may add statuses the client was never taught.
        EXPIRED = "EXPIRED", "Expired"

    quotation_no = models.CharField(max_length=30, unique=True, db_index=True)
    customer = models.ForeignKey(
        Customer, on_delete=models.PROTECT, related_name="quotations"
    )
    status = models.CharField(
        max_length=15, choices=Status.choices, default=Status.DRAFT, db_index=True
    )
    valid_until = models.DateField(null=True, blank=True)
    notes = models.TextField(blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_quotation"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.quotation_no} — {self.customer}"

    def save(self, *args, **kwargs):
        # Generated server-side, like Requisition.req_number: a client-supplied number would
        # be a second source of truth for something the server must guarantee is unique.
        if not self.quotation_no:
            from common.numbering import generate_document_number

            self.quotation_no = generate_document_number(
                Quotation, "quotation_no", "QT"
            )
        super().save(*args, **kwargs)


class QuotationItem(models.Model):
    quotation = models.ForeignKey(
        Quotation, on_delete=models.CASCADE, related_name="items"
    )
    variant_uom = models.ForeignKey(
        VariantUOM, on_delete=models.PROTECT, related_name="+"
    )
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = "pos_quotation_item"

    def __str__(self):
        return f"{self.quotation.quotation_no} — {self.variant_uom} × {self.qty}"


class SalesOrder(models.Model):
    """Phase 6 task 6A.2 (decision 05).

    The second of the two models decision 05 ruled were missing. Like Quotation it is a DOCUMENT,
    not a sale: no stock moves and no money is taken until it is fulfilled, which is why it does not
    touch InventoryBatch or the ledger.
    """

    class Status(models.TextChoices):
        # Phase 7 B1 (decision 19): CONFIRMED -> PARTIAL -> COMPLETED, plus CANCELLED.
        # PROCESSING and READY are LEGACY - Phase 5 let a client pick a status
        # (decision 22 #16 stopped that) and wrote these two. They stay as choices so
        # old rows keep validating, are never written again, and READ as CONFIRMED
        # everywhere (`effective_status`, the rule table in `services.py`, the wire).
        CONFIRMED = "CONFIRMED", "Confirmed"
        PROCESSING = "PROCESSING", "Processing"
        READY = "READY", "Ready"
        PARTIAL = "PARTIAL", "Partially fulfilled"
        COMPLETED = "COMPLETED", "Completed"
        CANCELLED = "CANCELLED", "Cancelled"

    order_no = models.CharField(max_length=30, unique=True, db_index=True)
    customer = models.ForeignKey(
        Customer, on_delete=models.PROTECT, related_name="sales_orders"
    )
    # SET_NULL, not PROTECT: an order may outlive the quotation it came from, and losing the order
    # because a quotation was deleted would be the wrong trade. The order stands on its own.
    quotation = models.ForeignKey(
        Quotation,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="orders",
    )
    status = models.CharField(
        max_length=15, choices=Status.choices, default=Status.CONFIRMED, db_index=True
    )
    notes = models.TextField(blank=True, default="")
    # Phase 7 B1 (decision 19 #4): cancelling is a reasoned, attributed event, exactly
    # like a failed delivery. PROTECT on the actor (same as `Delivery.created_by`) so the
    # trail never loses WHO cancelled a promise the shop made.
    cancel_reason = models.CharField(max_length=255, blank=True, default="")
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    cancelled_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_sales_order"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.order_no} — {self.customer}"

    @property
    def effective_status(self):
        """The status every rule and the wire read (decision 19).

        `PROCESSING` and `READY` are Phase 5 spellings of CONFIRMED. Mapping them HERE,
        on the model, is what keeps every later rule (edit, cancel, fulfil, the order
        sheet) free of a legacy branch: they all ask `effective_status`.
        """
        return LEGACY_SALES_ORDER_STATUSES.get(self.status, self.status)

    def save(self, *args, **kwargs):
        if not self.order_no:
            from common.numbering import generate_document_number

            self.order_no = generate_document_number(SalesOrder, "order_no", "SO")
        super().save(*args, **kwargs)


# Phase 7 B1 (decision 19): the two statuses Phase 5 wrote before the lifecycle existed.
# They stay as choices so legacy rows keep validating, are never written again, and read
# as CONFIRMED wherever this dict is applied - `SalesOrder.effective_status` is the only
# reader, so no rule anywhere else needs a legacy branch.
LEGACY_SALES_ORDER_STATUSES = {
    SalesOrder.Status.PROCESSING.value: SalesOrder.Status.CONFIRMED,
    SalesOrder.Status.READY.value: SalesOrder.Status.CONFIRMED,
}


class SalesOrderItem(models.Model):
    order = models.ForeignKey(
        SalesOrder, on_delete=models.CASCADE, related_name="items"
    )
    variant_uom = models.ForeignKey(
        VariantUOM, on_delete=models.PROTECT, related_name="+"
    )
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    # Phase 7 B1 (decision 19 #3): what has already been rung into a sale, and what the
    # manager wrote off. B4 adds to the first, B3 moves a remainder into the second; both
    # start at zero so every pre-Phase-7 line reads "nothing fulfilled, nothing cancelled".
    fulfilled_qty = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    cancelled_qty = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    class Meta:
        db_table = "pos_sales_order_item"

    def __str__(self):
        return f"{self.order.order_no} — {self.variant_uom} × {self.qty}"

    @property
    def remaining_qty(self) -> Decimal:
        """`qty - fulfilled - cancelled`: what a till may still ring (decision 19 #3)."""
        return (
            Decimal(self.qty)
            - Decimal(self.fulfilled_qty)
            - Decimal(self.cancelled_qty)
        )


class HeldCart(models.Model):
    cashier = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="held_carts"
    )
    customer = models.ForeignKey(
        Customer,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="held_carts",
    )
    notes = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "pos_held_cart"
        ordering = ["-created_at"]

    def __str__(self):
        return f"HeldCart {self.id} by {self.cashier}"


class HeldCartItem(models.Model):
    cart = models.ForeignKey(HeldCart, on_delete=models.CASCADE, related_name="items")
    variant_uom = models.ForeignKey(
        "inventory.VariantUOM", on_delete=models.PROTECT, related_name="+"
    )
    qty = models.DecimalField(max_digits=12, decimal_places=2)
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        db_table = "pos_held_cart_item"

    def __str__(self):
        return f"HeldCartItem {self.id} — {self.variant_uom} × {self.qty}"


class Shift(models.Model):
    """A cashier's working period: from an opening float to a counted close.

    Phase 4 (decision 06). Owns its transactions by explicit FK rather than deriving
    membership from a time window, because a midnight boundary or two overlapping
    cashiers makes a window ambiguous and unstorable. The Z-reading is NOT stored - it
    is recomputed from `transactions` on demand, so it cannot drift from the sales it
    summarises and a closed shift's numbers are identical every time they are asked for.
    """

    class Status(models.TextChoices):
        OPEN = "OPEN", "Open"
        CLOSED = "CLOSED", "Closed"

    cashier = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="shifts"
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.OPEN, db_index=True
    )
    opening_float = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Nullable because it does not exist until the cashier counts the drawer. A zero
    # default would be indistinguishable from "counted and found empty".
    closing_count = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    opened_at = models.DateTimeField(auto_now_add=True, db_index=True)
    closed_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True, default="")

    class Meta:
        db_table = "pos_shift"
        ordering = ["-opened_at"]
        constraints = [
            # "One open shift per cashier" is enforced by the DATABASE, not by the view:
            # a view-level check races two concurrent opens and lets both through.
            models.UniqueConstraint(
                fields=["cashier"],
                condition=models.Q(status="OPEN"),
                name="one_open_shift_per_cashier",
            ),
        ]

    def __str__(self):
        return f"Shift {self.id} — {self.cashier} ({self.status})"


class DocumentCounter(models.Model):
    """The sequence behind `TRX-YYYYMMDD-NNNN` and `OR-YYYYMMDD-NNNN`, one row per day.

    Decision 09 item 3. Both numbers used to be generated by reading the newest document
    and adding one, which is a race with a live till on either side of it: two requests
    read the same `-0007`, both write `-0008`, and the loser dies on `transaction_no`'s
    unique constraint as a 500 - a LOST SALE, not a slow one. A counter row locked with
    `select_for_update` inside the sale's own atomic block turns the sequence into a
    single serialized fact.

    `last` starts empty (a fresh day) and is SEEDED from the highest number already
    written for that prefix and day the first time the row is created - see
    `apps.pos.services.next_number`. Live data has documents that predate this table, and
    seeding from 0 would hand out their numbers a second time.
    """

    prefix = models.CharField(max_length=10)
    day = models.DateField()
    # No `default`: a counter that silently starts at 0 is exactly the collision this
    # table exists to prevent. `next_number` always supplies the seed - either "same as
    # the highest number already written today" on creation, or the previous value + 1.
    last = models.IntegerField()

    class Meta:
        db_table = "pos_document_counter"
        ordering = ["prefix", "day"]
        constraints = [
            models.UniqueConstraint(
                fields=["prefix", "day"], name="uniq_document_counter_prefix_day"
            ),
        ]

    def __str__(self):
        return f"{self.prefix}-{self.day:%Y%m%d} #{self.last}"


# ---------------------------------------------------------------------------
# Phase 4 task B1 (decision 18) — store settings and the discount approval.
# ---------------------------------------------------------------------------


class StoreSettings(models.Model):
    """The shop's own tax and discount policy: exactly ONE row, always pk=1.

    Decision 18 turned the static Admin Settings page into a real server setting, because
    both numbers are the trust boundary: the VAT rate decides what the receipt claims to
    the BIR, and the discount cap decides how much money a cashier may give away on their
    own authority. A client-side constant would be a suggestion; this row is what the
    checkout actually enforces, and only an Admin may change it.

    `load()` is the one reader. Prices on the shelf INCLUDE VAT (owner ruling), so
    `vat_rate` is applied backwards - `vatable = net / (1 + rate/100)` - never added on
    top.
    """

    SINGLETON_PK = 1

    vat_registered = models.BooleanField(default=True)
    vat_rate = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal("12.00")
    )
    discount_cap_percent = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal("10.00")
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_store_settings"
        verbose_name_plural = "store settings"
        constraints = [
            # "One settings row" enforced by the DATABASE: a second row would make the
            # checkout's answer depend on which row it happened to read first.
            models.CheckConstraint(
                condition=models.Q(pk=1), name="store_settings_singleton"
            ),
        ]

    def __str__(self):
        return (
            f"Store settings (VAT {self.vat_rate}%, cap {self.discount_cap_percent}%)"
        )

    @classmethod
    def load(cls):
        """The one settings row, created with the decision-18 defaults if absent."""
        try:
            return cls.objects.get_or_create(pk=cls.SINGLETON_PK)[0]
        except IntegrityError:
            # Two requests raced the INSERT and the primary key settled it; the loser
            # simply reads the winner's row.
            return cls.objects.get(pk=cls.SINGLETON_PK)


class DiscountApproval(models.Model):
    """One manager's on-the-spot permission to discount above the cap (decision 18).

    The token handed to the till is a `django.core.signing` signature over THIS row's
    `token_id`, so the token cannot be edited into a bigger percent - and the row is
    what makes it ONE-TIME: `used_at` is set under a row lock inside the sale that
    spends it, so a replayed token is refused rather than discounting a second sale.

    The approver's PASSWORD is never stored, never logged and never echoed: this row
    records WHO approved and HOW MUCH, which is all the audit trail needs.
    """

    token_id = models.UUIDField(unique=True, editable=False)
    approver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="discount_approvals",
    )
    percent = models.DecimalField(max_digits=5, decimal_places=2)
    reason = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    expires_at = models.DateTimeField()
    # Null until the approval is spent. Nullable because "not used yet" and "used at
    # midnight" must be distinguishable, and a sentinel timestamp would be a lie.
    used_at = models.DateTimeField(null=True, blank=True)
    transaction = models.ForeignKey(
        SalesTransaction,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="discount_approvals",
    )
    # Phase 7 B1 (decision 19 #1): an order below the cap is an approval spent on the
    # ORDER, not on a sale - fulfilment then charges the agreed price without asking
    # again. PROTECT, like `transaction`: the approval is evidence of a decision.
    sales_order = models.ForeignKey(
        SalesOrder,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="discount_approvals",
    )

    class Meta:
        db_table = "pos_discount_approval"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Approval {self.percent}% by {self.approver_id}"


# ---------------------------------------------------------------------------
# Phase 5 task B3 (decision 18) — delivery.
# ---------------------------------------------------------------------------


class Delivery(models.Model):
    """A till sale or a sales order marked Deliver: where it goes, who takes it, when.

    Decision 18 ruled the shape: address, contact name/phone, scheduled date, fee, and
    three forward-only statuses plus a failure with its reason. The fee is a
    "Delivery charge" on the receipt - VAT-inclusive, and priced from NO stock, so it
    joins the sale's `grand_total` while `discount_amount` stays the goods' business.

    Two deliberate details:

    * `sale` and `sales_order` are BOTH nullable but never both empty - a
      `CheckConstraint` enforces "at least one document" in the DATABASE, because a
      delivery that belongs to nothing is a slip that cannot be printed and a fee nobody
      can explain. BOTH may be set: Phase 7 B4 re-links an ORDER's delivery to the first
      fulfilment sale, and that row must keep the order it came from (decision 19). On a
      sale the fee is ALSO stored on `SalesTransaction.delivery_fee`; on an order it
      lives here until that first fulfilment carries it into the sale.
    * There is no `stored_at`/`pickup_location` column yet: B4 owns the location list
      and will add a nullable FK here, so this model is where that lands.

    Only the three roles the ruling names may move the status (`services
    .transition_delivery`); the cashier who took the order writes the row and nothing
    else. Every transition is row-locked and audited, so two clicks cannot both win.
    """

    class Status(models.TextChoices):
        SCHEDULED = "SCHEDULED", "Scheduled"
        OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY", "Out for delivery"
        DELIVERED = "DELIVERED", "Delivered"
        # Terminal: the trip was made and did not land the goods. The reason is required
        # and stays on the row - that sentence is what the next attempt is about.
        FAILED = "FAILED", "Failed"

    delivery_no = models.CharField(max_length=30, unique=True, db_index=True)
    # PROTECT both ways: a delivery is evidence that a trip was arranged for that
    # document, so deleting the sale underneath it must be refused, not cascade.
    sale = models.ForeignKey(
        SalesTransaction,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="deliveries",
    )
    sales_order = models.ForeignKey(
        SalesOrder,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="deliveries",
    )
    address = models.CharField(max_length=255)
    contact_name = models.CharField(max_length=150)
    contact_phone = models.CharField(max_length=50)
    scheduled_date = models.DateField(db_index=True)
    # >= 0 and two decimals, enforced by `services._validated_delivery` before the row
    # exists; the validator here is the second pair of eyes for ORM-written rows.
    fee = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(0)],
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.SCHEDULED, db_index=True
    )
    failure_reason = models.CharField(max_length=255, blank=True, default="")
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="deliveries"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "pos_delivery"
        # Soonest first, like the bills list: the schedule is a work queue. Tuples, not
        # lists, so this new model adds no RUF012 to the file (Django accepts either).
        ordering = ("scheduled_date", "id")
        constraints = (
            models.CheckConstraint(
                # Phase 7 B1 (decision 19): "at least one", not "exactly one" - a
                # delivery re-linked to the first fulfilment sale keeps its order, so
                # both columns may be set. Belonging to NOTHING is still refused.
                condition=(
                    models.Q(sale__isnull=False) | models.Q(sales_order__isnull=False)
                ),
                name="delivery_at_least_one_document",
            ),
        )

    def __str__(self):
        return f"{self.delivery_no} — {self.status}"

    def save(self, *args, **kwargs):
        # Generated server-side, like Quotation.quotation_no: a client-supplied number
        # would be a second source of truth for something the server must keep unique.
        if not self.delivery_no:
            from common.numbering import generate_document_number

            self.delivery_no = generate_document_number(Delivery, "delivery_no", "DEL")
        super().save(*args, **kwargs)
