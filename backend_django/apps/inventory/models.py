# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIncompatibleMethodOverride=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/models.py: the checker resolves its config from
# its WORKING DIRECTORY and does not run inside this repo here, so pyrightconfig.json is
# not found and this travels with the file. Without django-stubs every
# `Model.objects`, FK-attribute read (`self.po_item.variant`) and
# `BooleanField(default=True)` is a false positive on valid Django, and so is an
# `__str__` whose return type pyright reads off a `CharField`. Django's own
# `manage.py check` and the test run remain the authority.
"""Inventory Module — Product Catalog, Purchasing & Stock (Phase 2).

ERD mapping:
    CATEGORY          → Category
    BRAND             → Brand
    PRODUCT           → Product
    PRODUCT_VARIANT   → ProductVariant
    UNIT_OF_MEASURE   → UnitOfMeasure
    VARIANT_UOM       → VariantUOM
    SUPPLIER          → Supplier
    PURCHASE_ORDER    → PurchaseOrder
    PO_ITEM           → POItem
    GOODS_RECEIPT     → GoodsReceipt
    GOODS_RECEIPT_ITEM → GoodsReceiptItem
    INVENTORY_BATCH   → InventoryBatch
    STOCK_ADJUSTMENT  → StockAdjustment
    SYSTEM_ALERT      → SystemAlert
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import IntegrityError, models, transaction
from django.db.models.functions import Upper

# =========================================================================
# Selling-unit codes  (Phase 6, decisions 11/12/16)
# =========================================================================


def gs1_check_digit(digits: str) -> int:
    """The GS1 mod-10 check digit for `digits` (weights 3,1,3,1… from the RIGHTMOST).

    One function for both code kinds: it validates a factory EAN (`4800016123450`) and
    it derives an internal code from a selling unit's id, so the printed label and the
    scan agree on the same arithmetic.
    """
    total = sum(
        int(char) * (3 if position % 2 == 0 else 1)
        for position, char in enumerate(reversed(digits))
    )
    return (10 - total % 10) % 10


def derived_code(pk: int) -> str:
    """This shop's own code for a selling unit: `QB{id:06}-{check}`, e.g. QB000013-0.

    Derived, never random: unique by construction (ids are unique) and recomputable
    during an audit. The `QB` prefix is reserved so nobody can hand-type a code that a
    future unit will be given automatically.
    """
    digits = f"{pk:06d}"
    return f"QB{digits}-{gs1_check_digit(digits)}"


def normalise_barcode(value) -> str:
    """Trim + upper — the single normalisation the API, the seed and the till share.

    `'  qb000013-0 '` and `'QB000013-0'` are the same code, so the stored value and a
    scanned value compare equal without either side guessing.
    """
    return (value or "").strip().upper()


# =========================================================================
# Catalog master data  (Phase 1)
# =========================================================================


class Category(models.Model):
    name = models.CharField(max_length=100, unique=True, db_index=True)
    # Phase 4 Task 1: the archive replaces the DELETE a clerk wanted. A category is
    # PROTECT-referenced by its products, so deleting it was a 500, and deleting the
    # products first would have erased their sales history. Archiving hides the category
    # from the "new product" picker and leaves its products SELLABLE - the till prices a
    # line from the selling unit, never from the category.
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_category"
        verbose_name_plural = "categories"
        ordering = ["name"]

    def __str__(self):
        return self.name


class Brand(models.Model):
    name = models.CharField(max_length=100, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_brand"
        ordering = ["name"]

    def __str__(self):
        return self.name


class UnitOfMeasure(models.Model):
    code = models.CharField(max_length=20, unique=True, db_index=True)
    name = models.CharField(max_length=50)
    # Decision 16: whole units (Piece, Bag, Box, Pack, Roll, Sheet) are counted in ones;
    # measured ones (Kilogram, Metre, Litre…) take a fraction. The flag lives here so the
    # server, not a hard-coded client list, decides what a fractional quantity means.
    is_whole = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_uom"
        verbose_name = "unit of measure"
        verbose_name_plural = "units of measure"
        ordering = ["code"]

    def __str__(self):
        return f"{self.code} ({self.name})"


# =========================================================================
# Storage locations  (Phase 5 B4, decision 18 "Bodega lite")
# =========================================================================

# The two places migration 0011 creates and `seed_demo` restores after a flush.
STORE_LOCATION_NAME = "Store"
BODEGA_LOCATION_NAME = "Bodega"


class StorageLocation(models.Model):
    """Where a product is kept: a short Admin-managed list, one label per product.

    Decision 18 ruled the server side of "Bodega lite": the till shows "Bodega" on the
    line, the receipt says "Pick up at Bodega", so the pick-up point is a SERVER fact
    rather than a phrase typed into one device (`LocationHintStore` stays a device-only
    shelf hint and is untouched by this).

    **This is a label, not a second stock ledger.** Nothing counts stock per location,
    nothing transfers stock between them, and a batch's quantity does not care which
    location its product names. The full version - per-location counts and transfers -
    is explicitly out of scope for this phase.

    The NAME is unique case-insensitively (`Upper(name)`), because "Bodega" and
    "bodega" are one place with two spellings, and a till choosing between them would
    show two pick-up points. Deactivating is the supported exit (see `Product.stored_at`)
    and no location can be DELETEd: this is a `_CatalogBaseViewSet`, so the verb is 405.
    """

    name = models.CharField(max_length=100, db_index=True)
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_storage_location"
        # Tuples, not lists: this new model adds no RUF012 to the file (Django accepts
        # either), the same convention `apps/pos/models.py` records for `Delivery`.
        ordering = ("name",)
        constraints = (
            models.UniqueConstraint(Upper("name"), name="uniq_storage_location_name"),
        )

    def __str__(self):
        return self.name


def storage_location(name):
    """The location called `name`, created only when the shop has none (idempotent).

    Case-insensitive on purpose: a database that already has "store" must not gain a
    second row spelled "Store" (the unique constraint would refuse it anyway), and the
    migration, the seed and the FK default all have to agree on that. Read first, then
    create inside a savepoint, so losing a race answers the winning row instead of
    leaving the surrounding transaction unusable.
    """
    existing = StorageLocation.objects.filter(name__iexact=name).first()
    if existing is not None:
        return existing
    try:
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            return StorageLocation.objects.create(name=name)
    except IntegrityError:
        return StorageLocation.objects.get(name__iexact=name)


def default_storage_location_pk():
    """The FK default for `Product.stored_at`: the shop's **Store** row.

    A callable rather than `StorageLocation.objects.first()`: the answer has to be the
    row NAMED Store, and it has to exist even on a database whose locations were flushed
    (the seeder's own flush does exactly that), so it is created on demand.
    """
    return storage_location(STORE_LOCATION_NAME).pk


class Product(models.Model):
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name="products"
    )
    brand = models.ForeignKey(Brand, on_delete=models.PROTECT, related_name="products")
    base_name = models.CharField(max_length=255, db_index=True)
    description = models.TextField(blank=True, default="")
    image_url = models.URLField(blank=True, default="")
    # Phase 5 B4 (decision 18): the pick-up point the till, the receipt and the delivery
    # slip show. PROTECT, because a place goods are still assigned to must not vanish
    # from under the label; the exit is `StorageLocation.is_active`, and a location that
    # is deactivated keeps labelling the products that already point at it (the goods did
    # not move). Only NEW assignments of an inactive location are refused, with the
    # stable `INVALID_STORAGE_LOCATION`.
    stored_at = models.ForeignKey(
        StorageLocation,
        on_delete=models.PROTECT,
        related_name="products",
        default=default_storage_location_pk,
    )
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_product"
        ordering = ["base_name"]
        indexes = [
            models.Index(fields=["category", "is_active"]),
            models.Index(fields=["brand"]),
        ]

    def __str__(self):
        return self.base_name


class ProductVariant(models.Model):
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="variants"
    )
    variant_name = models.CharField(max_length=255, db_index=True)
    base_uom = models.ForeignKey(
        UnitOfMeasure,
        on_delete=models.PROTECT,
        related_name="+",
        help_text="Smallest divisible unit for stock tracking.",
    )
    min_stock_threshold = models.DecimalField(
        max_digits=12, decimal_places=2, default=0, validators=[MinValueValidator(0)]
    )
    max_stock_level = models.DecimalField(
        max_digits=12, decimal_places=2, default=0, validators=[MinValueValidator(0)]
    )
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_product_variant"
        ordering = ["product__base_name", "variant_name"]
        indexes = [models.Index(fields=["product", "is_active"])]

    def __str__(self):
        return f"{self.product.base_name} — {self.variant_name}"


class VariantUOM(models.Model):
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.CASCADE, related_name="selling_uoms"
    )
    uom = models.ForeignKey(UnitOfMeasure, on_delete=models.PROTECT, related_name="+")
    barcode_qr = models.CharField(max_length=100, blank=True, default="", db_index=True)
    conversion_factor = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    default_selling_price = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_variant_uom"
        verbose_name = "variant UOM"
        verbose_name_plural = "variant UOMs"
        ordering = ["variant", "uom"]
        constraints = [
            models.UniqueConstraint(fields=["variant", "uom"], name="uq_variant_uom"),
            # Phase 6 (decision 11): one scannable code per selling unit, compared
            # case-insensitively because every write normalises to upper. Blanks are left
            # out of the condition so the constraint never blocks a row that has no code
            # yet - `save()` gives it one straight away (decision 16).
            models.UniqueConstraint(
                Upper("barcode_qr"),
                condition=~models.Q(barcode_qr=""),
                name="uniq_variantuom_barcode",
            ),
        ]

    def __str__(self):
        return f"{self.variant} @ {self.uom.code} (×{self.conversion_factor})"

    def save(self, *args, **kwargs):
        """Every selling unit always carries a code (Phase 6, decision 16).

        Two writes in ONE transaction, because the derived code is built from the row's
        own id: the row first, then `barcode_qr`. The rule lives here rather than in the
        API so the Django admin, the seed command, a shell session and the serializer all
        obey it and no path can leave a unit unscannable.

        A non-blank value is normalised (trim + upper) on the way in, so a code typed in
        lower case by any of those paths still compares equal to a scan.
        """
        self.barcode_qr = normalise_barcode(self.barcode_qr)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            super().save(*args, **kwargs)
            if not self.barcode_qr:
                self.barcode_qr = derived_code(self.pk)
                super().save(update_fields=["barcode_qr"])


# =========================================================================
# Purchasing & Stock  (Phase 2)
# =========================================================================


class Supplier(models.Model):
    company_name = models.CharField(max_length=255, db_index=True)
    contact_person = models.CharField(max_length=255, blank=True, default="")
    phone = models.CharField(max_length=50, blank=True, default="")
    email = models.EmailField(blank=True, default="")
    address = models.TextField(blank=True, default="")
    # Phase 5 B2 (decision 18): payment terms in days. 0 means "due on receipt" - the
    # delegated default - so a bill's due date is simply the receipt date plus this.
    # A supplier bill SNAPSHOTS the value it was issued under (see SupplierBill), so
    # changing the terms later re-dates no bill that already exists.
    terms_days = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_supplier"
        ordering = ["company_name"]

    def __str__(self):
        return self.company_name


class PurchaseOrder(models.Model):
    class Status(models.TextChoices):
        DRAFT = "DRAFT", "Draft"
        ORDERED = "ORDERED", "Ordered"
        PARTIAL = "PARTIAL", "Partially Received"
        COMPLETE = "COMPLETE", "Complete"
        CANCELLED = "CANCELLED", "Cancelled"

    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name="purchase_orders"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    order_date = models.DateField(auto_now_add=True)
    expected_delivery = models.DateField(null=True, blank=True)
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.DRAFT, db_index=True
    )
    notes = models.TextField(blank=True, default="")
    # ------------------------------------------------------------------
    # Phase 5 B2 (decision 18) — the order's money lives on the HEADER.
    # ------------------------------------------------------------------
    # `discount_amount` is the only writable money figure: a peso discount on the whole
    # order, never above its gross (the serializer refuses that before anything is
    # written). It is split across the bills of the order's deliveries in proportion to
    # what each delivery was worth - see `payables.create_bill_for_receipt`.
    discount_amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(Decimal(0))],
    )
    # Shelf prices include VAT (owner ruling), so `True` is the normal case. `False`
    # means the supplier quotes NET of VAT and the tax is ADDED to the discounted net.
    vat_inclusive = models.BooleanField(default=True)
    # A SNAPSHOT of the shop's VAT rate when the API created the order: 0 when the shop
    # is not VAT registered (no VAT may be claimed), otherwise StoreSettings.vat_rate.
    # It is deliberately frozen - a later settings change must not rewrite what an order
    # already says, and each of its bills copies this number, so receipts of the same
    # order keep billing the same VAT for as long as the order exists.
    #
    # The model default is 0 WITHOUT reading StoreSettings, because only the API may
    # claim to have snapshotted the shop policy; rows written by fixtures/older tooling
    # (and every pre-B2 row, via migration 0010) mean "no VAT recorded", which preserves
    # their old totals exactly.
    vat_rate = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(Decimal(0))],
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "inventory_po"
        ordering = ["-order_date"]
        indexes = [
            models.Index(fields=["supplier", "-order_date"]),
            models.Index(fields=["status"]),
        ]

    def __str__(self):
        return f"PO #{self.pk} — {self.supplier.company_name}"

    # The money triple is COMPUTED, never stored on the order: a stored total would be a
    # second copy of `ordered_qty x unit_cost - discount` and would go stale the moment a
    # DRAFT line changed. A bill, by contrast, stores its own figures (it is history).
    #
    #   gross    = SUM(ordered_qty x unit_cost)          (the order as priced)
    #   net      = gross - discount_amount
    #   VAT      = inclusive: net - round(net / (1+rate/100))   (extracted)
    #              exclusive: round(net x rate/100)             (added)
    #   total    = inclusive: net   ·   exclusive: net + VAT
    #
    # Every figure is rounded HALF_UP to two decimals ONCE (the project's money rule), so
    # the parts always add back up. Imported inside the properties because `payables`
    # reads these models at module level.
    @property
    def gross_amount(self):
        from .payables import money

        return money(
            sum(
                (item.ordered_qty * item.unit_cost for item in self.items.all()),
                Decimal(0),
            )
        )

    @property
    def net_amount(self):
        from .payables import money

        return money(self.gross_amount - self.discount_amount)

    @property
    def vatable_amount(self):
        from .payables import vat_split

        return vat_split(
            self.net_amount, rate=self.vat_rate, inclusive=self.vat_inclusive
        )[0]

    @property
    def vat_amount(self):
        from .payables import vat_split

        return vat_split(
            self.net_amount, rate=self.vat_rate, inclusive=self.vat_inclusive
        )[1]

    @property
    def total_amount(self):
        from .payables import money

        if self.vat_inclusive:
            return self.net_amount
        return money(self.net_amount + self.vat_amount)


class POItem(models.Model):
    po = models.ForeignKey(
        PurchaseOrder, on_delete=models.CASCADE, related_name="items"
    )
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name="po_items"
    )
    # Phase 5 B1 (decision 18, "PO by package"): the selling unit this line is counted
    # in. `ordered_qty`, `unit_cost` and `received_qty` are all in THIS unit; receiving
    # converts to stock in base units (`qty x conversion_factor`) at a cost per base
    # unit (`unit_cost / conversion_factor`).
    #
    # PROTECT because a line is purchase history: the unit it names cannot be erased
    # while the line means something, and the catalog's in-use/freeze checks read this
    # table too.
    #
    # Nullable ONLY for rows written by fixtures/older tooling straight through the ORM:
    # the API always persists the unit it validated. A null line is READ as the variant's
    # base unit (factor 1) - exactly what every pre-B1 line meant - and migration 0009
    # points every existing row at its variant's real base row. A required column would
    # have failed every such fixture without a unit to give it.
    variant_uom = models.ForeignKey(
        VariantUOM,
        on_delete=models.PROTECT,
        related_name="po_items",
        null=True,
        blank=True,
    )
    ordered_qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    unit_cost = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    received_qty = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(Decimal(0))],
    )

    class Meta:
        db_table = "inventory_po_item"

    def __str__(self):
        return f"{self.variant} × {self.ordered_qty} @ {self.unit_cost}"


class GoodsReceipt(models.Model):
    po = models.ForeignKey(
        PurchaseOrder, on_delete=models.PROTECT, related_name="receipts"
    )
    received_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    receive_date = models.DateField(auto_now_add=True)
    delivery_receipt_no = models.CharField(max_length=100, blank=True, default="")
    notes = models.TextField(blank=True, default="")
    # Set by process_goods_receipt, inside the same transaction that mints the
    # batches. NULL = never processed. This is the double-process guard: it lives
    # on the row that is locked, so two concurrent process/ calls cannot both pass
    # it (the previous guard read `batches.exists()` outside any lock).
    processed_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "inventory_goods_receipt"
        ordering = ["-receive_date"]

    def __str__(self):
        return f"GR #{self.pk} ← PO #{self.po_id} ({self.receive_date})"


class GoodsReceiptItem(models.Model):
    """One delivered quantity on ONE goods receipt (decision 09 item 4).

    `POItem.received_qty` is a running total across every receipt of the PO, so it
    cannot answer "what did THIS delivery contain". Before this table existed the
    process step minted a batch from the running total on every receipt, which
    stocked 12 units for two deliveries of 5 and 2. A batch is now built from these
    lines, and `received_qty` stays what it always was: the cap the next delivery is
    checked against.
    """

    receipt = models.ForeignKey(
        GoodsReceipt, on_delete=models.CASCADE, related_name="lines"
    )
    # PROTECT: a line is stock evidence, so a PO item that has been delivered
    # cannot be deleted out from under the batches it explains.
    po_item = models.ForeignKey(
        POItem, on_delete=models.PROTECT, related_name="receipt_lines"
    )
    qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )

    class Meta:
        db_table = "inventory_goods_receipt_item"
        ordering = ["id"]

    def __str__(self):
        return f"GR #{self.receipt_id} line: {self.po_item.variant} × {self.qty}"


class InventoryBatch(models.Model):
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name="batches"
    )
    receipt = models.ForeignKey(
        GoodsReceipt, on_delete=models.PROTECT, related_name="batches"
    )
    initial_qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    current_qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    unit_cost_landed = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    markup_percentage = models.DecimalField(
        max_digits=5,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(Decimal(0))],
    )
    batch_selling_price = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    expiration_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "inventory_batch"
        ordering = ["receipt__receive_date"]
        indexes = [models.Index(fields=["variant", "current_qty"])]

    def __str__(self):
        return f"Batch #{self.pk} — {self.variant} ({self.current_qty} left)"


class StockAdjustment(models.Model):
    class AdjustmentType(models.TextChoices):
        SHRINKAGE = "SHRINKAGE", "Shrinkage / Loss"
        DAMAGE = "DAMAGE", "Damaged"
        CORRECTION = "CORRECTION", "Count Correction"
        RETURN = "RETURN", "Return to Supplier"

    variant = models.ForeignKey(
        ProductVariant, on_delete=models.PROTECT, related_name="adjustments"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    adjustment_type = models.CharField(max_length=15, choices=AdjustmentType.choices)
    qty_adjusted = models.DecimalField(max_digits=12, decimal_places=2)
    remarks = models.TextField(blank=True, default="")
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "inventory_stock_adjustment"
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.adjustment_type}: {self.variant} {self.qty_adjusted:+}"


class SystemAlert(models.Model):
    class AlertType(models.TextChoices):
        LOW_STOCK = "LOW_STOCK", "Low Stock"
        OUT_OF_STOCK = "OUT_OF_STOCK", "Out of Stock"
        EXPIRING = "EXPIRING", "Expiring Batch"

    alert_type = models.CharField(max_length=15, choices=AlertType.choices)
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.CASCADE, related_name="alerts"
    )
    message = models.TextField()
    is_resolved = models.BooleanField(default=False, db_index=True)
    # Decision 06 (Phase 2): resolving an alert is a named act. Without these two columns
    # the API could say "resolved" but not "by whom, when", and a second resolve would
    # have silently overwritten the first resolver.
    resolved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
    )
    resolved_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "inventory_system_alert"
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["is_resolved", "-created_at"])]

    def __str__(self):
        return f"[{self.alert_type}] {self.variant}"


# =========================================================================
# Supplier payables  (Phase 5 B2, decision 18)
# =========================================================================


class SupplierBill(models.Model):
    """What the shop owes one supplier for ONE processed goods receipt.

    Decision 18: "processing a delivery creates a supplier bill (received qty x cost,
    less its share of the PO discount; VAT shown), due = receipt date + supplier terms
    days". Created by `payables.create_bill_for_receipt` inside the SAME transaction that
    mints the batches and flips the PO's status, so a bill never exists without the stock
    it pays for and the stock never lands without its bill.

    `receipt` is ONE-TO-ONE on purpose: the receipt is the billing event, so a second
    bill for it is refused by the DATABASE, not by a view (the `processed_at` guard
    already refuses a second processing; this is the second lock on the same door).

    Every figure here is a SNAPSHOT and immutable - see `save()`. `balance_amount` is the
    single mutable number, moved only by `record_supplier_payment` under a row lock.

    Upgrade boundary (accepted): receipts processed BEFORE this phase have no bill and
    never get one - the migration creates no bills, so no retroactive debt appears for
    stock that was already paid for outside the system.
    """

    class Status(models.TextChoices):
        UNPAID = "UNPAID", "Unpaid"
        PARTIAL = "PARTIAL", "Partially Paid"
        PAID = "PAID", "Paid"

    receipt = models.OneToOneField(
        GoodsReceipt, on_delete=models.PROTECT, related_name="bill"
    )
    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name="bills"
    )
    purchase_order = models.ForeignKey(
        PurchaseOrder, on_delete=models.PROTECT, related_name="bills"
    )
    # Copied from the receipt (not a join) so the due date and the bill's own paperwork
    # stay readable even if a later code path ever changes how receipts are dated.
    received_date = models.DateField(db_index=True)
    # The supplier's terms AT ISSUANCE: editing the supplier afterwards re-dates no
    # existing bill, which is the same rule the PO's VAT rate snapshot follows.
    terms_days = models.PositiveIntegerField(default=0)
    due_date = models.DateField(db_index=True)
    # gross = SUM(delivered PACKAGE qty x the line's PACKAGE cost); discount = this
    # receipt's proportional share of the PO header discount; net = gross - discount;
    # vat/rate = the PO's snapshot split; total = gross - discount [+ VAT when the order
    # is VAT-exclusive].
    gross_amount = models.DecimalField(max_digits=12, decimal_places=2)
    discount_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    net_amount = models.DecimalField(max_digits=12, decimal_places=2)
    vat_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    vat_rate = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)
    # The one mutable figure: what is still owed. Never negative (the payment service
    # refuses an amount above it), so 0 is exactly "settled".
    balance_amount = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    created_at = models.DateTimeField(auto_now_add=True)

    # The financial face of the bill. `save()` refuses any change to one of these, so an
    # UPDATE - from the API, the Django admin, a shell session or a future service -
    # cannot rewrite what the shop agreed to owe. Listed once, here, so no caller can
    # forget one of them.
    IMMUTABLE_FIELDS = (
        "receipt",
        "supplier",
        "purchase_order",
        "received_date",
        "terms_days",
        "due_date",
        "gross_amount",
        "discount_amount",
        "net_amount",
        "vat_amount",
        "vat_rate",
        "total_amount",
    )

    class Meta:
        db_table = "inventory_supplier_bill"
        ordering = ["due_date", "pk"]  # noqa: RUF012 - declarative, never mutated
        indexes = [  # noqa: RUF012
            models.Index(fields=["supplier", "due_date"]),
            models.Index(fields=["purchase_order"]),
        ]

    def __str__(self):
        return (
            f"Bill #{self.pk} — {self.supplier.company_name} "
            f"({self.total_amount}, due {self.due_date})"
        )

    @property
    def paid_amount(self):
        """What has been paid so far - the total less the balance, never a stale copy."""
        return self.total_amount - self.balance_amount

    @property
    def vatable_amount(self):
        """The VAT-able part of what is owed. Works for BOTH tax treatments.

        Inclusive: total = net, so total - VAT = vatable.
        Exclusive: total = net + VAT, so total - VAT = net = vatable.
        """
        return self.total_amount - self.vat_amount

    @property
    def status(self):
        """Derived from the balance, never stored: two copies would drift."""
        if self.balance_amount <= 0:
            return self.Status.PAID
        if self.balance_amount >= self.total_amount:
            return self.Status.UNPAID
        return self.Status.PARTIAL

    @property
    def is_overdue(self):
        """Still owed AND past its due date (today inclusive is NOT overdue)."""
        from django.utils import timezone

        return self.balance_amount > 0 and self.due_date < timezone.localdate()

    def save(self, *args, **kwargs):
        """Insert freely; after that only the balance may move.

        The stored row is read on every update, so the guard is not a convention the
        next caller can skip - a `save()` that would rewrite money raises instead. The
        balance update path passes it because every immutable field is unchanged.
        """
        if self.pk is not None:
            stored = (
                type(self)
                .objects.filter(pk=self.pk)
                .values(*self.IMMUTABLE_FIELDS)
                .first()
            )
            if stored is not None:
                from .exceptions import ImmutablePayableRecord

                for field in self.IMMUTABLE_FIELDS:
                    # `.values()` returns a FOREIGN KEY as its id, while the instance
                    # holds the related row, so both sides are compared by pk. Comparing
                    # the row to the id would refuse every legitimate balance update.
                    current = getattr(self, field)
                    current = getattr(current, "pk", current)
                    if stored[field] != current:
                        raise ImmutablePayableRecord(
                            f"Supplier bill #{self.pk}: {field} is history and cannot "
                            "be changed. A wrong bill is corrected by a new business "
                            "event, never by editing this row."
                        )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        """A bill is the evidence of what the shop owes, so it cannot be erased."""
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Supplier bill #{self.pk} cannot be deleted: it is the record of what the "
            "shop owes for a delivery that was already received."
        )


class SupplierPayment(models.Model):
    """One payment against a supplier bill (decision 18).

    Append-only: `save()` refuses an UPDATE of an existing row and `delete()` refuses
    removal, the same discipline `AuditLog` and `CollectiblePayment` follow. A mistake is
    corrected by recording the real business event, not by rewriting the ledger.

    `paid_on` is the ISSUE moment (auto_now_add). Decision 18 keeps supplier cheques
    simple: they are recorded as paid whenever they are issued and lowering the bill
    balance at once - the clear/bounce workflow exists for CUSTOMER cheques only, so this
    table has no pending state.

    Phase 8 B1 (decision 20 #3) added the pending state that matters for a SUPPLIER
    cheque: it starts `ISSUED` and a Store Manager/Admin marks it `CLEARED` or `BOUNCED`.
    The bill balance STILL drops at issue (the money is promised when the cheque changes
    hands); clearing moves nothing, and a bounce puts the amount back on the bill. Every
    other method is born `CLEARED` - cash and transfers leave nothing to decide - which
    is also the migration default for rows that already existed.
    """

    class Method(models.TextChoices):
        CASH = "CASH", "Cash"
        CHEQUE = "CHEQUE", "Cheque"
        BANK_TRANSFER = "BANK_TRANSFER", "Bank Transfer"
        # Phase 8 B1 adds the CHOICE only; applying a credit note is B3's job, so no code
        # path creates a CREDIT payment yet (the serializer refuses one with no note).
        CREDIT = "CREDIT", "Supplier Credit"

    class Status(models.TextChoices):
        # Only a CHEQUE is ever ISSUED. CLEARED is the settled state of every other
        # method (and of a cheque the bank honoured), BOUNCED only ever applies to one.
        ISSUED = "ISSUED", "Issued"
        CLEARED = "CLEARED", "Cleared"
        BOUNCED = "BOUNCED", "Bounced"

    bill = models.ForeignKey(
        SupplierBill, on_delete=models.PROTECT, related_name="payments"
    )
    # Phase 8 B3 (decision 20 #1): the note an applied credit came from. NULL for every
    # other method, and the only row that ever carries it is `method=CREDIT`, written by
    # `payables.apply_credit_to_source_bill` inside the return's transaction.
    credit_note = models.ForeignKey(
        "SupplierCreditNote",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="payments",
    )
    # The actor is assigned from `request.user`; it is never a client input.
    paid_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )
    method = models.CharField(max_length=20, choices=Method.choices)
    reference = models.CharField(max_length=100, blank=True, default="")
    # Only a cheque carries these; the service refuses a cheque missing any of them.
    cheque_number = models.CharField(max_length=100, blank=True, default="")
    cheque_bank = models.CharField(max_length=100, blank=True, default="")
    cheque_date = models.DateField(null=True, blank=True)
    paid_on = models.DateTimeField(auto_now_add=True, db_index=True)

    # Phase 8 B1 (decision 20 #3): the cheque's own life. `CLEARED` is the column default
    # so the migration settles every existing row (old supplier cheques included) and any
    # creator that does not think about status. `payables.record_supplier_payment` is the
    # only writer that sets ISSUED.
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.CLEARED
    )
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    decided_at = models.DateTimeField(null=True, blank=True)
    decision_reason = models.CharField(max_length=255, blank=True, default="")

    # The ONLY fields a stored row may ever be written with, and only while it is ISSUED:
    # `payables.decide_supplier_cheque` stamps exactly these under the row lock. Listed
    # once, here, so neither the service nor a shell session can widen the door.
    DECISION_FIELDS = ("status", "decided_by", "decided_at", "decision_reason")

    class Meta:
        db_table = "inventory_supplier_payment"
        ordering = ["-paid_on", "-pk"]  # noqa: RUF012 - declarative, never mutated
        indexes = [models.Index(fields=["bill", "-paid_on"])]  # noqa: RUF012

    def __str__(self):
        return (
            f"Supplier payment #{self.pk} — Bill #{self.bill_id} "
            f"({self.amount} {self.method})"
        )

    def save(self, *args, **kwargs):
        """Insert only - except the one decision a cheque is waiting for.

        A stored payment is a fact about money that already moved, so an UPDATE raises.
        The single door is decision 20 #3: a row whose STORED status is `ISSUED` may be
        written with nothing but `DECISION_FIELDS`. The stored status is read on every
        write, so "decided once" holds even if a caller holds a stale instance, and
        `update_fields` is required - a bare `save()` rewrites every column and is
        refused.
        """
        if self.pk is not None:
            from .exceptions import ImmutablePayableRecord

            stored = type(self).objects.filter(pk=self.pk).values("status").first()
            if stored is not None:
                update_fields = kwargs.get("update_fields")
                is_decision = (
                    stored["status"] == self.Status.ISSUED
                    and bool(update_fields)
                    and set(update_fields) <= set(self.DECISION_FIELDS)
                )
                if not is_decision:
                    raise ImmutablePayableRecord(
                        f"Supplier payment #{self.pk} cannot be changed: a payment is a "
                        "record of money that already moved. Only an issued cheque may "
                        "still be cleared or bounced."
                    )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Supplier payment #{self.pk} cannot be deleted: remove it from the books "
            "only by recording the real business event."
        )


# =========================================================================
# Supplier returns  (Phase 8 B2, decision 20)
# =========================================================================


class SupplierReturn(models.Model):
    """Goods going BACK to a supplier, off the receipt they arrived on.

    Decision 20 #2: a return picks the PO RECEIPT the goods came in on, so the stock
    leaves THAT receipt's batches (see `services.allocate_from_receipt`) and the cap is
    what that delivery still holds - not the shop's total for the variant, which may sit
    in a dozen other deliveries with other landed costs.

    **No number of its own.** Decision 20 #1 makes the credit note the numbered
    document (Phase 8 B3), and a second sequence nobody prints would be a unique value to
    maintain for nothing. Until B3 lands, a return is identified by its pk and by the
    receipt it came from.

    Append-only like `SupplierBill`: every column is a snapshot of the act - which
    receipt, which supplier, which bill, why, who - and none of it may be edited or
    deleted afterwards. A wrong return is corrected by a new business event, never by
    rewriting this one.
    """

    receipt = models.ForeignKey(
        GoodsReceipt, on_delete=models.PROTECT, related_name="supplier_returns"
    )
    # Copied at write time, not joined through the receipt: a return names the supplier
    # and the PO it answers, so a payables screen can group by supplier in one query.
    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name="supplier_returns"
    )
    purchase_order = models.ForeignKey(
        PurchaseOrder, on_delete=models.PROTECT, related_name="supplier_returns"
    )
    # The bill the goods came in on, when the receipt was billed (Phase 5 B2). NULL for
    # a receipt processed before bills existed and for a zero-value delivery; B3's credit
    # note is then born unapplied instead of lowering a bill.
    bill = models.ForeignKey(
        SupplierBill,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="supplier_returns",
    )
    reason = models.TextField()
    # The actor comes from `request.user`; it is never a client input.
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "inventory_supplier_return"
        ordering = ["-created_at", "-pk"]  # noqa: RUF012 - declarative, never mutated

    def __str__(self):
        return f"Supplier return #{self.pk} ← receipt #{self.receipt_id}"

    def save(self, *args, **kwargs):
        """Insert only. Nothing on a stored return may be written again."""
        if self.pk is not None:
            from .exceptions import ImmutablePayableRecord

            raise ImmutablePayableRecord(
                f"Supplier return #{self.pk} cannot be changed: it records stock that "
                "has already left the shop. Correct it with a new business event."
            )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Supplier return #{self.pk} cannot be deleted: it is the only record of "
            "the stock that went back to the supplier."
        )


class SupplierReturnLine(models.Model):
    """One returned quantity, counted in the receipt LINE's package unit.

    `qty` is what the clerk typed (e.g. 2 BAG), `base_qty` is the stock that left
    (`qty x the line's conversion factor`), and `credit_value` is what those units were
    worth at the landed cost of the batches they came out of - rounded ONCE with
    `payables.money`, because the same stock may have left two batches at slightly
    different costs.

    The two quantities are stored rather than derived because the line's unit is a
    moving target: editing a selling unit's conversion factor is refused while history
    references it (decision 16), but the stored pair also keeps this row readable
    without a join to the PO line.
    """

    supplier_return = models.ForeignKey(
        SupplierReturn, on_delete=models.CASCADE, related_name="lines"
    )
    # PROTECT: the delivered line is the evidence of what arrived and what is still
    # returnable against it, so it cannot be removed out from under a return.
    receipt_line = models.ForeignKey(
        GoodsReceiptItem, on_delete=models.PROTECT, related_name="return_lines"
    )
    qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    base_qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    credit_value = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )

    class Meta:
        db_table = "inventory_supplier_return_line"
        ordering = ["pk"]  # noqa: RUF012 - declarative, never mutated

    def __str__(self):
        return (
            f"Return #{self.supplier_return_id} line: {self.qty} ({self.base_qty} base)"
        )

    def save(self, *args, **kwargs):
        if self.pk is not None:
            from .exceptions import ImmutablePayableRecord

            raise ImmutablePayableRecord(
                f"Supplier return line #{self.pk} cannot be changed: it records a "
                "quantity that has already left the shop."
            )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Supplier return line #{self.pk} cannot be deleted: it explains stock that "
            "is no longer on the rack."
        )


class SupplierReturnDeduction(models.Model):
    """Which batches one return line drew from, and how much from each.

    Mirrors `pos.SalesItemDeduction`: one row per batch touched, so a return spanning two
    batches writes two rows and the sum is exactly the line's `base_qty`. `unit_cost_landed`
    is a SNAPSHOT - a batch's cost is history, and the credit this return is worth must
    stay readable even if a later code path ever recomputes a batch's cost.
    """

    line = models.ForeignKey(
        SupplierReturnLine, on_delete=models.CASCADE, related_name="deductions"
    )
    batch = models.ForeignKey(
        InventoryBatch, on_delete=models.PROTECT, related_name="return_deductions"
    )
    qty = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal("0.01"))]
    )
    unit_cost_landed = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )

    class Meta:
        db_table = "inventory_supplier_return_deduction"
        ordering = ["pk"]  # noqa: RUF012 - declarative, never mutated
        indexes = [models.Index(fields=["batch"])]  # noqa: RUF012

    def __str__(self):
        return f"Return line #{self.line_id}: {self.qty} from batch #{self.batch_id}"

    def save(self, *args, **kwargs):
        if self.pk is not None:
            from .exceptions import ImmutablePayableRecord

            raise ImmutablePayableRecord(
                f"Supplier return deduction #{self.pk} cannot be changed: it records "
                "stock that has already left the shop."
            )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Supplier return deduction #{self.pk} cannot be deleted: it explains which "
            "batch the returned stock came out of."
        )


# =========================================================================
# Supplier credit notes  (Phase 8 B3, decision 20 #1)
# =========================================================================


class SupplierCreditNote(models.Model):
    """The numbered document a supplier return is worth (decision 20 #1).

    Decision 20 #1 is one combined rule: each supplier return creates a numbered CREDIT
    NOTE, and that note's value first lowers the unpaid balance of the bill the goods came
    in on. Whatever that bill cannot absorb - it was already paid, or the note is worth
    more than what is left - stays as supplier-level credit (`remaining_amount`) for a
    manager to apply by hand against any later bill of the same supplier.

    **`supplier_return` is ONE-TO-ONE**: a return is worth exactly one note, and the
    DATABASE refuses a second one. The number comes from `pos.services.next_number`
    (`CN-YYYYMMDD-NNNN`, a locked `DocumentCounter`), reserved inside the return's own
    transaction so two concurrent returns cannot share it.

    **Money shape** (the same two-way VAT rule bills follow, so a credit mirrors what was
    billed):

    * `value` = the returned stock's landed cost, `SUM(base qty x batch unit_cost_landed)`
      over the return's deductions, rounded once HALF_UP.
    * `vat_inclusive` (from the source bill's PO snapshot): `total_amount = value` and the
      tax is EXTRACTED - `vat_amount = value - round(value / (1 + rate/100))`.
    * VAT-exclusive: `vat_amount = round(value x rate/100)` and
      `total_amount = value + vat_amount`.
    * `vat_rate` is the SOURCE BILL's snapshot (the PO's own rate when the receipt created
      no bill), never today's settings: a later rate change re-prices no history.

    Append-only like `SupplierBill` - see `save()`. `remaining_amount` is the single
    mutable figure and moves only under the note's row lock, in the same transaction that
    creates the CREDIT payment lowering the bill.
    """

    number = models.CharField(max_length=24, unique=True)
    supplier_return = models.OneToOneField(
        SupplierReturn, on_delete=models.PROTECT, related_name="credit_note"
    )
    # Copied from the return (not joined) so a payables screen groups by supplier without
    # walking back through the return to the receipt to the PO.
    supplier = models.ForeignKey(
        Supplier, on_delete=models.PROTECT, related_name="credit_notes"
    )
    # The bill this credit tries to lower first. NULL when the receipt created no bill
    # (a pre-Phase-5 receipt or a zero-value delivery): the whole note is then born
    # unapplied and lives on as supplier credit.
    source_bill = models.ForeignKey(
        SupplierBill,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="credit_notes",
    )
    value = models.DecimalField(max_digits=12, decimal_places=2)
    vat_rate = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    vat_inclusive = models.BooleanField(default=True)
    vat_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total_amount = models.DecimalField(max_digits=12, decimal_places=2)
    # The one mutable figure: credit still available to apply. Never negative - the
    # application takes `min(remaining, bill balance)`, so 0 is exactly "used up".
    remaining_amount = models.DecimalField(
        max_digits=12, decimal_places=2, validators=[MinValueValidator(Decimal(0))]
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    # What the note was when it was issued. `save()` refuses any change to one of these,
    # so no UPDATE - API, admin, shell or a future service - can re-price a credit.
    IMMUTABLE_FIELDS = (
        "number",
        "supplier_return",
        "supplier",
        "source_bill",
        "value",
        "vat_rate",
        "vat_inclusive",
        "vat_amount",
        "total_amount",
    )

    class Meta:
        db_table = "inventory_supplier_credit_note"
        ordering = ["-created_at", "-pk"]  # noqa: RUF012 - declarative, never mutated
        indexes = [  # noqa: RUF012
            models.Index(fields=["supplier", "remaining_amount"]),
        ]

    def __str__(self):
        return f"Credit note {self.number} — {self.supplier.company_name}"

    @property
    def applied_amount(self):
        """How much of this note has already been used - derived, never stored."""
        return self.total_amount - self.remaining_amount

    @property
    def vatable_amount(self):
        """The VAT-able part, for both tax treatments (mirrors `SupplierBill`)."""
        return self.total_amount - self.vat_amount

    def save(self, *args, **kwargs):
        """Insert freely; after that only `remaining_amount` may move.

        The stored row is read on every update, so the guard holds even for a caller
        holding a stale instance - only the application path (which changes nothing else
        and passes `update_fields`) gets through.
        """
        if self.pk is not None:
            stored = (
                type(self)
                .objects.filter(pk=self.pk)
                .values(*self.IMMUTABLE_FIELDS)
                .first()
            )
            if stored is not None:
                from .exceptions import ImmutablePayableRecord

                for field in self.IMMUTABLE_FIELDS:
                    # `.values()` returns a FOREIGN KEY as its id while the instance holds
                    # the related row, so both sides are compared by pk.
                    current = getattr(self, field)
                    current = getattr(current, "pk", current)
                    if stored[field] != current:
                        raise ImmutablePayableRecord(
                            f"Credit note {self.number}: {field} is history and cannot "
                            "be changed. A wrong note is corrected by a counter-entry, "
                            "never by editing this row."
                        )
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        """A note is credit the shop is owed, so it cannot be erased."""
        from .exceptions import ImmutablePayableRecord

        raise ImmutablePayableRecord(
            f"Credit note {self.number} cannot be deleted: it records credit the supplier "
            "owes the shop for goods that already went back."
        )
