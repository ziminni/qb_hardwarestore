# pyright: reportAttributeAccessIssue=false, reportMissingImports=false
#
# Same directive and reason as apps/inventory/models.py and apps/inventory/views.py: the
# checker resolves its config from its WORKING DIRECTORY and does not run inside this
# repo, so pyrightconfig.json is not found and this travels with the file. Without
# django-stubs every `Model.objects` is a false positive on valid Django, and Django's own
# `manage.py check` plus the test run remain the authority on what this file does.
"""Inventory app — serializers for product catalog (Sprint 1)."""

from decimal import Decimal

from django.db import transaction
from rest_framework import serializers

from common.exceptions import refuse_fractional_whole_unit

from .exceptions import (
    BarcodeInvalid,
    BarcodeReservedPrefix,
    BarcodeTaken,
    DuplicateBaseUnit,
    InvalidPurchaseOrder,
    InvalidSellingUnit,
    InvalidStorageLocation,
    InvalidSupplierPayment,
    InvalidSupplierTerms,
    InvalidVariant,
    SellingUnitInUse,
    SupplierInactive,
)
from .models import (
    STORE_LOCATION_NAME,
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    StorageLocation,
    Supplier,
    SupplierBill,
    SupplierPayment,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
    derived_code,
    gs1_check_digit,
    normalise_barcode,
)
from .services import lock_selling_unit_lines


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name", "is_active", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]


class BrandSerializer(serializers.ModelSerializer):
    class Meta:
        model = Brand
        fields = ["id", "name", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]


class UnitOfMeasureSerializer(serializers.ModelSerializer):
    class Meta:
        model = UnitOfMeasure
        fields = ["id", "code", "name", "is_whole", "created_at", "updated_at"]
        # Read-only in the API: the flag decides what may be sold as a fraction, and
        # decision 16 keeps that a server fact (rare extras and corrections via admin).
        read_only_fields = ["id", "is_whole", "created_at", "updated_at"]


class StorageLocationSerializer(serializers.ModelSerializer):
    """Where a product is kept (Phase 5 B4, decision 18 "Bodega lite").

    `name` is checked HERE rather than left to the database's case-insensitive unique
    constraint, because an `IntegrityError` is a 500 and the shop's answer is a stable
    `{code, detail}` **400** (`INVALID_STORAGE_LOCATION`) that the client can branch on -
    the same reason `terms_days` is declared explicitly on a supplier.

    The pre-check is a read and the insert a write, so two Admins creating "bodega" at
    the same instant cannot both win; `StorageLocationViewSet` maps the loser's unique-
    constraint `IntegrityError` to this same 400 after its `atomic` block rolls back
    (`_refuse_lost_storage_name_race`), and re-raises any other constraint failure.
    """

    class Meta:
        model = StorageLocation
        fields = [  # noqa: RUF012 - declarative DRF Meta option, not mutable state
            "id",
            "name",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]  # noqa: RUF012

    def validate_name(self, value):
        name = (value or "").strip()
        if not name:
            raise InvalidStorageLocation(
                "a storage location needs a name: it is what the till and the delivery "
                "slip print as the pick-up point."
            )
        rivals = StorageLocation.objects.filter(name__iexact=name)
        if self.instance is not None:
            rivals = rivals.exclude(pk=self.instance.pk)
        holder = rivals.first()
        if holder is not None:
            raise InvalidStorageLocation(
                f'"{holder.name}" is already a storage location: names are compared '
                f'ignoring case, so "{name}" would be the same place.'
            )
        return name


def unit_in_use(unit) -> bool:
    """True when ANY of the six tables that PROTECT a selling unit references it.

    Phase 1d Task 1: the same references the removal rule and the freeze rule read
    (`pos.SalesItem`, `pos.HeldCartItem`, `pos.QuotationItem`, `pos.SalesOrderItem`,
    `requisitions.RequisitionItem`). Phase 5 B1 adds `POItem`: a purchase-order line is
    counted in its selling unit, so removing that unit would leave a live order whose
    quantities no longer mean anything. One definition here so a screen's "can this be
    removed?" and the delete itself cannot disagree. A single row costs six EXISTS
    queries; `annotate_unit_in_use` answers the same question for a whole list in one.
    """
    from apps.pos.models import HeldCartItem, QuotationItem, SalesItem, SalesOrderItem
    from apps.requisitions.models import RequisitionItem

    return any(
        model.objects.filter(variant_uom_id=unit.pk).exists()
        for model in (
            SalesItem,
            HeldCartItem,
            QuotationItem,
            SalesOrderItem,
            RequisitionItem,
            POItem,
        )
    )


def annotate_unit_in_use(queryset):
    """Attach `in_use` to every row of a `VariantUOM` queryset — one query, no N+1.

    Six `EXISTS` subqueries ride along with the list the view was already fetching, so a
    catalog screen can show the flag on every row without asking per unit.
    """
    from django.db.models import Exists, OuterRef

    from apps.pos.models import HeldCartItem, QuotationItem, SalesItem, SalesOrderItem
    from apps.requisitions.models import RequisitionItem

    reference = None
    for model in (
        SalesItem,
        HeldCartItem,
        QuotationItem,
        SalesOrderItem,
        RequisitionItem,
        POItem,
    ):
        exists = Exists(model.objects.filter(variant_uom=OuterRef("pk")))
        reference = exists if reference is None else reference | exists
    return queryset.annotate(in_use=reference)


