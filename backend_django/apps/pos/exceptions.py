"""POS API exceptions and the DRF exception handler that publishes them.

Decision 06, section 3: insufficient stock is an *expected* outcome of a sale, not a
crash, and the client needs to tell it apart from the server being broken. Before
this handler existed the failure surfaced as an uncaught `ValueError` -> HTTP 500,
and under `DEBUG=True` as an HTML page the client could not parse at all.
"""

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from apps.inventory.exceptions import InsufficientStock
from apps.collectibles.services import Overpayment


class ReturnError(ValueError):
    """A return the server refuses to record.

    A ValueError subclass so it reads as a client error, with a stable code the
    client branches on — the same shape as InsufficientStock and WalkInCannotOwe.
    Raised for: return-of-return, more-than-drew (within or across calls), negative
    unit price, unknown payment method, voided/non-completed original, no batches.
    """

    code = 'INVALID_RETURN'


class WalkInCannotOwe(Exception):
    """An anonymous walk-in sale cannot go into utang (decision 14).

    The shared `Walk-in Customer` record is a **placeholder, not a debtor**: a balance on
    it is money owed by nobody, which inflates receivables, makes the aging report report
    a fiction, and hides what actually happened - the till was short. The live database
    already carried 4,900.00 booked this way before the rule existed.

    Deliberately NOT a `ValueError`: unlike `InsufficientStock` there are no `except
    ValueError` call sites depending on it, and this is a business rule about who may owe,
    not a failed computation. The cashier either takes full payment or names a customer.
    """

    code = 'WALK_IN_CANNOT_OWE'

    def __init__(self, shortfall, customer_name='Walk-in Customer'):
        self.shortfall = shortfall
        self.customer_name = customer_name
        super().__init__(
            f'{customer_name} cannot be charged the shortfall of {shortfall}: an '
            'anonymous sale cannot go into utang. Take full payment, or record a '
            'customer for it.')


class NoOpenShift(Exception):
    """A sale was rung by a cashier who has no open shift (decision 06, ruling 2).

    The gate exists so every sale lands inside a Z-reading: an orphan sale is money the
    cashier is accountable for that the close-out never asks about. Raised from
    `process_sale` INSIDE its `transaction.atomic()`, so the refused sale leaves no
    transaction, no moved stock and no receipt behind - the client may keep its cart.

    Deliberately NOT a `ValueError`, for the same reason as `WalkInCannotOwe`: this is a
    workflow precondition, not a failed computation, and no `except ValueError` call site
    should swallow it.
    """

    code = 'NO_OPEN_SHIFT'

    def __init__(self, message=None):
        super().__init__(
            message
            or 'You have no open shift. Open a shift before ringing a sale.')


def handler(exc, context):
    """Return DRF's own response, except for a short-stock sale.

    The payload is the shape decision 06 approved:

        HTTP 400
        {"code": "INSUFFICIENT_STOCK", "detail": "...", "shortfall": "1.00",
         "variant_id": 8}

    `code` is the stable, machine-readable part the client branches on; `detail` is
    for the human; `shortfall` lets the cart say how much to remove; `variant_id`
    lets the cart point AT the offending row.

    `variant_id` was missing at first and its absence was a real gap, not a cosmetic
    one: decision 06 section 3 requires the client to "identify the offending line",
    and `detail` alone only lets it print a sentence. `InsufficientStock` already
    carried the id - `allocate_fifo` raises it with the variant - so the fix is this
    key, not a new exception field.

    Everything else falls through to DRF unchanged, so a genuine server error stays
    a 5xx and a validation error stays a 400 with DRF's field errors.
    """
    if isinstance(exc, InsufficientStock):
        return Response(
            {
                'code': InsufficientStock.code,
                'detail': str(exc),
                'shortfall': None if exc.shortfall is None else str(exc.shortfall),
                'variant_id': exc.variant_id,
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, Overpayment):
        return Response(
            {
                'code': exc.code,
                'detail': str(exc),
                'balance_due': f'{exc.balance_due:.2f}',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, ReturnError):
        return Response(
            {
                'code': exc.code,
                'detail': str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, WalkInCannotOwe):
        # The same shape as a short-stock rejection, and deliberately so: the client
        # branches on a stable `code`, and both are 400s that mean "this sale cannot be
        # recorded as entered" rather than "the server broke".
        return Response(
            {
                'code': WalkInCannotOwe.code,
                'detail': str(exc),
                'shortfall': None
                if exc.shortfall is None
                else str(exc.shortfall),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, NoOpenShift):
        # Same shape as the other two business-rule rejections: a stable `code` the
        # client branches on (open the shift prompt), and `detail` for the human.
        return Response(
            {
                'code': NoOpenShift.code,
                'detail': str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    return drf_exception_handler(exc, context)
    return drf_exception_handler(exc, context)
