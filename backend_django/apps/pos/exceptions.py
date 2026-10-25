"""POS API exceptions and the DRF exception handler that publishes them.

Decision 06, section 3: insufficient stock is an *expected* outcome of a sale, not a
crash, and the client needs to tell it apart from the server being broken. Before
this handler existed the failure surfaced as an uncaught `ValueError` -> HTTP 500,
and under `DEBUG=True` as an HTML page the client could not parse at all.
"""

from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from apps.inventory.exceptions import (
    CatalogWriteRefused,
    InsufficientStock,
    NoBatchHistory,
)
from apps.collectibles.services import Overpayment


class ReturnError(ValueError):
    """A return the server refuses to record.

    A ValueError subclass so it reads as a client error, with a stable code the
    client branches on — the same shape as InsufficientStock and WalkInCannotOwe.
    Raised for: return-of-return, more-than-drew (within or across calls), a selling
    unit that was not on the original sale, unknown payment method, voided/non-completed
    original, no batches.

    NOT raised for a bad client `unit_price` any more: since decision 01 the server prices
    the refund from the original sale line, so a client price is ignored rather than
    refused (see `InvalidSale` for the payload shapes that ARE refused).

    `INVALID_RETURN` is the fallback code. Phase 3 (decision 05) gave each REFUSAL its own
    stable code below, because the till has to tell a clerk what to do next: "link the
    original sale" (`UNLINKED_RETURN_FORBIDDEN`, a 403), "you cannot return that much"
    (`RETURN_QTY_EXCEEDED`, with the numbers), "this was a material release"
    (`RELEASE_NOT_RETURNABLE`), "write why" (`RETURN_REASON_REQUIRED`). One catch-all code
    would force the client to match on English prose.
    """

    code = 'INVALID_RETURN'


class ReturnOfReturn(ReturnError):
    """The original is itself a RETURN. Reversing a reversal has no meaning."""

    code = 'RETURN_OF_RETURN'


class OriginalNotCompleted(ReturnError):
    """The original is VOID or REFUNDED - only a COMPLETED sale can be reversed."""

    code = 'ORIGINAL_NOT_COMPLETED'


class ReleaseNotReturnable(ReturnError):
    """The original is a REQUISITION release, which is out of scope for returns.

    A release issues materials against a material token and books a collectible against
    the project; returning it is a requisition workflow (Phase 5+), not a till refund.
    Refused explicitly so the clerk is not told "return the original sale" about a
    document that is not a sale.
    """

    code = 'RELEASE_NOT_RETURNABLE'


class ReturnReasonRequired(ReturnError):
    """A return arrived with no reason (Phase 3, decision 05).

    Every refund leaves the shop with less money or less stock than a receipt says, so
    the audit trail must answer WHY without asking the cashier afterwards. Blank is not a
    reason, and neither is 300 characters pasted from somewhere: `MAX_RETURN_REASON_LENGTH`
    (255) is the contract, and HTTP carries no useful message above it.
    """

    code = 'RETURN_REASON_REQUIRED'


class ReturnQtyExceeded(ReturnError):
    """A line asks for more of a selling unit than the original sale still has (F5).

    The cap is by SELLING UNIT against what was SOLD, not against `SalesItemDeduction`
    rows: a sale rung before those rows existed had no cap at all, so a hand-written
    request could return 100 bags against a sale of 10, restock 100 and refund 100.

    Carries the four numbers so the till can say which line and by how much, instead of
    making the cashier re-count by hand.
    """

    code = 'RETURN_QTY_EXCEEDED'

    def __init__(self, variant_uom, sold, already_returned, requested):
        self.variant_uom = variant_uom
        self.sold = sold
        self.already_returned = already_returned
        self.requested = requested
        super().__init__(
            f'Selling unit {variant_uom} sold {sold} on this sale, '
            f'{already_returned} already returned, and {requested} is being asked for.')


class UnlinkedReturnForbidden(PermissionDenied):
    """A non-manager posted a return with no `original_transaction` (decision 05).

    A cashier returns against the receipt in their hand: the linked original is what
    prices the line, caps the quantity and finds the utang to settle. An unlinked refund
    is a manager's correction (their screen is Phase 5), so a till account cannot ring one.

    403, not 400: the endpoint is theirs to use and the body is well formed - what they
    may not do is refund money with nothing to refund it against. Same `{code, detail}`
    shape as `CreditLimitForbidden`, so the client branches on `code`.
    """

    code = 'UNLINKED_RETURN_FORBIDDEN'
    default_detail = (
        'A cashier must return against the original sale. Ask a Store Manager for an '
        'unlinked return.')


