# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/services.py: the checker resolves its config from
# its WORKING DIRECTORY and does not run inside this repo here, so pyrightconfig.json is
# not found and this travels with the file. Without django-stubs every `Model.objects`,
# every `with transaction.atomic():` and every read of a `DecimalField` as the `Decimal`
# Django returns at runtime (`adjustment.qty_adjusted`) is a false positive on valid
# Django -- the same three rules apps/pos/models.py and apps/pos/tests.py already drop.
"""Inventory app — services for purchasing, batch management & FIFO."""

from decimal import ROUND_HALF_UP, Decimal

from django.db import transaction
from django.db.models import F, Sum
from django.utils import timezone

from . import payables
from .exceptions import (
    InsufficientStock,
    NoBatchHistory,
    PurchaseOrderNotReceivable,
    ReceiptAlreadyProcessed,
    ReceiptQuantityUnrepresentable,
    SellingUnitInUse,
)
from .models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    SystemAlert,
    VariantUOM,
)

CENT = Decimal("0.01")


def lock_selling_units(unit_ids):
    """Lock the selling units a write is about to reference, in PK order.

    Phase 1d Task 3 (decision 16): `VariantUOMViewSet.destroy` removes a unit under this
    same row lock, while every writer here resolves its lines BEFORE it opens a
    transaction (a refused sale, quote, order or push must leave nothing behind). Without
    the lock the removal walks through that window and the writer's INSERT fails on the
    foreign key - a 500 for a race the clerk cannot act on. With it, one of the two
    waits.

    Sorted by PK so two writers queue in ONE order instead of deadlocking on two units
    taken in opposite orders.

    Returns the ids that are still there; the caller owns the refusal, because only it
    knows which document it was saving.
    """
    ids = {unit_id for unit_id in unit_ids if unit_id is not None}
    if not ids:
        return set()
    return set(
        VariantUOM.objects.select_for_update()
        .filter(pk__in=ids)
        .order_by("pk")
        .values_list("pk", flat=True)
    )


def lock_selling_unit_lines(lines, *, document):
    """`lock_selling_units`, then refuse the write if any unit disappeared.

    `lines` is `[(VariantUOM, whatever_the_caller_carries)]` - the shape every caller
    already holds. A unit that is gone between the read and this lock is a
    `400 SELLING_UNIT_IN_USE` (the removal's own code) naming the line, because the
    clerk's next move is the same as for a unit in use: reload the catalogue and add the
    item again.
    """
    lines = list(lines)
    held = lock_selling_units(line[0].pk for line in lines)
    for index, (unit, _extra) in enumerate(lines, start=1):
        if unit.pk not in held:
            raise SellingUnitInUse(
                f"Line {index} ({unit.variant}, {unit.uom.code}) was removed from the "
                f"catalogue while this {document} was being saved: reload and add the "
                "item again."
            )