def selling_unit_freeze_reason(unit) -> str:
    """Why this unit's variant/uom/factor is frozen: `'sold'`, `'requested'`, `'ordered'` or `''`.

    `'sold'` covers a `SalesItem` (money already taken, stock already deducted, so a
    change re-writes what the return cap and restock are measured against) and a
    `HeldCartItem` (a parked cart that will be sold as it stands, so the same change
    would reprice or re-measure a cart a cashier is holding).

    `'requested'` covers a `RequisitionItem` (decision 16, Q4): a project request names
    the selling unit CPMS was shown and the till releases it with one scan, so its factor
    and unit are as load-bearing as a sale's - the release prices and deducts in BASE
    units, and a changed factor would re-measure a request that is still open.

    `'ordered'` covers a `POItem` (Phase 5 B1, decision 18): a purchase-order line's
    quantity and cost are counted in this unit, and receiving multiplies by its factor
    to stock base units. Re-pointing or re-factoring the unit would re-measure an order
    the supplier has been told to deliver and change what its deliveries will stock.

    Quotations and sales orders are DOCUMENTS priced on the day they were written and move
    no stock; they count as USED for removal (`unit_in_use`) but stay out of this freeze.
    """
    from apps.pos.models import HeldCartItem, SalesItem
    from apps.requisitions.models import RequisitionItem

    if (
        SalesItem.objects.filter(variant_uom_id=unit.pk).exists()
        or HeldCartItem.objects.filter(variant_uom_id=unit.pk).exists()
    ):
        return "sold"
    if RequisitionItem.objects.filter(variant_uom_id=unit.pk).exists():
        return "requested"
    if POItem.objects.filter(variant_uom_id=unit.pk).exists():
        return "ordered"
    return ""


