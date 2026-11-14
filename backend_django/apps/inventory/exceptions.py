"""Inventory domain exceptions.

Kept separate from `services` so callers and the API layer can both import the type
without importing the service module.
"""


class CatalogWriteRefused(ValueError):
    """A catalog or purchasing write the server refuses (Phase 4 Tasks 1-2).

    Every one of these refusals was previously reachable with a well-formed request: a
    delete that 500'd on `PROTECT`, a selling unit with a factor of 0 (which divided
    every FIFO deduction by zero), two factor-1 units on one variant (making "the base
    unit" ambiguous), a purchase order placed from a body field instead of an action.

    Carries a stable `code` and a `detail` sentence, and `apps.pos.exceptions.handler`
    publishes them as the project's `{code, detail}` **400** - the same shape the till's
    refusals use, so a client branches on `code` instead of matching English prose.

    A `ValueError` subclass, like `InvalidSale`: the request is well formed, it just
    asks for something the shop's history does not allow. Raised from serializer
    `validate()` and from the purchasing actions, always BEFORE the first write, so a
    refused request leaves no row and no audit row behind.
    """

    code = "INVALID_CATALOG_WRITE"


class InvalidSellingUnit(CatalogWriteRefused):
    """A selling unit whose numbers cannot be used (factor <= 0, price < 0)."""

    code = "INVALID_SELLING_UNIT"


class DuplicateBaseUnit(CatalogWriteRefused):
    """A second conversion-factor-1 unit on one variant.

    Factor 1 IS the base unit: it is what `process_sale` multiplies a sold qty by and
    what a return restocks. Two of them on one variant make "how many base units is one
    box" unanswerable, so the second is refused rather than picked between.
    """

    code = "DUPLICATE_BASE_UNIT"


class SellingUnitInUse(CatalogWriteRefused):
    """A selling unit history holds: its meaning cannot change and it cannot go away.

    A sale line records `qty` in selling units and the FIFO deduction in BASE units
    (`qty x conversion_factor`), and a linked return caps and restocks against those two
    numbers. Changing the factor or re-pointing the unit afterwards re-writes the meaning
    of every past sale - and of the return the customer is about to make. The PRICE stays
    editable: a till may reprice, it may not rewrite history.

    Phase 1d Task 3 (decision 16) added REMOVAL to the same code: a unit referenced by
    any of the five PROTECT tables - a sale line (a sale or a return), a held cart, a
    project request, a quotation, a sales order - is refused instead of erased. A project
    request line freezes the unit exactly like a sale does (decision 16, Q4).
    """

    code = "SELLING_UNIT_IN_USE"


class BaseUnitRequired(CatalogWriteRefused):
    """A delete of the variant's factor-1 selling unit (Phase 1d Task 3, decision 16).

    Factor 1 IS the base unit: `process_sale` multiplies a sold quantity by it and a
    return restocks in it, so removing it would leave every quantity counted in a unit
    the product no longer has. Its own code because the clerk's next move is different
    from "this unit is used": remove another unit, or archive the product.
    """

    code = "BASE_UNIT_REQUIRED"


class InvalidVariant(CatalogWriteRefused):
    """A variant write the shop cannot accept.

    A negative `min_stock_threshold` / `max_stock_level` makes every sale "low stock"
    and every reorder quantity nonsense; `product` and `base_uom` are set at creation
    because changing either re-points the variant's whole stock and sales history.
    """

    code = "INVALID_VARIANT"


class SupplierInactive(CatalogWriteRefused):
    """A purchase order for a supplier that has been deactivated.

    An inactive supplier is one this shop has stopped buying from (the delete it used to
    have became the archive), so raising an order against it would put a document in the
    receiving queue that nobody intends to deliver.
    """

    code = "SUPPLIER_INACTIVE"

    def __init__(self, supplier):
        self.supplier_id = getattr(supplier, "pk", supplier)
        super().__init__(
            f"{supplier} is inactive: reactivate it before ordering from it."
        )