def process_goods_receipt(*, receipt: GoodsReceipt, user=None) -> list[InventoryBatch]:
    """Convert ONE GoodsReceipt into InventoryBatch entries.

    The batches come from the quantities THIS receipt delivered, never from
    `POItem.received_qty` — that field is the running total across every receipt of the
    PO, and minting a batch from it every time stocked 12 units for deliveries of 5 and
    2 (decision 09 item 4).

    **Units (Phase 5 B1, decision 18).** Every quantity a receipt carries is in the
    PO LINE's selling unit (`POItem.variant_uom`). Stock is counted in the variant's base
    unit, so a line becomes `line.qty x conversion_factor` base units at
    `unit_cost / conversion_factor` each. A factor-1 line is unchanged; a line with no
    unit (a fixture-written row) is read as the base unit, also unchanged.

    Legacy path: a receipt with no `lines` (the fixtures and `seed_demo` set
    `received_qty` directly, and any receipt recorded before lines existed) batches the
    DELTA — `received_qty` minus what this PO already put into stock for that variant —
    so a PO that was already received cannot be stocked twice and an empty process still
    returns [] without flipping the PO's status. The subtraction is done in BASE units
    on BOTH sides (`received_qty x factor` against the sum of the batches' `initial_qty`),
    because `received_qty` is a package count and a batch is a base count: subtracting
    one from the other directly would stock 2 bags as 2 kg.

    **Stock precision (Phase 5 B1 review fix).** A batch column holds TWO decimal places,
    so a delivery is only storable when `qty x factor` is a whole hundredth of the base
    unit. Every quantity is checked with `refuse_unrepresentable_stock` BEFORE any batch
    is created, and the refusal rolls the whole receipt back — an earlier line of the
    same delivery must not survive its sibling's refusal. Stock is never rounded: a
    factor-0.01 line receiving 0.01 used to stock 0.00 (a delivery that vanished while
    `received_qty` said it arrived) and 0.50 x 0.03 used to stock 0.02 (minted a
    hundredth nobody delivered). This runs for the ORM/legacy callers too, which never
    pass through the receipt POST's own check.

    Re-processing is refused by `processed_at`, checked with the receipt row locked:
    two concurrent process/ calls serialize on that row, and the second one sees the
    first one's timestamp. The old guard (`receipt.batches.exists()`) lived in the view,
    outside any lock, so both callers could pass it and double-count.

    The PO's STATUS is re-checked under its own row lock before anything is batched, so
    a receipt recorded before the order was cancelled cannot stock a cancelled order.
    """
    with transaction.atomic():
        receipt = GoodsReceipt.objects.select_for_update().get(pk=receipt.pk)
        if receipt.processed_at is not None:
            raise ReceiptAlreadyProcessed(receipt.pk)

        # Locked for the same reason: two receipts of the SAME PO processing at once
        # must not both read the PO's status and write a different verdict.
        po = PurchaseOrder.objects.select_for_update().get(pk=receipt.po_id)

        # The lock is only worth taking if the status is RE-CHECKED under it. A receipt
        # recorded while the order was ORDERED, an order cancelled before that delivery
        # was processed, and then a `process/` used to mint batches on a CANCELLED
        # order: stock in the rack explained by a document the books call cancelled.
        # Same stable code the receiving gate uses, so the client is told "this order is
        # closed" rather than "bad payload"; nothing is written and the receipt stays
        # unprocessed.
        if po.status not in (
            PurchaseOrder.Status.ORDERED,
            PurchaseOrder.Status.PARTIAL,
        ):
            raise PurchaseOrderNotReceivable(
                f"PO {po.pk} is {po.status} and cannot be processed: only an "
                "ORDERED or PARTIAL order can turn a receipt into stock."
            )

        batches = []

        lines = list(
            receipt.lines.select_related(
                "po_item__variant", "po_item__variant_uom__uom"
            )
        )
        # Validated in a first pass, batch by batch, ONLY then created: a refusal on the
        # third line must leave lines one and two unbatched, which is easier to trust
        # when nothing was written yet than when the rollback has to undo it.
        # (po_item, base_qty, package_qty): stock is minted from the BASE quantity and
        # the bill from the PACKAGE quantity, both from the same delivery.
        plan = []
        if lines:
            for line in lines:
                item = line.po_item
                # `line.qty` is in the PO line's selling unit; stock is base units.
                refuse_unrepresentable_stock(item=item, qty=line.qty)
                plan.append((item, line.qty * line_factor(item), line.qty))
        else:
            for item in po.items.select_related("variant", "variant_uom").filter(
                received_qty__gt=0
            ):
                already_batched = InventoryBatch.objects.filter(
                    receipt__po=po, variant=item.variant
                ).aggregate(total=Sum("initial_qty")).get("total") or Decimal(0)
                # Both sides in BASE units: `received_qty` is in the line's unit, so it
                # is multiplied before the subtraction. Never subtract a package count
                # from a base total - that is how 2 bags would restock as 2 kg.
                refuse_unrepresentable_stock(item=item, qty=item.received_qty)
                delta_base = item.received_qty * line_factor(item) - already_batched
                if delta_base > 0:
                    # The bill is priced per PACKAGE, so the base delta is divided back
                    # by the factor - exactly, because it came from a package count.
                    plan.append((item, delta_base, delta_base / line_factor(item)))

        for item, base_qty, _package_qty in plan:
            batches.append(_create_batch(receipt=receipt, item=item, base_qty=base_qty))

        # Phase 5 B2 (decision 18): the SAME transaction that stocks the delivery writes
        # what the shop owes for it. A failure here (or in the audit row the view writes
        # around this) rolls the batches, the status and the bill back together, so no
        # stock lands without its payable and no bill exists for stock that did not.
        #
        # Only a NONEMPTY plan is billed: a legacy receipt with nothing left to stock owes
        # nothing, and a zero-value delivery creates no bill (see
        # `payables.create_bill_for_receipt`). An already-processed receipt never reaches
        # here (`processed_at` is checked above), so history gets no retroactive bill.
        if plan:
            payables.create_bill_for_receipt(
                receipt=receipt,
                delivered=[(item, package_qty) for item, _base, package_qty in plan],
            )

        # Update PO status only when something was actually received: an
        # empty process used to flip a DRAFT PO to PARTIAL with zero batches.
        if batches:
            all_received = not po.items.filter(
                received_qty__lt=F("ordered_qty")
            ).exists()
            po.status = (
                PurchaseOrder.Status.COMPLETE
                if all_received
                else PurchaseOrder.Status.PARTIAL
            )
            po.save(update_fields=["status"])

        # Marked even when nothing was batched: the receipt HAS been consumed, so a
        # legacy receipt with nothing left to stock answers [] once and stays decided
        # instead of being re-examined by every stray retry.
        receipt.processed_at = timezone.now()
        receipt.save(update_fields=["processed_at"])

    return batches


