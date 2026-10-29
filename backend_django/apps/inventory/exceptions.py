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

    code = 'INVALID_CATALOG_WRITE'


class InvalidSellingUnit(CatalogWriteRefused):
    """A selling unit whose numbers cannot be used (factor <= 0, price < 0)."""

    code = 'INVALID_SELLING_UNIT'


class DuplicateBaseUnit(CatalogWriteRefused):
    """A second conversion-factor-1 unit on one variant.

    Factor 1 IS the base unit: it is what `process_sale` multiplies a sold qty by and
    what a return restocks. Two of them on one variant make "how many base units is one
    box" unanswerable, so the second is refused rather than picked between.
    """

    code = 'DUPLICATE_BASE_UNIT'


class SellingUnitInUse(CatalogWriteRefused):
    """A variant/uom/factor change on a selling unit that has already been SOLD.

    A sale line records `qty` in selling units and the FIFO deduction in BASE units
    (`qty x conversion_factor`), and a linked return caps and restocks against those two
    numbers. Changing the factor or re-pointing the unit afterwards re-writes the meaning
    of every past sale - and of the return the customer is about to make. The PRICE stays
    editable: a till may reprice, it may not rewrite history.
    """

    code = 'SELLING_UNIT_IN_USE'


class InvalidVariant(CatalogWriteRefused):
    """A variant write the shop cannot accept.

    A negative `min_stock_threshold` / `max_stock_level` makes every sale "low stock"
    and every reorder quantity nonsense; `product` and `base_uom` are set at creation
    because changing either re-points the variant's whole stock and sales history.
    """

    code = 'INVALID_VARIANT'


class SupplierInactive(CatalogWriteRefused):
    """A purchase order for a supplier that has been deactivated.

    An inactive supplier is one this shop has stopped buying from (the delete it used to
    have became the archive), so raising an order against it would put a document in the
    receiving queue that nobody intends to deliver.
    """

    code = 'SUPPLIER_INACTIVE'

    def __init__(self, supplier):
        self.supplier_id = getattr(supplier, 'pk', supplier)
        super().__init__(
            f'{supplier} is inactive: reactivate it before ordering from it.')


class InvalidPurchaseOrder(CatalogWriteRefused):
    """A purchase-order payload the shop cannot accept.

    No lines, an ordered qty of 0, a negative unit cost, an inactive variant, or the same
    variant on two lines. All of them are refused BEFORE the order row exists, so a
    refusal leaves no PO and no lines.
    """

    code = 'INVALID_PO'


class InvalidPurchaseOrderState(CatalogWriteRefused):
    """An action that does not apply to the order's current status.

    `place/` on anything but a DRAFT, `cancel/` on an already-cancelled order.
    """

    code = 'INVALID_PO_STATE'


class PurchaseOrderLocked(CatalogWriteRefused):
    """An edit to a purchase order that has left DRAFT.

    Once placed, the supplier has been told what to deliver; changing the lines or the
    supplier afterwards would make the receipt of what arrives disagree with the order it
    is booked against. Cancel and raise a new order instead.
    """

    code = 'PO_LOCKED'


class PurchaseOrderHasReceipts(CatalogWriteRefused):
    """A cancel of an order that has already received stock.

    Cancelling a PARTIAL/COMPLETE order would leave batches in the rack explained by a
    document the books call cancelled. Send the goods back through a stock adjustment.
    """

    code = 'PO_HAS_RECEIPTS'


class PurchaseOrderNotOrdered(CatalogWriteRefused):
    """A goods receipt against a DRAFT purchase order.

    A DRAFT has not been placed, so what arrives is not what this document asked for. The
    fix is to place it (`POST /purchase-orders/{id}/place/`) or record the delivery
    against the order that was actually placed.
    """

    code = 'PO_NOT_ORDERED'

    def __init__(self, po):
        super().__init__(
            f'PO #{getattr(po, "pk", po)} is DRAFT and cannot be received: place it '
            'first.')


class PurchaseOrderNotReceivable(CatalogWriteRefused):
    """A goods receipt against a COMPLETE or CANCELLED purchase order.

    Kept as its own code so a receiving screen can tell "place it first" from "this order
    is finished": one is a missing step, the other is a closed document.
    """

    code = 'PO_NOT_RECEIVABLE'



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

    code = 'INSUFFICIENT_STOCK'

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

    code = 'RECEIPT_ALREADY_PROCESSED'

    def __init__(self, receipt_pk, message=None):
        self.receipt_pk = receipt_pk
        super().__init__(
            message or f'Goods receipt {receipt_pk} was already processed.')


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

    code = 'NO_BATCH_HISTORY'

    def __init__(self, variant, message=None):
        self.variant_id = getattr(variant, 'pk', variant)
        super().__init__(
            message
            or f'Variant {variant} has no batch history: stock it with a goods '
               'receipt before correcting its quantity upwards.')


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

    code = 'BARCODE_TAKEN'


class BarcodeInvalid(CatalogWriteRefused):
    """A code that is not scannable (decision 12).

    Either it cannot be read as typed - not printable ASCII without spaces, or longer
    than 100 characters - or it is an all-digit 8/12/13-character manufacturer code whose
    GS1 mod-10 check digit does not match, i.e. a keying typo. Storing it would make the
    unit look scannable while no scanner can ever find it.
    """

    code = 'BARCODE_INVALID'


class BarcodeReservedPrefix(CatalogWriteRefused):
    """A hand-typed internal `QB…` code (decision 12).

    `QB` codes are generated from the selling unit's id, so a typed one is either a
    mistake or a code a future unit is going to be given - and then two units would hold
    it. Only a unit's OWN derived code is accepted, which makes a PATCH of a generated
    code a no-op instead of a refusal.
    """

    code = 'BARCODE_RESERVED_PREFIX'