class InvalidPurchaseOrder(CatalogWriteRefused):
    """A purchase-order payload the shop cannot accept.

    No lines, an ordered qty of 0, a negative unit cost, an inactive variant, the same
    variant on two lines, or a `variant_uom` that does not belong to the line's variant
    (Phase 5 B1, decision 18). A line is COUNTED in its selling unit, so a unit from
    another product would price and stock a different product's package; a unit id that
    does not exist, or a variant with no base selling unit when the unit is omitted, is
    refused for the same reason - never guessed at. All of them are refused BEFORE the
    order row exists, so a refusal leaves no PO and no lines.
    """

    code = "INVALID_PO"


class InvalidPurchaseOrderState(CatalogWriteRefused):
    """An action that does not apply to the order's current status.

    `place/` on anything but a DRAFT, `cancel/` on an already-cancelled order.
    """

    code = "INVALID_PO_STATE"


class PurchaseOrderLocked(CatalogWriteRefused):
    """An edit to a purchase order that has left DRAFT.

    Once placed, the supplier has been told what to deliver; changing the lines or the
    supplier afterwards would make the receipt of what arrives disagree with the order it
    is booked against. Cancel and raise a new order instead.
    """

    code = "PO_LOCKED"


class PurchaseOrderHasReceipts(CatalogWriteRefused):
    """A cancel of an order that has already received stock.

    Cancelling a PARTIAL/COMPLETE order would leave batches in the rack explained by a
    document the books call cancelled. Send the goods back through a stock adjustment.
    """

    code = "PO_HAS_RECEIPTS"


class PurchaseOrderNotOrdered(CatalogWriteRefused):
    """A goods receipt against a DRAFT purchase order.

    A DRAFT has not been placed, so what arrives is not what this document asked for. The
    fix is to place it (`POST /purchase-orders/{id}/place/`) or record the delivery
    against the order that was actually placed.
    """

    code = "PO_NOT_ORDERED"

    def __init__(self, po):
        super().__init__(
            f"PO #{getattr(po, 'pk', po)} is DRAFT and cannot be received: place it "
            "first."
        )


class PurchaseOrderNotReceivable(CatalogWriteRefused):
    """A goods receipt against a COMPLETE or CANCELLED purchase order.

    Kept as its own code so a receiving screen can tell "place it first" from "this order
    is finished": one is a missing step, the other is a closed document.
    """

    code = "PO_NOT_RECEIVABLE"


class ReceiptQuantityUnrepresentable(CatalogWriteRefused):
    """A delivered quantity whose exact base-unit stock cannot be kept as it is.

    `InventoryBatch.initial_qty`/`current_qty` hold TWO decimal places, so a receipt is
    only storable when `qty x conversion_factor` is a whole hundredth of the variant's
    base unit. `_create_batch` used to quantize that product HALF_UP instead, which made
    a factor-0.01 line receiving 0.01 stock **0.00** (stocked nothing while
    `received_qty` said the delivery arrived) and made 0.50 x 0.03 = 0.015 stock
    **0.02** (minted a hundredth nobody delivered). Rounding stock is never right: the
    shelf and the books then disagree, and the only honest answer is to ask for a
    quantity that fits.

    Raised BEFORE the receipt row is written (the POST path) and again inside
    `process_goods_receipt`'s atomic block (the ORM/legacy path), so the refusal always
    means "nothing changed". A `CatalogWriteRefused` subclass, so the shared handler
    publishes the project's `{code, detail}` **400** with no new machinery.
    """

    code = "RECEIPT_QUANTITY_UNREPRESENTABLE"


class InsufficientStock(ValueError):
    """A FIFO allocation could not be satisfied by the stock on hand.

    **Subclasses `ValueError` deliberately, and that is load-bearing.** Ten call
    sites catch `except ValueError` around `allocate_fifo` and five tests assert
    `assertRaises(ValueError)`, so raising a sibling type instead would break all
    fifteen. Subclassing keeps every existing handler working while letting a DRF
    exception handler match the precise type, so an unrelated `ValueError` bug
    elsewhere can never be mis-reported to a cashier as "not enough stock".

    Carries the `shortfall` because decision 06 requires the checkout client to be
    told how far short the sale was, so it can name the offending line.
    """

    code = "INSUFFICIENT_STOCK"

    def __init__(self, message, *, shortfall=None, variant_id=None):
        super().__init__(message)
        self.shortfall = shortfall
        self.variant_id = variant_id