def line_factor(item: POItem) -> Decimal:
    """How many base units ONE selling unit of this PO line is.

    A line with no `variant_uom` was written by a fixture or older tooling straight
    through the ORM. It is counted in the variant's base unit, which is a factor of 1 -
    exactly what every pre-B1 line meant - so it keeps its numbers. The API always stores
    the unit it validated.
    """
    return item.variant_uom.conversion_factor if item.variant_uom_id else Decimal(1)


def refuse_unrepresentable_stock(*, item: POItem, qty: Decimal) -> None:
    """Refuse a delivery whose converted stock is not a whole hundredth of a base unit.

    The batch columns hold two decimal places, so `qty x factor` has to LAND on one of
    them. `_create_batch` used to quantize it HALF_UP instead, which stocked 0.00 for a
    legitimate factor-0.01 unit receiving 0.01 (0.0001) and stocked 0.02 for 0.50 x 0.03
    (0.015): one delivery disappeared and the other minted stock nobody delivered. Both
    leave the shelf disagreeing with the books, so the delivery is refused with a code and
    a sentence naming the quantity, and the clerk re-counts.

    Called on the receipt POST, before the receipt row is written, and again from
    `process_goods_receipt` for the ORM/legacy callers that never pass through the view.
    The `qty` here is the RECEIVED quantity in the line's selling unit, which is what the
    clerk can act on; `factor` and both codes are in the sentence so the answer is
    obvious without the client doing the arithmetic.
    """
    factor = line_factor(item)
    base_qty = qty * factor
    if base_qty == base_qty.quantize(CENT):
        return
    unit_code = (
        item.variant_uom.uom.code if item.variant_uom_id else item.variant.base_uom.code
    )
    raise ReceiptQuantityUnrepresentable(
        f"Receiving {qty} {unit_code} of {item.variant} (1 {unit_code} = {factor} "
        f"{item.variant.base_uom.code}) is exactly {base_qty} "
        f"{item.variant.base_uom.code} of stock, and stock is kept in whole hundredths "
        "of the base unit: record a quantity that converts to a whole hundredth (0.01) "
        "of the base unit."
    )