class InvalidSale(ValueError):
    """A sale or return payload the server refuses to record (decision 01).

    Raised BEFORE anything is written, for every shape the checkout endpoint used to
    answer with a 500: an empty cart, a line whose `variant_id` is not a selling unit,
    a qty that is not a positive finite number, an unknown payment method, a negative
    tendered amount.

    A ValueError subclass for the same reason as ReturnError - it reads as a client
    error - with a stable `code` the client branches on, and `detail` for the cashier.
    A forged `unit_price` is deliberately NOT an error: the server ignores it, so an
    older client that still sends one keeps working.
    """

    code = 'INVALID_SALE'


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


class CreditLimitExceeded(Exception):
    """A credit sale that would push the customer past their limit (decision 08).

    The limit is a hard block on the SERVER, not a warning on the client: a client-side
    check is advisory and this one is about money, so a hand-written request would
    otherwise be free to book unlimited utang against a named customer.

    Raised from `process_sale` INSIDE its `transaction.atomic()`, after the shortfall is
    known and with the customer row locked, so the refused sale rolls back wholesale -
    no transaction, no ledger, no moved stock - and two tills cannot both pass the same
    stale outstanding balance.

    Carries the three numbers the till needs to explain the refusal (limit, outstanding,
    shortfall) so the cashier can see how much to collect rather than just "no".
    Deliberately NOT a `ValueError`, for the same reason as `WalkInCannotOwe`: this is a
    business rule, not a failed computation, and no `except ValueError` may swallow it.
    """

    code = 'CREDIT_LIMIT_EXCEEDED'

    def __init__(self, limit, outstanding, shortfall,
                 customer_name='This customer'):
        self.limit = limit
        self.outstanding = outstanding
        self.shortfall = shortfall
        self.customer_name = customer_name
        super().__init__(
            f'{customer_name} is over the credit limit of {limit:.2f}: already owed '
            f'{outstanding:.2f} plus this sale\'s {shortfall:.2f} comes to '
            f'{outstanding + shortfall:.2f}. Collect the difference, or ring the sale '
            'in full.')


class IdempotencyKeyReused(Exception):
    """The same `Idempotency-Key` arrived with a DIFFERENT body (decision 09 item 2).

    A replay is only safe when it is the SAME request: the client retried because it never
    saw the answer. Reusing the key for a different cart is a client bug, and quietly
    ringing the second cart under the first one's receipt would be worse than refusing -
    the cashier would hand over goods the receipt does not describe.

    HTTP 409, not 400: the request is well-formed and the server knows exactly what
    conflicts with what. "Conflict" is precisely this case. Deliberately NOT a
    `ValueError`, so no `except ValueError` call site can mistake it for a sale that was
    merely written wrong.
    """

    code = 'IDEMPOTENCY_KEY_REUSED'

    def __init__(self, idempotency_key=''):
        self.idempotency_key = idempotency_key
        super().__init__(
            f'Idempotency-Key {idempotency_key!r} was already used for a different '
            'request. Use a new key for a new sale.')


class InvalidIdempotencyKey(ValueError):
    """The `Idempotency-Key` header itself is unusable (decision 09 item 2).

    Empty (every retry would then look like the same request) or longer than the 64-char
    column it is stored in (a truncated key silently stops identifying the attempt).
    A ValueError subclass for the same reason as `InvalidSale`: it is a wrongly built
    request, and the client's answer is to generate a proper key and retry.
    """

    code = 'INVALID_IDEMPOTENCY_KEY'


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


class InvalidPaymentMethod(ValueError):
    """A payment method a client may not write (C2, 2026-10-24).

    `Payment.method` and `CollectiblePayment.payment_method` hold the WIRE CODES
    (`CASH`, `CARD`, `GCASH`, `BANK_TRANSFER`); the labels (`'Cash'`) belong to the
    screens. Nothing on the server enforced that for a hand-written request, so a client
    could post a label — which every consumer that branches on the code then misses,
    `compute_z_reading`'s `by_method` among them — or `RETURN_CREDIT`, the marker
    `process_return` writes itself to explain a debt settled by goods coming back. A
    client that can post that can erase a receivable with no money and no goods.

    A `ValueError` subclass, like `InvalidSale`: it is a wrongly built request, and the
    client's answer is to send the code it already has in its tender-method table.
    """

    code = 'INVALID_PAYMENT_METHOD'

    def __init__(self, method=''):
        self.method = method
        super().__init__(
            f'{method!r} is not a payment method this server records. Send one of '
            'CASH, CARD, GCASH or BANK_TRANSFER.')