class ReceiptAlreadyProcessed(ValueError):
    """This goods receipt has already been turned into batches (decision 09 item 4).

    The guard used to live in the VIEW as `receipt.batches.exists()` — a read outside any
    transaction — so two concurrent process/ calls could both pass it and double-count
    the stock. It now lives in `process_goods_receipt`, inside the atomic block holding
    the receipt row's lock, with `GoodsReceipt.processed_at` as the evidence.

    A `ValueError` subclass, so it reads as a client error: the request is well-formed,
    it just names a receipt whose delivery is already in stock.
    """

    code = "RECEIPT_ALREADY_PROCESSED"

    def __init__(self, receipt_pk, message=None):
        self.receipt_pk = receipt_pk
        super().__init__(
            message or f"Goods receipt {receipt_pk} was already processed."
        )


class NoBatchHistory(ValueError):
    """A positive stock adjustment for a variant that has never been delivered.

    There is nowhere to put the quantity. The ledger ruling for decision 09 item 5:
    "create a batch" was the plan, but `InventoryBatch.receipt` is a non-null PROTECT
    foreign key, so a receipt-less batch would need a schema change — instead the
    adjustment reopens the newest EXISTING batch for the variant, and when there is no
    batch at all the adjustment is refused rather than booked against nothing.

    A `ValueError` subclass for the same reason as `InsufficientStock`: the request is
    well-formed, it just names a variant this shop has never stocked, and the client's
    answer is "record the delivery first".
    """

    code = "NO_BATCH_HISTORY"

    def __init__(self, variant, message=None):
        self.variant_id = getattr(variant, "pk", variant)
        super().__init__(
            message
            or f"Variant {variant} has no batch history: stock it with a goods "
            "receipt before correcting its quantity upwards."
        )


class BarcodeTaken(CatalogWriteRefused):
    """Another selling unit already carries this code (Phase 6, decision 11).

    A code is what a scan resolves to, so two units sharing one make the till a coin
    toss. The second write is refused and the detail names the holder (product ·
    variant · unit), which leaks nothing: an inventory role may already read every
    catalog row.

    Raised by the serializer's pre-check for a readable sentence, and again by the view
    when the DB constraint refuses the race the pre-check cannot win (two tills, one
    code).
    """

    code = "BARCODE_TAKEN"


class BarcodeInvalid(CatalogWriteRefused):
    """A code that is not scannable (decision 12).

    Either it cannot be read as typed - not printable ASCII without spaces, or longer
    than 100 characters - or it is an all-digit 8/12/13-character manufacturer code whose
    GS1 mod-10 check digit does not match, i.e. a keying typo. Storing it would make the
    unit look scannable while no scanner can ever find it.
    """

    code = "BARCODE_INVALID"


class BarcodeReservedPrefix(CatalogWriteRefused):
    """A hand-typed internal `QB…` code (decision 12).

    `QB` codes are generated from the selling unit's id, so a typed one is either a
    mistake or a code a future unit is going to be given - and then two units would hold
    it. Only a unit's OWN derived code is accepted, which makes a PATCH of a generated
    code a no-op instead of a refusal.
    """

    code = "BARCODE_RESERVED_PREFIX"


# ---------------------------------------------------------------------------
# Supplier payables (Phase 5 B2, decision 18)
# ---------------------------------------------------------------------------


class PayablesRefused(CatalogWriteRefused):
    """A supplier-payables write the shop refuses.

    Same family - and therefore the same `{code, detail}` **400** - as every other
    catalog/purchasing refusal: the request is well formed, it just asks for something
    the shop's money rules do not allow. Raised BEFORE the first write (serializer
    `validate()`) or under the bill's row lock (a payment), so a refusal leaves no
    payment, no balance change and no audit row behind.
    """

    code = "INVALID_PAYABLES_WRITE"


class InvalidSupplierTerms(PayablesRefused):
    """Payment terms that cannot be a due date (`terms_days` below zero).

    Zero is valid and means "due on receipt"; a negative number would date the bill
    before the goods arrived, so the column is a `PositiveIntegerField` and the write
    is refused explicitly instead of failing on a database error.
    """

    code = "INVALID_SUPPLIER_TERMS"