def _create_batch(
    *, receipt: GoodsReceipt, item: POItem, base_qty: Decimal
) -> InventoryBatch:
    """One batch for one delivered BASE quantity; also re-checks the low-stock threshold.

    `unit_cost` is per SELLING unit of the line while a batch's landed cost is per BASE
    unit, so the cost is divided by the line's factor and quantized to the cent the column
    stores (`ROUND_HALF_UP`, the project's money rounding): P100 per 3 kg package is
    P33.33/kg and the delivery is still 3 kg. Cost MAY round; stock may not - `base_qty`
    arrives already checked by `refuse_unrepresentable_stock`, so the quantize below only
    fixes the column's scale and can never change the number.

    `batch_selling_price` is set EQUAL to the landed cost, with `markup_percentage` 0:
    this path writes no markup, so there is no multiplication to apply here and a batch
    created from a receipt sells at cost until something changes its price.
    """
    factor = line_factor(item)
    base_qty = base_qty.quantize(CENT, rounding=ROUND_HALF_UP)
    unit_cost_per_base = (item.unit_cost / factor).quantize(
        CENT, rounding=ROUND_HALF_UP
    )
    batch = InventoryBatch.objects.create(
        variant=item.variant,
        receipt=receipt,
        initial_qty=base_qty,
        current_qty=base_qty,
        unit_cost_landed=unit_cost_per_base,
        markup_percentage=Decimal(0),
        batch_selling_price=unit_cost_per_base,
    )
    _check_low_stock(item.variant)
    return batch


def allocate_fifo(*, variant_id: int, qty_needed: Decimal):
    """FIFO stock allocator.

    Given a variant and desired quantity, iterate through batches
    ordered by receipt date (oldest first). Returns a list of
    (batch, qty_to_deduct) tuples and deducts current_qty.

    Raises ValueError if there isn't enough stock.
    """
    from .models import ProductVariant

    batches = (
        InventoryBatch.objects.select_for_update()
        .filter(variant_id=variant_id, current_qty__gt=0)
        .order_by("receipt__receive_date")
    )

    allocations = []
    remaining = qty_needed

    for batch in batches:
        if remaining <= 0:
            break
        take = min(batch.current_qty, remaining)
        batch.current_qty -= take
        allocations.append((batch, take))
        remaining -= take

    if remaining > 0:
        variant = ProductVariant.objects.get(pk=variant_id)
        raise InsufficientStock(
            f"Insufficient stock for {variant}.",
            shortfall=remaining,
            variant_id=variant_id,
        )

    # Bulk save deductions
    InventoryBatch.objects.bulk_update([b for b, _ in allocations], ["current_qty"])

    return allocations


