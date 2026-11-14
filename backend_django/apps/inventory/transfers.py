# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/inventory/services.py: the checker resolves its config
# from its WORKING DIRECTORY and does not find this repo's pyrightconfig.json, so without
# django-stubs every `Model.objects`, every `with transaction.atomic():` and every read of
# a `DecimalField` as the `Decimal` Django returns is a false positive on valid Django.
"""Phase 9 B4 (decision 21 §3, plan Design 2/6/11/12) — moving stock between shelves.

ONE step, at once: the stock team writes "move N BAG from Store to Bodega", the quantity
leaves the source shelf's batches FIFO-first and lands in NEW batches on the destination
shelf, and the numbered `TR-YYYYMMDD-NNNN` slip plus the `STOCK_TRANSFER` audit row are the
record. There is no in-transit state and nothing to receive later.

Why new batches instead of moving the old ones (plan Design 2): `InventoryBatch.location`
is IMMUTABLE, which is what makes `SalesItemDeduction.batch.location` a stable "where it
was taken". A transfer therefore COPIES receipt, landed cost, selling price, markup and
expiry onto a destination batch and sets `source_batch`, so cost and FIFO age travel with
the goods while every "what did this receipt bring in" sum skips the copy exactly once.
"""

from decimal import Decimal

from django.db import transaction

from common.exceptions import refuse_fractional_whole_unit, refuse_inactive_selling_unit

from .exceptions import (
    InsufficientStock,
    InvalidStockTransfer,
    InvalidStorageLocation,
    TransferQuantityUnrepresentable,
)
from .models import (
    InventoryBatch,
    StockTransfer,
    StockTransferLine,
    StockTransferMove,
    StorageLocation,
)
from .services import _check_low_stock, allocate_fifo, lock_selling_unit_lines

CENT = Decimal("0.01")


def _resolved_lines(lines):
    """`[(variant_uom, qty)]` → `[(variant_uom, qty, base_qty)]`, one per line.

    Every refusal here is about the LINE the clerk typed, and all of them fire before the
    first write, so the 400 also means "nothing changed":

    * an ARCHIVED variant (or archived product) is off the catalogue - same rule and code
      (`INACTIVE_SELLING_UNIT`) the till and the supplier return apply;
    * a fraction on a whole unit (`WHOLE_UNIT_QUANTITY`): half a BAG is not stock anybody
      can put on a shelf;
    * a conversion that does not land on a whole hundredth of the base unit
      (`TRANSFER_QUANTITY_UNREPRESENTABLE`): the batch columns store two decimal places,
      so 0.50 × 0.03 = 0.015 base units would have to be silently rounded - one shelf
      losing 0.005 and the other gaining it. Refused instead, with the arithmetic in the
      sentence so the clerk can re-count.

    The result is sorted by VARIANT PK (plan Design 12): two transfers touching the same
    two variants queue on the batch rows in one order instead of deadlocking.
    """
    resolved = []
    for variant_uom, qty in lines:
        refuse_inactive_selling_unit(
            variant_uom=variant_uom, what=f"Line for {variant_uom.variant}"
        )
        refuse_fractional_whole_unit(
            is_whole=variant_uom.uom.is_whole,
            qty=qty,
            what=f"{qty} × {variant_uom.uom.code} of {variant_uom.variant}",
        )
        base_qty = qty * variant_uom.conversion_factor
        if base_qty != base_qty.quantize(CENT):
            raise TransferQuantityUnrepresentable(
                f"Moving {qty} {variant_uom.uom.code} of {variant_uom.variant} (1 "
                f"{variant_uom.uom.code} = {variant_uom.conversion_factor} "
                f"{variant_uom.variant.base_uom.code}) is exactly {base_qty} "
                f"{variant_uom.variant.base_uom.code} of stock, and stock is kept in "
                "whole hundredths of the base unit: transfer a quantity that converts to "
                "a whole hundredth (0.01) of the base unit."
            )
        resolved.append((variant_uom, qty, base_qty))
    resolved.sort(key=lambda entry: entry[0].variant_id)
    return resolved