class InvalidSupplierPayment(PayablesRefused):
    """A supplier payment the shop cannot record.

    Covers everything a payment can be wrong about before any money moves: an amount
    that is zero, negative, not a number (`NaN`/`Infinity` are refused, not coerced), an
    unknown method, or a cheque missing its number, bank or date - the three facts that
    make a cheque answerable later.
    """

    code = "INVALID_SUPPLIER_PAYMENT"


class Overpayment(PayablesRefused):
    """A payment larger than what the bill still owes.

    A supplier bill is not a credit line: paying past the balance would put the shop in
    credit with the supplier through a column that only ever counts down, so the amount
    is refused and the balance is left exactly as it was.
    """

    code = "OVERPAYMENT"

    def __init__(self, bill, amount, message=None):
        self.bill_pk = getattr(bill, "pk", bill)
        super().__init__(
            message
            or (
                f"Bill #{self.bill_pk} has {bill.balance_amount} left to pay: "
                f"{amount} is more than that. Record a payment up to the balance."
            )
        )


class BillPaid(PayablesRefused):
    """A payment against a bill that is already settled.

    Its own code because the clerk's next move differs from an overpayment: there is
    nothing to fix, the bill is done. It is also what two concurrent payments produce -
    the loser reads a zero balance under the same row lock.
    """

    code = "BILL_PAID"

    def __init__(self, bill, message=None):
        self.bill_pk = getattr(bill, "pk", bill)
        super().__init__(message or f"Bill #{self.bill_pk} is already paid in full.")


class CreditExceedsRemaining(PayablesRefused):
    """More supplier credit asked for than the note still has (Phase 8 B4).

    A credit note is not a line of credit: `remaining_amount` counts down as the credit is
    applied, and spending past it would invent money the supplier never owed back. The
    check runs under the note's own row lock, so two managers applying at once cannot
    both spend the last peso - the loser reads 0.00 left and lands here.
    """

    code = "CREDIT_EXCEEDS_REMAINING"

    def __init__(self, note, amount):
        self.note_pk = note.pk
        super().__init__(
            f"Credit note {note.number} has {note.remaining_amount} left to apply: "
            f"{amount} is more than that. Apply credit up to the remaining amount."
        )


class CreditNoteSupplierMismatch(PayablesRefused):
    """A credit note spent on another supplier's bill (Phase 8 B4).

    Supplier credit belongs to ONE supplier: the note records goods that supplier took
    back, so it can only ever settle that supplier's bills. Applying it elsewhere would
    pay a stranger with money the creditor owes, so the mismatch is refused under the
    note's lock before the bill is even touched.
    """

    code = "CREDIT_NOTE_SUPPLIER_MISMATCH"

    def __init__(self, note, bill):
        self.note_pk = note.pk
        self.bill_pk = getattr(bill, "pk", bill)
        super().__init__(
            f"Credit note {note.number} belongs to {note.supplier.company_name} and "
            f"cannot be applied to bill #{self.bill_pk}, which is owed to another "
            "supplier."
        )


class ImmutablePayableRecord(ValueError):
    """A write that would rewrite money that has already been agreed or paid.

    NOT a client-facing refusal: no endpoint offers such a write (bills are read-only,
    payments are append-only), so reaching this is a programming error or a shell
    session. It subclasses `ValueError` so a stray caller still reads as "asked for
    something impossible" rather than as a 500 from the database.
    """

    code = "IMMUTABLE_PAYABLE_RECORD"


class InvalidSupplierReturn(PayablesRefused):
    """A supplier return the shop cannot record, for a reason that is not the quantity.

    Three shapes: no reason (a return with no story behind it is an unexplained hole in
    the stock ledger), no lines at all, and a receipt line that belongs to a DIFFERENT
    receipt (that would take stock off a delivery the clerk did not pick).

    Not raised for a quantity problem: a fractional or unrepresentable quantity is the
    project's own `WHOLE_UNIT_QUANTITY` / `RECEIPT_QUANTITY_UNREPRESENTABLE` (the same two
    answers receiving gives), and an over-return is `RETURN_EXCEEDS_RECEIPT`.
    """

    code = "INVALID_SUPPLIER_RETURN"


