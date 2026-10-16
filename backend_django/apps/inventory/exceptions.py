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