def apply_stock_adjustment(*, adjustment: StockAdjustment) -> None:
    """Move stock for one manual adjustment; MUST run inside the caller's atomic block.

    Negative `qty_adjusted` = removal (shrinkage / damage) through FIFO, so the loss comes
    off the oldest stock first and an over-deduction surfaces as `InsufficientStock`
    rather than as silently negative stock.

    Positive `qty_adjusted` = addition (count correction / return) onto the NEWEST batch
    of that variant, whatever its `current_qty` is. Two defects lived here before:

    1. The batch lookup filtered `current_qty__gt=0`, so a correction booked against an
       out-of-stock variant matched nothing, wrote a StockAdjustment row and moved no
       stock - the ledger asserted stock the shelves did not have (audit gap 09 item 5).
    2. When no batch matched at all, nothing was raised and the caller kept the row.
       A variant that has never been delivered cannot be corrected upwards: there is
       nowhere to put the quantity. The ledger ruling replaced the plan's "create a
       batch" with "reopen the newest EXISTING batch", because `InventoryBatch.receipt`
       is a non-null PROTECT FK and a receipt-less batch would need a schema change.
       `NoBatchHistory` (400 NO_BATCH_HISTORY) is the refusal, and because the caller in
       `StockAdjustmentViewSet` wraps create + apply in ONE atomic block, refusing it
       leaves no adjustment row behind.

    The old removal branch caught its own `ValueError` and called `allocate_fifo` a second
    time; the retry could only ever raise again (the stock needed to satisfy it does not
    appear between two calls), so it doubled the work and hid the real error class. It is
    gone: `InsufficientStock` propagates to the DRF handler, which answers 400.
    """
    from .models import InventoryBatch

    variant = adjustment.variant
    qty = adjustment.qty_adjusted

    if qty < 0:  # removal (shrinkage / damage)
        # The result is deliberately not bound: `allocate_fifo` both deducts and returns
        # the allocation, and this caller only needs the deduction.
        allocate_fifo(variant_id=variant.pk, qty_needed=abs(qty))
    elif qty > 0:  # addition (correction / return)
        # Newest batch FIRST, and `current_qty` is not filtered: an emptied batch is
        # exactly the one a correction is meant to reopen. Locked so two corrections
        # cannot read the same `current_qty` and lose one of the increments.
        batch = (
            InventoryBatch.objects.select_for_update()
            .filter(variant=variant)
            .order_by("-receipt__receive_date", "-id")
            .first()
        )
        if batch is None:
            raise NoBatchHistory(variant)
        batch.current_qty += qty
        batch.save(update_fields=["current_qty"])

    _check_low_stock(variant)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def check_low_stock_after_stock_out(*, variant_ids) -> list:
    """Re-evaluate the threshold for each variant that just LOST stock (Task 4.3).

    The PUBLIC entry point for the two stock-OUT paths — `process_sale` and
    `release_materials`. Both call it once, after every line of their transaction has
    been deducted through FIFO and still INSIDE that transaction, so the alert and the
    sale commit or roll back together: a sale refused for short stock leaves no alert
    claiming the shelf is low.

    `_check_low_stock` stays private because a receipt and a manual adjustment call it
    for one variant at a time. This wrapper exists so those two cross-app callers depend
    on a name that says WHY they are asking, not on an underscore function.

    Variants are locked and checked in PK ORDER: two tills selling the last bags of
    different variants at the same moment would otherwise grab the same two rows in
    opposite order and deadlock.
    """
    alerts = []
    for variant in ProductVariant.objects.filter(pk__in=set(variant_ids)).order_by(
        "pk"
    ):
        alert = _check_low_stock(variant)
        if alert is not None:
            alerts.append(alert)
    return alerts


def _check_low_stock(variant):
    """Raise the ONE alert this variant's stock calls for, or return None.

    Two jobs, and both were missing before Phase 4:

    * **Escalation.** Out of stock wins over low stock (an OUT alert is the more urgent
      fact), and the open LOW alert is left exactly as it is — resolving it stays a
      named act (decision 06).
    * **Dedup.** An **unresolved** alert of the SAME type already on this variant
      suppresses a second one. Without it every goods receipt re-raised the same "below
      threshold" row, so the screen a stocker watches collected duplicates. Resolved
      rows are history and do not suppress anything.

    The variant row is LOCKED before the existence check, so two concurrent sales cannot
    both read "no open alert" and both insert. A restock does NOT auto-resolve anything:
    restoring stock is not the same act as clearing the alert.
    """
    from django.db.models import Sum

    with transaction.atomic():
        # Re-read under the lock: the caller's `variant` may be a stale in-memory copy,
        # and the threshold is the number the decision is made on.
        locked = ProductVariant.objects.select_for_update().get(pk=variant.pk)
        total = (
            InventoryBatch.objects.filter(variant=locked, current_qty__gt=0).aggregate(
                total=Sum("current_qty")
            )
        ).get("total") or Decimal(0)
        threshold = locked.min_stock_threshold

        if total <= 0:
            alert_type = SystemAlert.AlertType.OUT_OF_STOCK
            message = f"{locked} is out of stock."
        elif threshold > 0 and total < threshold:
            alert_type = SystemAlert.AlertType.LOW_STOCK
            message = (
                f"{locked} stock ({total}) is below minimum threshold ({threshold})."
            )
        else:
            return None

        already_open = SystemAlert.objects.filter(
            variant=locked, alert_type=alert_type, is_resolved=False
        ).exists()
        if already_open:
            return None

        return SystemAlert.objects.create(
            alert_type=alert_type,
            variant=locked,
            message=message,
        )