class VariantUOMSerializer(serializers.ModelSerializer):
    """A selling unit — the row the till prices a line from.

    `conversion_factor` and `default_selling_price` are declared EXPLICITLY, without the
    model's `MinValueValidator`s, because DRF copies those validators onto the generated
    field and they run before `validate()`: a factor of 0 answered
    `{"conversion_factor": ["Ensure this value is greater than or equal to 0.01."]}`, a
    dict no client can branch on. Declaring the two fields keeps the same refusal but in
    the project's stable `{code, detail}` shape (`INVALID_SELLING_UNIT`).
    """

    uom_code = serializers.CharField(source="uom.code", read_only=True)
    uom_name = serializers.CharField(source="uom.name", read_only=True)
    # Task 3 (decision 13): a scan that misses the till's catalogue asks the server, and
    # a miss has to explain WHY the unit cannot be sold - "belongs to <product>, which is
    # archived" is a different message from "no product has that code". Names and both
    # archive flags travel with the row so the client needs no second request.
    product_name = serializers.CharField(
        source="variant.product.base_name", read_only=True
    )
    variant_name = serializers.CharField(source="variant.variant_name", read_only=True)
    variant_is_active = serializers.BooleanField(
        source="variant.is_active", read_only=True
    )
    product_is_active = serializers.BooleanField(
        source="variant.product.is_active", read_only=True
    )
    conversion_factor = serializers.DecimalField(max_digits=12, decimal_places=2)
    default_selling_price = serializers.DecimalField(max_digits=12, decimal_places=2)
    # Phase 1d Task 1: the till reads whether this unit is counted in ones instead of
    # keeping its own list, and a screen offers "remove" only where nothing references
    # the unit. Both are computed, so neither is writable here.
    uom_is_whole = serializers.BooleanField(source="uom.is_whole", read_only=True)
    # Phase 5 B4 (decision 18): the till shows this label on the line the unit prices,
    # and the scan lookup needs it too (the till may not hold the product list).
    # Read-only here: the label hangs off the PRODUCT, not off a selling unit.
    stored_at = serializers.IntegerField(
        source="variant.product.stored_at_id", read_only=True
    )
    stored_at_name = serializers.CharField(
        source="variant.product.stored_at.name", read_only=True
    )
    in_use = serializers.SerializerMethodField()

    # Frozen once the unit has been sold or requested: they decide what a past or pending
    # document MEANT. The price is deliberately absent — a shop reprices all the time and
    # the sale line keeps its own `unit_price`, so raising the price cannot corrupt
    # history. Keyed by `selling_unit_freeze_reason`, which is also what decides the
    # sentence the clerk reads.
    FROZEN_ONCE_SOLD = ("variant", "uom", "conversion_factor")
    FROZEN_SENTENCE = {
        "sold": ("has been sold", "past sales and returns"),
        "requested": ("is on a project request", "that request and its release"),
        "ordered": (
            "is on a purchase order",
            "that order and the stock its receiving creates",
        ),
    }

    class Meta:
        model = VariantUOM
        fields = [
            "id",
            "variant",
            "uom",
            "uom_code",
            "uom_name",
            "uom_is_whole",
            "product_name",
            "variant_name",
            "product_is_active",
            "variant_is_active",
            "barcode_qr",
            "conversion_factor",
            "default_selling_price",
            "stored_at",
            "stored_at_name",
            "in_use",
        ]
        read_only_fields = ["id"]

    def get_in_use(self, obj):
        """`annotate_unit_in_use`'s annotation when the view attached one, else ask.

        Views annotate their querysets, so a LIST costs one query. A response to a write
        returns the row the serializer just saved, which carries no annotation, so the
        single-row check is what answers there — five EXISTS queries for one unit, never
        per row of a list.
        """
        annotated = getattr(obj, "in_use", None)
        if annotated is not None:
            return annotated
        return unit_in_use(obj)

    def validate_barcode_qr(self, value):
        """One normalised, check-digit-valid, unclaimed code per selling unit.

        Decisions 11/12: trim + upper so a stored code equals a scanned one; printable
        ASCII without spaces so it can be printed and read; a GS1 check digit on an
        all-digit 8/12/13-character manufacturer code so a keying typo is caught before
        the label is trusted; `QB` reserved for codes the server derives itself.

        An empty value is ALLOWED and returned empty: the model's `save()` then derives
        this unit's own `QB` code (decision 16), which is what makes a PATCH of `''` a
        restore rather than an unscannable row.
        """
        code = normalise_barcode(value)
        if not code:
            return ""

        if len(code) > 100 or not all(33 <= ord(char) < 127 for char in code):
            raise BarcodeInvalid(
                "barcode_qr must be printable ASCII without spaces or control "
                "characters, at most 100 characters: a code is printed and read by a "
                "scanner, so it has to survive both."
            )

        if code.isdigit() and len(code) in (8, 12, 13):
            expected = gs1_check_digit(code[:-1])
            if expected != int(code[-1]):
                raise BarcodeInvalid(
                    f"{code} fails the GS1 check digit: the last digit should be "
                    f"{expected}. Re-read the number on the package."
                )

        if code.startswith("QB"):
            own = derived_code(self.instance.pk) if self.instance is not None else None
            if code != own:
                detail = f'{code} is refused: "QB" codes are generated by the server.'
                raise BarcodeReservedPrefix(
                    f"{detail} This unit's own code is {own}."
                    if own
                    else f"{detail} A new selling unit is given its own code automatically."
                )

        holder = self._barcode_holder(code)
        if holder is not None:
            raise BarcodeTaken(
                f"{code} is already the code of {holder.variant.product.base_name} · "
                f"{holder.variant.variant_name} · {holder.uom.code}. A code is what a "
                "scan resolves to, so one unit per code."
            )

        return code

    def _barcode_holder(self, code):
        """The OTHER selling unit already holding `code`, case-insensitively.

        Only a readable refusal - the DB constraint is the real guard, because this read
        and the write are not one atomic step (see `VariantUOMViewSet`).
        """
        rivals = VariantUOM.objects.filter(barcode_qr__iexact=code)
        if self.instance is not None:
            rivals = rivals.exclude(pk=self.instance.pk)
        return rivals.select_related("variant__product", "uom").first()

    def validate(self, attrs):
        variant = attrs.get("variant")
        if variant is None and self.instance is not None:
            variant = self.instance.variant
        factor = attrs.get("conversion_factor")
        if factor is None and self.instance is not None:
            factor = self.instance.conversion_factor
        price = attrs.get("default_selling_price")
        if price is None and self.instance is not None:
            price = self.instance.default_selling_price

        if factor is not None and factor <= 0:
            raise InvalidSellingUnit(
                "conversion_factor must be greater than 0: it is how many base units "
                "one selling unit is, and a sale multiplies by it."
            )
        if price is not None and price < 0:
            raise InvalidSellingUnit("default_selling_price must not be negative.")

        if factor is not None and factor == 1 and variant is not None:
            # Factor 1 IS the base unit. Checked on create and whenever the factor is
            # written, so an unrelated PATCH cannot re-open the ambiguity either.
            rivals = VariantUOM.objects.filter(variant=variant, conversion_factor=1)
            if self.instance is not None:
                rivals = rivals.exclude(pk=self.instance.pk)
            if rivals.exists():
                raise DuplicateBaseUnit(
                    f"{variant} already has a conversion-factor-1 selling unit: a "
                    "variant has exactly one base unit."
                )

        if self.instance is not None:
            changed = [
                field
                for field in self.FROZEN_ONCE_SOLD
                if field in attrs
                and _field_value(attrs[field])
                != _field_value(getattr(self.instance, field))
            ]
            reason = selling_unit_freeze_reason(self.instance) if changed else ""
            if reason:
                state, history = self.FROZEN_SENTENCE[reason]
                raise SellingUnitInUse(
                    f"{self.instance} {state}: {', '.join(changed)} cannot be "
                    f"changed without rewriting what {history} mean. Create a new "
                    "selling unit; the price stays editable."
                )

        if (
            self.instance is not None
            and "barcode_qr" in attrs
            and not attrs["barcode_qr"]
            and self.instance.barcode_qr == derived_code(self.instance.pk)
        ):
            # A blank code means "restore my own code" (decision 16). When that IS the
            # stored code the PATCH changes nothing, so it must not write an `UPDATE`
            # audit row claiming an edit that `save()` then undoes - the same rule
            # `_nothing_changed` applies to a `{}` body.
            attrs.pop("barcode_qr")

        return attrs


