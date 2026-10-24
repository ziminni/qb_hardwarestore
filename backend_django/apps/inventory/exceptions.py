"""Inventory domain exceptions.

Kept separate from `services` so callers and the API layer can both import the type
without importing the service module.
"""


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
