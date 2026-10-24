# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/services.py: the checker resolves its config from
# its WORKING DIRECTORY and does not run inside this repo here, so pyrightconfig.json is
# not found and this travels with the file. Without django-stubs every `Model.objects`,
# every `with transaction.atomic():` and every read of a `DecimalField` as the `Decimal`
# Django returns at runtime (`adjustment.qty_adjusted`) is a false positive on valid
# Django -- the same three rules apps/pos/models.py and apps/pos/tests.py already drop.
"""Inventory app — services for purchasing, batch management & FIFO."""

from decimal import Decimal

from django.db import transaction
from django.db.models import F, Sum
from django.utils import timezone


from .exceptions import InsufficientStock, NoBatchHistory, ReceiptAlreadyProcessed
from .models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    PurchaseOrder,
    StockAdjustment,
    SystemAlert,
)


def process_goods_receipt(*, receipt: GoodsReceipt, user=None) -> list[InventoryBatch]:
    """Convert ONE GoodsReceipt into InventoryBatch entries.

    The batches come from the quantities THIS receipt delivered, never from
    `POItem.received_qty` — that field is the running total across every receipt of the
    PO, and minting a batch from it every time stocked 12 units for deliveries of 5 and
    2 (decision 09 item 4).

    Legacy path: a receipt with no `lines` (the fixtures and `seed_demo` set
    `received_qty` directly, and any receipt recorded before lines existed) batches the
    DELTA — `received_qty` minus what this PO already put into stock for that variant —
    so a PO that was already received cannot be stocked twice and an empty process still
    returns [] without flipping the PO's status.

    Re-processing is refused by `processed_at`, checked with the receipt row locked:
    two concurrent process/ calls serialize on that row, and the second one sees the
    first one's timestamp. The old guard (`receipt.batches.exists()`) lived in the view,
    outside any lock, so both callers could pass it and double-count.
    """
    with transaction.atomic():
        receipt = GoodsReceipt.objects.select_for_update().get(pk=receipt.pk)
        if receipt.processed_at is not None:
            raise ReceiptAlreadyProcessed(receipt.pk)

        # Locked for the same reason: two receipts of the SAME PO processing at once
        # must not both read the PO's status and write a different verdict.
        po = PurchaseOrder.objects.select_for_update().get(pk=receipt.po_id)
        batches = []

        lines = list(receipt.lines.select_related('po_item__variant'))
        if lines:
            for line in lines:
                batches.append(
                    _create_batch(
                        receipt=receipt, item=line.po_item, qty=line.qty))
        else:
            for item in po.items.select_related('variant').filter(received_qty__gt=0):
                already_batched = (
                    InventoryBatch.objects
                    .filter(receipt__po=po, variant=item.variant)
                    .aggregate(total=Sum('initial_qty'))
                    .get('total') or Decimal('0')
                )
                delta = item.received_qty - already_batched
                if delta > 0:
                    batches.append(
                        _create_batch(receipt=receipt, item=item, qty=delta))

        # Update PO status only when something was actually received: an
        # empty process used to flip a DRAFT PO to PARTIAL with zero batches.
        if batches:
            all_received = not po.items.filter(
                received_qty__lt=F('ordered_qty')
            ).exists()
            po.status = (
                PurchaseOrder.Status.COMPLETE
                if all_received
                else PurchaseOrder.Status.PARTIAL
            )
            po.save(update_fields=['status'])

        # Marked even when nothing was batched: the receipt HAS been consumed, so a
        # legacy receipt with nothing left to stock answers [] once and stays decided
        # instead of being re-examined by every stray retry.
        receipt.processed_at = timezone.now()
        receipt.save(update_fields=['processed_at'])

    return batches


def _create_batch(*, receipt: GoodsReceipt, item: POItem, qty: Decimal) -> InventoryBatch:
    """One batch for one delivered quantity; also re-checks the low-stock threshold.

    batch_selling_price = unit_cost_landed * (1 + markup_percentage / 100); markup is
    set per batch and defaults to 0 here, so the two are equal unless a caller sets it.
    """
    batch = InventoryBatch.objects.create(
        variant=item.variant,
        receipt=receipt,
        initial_qty=qty,
        current_qty=qty,
        unit_cost_landed=item.unit_cost,
        markup_percentage=Decimal('0'),
        batch_selling_price=item.unit_cost,
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
        InventoryBatch.objects
        .select_for_update()
        .filter(variant_id=variant_id, current_qty__gt=0)
        .order_by('receipt__receive_date')
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
            f'Insufficient stock for {variant}.',
            shortfall=remaining,
            variant_id=variant_id,
        )

    # Bulk save deductions
    InventoryBatch.objects.bulk_update(
        [b for b, _ in allocations], ['current_qty']
    )

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
            InventoryBatch.objects
            .select_for_update()
            .filter(variant=variant)
            .order_by('-receipt__receive_date', '-id')
            .first()
        )
        if batch is None:
            raise NoBatchHistory(variant)
        batch.current_qty += qty
        batch.save(update_fields=['current_qty'])

    _check_low_stock(variant)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _check_low_stock(variant):
    """Generate a SystemAlert if total current_qty < min_stock_threshold."""
    from django.db.models import Sum

    total = (
        InventoryBatch.objects
        .filter(variant=variant, current_qty__gt=0)
        .aggregate(total=Sum('current_qty'))
    ).get('total') or Decimal('0')

    variant.refresh_from_db(fields=['min_stock_threshold'])
    threshold = variant.min_stock_threshold

    if total <= 0:
        SystemAlert.objects.create(
            alert_type=SystemAlert.AlertType.OUT_OF_STOCK,
            variant=variant,
            message=f'{variant} is out of stock.',
        )
    elif threshold > 0 and total < threshold:
        SystemAlert.objects.create(
            alert_type=SystemAlert.AlertType.LOW_STOCK,
            variant=variant,
            message=(
                f'{variant} stock ({total}) is below '
                f'minimum threshold ({threshold}).'
            ),
        )