def _field_value(value):
    """A comparable key for a validated field: an FK instance compares by its pk."""
    return getattr(value, "pk", value)


class ProductVariantSerializer(serializers.ModelSerializer):
    """A variant. Thresholds may not go negative; product/base_uom are set once.

    Both thresholds are declared explicitly for the same reason as the selling unit's
    factor: the model's `MinValueValidator(0)` fired first and answered with DRF's
    field-error dict instead of the project's `INVALID_VARIANT` code.
    """

    base_uom_code = serializers.CharField(source="base_uom.code", read_only=True)
    selling_uoms = VariantUOMSerializer(many=True, read_only=True)
    # Phase 5 B4 (decision 18): a variant is stored where its PRODUCT is, read-only -
    # moving goods between places is not this phase's job (no per-location stock).
    stored_at = serializers.IntegerField(source="product.stored_at_id", read_only=True)
    stored_at_name = serializers.CharField(
        source="product.stored_at.name", read_only=True
    )
    min_stock_threshold = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False
    )
    max_stock_level = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False
    )

    class Meta:
        model = ProductVariant
        fields = [
            "id",
            "product",
            "variant_name",
            "base_uom",
            "base_uom_code",
            "min_stock_threshold",
            "max_stock_level",
            "stored_at",
            "stored_at_name",
            "is_active",
            "selling_uoms",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    # Set at creation: stock batches, sale deductions and every historical figure hang
    # off these two, so re-pointing them would rewrite the variant's whole history.
    FROZEN_AFTER_CREATION = ("product", "base_uom")

    def validate(self, attrs):
        for field in ("min_stock_threshold", "max_stock_level"):
            value = attrs.get(field)
            if value is not None and value < 0:
                raise InvalidVariant(f"{field} must not be negative.")

        if self.instance is not None:
            for field in self.FROZEN_AFTER_CREATION:
                if field not in attrs:
                    continue
                if _field_value(attrs[field]) != _field_value(
                    getattr(self.instance, field)
                ):
                    raise InvalidVariant(
                        f"{field} is set when the variant is created: changing it "
                        "would re-point its stock and sales history."
                    )

        return attrs


class ProductSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source="category.name", read_only=True)
    brand_name = serializers.CharField(source="brand.name", read_only=True)
    # Phase 5 B4 (decision 18): the ONE writable place. A product is stored somewhere;
    # its variants, selling units, sale lines and delivery slips all READ this label, so
    # there is no second copy of the fact to keep in step.
    stored_at_name = serializers.CharField(source="stored_at.name", read_only=True)
    variants = ProductVariantSerializer(many=True, read_only=True)

    class Meta:
        model = Product
        fields = [  # noqa: RUF012 - declarative DRF Meta option, not mutable state
            "id",
            "category",
            "category_name",
            "brand",
            "brand_name",
            "base_name",
            "description",
            "image_url",
            "stored_at",
            "stored_at_name",
            "is_active",
            "variants",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def validate(self, attrs):
        """The location the write LEAVES the product at must be active (decision 18).

        Deactivating takes a place out of the picker the product form offers, so a write
        that names it would put goods somewhere the shop has just said it no longer
        uses. A product that already carried the label BEFORE it was deactivated keeps
        it: the goods did not move, and the label is where they are - the asymmetry is
        deliberate and is stated in ENDPOINTS.md.

        The check is on the RESULT of the write, not only on an explicit `stored_at`:
        a CREATE that omits the field leaves the model default (Store), and if that row
        was deactivated the product used to be silently assigned to it. A missing
        `stored_at` on an UPDATE changes nothing, so an existing label survives even if
        it is now inactive.
        """
        location = attrs.get("stored_at")
        if location is None and self.instance is None:
            # Read the default row instead of calling the model helper: validation must
            # not write. A missing Store is created active by the model's default on save.
            location = StorageLocation.objects.filter(
                name__iexact=STORE_LOCATION_NAME
            ).first()
        if location is not None and not location.is_active:
            raise InvalidStorageLocation(
                f'"{location.name}" is not an active storage location: pick one that is '
                "in the list, or have an Admin restore it."
            )
        return attrs


class SupplierSerializer(serializers.ModelSerializer):
    """A supplier, including the payment terms a bill's due date is built from.

    `terms_days` is declared WITHOUT the column's own validator so a negative value is
    the project's `INVALID_SUPPLIER_TERMS` code instead of DRF's field-error dict (the
    same reason the selling unit's factor is declared explicitly). 0 is valid and means
    "due on receipt".
    """

    terms_days = serializers.IntegerField(required=False)

    class Meta:
        model = Supplier
        fields = [
            "id",
            "company_name",
            "contact_person",
            "phone",
            "email",
            "address",
            "terms_days",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def validate_terms_days(self, value):
        if value is None or value < 0:
            raise InvalidSupplierTerms(
                "terms_days must be 0 or more: it is the number of days the supplier "
                "gives the shop to pay, and 0 means due on receipt."
            )
        return value


class SellingUnitPrimaryKeyField(serializers.IntegerField):
    """A selling-unit id on the way in, the referenced unit's pk on the way out.

    `IntegerField` alone cannot render the field: `validate()` replaces the id with the
    `VariantUOM` instance so the line can be created with it, and DRF's `int()` on that
    instance raised `TypeError` AFTER the order was written. Rendering the pk keeps the
    wire value an id and the model value a row.
    """

    def to_representation(self, value):
        return getattr(value, "pk", value)


class POItemSerializer(serializers.ModelSerializer):
    """One purchase-order line — a NESTED write, because there is no `/po-items/` endpoint.

    `po` is read-only: the parent serializer creates the lines under the order it is
    building, so a client sending a `po` here was sending a value that was then
    overwritten. `received_qty` is read-only for the same reason and a stronger one — it
    is the running total the goods-receipt path accumulates under a lock (Task 6B.2), and
    a client-writable one would let a delivery be claimed without stock moving.

    `ordered_qty` / `unit_cost` are declared WITHOUT the model's validators so the
    refusal is the project's `INVALID_PO` code instead of DRF's field-error dict.

    **Phase 5 B1 (decision 18):** `variant_uom` is the selling unit the line is counted
    in (`ordered_qty`, `unit_cost`, `received_qty` are all in it). It is an
    `IntegerField` rather than a `PrimaryKeyRelatedField` so a bad id is the project's
    `INVALID_PO` sentence instead of DRF's field-error dict, and it may be OMITTED: the
    line then defaults to the variant's base selling unit, which is what every pre-B1
    line meant. `uom_code` / `conversion_factor` / `uom_is_whole` are READ-ONLY copies of
    the referenced unit, so a purchasing or receiving screen can say "2 BAG (50 kg) at
    P250/bag" without a second request per line; a null unit (a fixture-written row)
    reads as the base unit and reports null.
    """

    variant_name = serializers.CharField(source="variant.variant_name", read_only=True)
    variant_uom = SellingUnitPrimaryKeyField(required=False, allow_null=True)
    uom_code = serializers.CharField(source="variant_uom.uom.code", read_only=True)
    conversion_factor = serializers.DecimalField(
        source="variant_uom.conversion_factor",
        max_digits=12,
        decimal_places=2,
        read_only=True,
    )
    uom_is_whole = serializers.BooleanField(
        source="variant_uom.uom.is_whole", read_only=True
    )
    ordered_qty = serializers.DecimalField(max_digits=12, decimal_places=2)
    unit_cost = serializers.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        model = POItem
        fields = [
            "id",
            "po",
            "variant",
            "variant_name",
            "variant_uom",
            "uom_code",
            "conversion_factor",
            "uom_is_whole",
            "ordered_qty",
            "unit_cost",
            "received_qty",
        ]
        read_only_fields = ["id", "po", "received_qty"]

    def validate(self, attrs):
        qty = attrs.get("ordered_qty")
        if qty is None or qty <= 0:
            raise InvalidPurchaseOrder(
                "ordered_qty must be greater than 0: a line for nothing is not an order."
            )
        cost = attrs.get("unit_cost")
        if cost is None or cost < 0:
            raise InvalidPurchaseOrder("unit_cost must not be negative.")
        variant = attrs.get("variant")
        if variant is None:
            return attrs
        if not variant.is_active:
            raise InvalidPurchaseOrder(
                f"{variant} is inactive: it cannot be ordered until it is restored."
            )

        unit = self._selling_unit(variant, attrs.get("variant_uom"))
        attrs["variant_uom"] = unit
        # Phase 5 B1 (decision 18): the whole-number rule follows the unit the line is
        # COUNTED in, not the product's base unit. 2.5 bags is refused because a bag is
        # whole; 2.5 kg is accepted because the line names the measured KG unit.
        refuse_fractional_whole_unit(
            is_whole=unit.uom.is_whole, qty=qty, what=f"{variant} in {unit.uom.code}"
        )
        return attrs

    @staticmethod
    def _selling_unit(variant, unit_id):
        """The `VariantUOM` this line names, defaulting to the variant's base row.

        The default is the REAL base row (`uom == variant.base_uom` and factor 1), never
        "the first selling unit": a packaged variant lists its BAG before its KG, so list
        order would silently re-measure a kg order in bags. A variant with no such row is
        refused rather than guessed at.
        """
        if unit_id is None:
            unit = (
                VariantUOM.objects.select_related("uom")
                .filter(variant=variant, uom=variant.base_uom, conversion_factor=1)
                .first()
            )
            if unit is None:
                raise InvalidPurchaseOrder(
                    f"{variant} has no base selling unit ({variant.base_uom.code} x1): "
                    "a line is counted in one of its selling units, so create the base "
                    "unit before ordering it."
                )
            return unit

        unit = (
            VariantUOM.objects.select_related("variant__product", "uom")
            .filter(pk=unit_id)
            .first()
        )
        if unit is None:
            raise InvalidPurchaseOrder(
                f"variant_uom {unit_id} does not exist: a line names a selling unit of "
                "its own variant."
            )
        if unit.variant_id != variant.pk:
            raise InvalidPurchaseOrder(
                f"variant_uom {unit_id} belongs to {unit.variant}, not {variant}: a "
                "line is counted in a selling unit of its own variant."
            )
        return unit


class PurchaseOrderSerializer(serializers.ModelSerializer):
    """A purchase order with its lines as a nested write (Phase 4 Task 2).

    `status` is READ-ONLY and the transitions are actions (`place/`, `cancel/`), for the
    same reason `/requisitions/` works that way: placing an order is an event with an
    audit row and a supplier conversation behind it, not a field a PATCH may set.
    `created_by` is the caller, assigned in the view from `request.user`.
    """

    items = POItemSerializer(many=True, required=False)
    created_by_name = serializers.CharField(
        source="created_by.full_name", read_only=True
    )

    # Phase 5 B2 (decision 18): the money. `discount_amount` is the ONE writable figure;
    # everything else is computed from the lines and the header, so a client that sends
    # `total_amount` is sending a value the server never reads (and never trusts).
    discount_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False
    )
    gross_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    net_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    vatable_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    vat_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    total_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = PurchaseOrder
        fields = [
            "id",
            "supplier",
            "created_by",
            "created_by_name",
            "order_date",
            "expected_delivery",
            "status",
            "notes",
            "discount_amount",
            "vat_inclusive",
            "vat_rate",
            "gross_amount",
            "net_amount",
            "vatable_amount",
            "vat_amount",
            "total_amount",
            "items",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "created_by",
            "order_date",
            "status",
            # The rate is a SNAPSHOT the API takes from StoreSettings when it creates
            # the order: a body that could set it would let a client claim any VAT rate,
            # and a body that could change it later would rewrite what the order says.
            "vat_rate",
            "gross_amount",
            "net_amount",
            "vatable_amount",
            "vat_amount",
            "total_amount",
            "created_at",
            "updated_at",
        ]

    def validate(self, attrs):
        supplier = attrs.get("supplier")
        if supplier is None and self.instance is not None:
            supplier = self.instance.supplier
        if supplier is None:
            raise InvalidPurchaseOrder("a purchase order needs a supplier.")
        if not supplier.is_active:
            raise SupplierInactive(supplier)

        if "items" in attrs:
            lines = attrs["items"] or []
            if not lines:
                raise InvalidPurchaseOrder("a purchase order needs at least one line.")
            seen = {}
            for line in lines:
                variant = line["variant"]
                if variant.pk in seen:
                    raise InvalidPurchaseOrder(
                        f"{variant} appears twice: an order carries one line per "
                        "variant (raise its quantity instead)."
                    )
                seen[variant.pk] = True
        elif self.instance is None:
            raise InvalidPurchaseOrder("a purchase order needs at least one line.")

        # Phase 5 B2: the discount is money, so it is checked against the order's OWN
        # gross - computed from the lines this payload carries (or the stored ones on a
        # PATCH that only touches the header). Refused BEFORE the write, so a refused
        # discount leaves no order and no lines.
        discount = attrs.get("discount_amount")
        if discount is None and self.instance is not None:
            discount = self.instance.discount_amount
        if discount is not None:
            if discount < 0:
                raise InvalidPurchaseOrder(
                    "discount_amount must not be negative: a negative discount is a "
                    "surcharge, which this order does not model."
                )
            if discount > self._gross(attrs):
                raise InvalidPurchaseOrder(
                    f"discount_amount {discount} is more than the order's gross "
                    f"{self._gross(attrs)}: a discount cannot exceed what the order is "
                    "worth."
                )

        return attrs

    def _gross(self, attrs):
        """The order's gross for the payload being validated (lines it carries, else stored)."""
        from .payables import money

        if "items" in attrs:
            return money(
                sum(
                    (
                        line["ordered_qty"] * line["unit_cost"]
                        for line in attrs["items"]
                    ),
                    Decimal(0),
                )
            )
        if self.instance is not None:
            return self.instance.gross_amount
        return Decimal("0.00")

    def create(self, validated_data):
        from apps.pos.models import StoreSettings

        # The VAT rate is SNAPSHOTTED here, once, from the shop's own policy: 0 when the
        # shop is not VAT registered (it may not claim VAT at all), otherwise the current
        # rate. Every bill of this order copies the number, so a later settings change
        # cannot rewrite what a delivery of THIS order was billed with. Read under the
        # same block as the write so the rate and the order are one consistent fact.
        store = StoreSettings.load()
        validated_data["vat_rate"] = (
            store.vat_rate if store.vat_registered else Decimal("0.00")
        )
        lines = validated_data.pop("items")
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            # Phase 5 B1: the lines reference selling units, so this writer takes the
            # SAME PK-ordered row locks `VariantUOMViewSet.destroy` takes. Without them
            # a removal committing between validation and this INSERT made the write a
            # 500 on the foreign key. With them one side waits and the loser is told
            # `SELLING_UNIT_IN_USE`, exactly like the sale/quote/order writers.
            lock_selling_unit_lines(
                [(line["variant_uom"], line) for line in lines],
                document="purchase order",
            )
            po = PurchaseOrder.objects.create(**validated_data)
            POItem.objects.bulk_create([POItem(po=po, **line) for line in lines])
        return po

    def update(self, instance, validated_data):
        lines = validated_data.pop("items", None)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            if lines is not None:
                # Same locks as `create`, and taken BEFORE the old rows are deleted: a
                # unit removed while this PATCH waits is refused instead of leaving a
                # half-replaced order.
                lock_selling_unit_lines(
                    [(line["variant_uom"], line) for line in lines],
                    document="purchase order",
                )
            po = super().update(instance, validated_data)
            if lines is not None:
                # Replaced wholesale: keeping the old rows would leave an order whose
                # lines nobody asked for. Only reachable while DRAFT (the viewset refuses
                # the PATCH otherwise), so no receipt can be PROTECT-ing a line here.
                po.items.all().delete()
                POItem.objects.bulk_create([POItem(po=po, **line) for line in lines])
        return po


class InventoryBatchSerializer(serializers.ModelSerializer):
    class Meta:
        model = InventoryBatch
        fields = [
            "id",
            "variant",
            "receipt",
            "initial_qty",
            "current_qty",
            "unit_cost_landed",
            "markup_percentage",
            "batch_selling_price",
            "expiration_date",
            "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class GoodsReceiptItemSerializer(serializers.ModelSerializer):
    """One delivered line. Read-only: lines are created by the receipt POST itself.

    `variant`/`variant_name` are here because a receiving screen has to label the line
    without a second request per po_item, and the po_item id alone does not say what was
    delivered. `qty` is the quantity THIS receipt delivered, not the running total.
    """

    variant = serializers.IntegerField(source="po_item.variant_id", read_only=True)
    variant_name = serializers.CharField(
        source="po_item.variant.variant_name", read_only=True
    )

    class Meta:
        model = GoodsReceiptItem
        fields = ["id", "po_item", "variant", "variant_name", "qty"]
        read_only_fields = fields


class GoodsReceiptSerializer(serializers.ModelSerializer):
    batches = InventoryBatchSerializer(many=True, read_only=True)
    lines = GoodsReceiptItemSerializer(many=True, read_only=True)
    received_by_name = serializers.CharField(
        source="received_by.full_name", read_only=True
    )

    class Meta:
        model = GoodsReceipt
        fields = [
            "id",
            "po",
            "received_by",
            "received_by_name",
            "receive_date",
            "delivery_receipt_no",
            "notes",
            "lines",
            "batches",
            "processed_at",
            "created_at",
        ]
        # `received_by` is READ-ONLY: the actor is not the client's to choose. The viewset
        # already passes `request.user` into creation, so a writable `received_by` was
        # demanded by validation and then had to be sent — every client had to supply a
        # value that means nothing. Same invariant as the checkout's `cashier` field.
        # `processed_at` is read-only for the same reason the timestamp is: the server's
        # process/ call sets it, and a client-writable one would let a caller mark a
        # receipt done (or un-done) without any stock moving.
        read_only_fields = [
            "id",
            "received_by",
            "receive_date",
            "processed_at",
            "created_at",
        ]


class StockAdjustmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockAdjustment
        fields = [
            "id",
            "variant",
            "user",
            "adjustment_type",
            "qty_adjusted",
            "remarks",
            "timestamp",
        ]
        # `user` is READ-ONLY because the actor is never the client's to choose.
        # StockAdjustmentViewSet.perform_create already does
        # `serializer.save(user=self.request.user)`, so a writable `user` was
        # both demanded by validation and then discarded -- every client was
        # forced to send a value that had no effect, and a client could have
        # attributed an adjustment to somebody else. Found by POSTing this
        # endpoint's real body to the running server: HTTP 400
        # {"user":["This field is required."]}.
        read_only_fields = ["id", "timestamp", "user"]

    def validate_qty_adjusted(self, value):
        # A zero adjustment is not a correction, it is a no-op with a receipt: a
        # StockAdjustment row is the stock ledger's evidence that quantity moved, so a row
        # that moved nothing is a false record. Refused HERE rather than in the service
        # because it is a payload fact (sign is meaningful, magnitude must be non-zero)
        # and DRF turns it into the same 400 the other validation errors use.
        if value == 0:
            raise serializers.ValidationError(
                "qty_adjusted must not be 0: an adjustment records stock that moved, "
                "and use a negative value for a removal."
            )
        return value

    def validate(self, attrs):
        # Phase 1d Task 2 (decision 16, Q1): an adjustment moves BASE units, so the check
        # is the variant's base unit - a bag product takes whole bags, a kg product 2.5.
        # Both fields are read here because `qty_adjusted` alone cannot see the variant.
        variant = attrs.get("variant") or getattr(self.instance, "variant", None)
        qty = attrs.get("qty_adjusted")
        if qty is None and self.instance is not None:
            qty = self.instance.qty_adjusted
        if variant is not None and qty is not None:
            refuse_fractional_whole_unit(
                is_whole=variant.base_uom.is_whole,
                qty=qty,
                what=f"{variant} in {variant.base_uom.code}",
            )
        return attrs


class SystemAlertSerializer(serializers.ModelSerializer):
    """An alert raised by the system, plus who cleared it and when.

    `resolved_by_name` is derived rather than stored (expressive-dev rule: one home per
    fact) and prefers the human `full_name`, falling back to the username because a
    seeded account may have a blank full name.
    """

    resolved_by_name = serializers.SerializerMethodField()

    class Meta:
        model = SystemAlert
        # Every field is read-only: alerts are system-generated and the only write the
        # API accepts is POST /alerts/{id}/resolve/ (decision 06), which sets the trail
        # from `request.user` and the server clock - never from the payload.
        fields = [  # noqa: RUF012 - declarative DRF Meta option, not mutable state
            "id",
            "alert_type",
            "variant",
            "message",
            "is_resolved",
            "resolved_by",
            "resolved_by_name",
            "resolved_at",
            "created_at",
        ]
        read_only_fields = fields

    def get_resolved_by_name(self, alert):
        resolver = alert.resolved_by
        if resolver is None:
            return None
        return resolver.full_name or resolver.username


# =========================================================================
# Supplier payables  (Phase 5 B2, decision 18)
# =========================================================================


class SupplierPaymentSerializer(serializers.ModelSerializer):
    """One payment against a bill — append-only, and the actor is never the body's.

    `amount` and `method` are declared as plain strings and parsed HERE, because DRF's
    own `DecimalField`/`ChoiceField` refuse `NaN`, `Infinity` and an unknown method with
    its generic field-error dict. The shop's answer is one stable code
    (`INVALID_SUPPLIER_PAYMENT`) with a sentence, which is what the client branches on -
    so the parsing is explicit and every refusal happens before the service writes
    anything.

    `bill` is writable (it names what is being paid). Everything the server knows better
    is read-only: `paid_by` is the caller, `paid_on` is the server clock.
    """

    amount = serializers.CharField()
    method = serializers.CharField()
    reference = serializers.CharField(
        required=False, allow_blank=True, max_length=100, default=""
    )
    cheque_number = serializers.CharField(
        required=False, allow_blank=True, max_length=100, default=""
    )
    cheque_bank = serializers.CharField(
        required=False, allow_blank=True, max_length=100, default=""
    )
    paid_by_name = serializers.CharField(source="paid_by.full_name", read_only=True)

    class Meta:
        model = SupplierPayment
        fields = [  # noqa: RUF012 - declarative DRF Meta option, not mutable state
            "id",
            "bill",
            "amount",
            "method",
            "reference",
            "cheque_number",
            "cheque_bank",
            "cheque_date",
            "paid_by",
            "paid_by_name",
            "paid_on",
        ]
        read_only_fields = ["id", "paid_by", "paid_on"]  # noqa: RUF012

    def validate_amount(self, value):
        """A peso amount, parsed once: `{code, detail}` instead of a field-error dict."""
        from .payables import _validated_amount

        return _validated_amount(value)

    def validate_method(self, value):
        code = str(value).strip().upper()
        if code not in SupplierPayment.Method.values:
            raise InvalidSupplierPayment(
                f"method {value!r} is not one of "
                f"{', '.join(SupplierPayment.Method.values)}."  # pyright: ignore[reportArgumentType, reportCallIssue]
            )
        return code

    def validate(self, attrs):
        """A cheque must carry the three facts that make it answerable later.

        Decision 18 records a SUPPLIER cheque as paid when issued, so there is no
        clear/bounce step to fill these in afterwards: a cheque whose number, bank or
        date is unknown could never be reconciled with the bank statement, so the
        payment is refused now.
        """
        method = attrs.get("method")
        if method == SupplierPayment.Method.CHEQUE:
            missing = [
                label
                for field, label in (
                    ("cheque_number", "cheque_number"),
                    ("cheque_bank", "cheque_bank"),
                    ("cheque_date", "cheque_date"),
                )
                if not attrs.get(field)
            ]
            if missing:
                raise InvalidSupplierPayment(
                    "a cheque payment needs "
                    + ", ".join(missing)
                    + ": record the cheque's number, bank and date so it can be "
                    "reconciled."
                )
        else:
            # A cash or transfer payment has no cheque: clearing them keeps a stale
            # number from being read as if it belonged to this payment.
            attrs["cheque_number"] = ""
            attrs["cheque_bank"] = ""
            attrs["cheque_date"] = None
        return attrs


class SupplierBillSerializer(serializers.ModelSerializer):
    """One supplier bill, read-only, with its payment history and derived status.

    Every figure is a snapshot written when the receipt was processed
    (`payables.create_bill_for_receipt`); nothing here is writable, and the viewset has
    no create/update/delete verb at all - a bill is history, not a document the API
    edits. The status, paid amount and overdue flag are DERIVED from the balance and the
    due date, so a list can never disagree with the ledger.
    """

    supplier_name = serializers.CharField(
        source="supplier.company_name", read_only=True
    )
    payments = SupplierPaymentSerializer(many=True, read_only=True)
    vatable_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    paid_amount = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    status = serializers.CharField(read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)

    class Meta:
        model = SupplierBill
        fields = [  # noqa: RUF012 - declarative DRF Meta option, not mutable state
            "id",
            "receipt",
            "purchase_order",
            "supplier",
            "supplier_name",
            "received_date",
            "terms_days",
            "due_date",
            "gross_amount",
            "discount_amount",
            "net_amount",
            "vatable_amount",
            "vat_amount",
            "vat_rate",
            "total_amount",
            "balance_amount",
            "paid_amount",
            "status",
            "is_overdue",
            "payments",
            "created_at",
        ]
        # Everything a client could send is refused by the viewset's missing verbs; this
        # is the second lock, so a future mixin cannot quietly make a bill writable.
        read_only_fields = fields
