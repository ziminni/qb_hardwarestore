"""Inventory app — services for purchasing, batch management & FIFO."""

from decimal import Decimal

from django.db import transaction
from django.db.models import F, Sum


from .models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    PurchaseOrder,
    StockAdjustment,
    SystemAlert,
)


def process_goods_receipt(*, receipt: GoodsReceipt, user=None) -> list[InventoryBatch]:
    """Convert a GoodsReceipt into InventoryBatch entries.

    For every POItem marked as received, create one InventoryBatch.
    The batch_selling_price = unit_cost_landed * (1 + markup_percentage / 100).
    """
    po = receipt.po
    batches = []

    with transaction.atomic():
        for item in po.items.filter(received_qty__gt=0):
            markup = Decimal('0')
            batch_price = item.unit_cost
            # Markup is set per batch; default to 0 if not specified.

            batch = InventoryBatch.objects.create(
                variant=item.variant,
                receipt=receipt,
                initial_qty=item.received_qty,
                current_qty=item.received_qty,
                unit_cost_landed=item.unit_cost,
                markup_percentage=markup,
                batch_selling_price=batch_price,
            )
            batches.append(batch)

            # Check if we need a low-stock alert
            _check_low_stock(item.variant)

        # Update PO status
        all_received = not po.items.filter(
            received_qty__lt=F('ordered_qty')
        ).exists()
        po.status = (
            PurchaseOrder.Status.COMPLETE
            if all_received
            else PurchaseOrder.Status.PARTIAL
        )
        po.save(update_fields=['status'])

    return batches


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
        raise ValueError(
            f'Insufficient stock for {variant}. '
            f'Needed {qty_needed}, short by {remaining}.'
        )

    # Bulk save deductions
    InventoryBatch.objects.bulk_update(
        [b for b, _ in allocations], ['current_qty']
    )

    return allocations


def apply_stock_adjustment(*, adjustment: StockAdjustment) -> None:
    """Apply a manual stock adjustment by reducing the newest batch.

    Negative qty_adjusted = removal; positive = add back (uses oldest batch).
    After applying, check low-stock thresholds.
    """
    from .models import InventoryBatch

    variant = adjustment.variant
    qty = adjustment.qty_adjusted

    if qty < 0:  # removal (shrinkage / damage)
        try:
            alloc = allocate_fifo(variant_id=variant.pk, qty_needed=abs(qty))
        except ValueError:
            alloc = allocate_fifo(variant_id=variant.pk, qty_needed=abs(qty))
    elif qty > 0:  # addition (correction / return)
        # Add to the most recent active batch
        batch = (
            InventoryBatch.objects
            .filter(variant=variant, current_qty__gt=0)
            .order_by('-receipt__receive_date')
            .first()
        )
        if batch:
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
