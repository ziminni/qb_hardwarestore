# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportArgumentType=false
"""Bodega module services (decision 25). Read `models.py`'s docstring first.

Everything that writes runs inside the caller's `transaction.atomic()` and locks the row
that serialises it: the SALE for a release (two checkers on one receipt queue instead of
both handing over the last cubic metre), the DELIVERY for a check.
"""

from collections import defaultdict
from decimal import Decimal

from django.db.models import Q, Sum
from django.utils import timezone

from apps.inventory.models import (
    InventoryBatch,
    ProductVariant,
    StockAdjustment,
    StorageLocation,
)
from apps.inventory.services import apply_stock_adjustment
from apps.pos.models import Delivery, SalesItemDeduction, SalesTransaction
from common.numbering import generate_document_number

from .exceptions import (
    InvalidBodegaDelivery,
    InvalidBodegaRelease,
    NoBodegaClaim,
    ReleaseExceedsClaim,
)
from .models import (
    BodegaDelivery,
    BodegaDeliveryLine,
    BodegaRelease,
    BodegaReleaseLine,
)

ZERO = Decimal(0)
CENT = Decimal("0.01")


def bodega_locations():
    """Every shelf the checker runs, active or not (stock on a closed one still leaves)."""
    return StorageLocation.objects.filter(is_bodega=True)


# ---------------------------------------------------------------------------
# Claims: derived, never stored
# ---------------------------------------------------------------------------


def _dispatch_sales(sale_ids=None, *, scheduled_only=False):
    slips = Delivery.objects.all()
    if scheduled_only:
        slips = slips.filter(status=Delivery.Status.SCHEDULED)
    sales = SalesTransaction.objects.filter(
        Q(pk__in=slips.values("sale_id").filter(sale_id__isnull=False))
        | Q(
            items__order_line__order_id__in=slips.values("sales_order_id").filter(
                sales_order_id__isnull=False
            )
        )
    )
    if sale_ids is not None:
        sales = sales.filter(pk__in=sale_ids)
    return sales.values("pk")


def _sold_by_key(sale_ids=None, *, excluded_sales=None):
    """`{(sale_id, variant_id, location_id): base qty}` taken from Bodega shelves, net of
    linked returns. `sale_ids=None` means every sale."""
    sold = defaultdict(lambda: ZERO)
    taken = SalesItemDeduction.objects.filter(
        batch__location__is_bodega=True,
        qty__gt=0,
        sales_item__transaction__status=SalesTransaction.Status.COMPLETED,
    )
    given_back = SalesItemDeduction.objects.filter(
        batch__location__is_bodega=True,
        qty__lt=0,
        sales_item__transaction__original_transaction__isnull=False,
    )
    if sale_ids is not None:
        taken = taken.filter(sales_item__transaction_id__in=sale_ids)
        given_back = given_back.filter(
            sales_item__transaction__original_transaction_id__in=sale_ids
        )
    if excluded_sales is not None:
        taken = taken.exclude(sales_item__transaction_id__in=excluded_sales)
        given_back = given_back.exclude(
            sales_item__transaction__original_transaction_id__in=excluded_sales
        )
    for row in taken.values(
        "sales_item__transaction_id",
        "sales_item__variant_uom__variant_id",
        "batch__location_id",
    ).annotate(total=Sum("qty")):
        key = (
            row["sales_item__transaction_id"],
            row["sales_item__variant_uom__variant_id"],
            row["batch__location_id"],
        )
        sold[key] += row["total"]
    for row in given_back.values(
        "sales_item__transaction__original_transaction_id",
        "sales_item__variant_uom__variant_id",
        "batch__location_id",
    ).annotate(total=Sum("qty")):
        key = (
            row["sales_item__transaction__original_transaction_id"],
            row["sales_item__variant_uom__variant_id"],
            row["batch__location_id"],
        )
        sold[key] += row["total"]  # negative
    return sold


def _released_by_key(sale_ids=None, *, excluded_sales=None):
    released = defaultdict(lambda: ZERO)
    rows = BodegaReleaseLine.objects.all()
    if sale_ids is not None:
        rows = rows.filter(release__sale_id__in=sale_ids)
    if excluded_sales is not None:
        rows = rows.exclude(release__sale_id__in=excluded_sales)
    for row in rows.values("release__sale_id", "variant_id", "location_id").annotate(
        total=Sum("qty")
    ):
        released[(row["release__sale_id"], row["variant_id"], row["location_id"])] += (
            row["total"]
        )
    return released