class CreditLimitForbidden(PermissionDenied):
    """A non-manager tried to set `Customer.total_credit_limit` (Phase 2 Task 2).

    Decision 08 made the credit limit a hard block enforced on the SERVER, so the number
    it is enforced against must not be writable by the person the block is aimed at: a
    cashier who could raise a customer's limit would void the block for their own sale.
    Only a Store Manager or an Admin may set it.

    A `PermissionDenied` subclass, so the refusal is a 403 by DRF's own reasoning - the
    caller may use the endpoint, just not this field - and the handler below gives it
    the project's stable `{code, detail}` shape. Raised BEFORE the serializer touches
    anything, so a refused request writes nothing at all.
    """

    code = 'CREDIT_LIMIT_FORBIDDEN'
    default_detail = (
        'Only a Store Manager or an Admin may change a customer credit limit.')


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
    if isinstance(exc, CatalogWriteRefused):
        # Phase 4 Tasks 1-2: catalog/purchasing refusals (a delete, an unusable selling
        # unit, a purchase order in the wrong state). Raised BEFORE the first write - in
        # a serializer `validate()` or a view action - so the 400 also means "nothing
        # changed". Same `{code, detail}` shape as the till's refusals.
        return Response(
            {'code': exc.code, 'detail': str(exc)},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, NoBatchHistory):
        # A positive stock adjustment for a variant this shop has never received. Raised
        # inside `StockAdjustmentViewSet.perform_create`'s atomic block, so the
        # StockAdjustment row is rolled back with it - the client records the delivery and
        # retries. 400 and the same {code, detail} shape as the other business rules, in
        # place of the silent no-op that used to keep the row.
        return Response(
            {
                'code': NoBatchHistory.code,
                'detail': str(exc),
                'variant_id': exc.variant_id,
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
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
    if isinstance(exc, ReturnQtyExceeded):
        # Quantity refusals carry the four numbers the till needs to correct the line:
        # which selling unit, what was sold, what came back already, what was asked for.
        # 2-decimal strings for the same reason money is: `SalesItem.qty` is a Decimal,
        # and a JSON float loses both the scale and the exactness.
        return Response(
            {
                'code': exc.code,
                'detail': str(exc),
                'variant_uom': exc.variant_uom,
                'sold': f'{exc.sold:.2f}',
                'already_returned': f'{exc.already_returned:.2f}',
                'requested': f'{exc.requested:.2f}',
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
    if isinstance(exc, UnlinkedReturnForbidden):
        # 403 for the same reason as CreditLimitForbidden, and answered HERE rather than
        # by DRF's default handler so the payload keeps the project's {code, detail} shape.
        return Response(
            {
                'code': UnlinkedReturnForbidden.code,
                'detail': str(exc.detail),
            },
            status=status.HTTP_403_FORBIDDEN,
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
    if isinstance(exc, CreditLimitExceeded):
        # Decision 08's payload: the stable `code` the client branches on, a sentence
        # for the cashier, and the three money figures as 2-decimal strings (never
        # floats - a float in a money field is how 0.1 + 0.2 happens at a till).
        return Response(
            {
                'code': CreditLimitExceeded.code,
                'detail': str(exc),
                'limit': f'{exc.limit:.2f}',
                'outstanding': f'{exc.outstanding:.2f}',
                'shortfall': f'{exc.shortfall:.2f}',
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
    if isinstance(exc, IdempotencyKeyReused):
        # 409, and its own branch: a conflict is not a bad request. The client must not
        # retry blindly here - it has to mint a NEW key for what is a different sale.
        return Response(
            {
                'code': IdempotencyKeyReused.code,
                'detail': str(exc),
            },
            status=status.HTTP_409_CONFLICT,
        )
    if isinstance(exc, InvalidIdempotencyKey):
        return Response(
            {
                'code': InvalidIdempotencyKey.code,
                'detail': str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, InvalidSale):
        # The checkout payload itself is wrong (empty cart, unknown selling unit, qty
        # that is not a positive number, bogus payment method). One code for the whole
        # class of them: the client's answer is always "show the detail and let the
        # cashier fix the cart", and `detail` names the offending line.
        return Response(
            {
                'code': InvalidSale.code,
                'detail': str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, InvalidPaymentMethod):
        # The {code, detail} shape the client branches on, for the same reason as
        # InvalidSale: a label is a client bug, not a server fault, and the message
        # names the four codes so the answer is obvious.
        return Response(
            {
                'code': InvalidPaymentMethod.code,
                'detail': str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, CreditLimitForbidden):
        # 403, not 400: the request is well formed and the caller is allowed to use
        # `/customers/` - what they may not do is set this one money field. Same
        # {code, detail} shape as the other refusals so the client branches on `code`.
        return Response(
            {
                'code': CreditLimitForbidden.code,
                'detail': str(exc.detail),
            },
            status=status.HTTP_403_FORBIDDEN,
        )
    return drf_exception_handler(exc, context)
