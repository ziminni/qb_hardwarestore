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
    return drf_exception_handler(exc, context)
    return drf_exception_handler(exc, context)