def claim_lines(sale_ids=None):
    """Every claim line: `[{sale_id, variant_id, location_id, sold, released, remaining}]`.

    `remaining` never goes below zero: goods handed over and THEN returned at the counter
    make `sold - released` negative, and "owes the customer -2" means nothing at a gate.
    """
    dispatch = _dispatch_sales(sale_ids)
    sold = _sold_by_key(sale_ids, excluded_sales=dispatch)
    released = _released_by_key(sale_ids, excluded_sales=dispatch)
    lines = []
    for key in set(sold) | set(released):
        sale_id, variant_id, location_id = key
        net = max(sold.get(key, ZERO), ZERO)
        out = released.get(key, ZERO)
        if net <= 0 and out <= 0:
            continue
        lines.append(
            {
                "sale_id": sale_id,
                "variant_id": variant_id,
                "location_id": location_id,
                "sold": net,
                "released": out,
                "remaining": max(net - out, ZERO),
            }
        )
    return lines


def unreleased_by_variant_location():
    """`{(variant_id, location_id): base qty paid for and still on the shelf}`."""
    totals = defaultdict(lambda: ZERO)
    for line in claim_lines():
        totals[(line["variant_id"], line["location_id"])] += line["remaining"]
    return totals


def find_sale(reference):
    """The sale a receipt names: its transaction number or its OR number."""
    reference = (reference or "").strip()
    if not reference:
        raise NoBodegaClaim("Type or scan the receipt number to find the claim.")
    sale = (
        SalesTransaction.objects.filter(
            Q(transaction_no__iexact=reference)
            | Q(receipt__or_number__iexact=reference)
        )
        .exclude(source=SalesTransaction.Source.RETURN)
        .first()
    )
    if sale is None:
        raise NoBodegaClaim(f'No sale has the receipt number "{reference}".')
    if _dispatch_sales([sale.pk]).exists():
        raise NoBodegaClaim("This receipt is for delivery. Open Sales → Deliveries.")
    return sale


# ---------------------------------------------------------------------------
# Releases
# ---------------------------------------------------------------------------


def record_release(*, sale, checker, received_by, plate_no, notes, lines):
    """Hand goods over against `sale`'s claim. `lines` = `[(variant, location, qty)]`.

    Caller holds `transaction.atomic()`. The sale row is locked first, so two releases of
    one receipt are serialised and the second sees what the first handed over.
    """
    SalesTransaction.objects.select_for_update().get(pk=sale.pk)
    received_by = (received_by or "").strip()
    if not received_by:
        raise InvalidBodegaRelease(
            "Write the name of the person who received the goods: the release is the "
            "store's proof that they left."
        )
    wanted = defaultdict(lambda: ZERO)
    for variant, location, qty in lines:
        if qty is None or qty <= 0:
            raise InvalidBodegaRelease(
                "Every released quantity must be more than zero."
            )
        if qty != qty.quantize(CENT):
            raise InvalidBodegaRelease(
                f"{qty} has more than two decimal places; stock is kept to 0.01."
            )
        wanted[(variant.pk, location.pk)] += qty
    if not wanted:
        raise InvalidBodegaRelease("Choose at least one item to release.")

    open_lines = {
        (line["variant_id"], line["location_id"]): line
        for line in claim_lines([sale.pk])
    }
    if not open_lines:
        raise NoBodegaClaim(
            f"Sale {sale.transaction_no} took nothing from the Bodega, so there is "
            "nothing to release here."
        )
    variants = ProductVariant.objects.select_related("product", "base_uom").in_bulk(
        [variant_id for variant_id, _ in wanted]
    )
    for (variant_id, location_id), qty in wanted.items():
        remaining = open_lines.get((variant_id, location_id), {}).get("remaining", ZERO)
        if qty > remaining:
            variant = variants[variant_id]
            raise ReleaseExceedsClaim(
                f"{variant}: only {remaining} {variant.base_uom.code} is still to be "
                f"collected on {sale.transaction_no}, and {qty} was entered."
            )

    release = BodegaRelease.objects.create(
        number=generate_document_number(BodegaRelease, "number", "BR"),
        sale=sale,
        checker=checker,
        received_by=received_by[:150],
        plate_no=(plate_no or "").strip()[:30],
        notes=(notes or "").strip()[:255],
    )
    BodegaReleaseLine.objects.bulk_create(
        [
            BodegaReleaseLine(
                release=release, variant_id=variant_id, location_id=location_id, qty=qty
            )
            for (variant_id, location_id), qty in sorted(wanted.items())
        ]
    )
    return release