class ReceiptNotProcessed(PayablesRefused):
    """A return against a receipt that never became stock.

    An unprocessed receipt has moved nothing into the rack, so there is nothing to send
    back: the goods are not on the shelf yet. Its own code because the clerk's next move
    is to process the delivery (or pick the receipt that was processed).
    """

    code = "RECEIPT_NOT_PROCESSED"


class ReturnExceedsReceipt(PayablesRefused):
    """A returned quantity larger than this receipt line can still give back.

    Decision 20 #2: the cap is `min(delivered base qty - base already returned on that
    line, the receipt's batches' current qty)`. The first half keeps a line from returning
    the same bags twice; the second keeps the books off stock that a sale, a damage
    adjustment (or an earlier return through the other receipt line of the same variant)
    has already taken. Raised UNDER the receipt's row lock and BEFORE any write of the
    line's quantity, so a refused return leaves no return, no deduction and no moved
    stock.
    """

    code = "RETURN_EXCEEDS_RECEIPT"

    def __init__(self, message):
        super().__init__(message)


class ReturnAdjustmentRetired(CatalogWriteRefused):
    """A new stock adjustment of type RETURN - the path decision 20 replaced.

    Before Phase 8 B2 the adjust dialog offered "Supplier Return" and POSTed
    `adjustment_type=RETURN`, which moved stock out through FIFO with NO credit note, no
    record of which receipt the goods came from and no cap. The way out is
    `POST /supplier-returns/`, which does all three. Historic RETURN rows keep their label
    - the refusal is on the CREATE path only, so the ledger still shows what happened.
    """

    code = "USE_SUPPLIER_RETURN"


# ---------------------------------------------------------------------------
# Storage locations (Phase 5 B4, decision 18)
# ---------------------------------------------------------------------------


class InvalidStorageLocation(CatalogWriteRefused):
    """A storage location the shop cannot accept (Phase 5 B4, decision 18).

    Three shapes, all refused BEFORE any write so a refusal leaves no row and no audit
    row: a blank name, a name that already belongs to another location (compared
    case-insensitively, because "Bodega" and "bodega" are one place), and an INACTIVE
    location being given to a product - deactivating removes a place from the picker, so
    assigning it would put goods in a spot the shop has just said it no longer uses.

    A product that is already labelled with a location that is LATER deactivated keeps
    that label: the goods did not move, and the label is where they are. That asymmetry
    is the ruling for this phase and is stated in ENDPOINTS.md.
    """

    code = "INVALID_STORAGE_LOCATION"


# ---------------------------------------------------------------------------
# Stock transfers (Phase 9 B4, decision 21 §3)
# ---------------------------------------------------------------------------


class InvalidStockTransfer(CatalogWriteRefused):
    """A transfer with nothing to move (Phase 9 B4, plan Design 6).

    Raised by `transfers.record_stock_transfer` for an empty line list, so the ORM path is
    refused exactly like the API: a numbered slip that moves no stock is a slip the shop
    would later reconcile against a shelf that never changed.
    """

    code = "INVALID_STOCK_TRANSFER"


class TransferQuantityUnrepresentable(CatalogWriteRefused):
    """A transfer quantity that is not a whole hundredth of the base unit (Phase 9 B4).

    The batch columns hold two decimal places, so `qty × conversion_factor` has to LAND on
    one of them. The same rule a goods receipt applies to a delivery
    (`ReceiptQuantityUnrepresentable`), for the same reason: rounding 0.015 base units
    means one shelf silently loses a fraction and the other gains it, and the two shelves
    then disagree with the shop's total - on a document whose whole job is moving an exact
    quantity. Its own code, because the answer differs: this is a transfer, not a
    delivery. Raised before the first write, so a refusal moves nothing.
    """

    code = "TRANSFER_QUANTITY_UNREPRESENTABLE"


# ---------------------------------------------------------------------------
# Excel catalogue import (Phase 3 B1, decision 23)
# ---------------------------------------------------------------------------


class CatalogueImportRefused(CatalogWriteRefused):
    """A catalogue import request the server cannot even read as a sheet.

    Phase 3 B1 (decision 23): the file is parsed in the Flutter app and arrives here as
    JSON rows, so the only whole-request answers are "that is not a list of rows" and
    "that is too many rows" (`CatalogueImportTooLarge`). Everything a ROW gets wrong is a
    row error in the preview body instead, because the clerk has to fix cells in Excel and
    re-upload, not re-run the request.
    """

    code = "INVALID_CATALOGUE_IMPORT"