def record_stock_transfer(
    *,
    from_location: StorageLocation,
    to_location: StorageLocation,
    lines,
    user,
    remarks="",
) -> StockTransfer:
    """Move `lines` of stock between two shelves; returns the stored transfer.

    `lines` is `[(VariantUOM, qty_in_that_selling_unit)]`. The transfer row, its lines, the
    moved quantities, the new destination batches, the low-stock check, the reserved number
    and (in the caller) the audit row are ONE transaction: a refusal anywhere leaves no
    header, no line, no move, no new batch and no audit row.

    **Lock order (plan Design 12), inside this block:**

    (0) the SELLING UNITS the lines name, in PK order (`lock_selling_unit_lines`) - before
        the batch rows, because a sale takes them in that order too. This step was found
        by the concurrent-transfer-vs-sale test: without it the transfer held the batch
        row and then waited on the selling-unit row a sale held, while the sale waited on
        the batch row - one deadlock per busy afternoon;
    (a) the DESTINATION shelf under `select_for_update` - the only way a shelf becomes
        unusable mid-write is an Admin deactivating it, so holding the row fences that
        race and an inactive destination is refused with `INVALID_STORAGE_LOCATION`;
    (b) the source shelf's batches, one ordered FIFO query per variant, variants in PK
        order (`_resolved_lines` sorted them);
    (c) the `ProductVariant` row through `_check_low_stock` - total unchanged, so this can
        only confirm the alert state, but it keeps the writer in the documented order;
    (d) the `DocumentCounter` through `next_number` LAST, so a refused transfer never
        consumes a number.

    The SOURCE shelf is deliberately not locked: stock that is already on a deactivated
    shelf stays transferable OUT (plan Design 11), and the batches themselves are the
    quantity being checked.

    A short shelf raises `InsufficientStock` naming the SHELF - the Bodega's stock must not
    pay for a Store shortage, and "not enough stock" without the place sends the stocker
    looking at every shelf in the shop.
    """
    if from_location.pk == to_location.pk:
        raise InvalidStorageLocation(
            f"{from_location.name} is both the source and the destination: a transfer "
            "must move stock to a different shelf."
        )
    if not lines:
        raise InvalidStockTransfer("A stock transfer needs at least one line.")

    resolved = _resolved_lines(lines)

    with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
        # (0) Selling units first, in PK order: the same first resource `process_sale`
        # locks, so the two writers queue instead of deadlocking.
        lock_selling_unit_lines(
            [(entry[0], entry[1]) for entry in resolved], document="stock transfer"
        )

        destination = StorageLocation.objects.select_for_update().get(pk=to_location.pk)
        if not destination.is_active:
            raise InvalidStorageLocation(
                f"{destination.name} is deactivated and cannot receive stock: transfer "
                "to an active location, or have this one reactivated."
            )

        # (b) Allocate every line off the SOURCE shelf only, in variant-PK order.
        allocations = []
        for variant_uom, qty, base_qty in resolved:
            try:
                taken = allocate_fifo(
                    variant_id=variant_uom.variant_id,
                    qty_needed=base_qty,
                    location_id=from_location.pk,
                )
            except InsufficientStock as exc:
                unit = variant_uom.variant.base_uom.code
                assert exc.shortfall is not None  # allocate_fifo always reports one
                # Quantized to the column's scale: `allocate_fifo` subtracts Decimals of
                # different exponents, so the raw shortfall can read "3.0000" next to a
                # shelf that counts in hundredths.
                shortfall = exc.shortfall.quantize(CENT)
                raise InsufficientStock(
                    f"Not enough {variant_uom.variant} at {from_location.name}: "
                    f"{shortfall} {unit} short of the {base_qty} {unit} this line "
                    "moves. Transfer only what that shelf holds, or pick a source shelf "
                    "that has it.",
                    shortfall=shortfall,
                    variant_id=exc.variant_id,
                ) from exc
            allocations.append((variant_uom, qty, base_qty, taken))

        # (b) continues: the DESTINATION batches, one per source batch taken. They are
        # written here, before the variant rows and the number, so the write order is the
        # documented one. The lines and moves wait for the header below (they point at
        # it), so they are staged here as `moved`.
        moved = []
        for variant_uom, qty, base_qty, taken in allocations:
            line_moves = []
            for source_batch, take in taken:
                # The destination batch COPIES the source: same delivery, same landed
                # cost, same price, same expiry, and `source_batch` marks it as a move so
                # no receipt sum counts the goods twice. `initial_qty` is the moved
                # quantity, because that is all this batch ever held here.
                dest_batch = InventoryBatch.objects.create(
                    variant=variant_uom.variant,
                    receipt=source_batch.receipt,
                    location=destination,
                    source_batch=source_batch,
                    initial_qty=take,
                    current_qty=take,
                    unit_cost_landed=source_batch.unit_cost_landed,
                    markup_percentage=source_batch.markup_percentage,
                    batch_selling_price=source_batch.batch_selling_price,
                    expiration_date=source_batch.expiration_date,
                )
                line_moves.append((source_batch, dest_batch, take))
            moved.append((variant_uom, qty, base_qty, line_moves))

        # (c) Variant rows, in PK order, after the batches - the documented order. The
        # variant's TOTAL is unchanged by a move, so this can only confirm what the
        # threshold already said; it is here for the lock order, not for a new alert.
        for variant_id in dict.fromkeys(
            variant_uom.variant_id for variant_uom, _qty, _base, _moves in moved
        ):
            _check_low_stock(_variant_ref(variant_id))

        # (d) The number is reserved LAST: everything above can refuse, and a refused
        # transfer must not burn a slip number.
        from apps.pos.services import next_number

        transfer = StockTransfer.objects.create(
            number=next_number("TR"),
            from_location=from_location,
            to_location=destination,
            user=user,
            remarks=remarks or "",
        )

        # The lines and moves of the batches already written, now that the header exists.
        for variant_uom, qty, base_qty, line_moves in moved:
            line = StockTransferLine.objects.create(
                transfer=transfer,
                variant_uom=variant_uom,
                qty=qty,
                base_qty=base_qty,
            )
            for source_batch, dest_batch, take in line_moves:
                StockTransferMove.objects.create(
                    line=line,
                    source_batch=source_batch,
                    dest_batch=dest_batch,
                    qty=take,
                )

    return transfer


def _variant_ref(variant_id: int):
    """The variant row for `_check_low_stock`, which re-reads it under its lock anyway."""
    from .models import ProductVariant

    return ProductVariant(pk=variant_id)