# ---------------------------------------------------------------------------
# Stock view
# ---------------------------------------------------------------------------


def bodega_stock():
    """One row per (variant, Bodega shelf) the Bodega holds or is home to.

    `on_hand` is the books (what the till may still sell); `unreleased` is paid for and
    not yet collected. Scheduled dispatch stock is physically present until it goes out.
    """
    locations = {loc.pk: loc for loc in bodega_locations()}
    if not locations:
        return []
    on_hand = defaultdict(lambda: ZERO)
    for row in (
        InventoryBatch.objects.filter(location_id__in=locations)
        .values("variant_id", "location_id")
        .annotate(total=Sum("current_qty"))
    ):
        on_hand[(row["variant_id"], row["location_id"])] = row["total"] or ZERO
    unreleased = unreleased_by_variant_location()
    scheduled_sales = _dispatch_sales(scheduled_only=True)
    already_released = _released_by_key(scheduled_sales)
    dispatch = defaultdict(lambda: ZERO)
    for key, qty in _sold_by_key(scheduled_sales).items():
        dispatch[key[1:]] += max(qty - already_released[key], ZERO)
    for_checking = defaultdict(lambda: ZERO)
    for row in (
        BodegaDeliveryLine.objects.filter(
            delivery__status=BodegaDelivery.Status.PENDING,
            delivery__location_id__in=locations,
        )
        .values("variant_id", "delivery__location_id")
        .annotate(total=Sum("delivered_qty"))
    ):
        for_checking[(row["variant_id"], row["delivery__location_id"])] = row["total"]
    keys = (
        set(on_hand)
        | {key for key, qty in unreleased.items() if qty > 0}
        | {key for key, qty in dispatch.items() if qty > 0}
        | set(for_checking)
    )
    # A product whose HOME is a Bodega belongs on the list even before its first delivery.
    for variant_id, location_id in ProductVariant.objects.filter(
        is_active=True, product__stored_at_id__in=locations
    ).values_list("id", "product__stored_at_id"):
        keys.add((variant_id, location_id))
    variants = ProductVariant.objects.select_related(
        "product", "product__category", "base_uom"
    ).in_bulk({variant_id for variant_id, _ in keys})
    rows = []
    for variant_id, location_id in keys:
        variant = variants.get(variant_id)
        if variant is None or location_id not in locations:
            continue
        held = on_hand.get((variant_id, location_id), ZERO)
        open_qty = unreleased.get((variant_id, location_id), ZERO)
        rows.append(
            {
                "variant_id": variant_id,
                "product_name": variant.product.base_name,
                "variant_name": variant.variant_name,
                "category": variant.product.category.name,
                "unit": variant.base_uom.code,
                "location_id": location_id,
                "location_name": locations[location_id].name,
                "is_home": variant.product.stored_at_id == location_id,
                "on_hand": held,
                "unreleased": open_qty,
                "awaiting_dispatch": dispatch.get((variant_id, location_id), ZERO),
                "physical": held
                + open_qty
                + dispatch.get((variant_id, location_id), ZERO),
                "for_checking": for_checking.get((variant_id, location_id), ZERO),
                "min_stock": variant.min_stock_threshold,
            }
        )
    rows.sort(key=lambda r: (r["location_name"], r["product_name"], r["variant_name"]))
    return rows


# ---------------------------------------------------------------------------
# Deliveries waiting for the checker
# ---------------------------------------------------------------------------


def hold_delivery_for_check(*, receipt, lines):
    """Park a receipt's Bodega lines until the checker confirms them.

    Called by `process_goods_receipt` inside its atomic block. `lines` =
    `[(po_item, base_qty, location)]`; one `BodegaDelivery` per Bodega shelf.
    """
    by_location = defaultdict(list)
    for item, base_qty, location in lines:
        by_location[location.pk].append((item, base_qty, location))
    for entries in by_location.values():
        delivery = BodegaDelivery.objects.create(
            number=generate_document_number(BodegaDelivery, "number", "BD"),
            receipt=receipt,
            location=entries[0][2],
        )
        BodegaDeliveryLine.objects.bulk_create(
            [
                BodegaDeliveryLine(
                    delivery=delivery,
                    po_item=item,
                    variant_id=item.variant_id,
                    delivered_qty=base_qty,
                )
                for item, base_qty, _location in entries
            ]
        )