class CatalogueImportTooLarge(CatalogueImportRefused):
    """More rows than one import accepts (decision 23: 2,000 rows per file).

    Refused for the WHOLE request rather than per row: a file past the cap is not a file
    with a bad row, it is a file the shop has to split, and a preview that quietly ignored
    the 2,001st row would apply a catalogue the clerk never saw.
    """

    code = "CATALOGUE_IMPORT_TOO_LARGE"


class CatalogueImportRowsRefused(CatalogWriteRefused):
    """A sheet whose rows still have errors when the apply runs (Phase 3 B2).

    The preview already showed these, so the client should have kept Apply disabled; the
    refusal exists because the SAME validation runs again under the apply's locks (a
    catalogue that moved can turn a clean row into a refused one). The row error list
    travels with the refusal in `errors`, so the dialog renders the same table it renders
    for a preview instead of a bare sentence.
    """

    code = "CATALOGUE_IMPORT_ROW_ERRORS"

    def __init__(self, errors):
        self.errors = errors
        count = len(errors)
        super().__init__(
            f"This sheet still has {count} row error{'s' if count != 1 else ''}: nothing "
            "was written. Fix the cells the preview lists and run the preview again."
        )


class CataloguePreviewStale(CatalogWriteRefused):
    """The catalogue moved between the preview and the apply (Phase 3 B2, decision 23).

    A **409**, not a 400: the request is well formed, the rows were validated once and the
    caller is allowed to write. What changed is the catalogue underneath - a price, a
    barcode, a whole row - so the fingerprint the preview returned no longer matches the
    one recomputed under the apply's row locks. Writing anyway would apply a file the
    clerk never saw, so the answer is "run the preview again" and nothing is written.

    The status is the CALLER's to apply: `apps.pos.exceptions.handler` answers every
    `CatalogWriteRefused` with 400, so `catalogue_import_apply_view` catches this one and
    answers 409 itself, leaving the shared handler untouched.
    """

    code = "CATALOGUE_PREVIEW_STALE"

    def __init__(self):
        super().__init__("Run the preview again")


class CatalogueImportBusy(CatalogWriteRefused):
    """Another writer held a referenced row past the apply's `lock_timeout`.

    A **503**, not a 400: nothing about the request was wrong. A sale, a receipt, an
    adjustment or a transfer was holding a selling unit (or the variant above it) for
    longer than the apply was willing to wait, so the apply gave up instead of parking
    behind it - the catalogue is BUSY, and the same request will very likely work a
    moment later.

    Retryable, and `Retry-After` is set by the caller. Nothing is written: the timeout is
    raised inside the `atomic` block and caught outside it, so the whole apply rolls back.

    The status is the CALLER's to apply: `apps.pos.exceptions.handler` answers every
    `CatalogWriteRefused` with 400, so `catalogue_import_apply_view` catches this one and
    answers 503 itself, leaving the shared handler untouched.
    """

    code = "CATALOGUE_IMPORT_BUSY"

    def __init__(self):
        super().__init__("The catalogue is busy. Try again in a moment.")


class CatalogueImportNotSaved(CatalogWriteRefused):
    """A non-barcode constraint failure while the apply was writing.

    The barcode race has its own 400 (`BARCODE_TAKEN`). Anything else - a product or
    variant name another admin took while this apply ran, a concurrent create - is the
    same story as a stale fingerprint: the catalogue moved under the file, so the rows
    the preview saw are no longer the rows on disk. Answered as a **409** rather than an
    unhandled 500, because "run the preview again" IS the clerk's next move and the
    transaction has already rolled back (nothing is saved).

    The status is the CALLER's to apply: `apps.pos.exceptions.handler` answers every
    `CatalogWriteRefused` with 400, so `catalogue_import_apply_view` answers 409 itself.
    """

    code = "CATALOGUE_IMPORT_NOT_SAVED"

    def __init__(self):
        super().__init__("The import could not be saved. Run the preview again.")