def _write_off(*, variant, location, user, qty, adjustment_type, remarks):
    adjustment = StockAdjustment.objects.create(
        variant=variant,
        location=location,
        user=user,
        adjustment_type=adjustment_type,
        qty_adjusted=-qty,
        remarks=remarks[:500],
    )
    apply_stock_adjustment(adjustment=adjustment)


def confirm_delivery(*, delivery_id, checker, lines, notes=""):
    """The checker's verdict. `lines` = `{line_id: (good_qty, damaged_qty, remarks)}`.

    The whole delivered quantity is stocked on the Bodega shelf (so the receipt, the
    bill and the batch agree), and at once the damaged pieces are written off as DAMAGE
    and anything that never arrived as SHRINKAGE. What is left on the books is exactly
    the good quantity the checker saw. Every line must be answered.
    """
    from apps.inventory.services import _create_batch

    delivery = (
        BodegaDelivery.objects.select_for_update()
        .select_related("location", "receipt")
        .filter(pk=delivery_id)
        .first()
    )
    if delivery is None:
        raise InvalidBodegaDelivery(f"Delivery #{delivery_id} does not exist.")
    if delivery.status != BodegaDelivery.Status.PENDING:
        raise InvalidBodegaDelivery(f"{delivery.number} was already checked.")
    rows = list(
        delivery.lines.select_related(
            "po_item__variant_uom", "variant__product", "variant__base_uom"
        ).order_by("variant_id", "id")
    )
    missing_answers = [row for row in rows if row.pk not in lines]
    if missing_answers:
        raise InvalidBodegaDelivery(
            f"Check every product on {delivery.number}: "
            f"{missing_answers[0].variant} has no count yet."
        )
    for row in rows:
        good, damaged, remarks = lines[row.pk]
        unit = row.variant.base_uom
        for label, qty in (("good", good), ("damaged", damaged)):
            if qty is None or qty < 0:
                raise InvalidBodegaDelivery(
                    f"{row.variant}: the {label} quantity cannot be negative."
                )
            if qty != qty.quantize(CENT):
                raise InvalidBodegaDelivery(
                    f"{qty} has more than two decimal places; stock is kept to 0.01."
                )
            if unit.is_whole and qty != qty.to_integral_value():
                raise InvalidBodegaDelivery(
                    f"{row.variant} is counted in whole {unit.code}: {qty} is not."
                )
        if good + damaged > row.delivered_qty:
            raise InvalidBodegaDelivery(
                f"{row.variant}: {good} good + {damaged} damaged is more than the "
                f"{row.delivered_qty} {unit.code} the stocker received."
            )

    for row in rows:
        good, damaged, remarks = lines[row.pk]
        batch = _create_batch(
            receipt=delivery.receipt,
            item=row.po_item,
            base_qty=row.delivered_qty,
            location=delivery.location,
        )
        missing = row.delivered_qty - good - damaged
        note = f"Bodega delivery check {delivery.number}" + (
            f": {remarks}" if remarks else ""
        )
        if damaged > 0:
            _write_off(
                variant=row.variant,
                location=delivery.location,
                user=checker,
                qty=damaged,
                adjustment_type=StockAdjustment.AdjustmentType.DAMAGE,
                remarks=f"{note} (damaged on delivery)",
            )
        if missing > 0:
            _write_off(
                variant=row.variant,
                location=delivery.location,
                user=checker,
                qty=missing,
                adjustment_type=StockAdjustment.AdjustmentType.SHRINKAGE,
                remarks=f"{note} (not delivered)",
            )
        row.good_qty = good
        row.damaged_qty = damaged
        row.remarks = (remarks or "").strip()[:255]
        row.batch = batch
        row.save(update_fields=["good_qty", "damaged_qty", "remarks", "batch"])

    delivery.status = BodegaDelivery.Status.CHECKED
    delivery.checked_by = checker
    delivery.checked_at = timezone.now()
    delivery.notes = (notes or "").strip()[:255]
    delivery.save(update_fields=["status", "checked_by", "checked_at", "notes"])
    return delivery
