# pyright: reportMissingImports=false
"""POS API exceptions and the DRF exception handler that publishes them.

Decision 06, section 3: insufficient stock is an *expected* outcome of a sale, not a
crash, and the client needs to tell it apart from the server being broken. Before
this handler existed the failure surfaced as an uncaught `ValueError` -> HTTP 500,
and under `DEBUG=True` as an HTML page the client could not parse at all.
"""

from collections.abc import Mapping
from types import MappingProxyType

from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from apps.collectibles.services import Overpayment
from apps.inventory.exceptions import (
    CatalogWriteRefused,
    InsufficientStock,
    NoBatchHistory,
)
from common.exceptions import WholeUnitQuantity


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

    code = "INVALID_RETURN"


class ReturnOfReturn(ReturnError):
    """The original is itself a RETURN. Reversing a reversal has no meaning."""

    code = "RETURN_OF_RETURN"


class OriginalNotCompleted(ReturnError):
    """The original is VOID or REFUNDED - only a COMPLETED sale can be reversed."""

    code = "ORIGINAL_NOT_COMPLETED"


class ReleaseNotReturnable(ReturnError):
    """The original is a REQUISITION release, which is out of scope for returns.

    A release issues materials against a material token and books a collectible against
    the project; returning it is a requisition workflow (Phase 5+), not a till refund.
    Refused explicitly so the clerk is not told "return the original sale" about a
    document that is not a sale.
    """

    code = "RELEASE_NOT_RETURNABLE"


class ReturnReasonRequired(ReturnError):
    """A return arrived with no reason (Phase 3, decision 05).

    Every refund leaves the shop with less money or less stock than a receipt says, so
    the audit trail must answer WHY without asking the cashier afterwards. Blank is not a
    reason, and neither is 300 characters pasted from somewhere: `MAX_RETURN_REASON_LENGTH`
    (255) is the contract, and HTTP carries no useful message above it.
    """

    code = "RETURN_REASON_REQUIRED"


class ReturnQtyExceeded(ReturnError):
    """A line asks for more of a selling unit than the original sale still has (F5).

    The cap is by SELLING UNIT against what was SOLD, not against `SalesItemDeduction`
    rows: a sale rung before those rows existed had no cap at all, so a hand-written
    request could return 100 bags against a sale of 10, restock 100 and refund 100.

    Carries the four numbers so the till can say which line and by how much, instead of
    making the cashier re-count by hand.
    """

    code = "RETURN_QTY_EXCEEDED"

    def __init__(self, variant_uom, sold, already_returned, requested):
        self.variant_uom = variant_uom
        self.sold = sold
        self.already_returned = already_returned
        self.requested = requested
        super().__init__(
            f"Selling unit {variant_uom} sold {sold} on this sale, "
            f"{already_returned} already returned, and {requested} is being asked for."
        )


class UnlinkedReturnForbidden(PermissionDenied):
    """A non-manager posted a return with no `original_transaction` (decision 05).

    A cashier returns against the receipt in their hand: the linked original is what
    prices the line, caps the quantity and finds the utang to settle. An unlinked refund
    is a manager's correction (their screen is Phase 5), so a till account cannot ring one.

    403, not 400: the endpoint is theirs to use and the body is well formed - what they
    may not do is refund money with nothing to refund it against. Same `{code, detail}`
    shape as `CreditLimitForbidden`, so the client branches on `code`.
    """

    code = "UNLINKED_RETURN_FORBIDDEN"
    default_detail = (
        "A cashier must return against the original sale. Ask a Store Manager for an "
        "unlinked return."
    )


class PaymentExceedsTotal(ValueError):
    """Tenders that ask the drawer for change it never took (QA High, Phase 4 close).

    Change is paid out of the CASH drawer. Cash 0.00 + GCash 240.00 on a 225.00 sale
    would ask the drawer for 15.00 of money that went to a wallet, so the sale is
    refused and the cashier is told which amount to lower. Raised before the last write
    of the sale, inside its atomic block, so a refusal leaves nothing behind.
    """

    code = "PAYMENT_EXCEEDS_TOTAL"

    def __init__(self, *, change_given, cash_tendered):
        super().__init__(
            f"Change of {change_given:.2f} is due but only {cash_tendered:.2f} was "
            "taken in cash. Change is paid from the drawer: lower the card or GCash "
            "amount and take the rest in cash."
        )
        self.change_given = change_given
        self.cash_tendered = cash_tendered


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

    code = "INVALID_SALE"


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

    code = "WALK_IN_CANNOT_OWE"

    def __init__(self, shortfall, customer_name="Walk-in Customer"):
        self.shortfall = shortfall
        self.customer_name = customer_name
        super().__init__(
            f"{customer_name} cannot be charged the shortfall of {shortfall}: an "
            "anonymous sale cannot go into utang. Take full payment, or record a "
            "customer for it."
        )


class WalkInCannotOrder(Exception):
    """An order cannot be booked against the walk-in placeholder (B5, decision 19).

    A fulfilment rings the ORDER's customer into an ordinary sale, and decision 14 lets
    only a NAMED customer owe. An order on the placeholder would therefore promise goods
    to nobody - and could one day carry a balance owed by nobody, the same fiction
    `WalkInCannotOwe` refuses at the till. Decision 19 shipped this as a premise
    ("walk-in orders are already impossible"); B5 makes it code at ORDER CREATE, in the
    serializer's `validate`, so a refusal writes nothing.
    """

    code = "WALK_IN_CANNOT_ORDER"

    def __init__(self, customer_name="Walk-in Customer"):
        super().__init__(
            f"An order cannot be booked for {customer_name}: the walk-in record is a "
            "placeholder, not a customer. Name the customer the order is for."
        )


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

    code = "CREDIT_LIMIT_EXCEEDED"

    def __init__(self, limit, outstanding, shortfall, customer_name="This customer"):
        self.limit = limit
        self.outstanding = outstanding
        self.shortfall = shortfall
        self.customer_name = customer_name
        super().__init__(
            f"{customer_name} is over the credit limit of {limit:.2f}: already owed "
            f"{outstanding:.2f} plus this sale's {shortfall:.2f} comes to "
            f"{outstanding + shortfall:.2f}. Collect the difference, or ring the sale "
            "in full."
        )


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

    code = "IDEMPOTENCY_KEY_REUSED"

    def __init__(self, idempotency_key=""):
        self.idempotency_key = idempotency_key
        super().__init__(
            f"Idempotency-Key {idempotency_key!r} was already used for a different "
            "request. Use a new key for a new sale."
        )


class InvalidIdempotencyKey(ValueError):
    """The `Idempotency-Key` header itself is unusable (decision 09 item 2).

    Empty (every retry would then look like the same request) or longer than the 64-char
    column it is stored in (a truncated key silently stops identifying the attempt).
    A ValueError subclass for the same reason as `InvalidSale`: it is a wrongly built
    request, and the client's answer is to generate a proper key and retry.
    """

    code = "INVALID_IDEMPOTENCY_KEY"


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

    code = "NO_OPEN_SHIFT"

    def __init__(self, message=None):
        super().__init__(
            message or "You have no open shift. Open a shift before ringing a sale."
        )


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

    code = "INVALID_PAYMENT_METHOD"

    def __init__(self, method=""):
        self.method = method
        super().__init__(
            f"{method!r} is not a payment method this server records. Send one of "
            "CASH, CARD, GCASH or BANK_TRANSFER."
        )


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

    code = "CREDIT_LIMIT_FORBIDDEN"
    default_detail = (
        "Only a Store Manager or an Admin may change a customer credit limit."
    )


class DiscountError(ValueError):
    """A whole-sale discount the server refuses (Phase 4 task B1, decision 18).

    One base class for the four refusals the till has to tell apart, because they lead
    to four different actions: fix the cart (`INVALID_DISCOUNT`), write why
    (`DISCOUNT_REASON_REQUIRED`), get a manager (`DISCOUNT_OVER_CAP`), or ask the manager
    to approve AGAIN (`DISCOUNT_APPROVAL_INVALID`). A single catch-all code would force
    the client to match on English prose.

    A `ValueError` subclass like `InvalidSale`, and raised from `process_sale` BEFORE the
    first write (or from inside its atomic block, which rolls back wholesale), so a
    refused discount leaves no sale, no receipt, no moved stock and no spent approval.

    `extra` carries the numbers a refusal is only useful WITH - the cap and the
    requested percent - into the `{code, detail}` body the handler publishes.
    """

    code = "INVALID_DISCOUNT"
    # Immutable default, not `{}`: a mutable class attribute is shared by every subclass,
    # so one refusal's figures would leak into the next. Instances that carry numbers
    # assign their own dict (`DiscountOverCap`), which stays compatible with
    # `payload.update(exc.extra)` below.
    extra: Mapping[str, object] = MappingProxyType({})


class InvalidDiscount(DiscountError):
    """The discount itself is unusable: unknown kind, bad value, more than the sale."""

    code = "INVALID_DISCOUNT"


class DiscountReasonRequired(DiscountError):
    """A discount above zero with no reason. Money leaving the shop explains itself."""

    code = "DISCOUNT_REASON_REQUIRED"


class DiscountOverCap(DiscountError):
    """Above the Admin's cap with no approval token (decision 18).

    Carries `cap_percent` and `requested_percent` so the till can open the approval
    dialog already knowing what it is asking a manager to sign off.
    """

    code = "DISCOUNT_OVER_CAP"

    def __init__(self, cap_percent, requested_percent):
        self.cap_percent = cap_percent
        self.requested_percent = requested_percent
        self.extra = {
            "cap_percent": f"{cap_percent:.2f}",
            "requested_percent": f"{requested_percent:.2f}",
        }
        super().__init__(
            f"This discount is {requested_percent:.2f} percent and the limit is "
            f"{cap_percent:.2f}. Ask a Store Manager or Admin to approve it."
        )


class DiscountApprovalInvalid(DiscountError):
    """The approval token is missing, forged, expired, already spent, or too small.

    One code for all of it on purpose: every one of these means the same thing to the
    cashier - ask the manager to approve again - and distinguishing them would tell a
    client which part of the token to try next.
    """

    code = "DISCOUNT_APPROVAL_INVALID"


class ChequeError(ValueError):
    """A cheque the server refuses to record or decide (B2, decision 18).

    Same `{code, detail, **extra}` shape as `DiscountError`, so the till branches on a
    stable code and gets the figures it needs to correct the tender. Raised BEFORE the
    first write on every path, so a refusal means "nothing changed".

    `http_status` is a class attribute because ONE of these is not a bad request: a
    cheque already decided is a CONFLICT (409) - the caller asked for a second decision
    on a fact that is already settled, and retrying will never help.
    """

    code = "INVALID_CHEQUE"
    http_status = status.HTTP_400_BAD_REQUEST
    # Same reason as `DiscountError.extra`: immutable default, per-instance dict override.
    extra: Mapping[str, object] = MappingProxyType({})

    def __init__(self, detail, **extra):
        self.extra = extra
        super().__init__(detail)


class ChequeNeedsCustomer(ChequeError):
    """A cheque against the shared walk-in record (decision 14's rule, one tender on).

    A pending cheque becomes a debt on the customer's utang ledger. A walk-in is a
    placeholder, so that debt would be owed by nobody: the aging report would carry it
    forever and no one could clear or chase it.
    """

    code = "CHEQUE_NEEDS_CUSTOMER"

    def __init__(self, customer_name):
        super().__init__(
            f"A cheque needs a named customer. {customer_name} is a walk-in, so there "
            "is nobody to owe the money until the cheque clears. Pick the customer who "
            "wrote the cheque, or take another payment."
        )


class ChequeDetailsRequired(ChequeError):
    """A cheque with no number, bank or date.

    Those three are what the shop would have to produce at the bank to collect, so a
    cheque without them is not a record of anything - and once it is PENDING the shop
    has recorded money it cannot chase.
    """

    code = "CHEQUE_DETAILS_REQUIRED"

    def __init__(self, missing):
        self.missing = list(missing)
        super().__init__(
            "A cheque needs its "
            f"{self._sentence(self.missing)}. Fill it in and try again.",
            missing=self.missing,
        )

    @staticmethod
    def _sentence(fields):
        if len(fields) == 1:
            return fields[0]
        return f"{', '.join(fields[:-1])} and {fields[-1]}"


class ChequeExceedsBalance(ChequeError):
    """Cheques worth more than the sale still owes.

    Change comes from the DRAWER. Handing back cash for a cheque would be lending money
    against funds the shop has not received, so the tender is refused and the cashier is
    told which number to lower.
    """

    code = "CHEQUE_EXCEEDS_BALANCE"

    def __init__(self, cheque_total, owed):
        super().__init__(
            f"The cheque adds up to {cheque_total:.2f} but only {owed:.2f} is still "
            "owed. Change comes from cash: lower the cheque amount and take the rest in "
            "cash.",
            cheque_total=f"{cheque_total:.2f}",
            owed=f"{owed:.2f}",
        )


class ChequeReasonRequired(ChequeError):
    """A bounced cheque with no reason.

    The debt stays on the customer's ledger, so the trail has to say WHY the bank
    refused it - that sentence is what the next collection call is about.
    """

    code = "CHEQUE_REASON_REQUIRED"

    def __init__(self):
        super().__init__(
            "A bounced cheque needs a reason. Write down why the bank refused it."
        )


class ChequeAlreadyDecided(ChequeError):
    """A second clear or bounce on a cheque that is no longer PENDING.

    409, not 400: the request is well formed and the caller is allowed to decide
    cheques - this one is simply settled already. Clearing twice would pay the ledger
    twice, which is money out of a customer's debt that never came in.
    """

    code = "CHEQUE_ALREADY_DECIDED"
    http_status = status.HTTP_409_CONFLICT

    def __init__(self, current_status, cheque_number):
        label = cheque_number or "This cheque"
        super().__init__(
            f"{label} is already {str(current_status).lower()} and cannot be decided "
            "again.",
            status=current_status,
        )


class DeliveryError(ValueError):
    """A delivery the server refuses to record or move (B3, decision 18).

    Same ``{code, detail, **extra}`` shape as `ChequeError`, so the deliveries page
    branches on a stable code instead of English prose. Raised BEFORE the first write on
    every path, so a refusal always means "nothing changed".

    ``http_status`` is a class attribute because two of these are not bad requests:
    a jump the state machine does not allow, and a second move on a terminal row, are
    CONFLICTS (409) - the request is well formed and the caller is allowed, the fact is
    simply already settled. The client's answer is to reload the row, not to retry.
    """

    code = "INVALID_DELIVERY"
    http_status = status.HTTP_400_BAD_REQUEST
    # Same reason as `ChequeError.extra`: immutable default, per-instance dict override.
    extra: Mapping[str, object] = MappingProxyType({})

    def __init__(self, detail, **extra):
        self.extra = extra
        super().__init__(detail)


class InvalidDelivery(DeliveryError):
    """The `delivery` object on a checkout or an order is unusable.

    Decision 18 lists what a delivery IS - address, contact name/phone, scheduled date and
    a fee - and a slip missing any of them cannot be handed to a driver: there is nowhere
    to go, nobody to call, or no day to go on. The fee is money, so it must be a
    non-negative amount of whole centavos.
    """

    code = "INVALID_DELIVERY"


class DeliveryTransitionInvalid(DeliveryError):
    """A status move the state machine does not allow (jump, or a terminal row).

    ``SCHEDULED -> OUT_FOR_DELIVERY -> DELIVERED``, or ``FAILED`` from either of the two
    live states. Nothing moves backwards and nothing moves out of DELIVERED/FAILED: a
    delivered slip cannot be un-delivered, and letting one be edited would make the
    schedule disagree with what the driver actually did.
    """

    code = "DELIVERY_TRANSITION_INVALID"
    http_status = status.HTTP_409_CONFLICT

    def __init__(self, current_status, action):
        super().__init__(
            f"A delivery that is {str(current_status).lower()} cannot be moved by "
            f"{action!r}: it goes Scheduled -> Out for delivery -> Delivered, or fails "
            "with a reason, and a finished delivery stays finished.",
            status=current_status,
            action=action,
        )


class DeliveryReasonRequired(DeliveryError):
    """A FAILED delivery with no reason.

    The trip was made and the goods did not land. That sentence is what the next attempt
    (and the customer's phone call) is about, so it is required and it is stored.
    """

    code = "DELIVERY_REASON_REQUIRED"

    def __init__(self):
        super().__init__(
            "A failed delivery needs a reason. Write down what went wrong."
        )


class SalesOrderError(ValueError):
    """An order action the server refuses (Phase 7 B3, decision 19 #4).

    Same ``{code, detail, **extra}`` shape as `DeliveryError`, so the order sheet and the
    cancel dialog branch on a stable code instead of English prose. Every raise happens
    BEFORE the first write of its transaction, so a refusal always means "nothing
    changed" - no new line, no moved quantity, no audit row, no spent approval.

    ``http_status`` is a class attribute because these are not all bad requests: an order
    that has moved on (a fulfilment landed, the slip has left) is a CONFLICT, while a
    promise the state machine has already settled is a bad request.
    """

    code = "INVALID_SALES_ORDER"
    http_status = status.HTTP_400_BAD_REQUEST
    # Same reason as `DeliveryError.extra`: immutable default, per-instance override.
    extra: Mapping[str, object] = MappingProxyType({})

    def __init__(self, detail, **extra):
        self.extra = extra
        super().__init__(detail)


class SalesOrderEditRefused(SalesOrderError):
    """The order cannot be edited in the state it is in.

    Decision 19 #4 lets a manager edit a promise the shop has NOT started keeping: while
    the order reads CONFIRMED and nothing has been fulfilled. Once a single unit has been
    rung into a sale - or the order is cancelled or completed - the lines are the record
    of what was promised and cannot be rewritten; cancelling the remainder (B3's
    `cancel/`) is the action left.

    The same refusal covers the delivery slip: its address, contact, date and fee may be
    corrected only while it is still SCHEDULED. A slip the driver already has cannot be
    changed underneath them.
    """

    code = "SALES_ORDER_NOT_EDITABLE"


class SalesOrderTransitionInvalid(SalesOrderError):
    """The order is already over, so the move the caller asked for does not exist.

    COMPLETED and CANCELLED are terminal - `SALES_ORDER_TRANSITIONS` in `services.py` has
    no entry for them - so a second cancel is refused with the code the client branches
    on instead of silently doing nothing.
    """

    code = "SALES_ORDER_TRANSITION_INVALID"


class SalesOrderCancelBlocked(SalesOrderError):
    """The goods are already on their way, so the order cannot be written off (409).

    A CONFLICT rather than a bad request because this one can change: once the trip lands
    the order can be cancelled or fulfilled normally. A delivery that is still SCHEDULED
    is not blocked - cancelling fails it with "Order cancelled: <reason>".
    """

    code = "SALES_ORDER_CANCEL_BLOCKED"
    http_status = status.HTTP_409_CONFLICT


class SalesOrderFulfilRefused(SalesOrderError):
    """The fulfilment payload cannot be rung as it stands (Phase 7 B4, decision 19 #3).

    Four ways to get here, all answered before anything is written: no lines at all, a
    line naming an order line that belongs to a DIFFERENT order, the same order line twice
    (two entries would each pass `qty <= remaining` while together exceeding it), and a
    quantity above what that line still has to give.

    A 400 rather than a 409: the till can fix all four by reading the order back and
    correcting the cart, and `detail` names the line and the figure to change.
    """

    code = "SALES_ORDER_FULFIL_REFUSED"


class SalesOrderDeliveryNotAccepted(SalesOrderError):
    """A fulfilment tried to bring its own delivery slip (Phase 7 B4, decision 19).

    The fee lives on the ORDER's `Delivery` row, written when the order was taken and
    correctable by a manager's edit, and the FIRST fulfilment bills it once. A `delivery`
    object on the fulfilment body is therefore refused on every fulfilment - not only the
    later ones - because accepting it on the first would either duplicate the slip or
    silently drop a charge the cashier typed. The answer names where the fee lives.
    """

    code = "SALES_ORDER_DELIVERY_NOT_ACCEPTED"


class SalesOrderReasonRequired(SalesOrderError):
    """An edit or a cancel with no reason.

    Decision 19 #4 makes both actions reasoned and audited, so the sentence is what the
    trail is for: "customer backed out" is the fact that survives everyone's memory. One
    code for both endpoints (the client's answer is "ask for a reason" either way) and one
    length rule, the `cancel_reason` column's 255.
    """

    code = "SALES_ORDER_REASON_REQUIRED"

    def __init__(self, what="cancelled"):
        super().__init__(
            f"An order cannot be {what} without a reason. Write down why: it goes into "
            "the audit trail."
        )


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
    if isinstance(exc, WholeUnitQuantity):
        # Phase 1d Task 2 (decision 16): a fractional quantity on a unit counted in whole
        # numbers. Raised BEFORE the first write on every path that carries a quantity -
        # sale, return, held cart, quotation, sales order, purchase order, goods receipt,
        # stock adjustment and the CPMS import - so this 400 also means "nothing
        # changed". Its own branch, because `InvalidSale`'s code would tell the client
        # the wrong thing to do about it.
        return Response(
            {"code": exc.code, "detail": str(exc)},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, CatalogWriteRefused):
        # Phase 4 Tasks 1-2: catalog/purchasing refusals (a delete, an unusable selling
        # unit, a purchase order in the wrong state). Raised BEFORE the first write - in
        # a serializer `validate()` or a view action - so the 400 also means "nothing
        # changed". Same `{code, detail}` shape as the till's refusals.
        return Response(
            {"code": exc.code, "detail": str(exc)},
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
                "code": NoBatchHistory.code,
                "detail": str(exc),
                "variant_id": exc.variant_id,
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, InsufficientStock):
        return Response(
            {
                "code": InsufficientStock.code,
                "detail": str(exc),
                "shortfall": None if exc.shortfall is None else str(exc.shortfall),
                "variant_id": exc.variant_id,
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, Overpayment):
        return Response(
            {
                "code": exc.code,
                "detail": str(exc),
                "balance_due": f"{exc.balance_due:.2f}",
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
                "code": exc.code,
                "detail": str(exc),
                "variant_uom": exc.variant_uom,
                "sold": f"{exc.sold:.2f}",
                "already_returned": f"{exc.already_returned:.2f}",
                "requested": f"{exc.requested:.2f}",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, ReturnError):
        return Response(
            {
                "code": exc.code,
                "detail": str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, UnlinkedReturnForbidden):
        # 403 for the same reason as CreditLimitForbidden, and answered HERE rather than
        # by DRF's default handler so the payload keeps the project's {code, detail} shape.
        return Response(
            {
                "code": UnlinkedReturnForbidden.code,
                "detail": str(exc.detail),
            },
            status=status.HTTP_403_FORBIDDEN,
        )
    if isinstance(exc, WalkInCannotOwe):
        # The same shape as a short-stock rejection, and deliberately so: the client
        # branches on a stable `code`, and both are 400s that mean "this sale cannot be
        # recorded as entered" rather than "the server broke".
        return Response(
            {
                "code": WalkInCannotOwe.code,
                "detail": str(exc),
                "shortfall": None if exc.shortfall is None else str(exc.shortfall),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, WalkInCannotOrder):
        # B5: the same shape as `WalkInCannotOwe` - a stable `code` the client branches on
        # and a sentence for the human, 400 because this order cannot be recorded as
        # entered. Raised in the serializer's `validate`, so nothing was written.
        return Response(
            {"code": WalkInCannotOrder.code, "detail": str(exc)},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, CreditLimitExceeded):
        # Decision 08's payload: the stable `code` the client branches on, a sentence
        # for the cashier, and the three money figures as 2-decimal strings (never
        # floats - a float in a money field is how 0.1 + 0.2 happens at a till).
        return Response(
            {
                "code": CreditLimitExceeded.code,
                "detail": str(exc),
                "limit": f"{exc.limit:.2f}",
                "outstanding": f"{exc.outstanding:.2f}",
                "shortfall": f"{exc.shortfall:.2f}",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, NoOpenShift):
        # Same shape as the other two business-rule rejections: a stable `code` the
        # client branches on (open the shift prompt), and `detail` for the human.
        return Response(
            {
                "code": NoOpenShift.code,
                "detail": str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, IdempotencyKeyReused):
        # 409, and its own branch: a conflict is not a bad request. The client must not
        # retry blindly here - it has to mint a NEW key for what is a different sale.
        return Response(
            {
                "code": IdempotencyKeyReused.code,
                "detail": str(exc),
            },
            status=status.HTTP_409_CONFLICT,
        )
    if isinstance(exc, InvalidIdempotencyKey):
        return Response(
            {
                "code": InvalidIdempotencyKey.code,
                "detail": str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, DiscountError):
        # Phase 4 task B1 (decision 18): the discount refusals, in the project's stable
        # {code, detail} shape. Raised before the first write, so the 400 also means
        # "nothing changed" - no sale, no moved stock, no spent approval.
        # `object` values because the extra figures are 2-decimal strings and lists, and
        # `extra` is a Mapping now, not a plain dict.
        payload: dict[str, object] = {"code": exc.code, "detail": str(exc)}
        payload.update(exc.extra)
        return Response(payload, status=status.HTTP_400_BAD_REQUEST)
    if isinstance(exc, DeliveryError):
        # Phase 5 task B3 (decision 18): the delivery refusals. Same {code, detail,
        # **extra} shape and the same "nothing changed" guarantee; the status is the
        # exception's own, because a forbidden jump or a second move on a finished
        # delivery is a CONFLICT (409), not a bad request.
        payload: dict[str, object] = {"code": exc.code, "detail": str(exc)}
        payload.update(exc.extra)
        return Response(payload, status=exc.http_status)
    if isinstance(exc, SalesOrderError):
        # Phase 7 task B3 (decision 19 #4): the order edit/cancel refusals, in the same
        # shape and with the same guarantee. Ordered AFTER `DeliveryError` because the
        # two families are unrelated classes; the status is the exception's own, since
        # an order that has moved on or whose goods have left is a CONFLICT.
        payload: dict[str, object] = {"code": exc.code, "detail": str(exc)}
        payload.update(exc.extra)
        return Response(payload, status=exc.http_status)
    if isinstance(exc, ChequeError):
        # Phase 4 task B2 (decision 18): the cheque refusals. Same shape and the same
        # "nothing changed" guarantee; the status is the exception's own, because
        # `CHEQUE_ALREADY_DECIDED` is a conflict, not a bad request.
        payload: dict[str, object] = {"code": exc.code, "detail": str(exc)}
        payload.update(exc.extra)
        return Response(payload, status=exc.http_status)
    if isinstance(exc, PaymentExceedsTotal):
        # QA High (Phase 4 close): a non-cash tender claiming more change than the cash
        # taken can pay for. Same {code, detail} shape plus the two figures, so the till
        # can name the amount to lower instead of matching on English prose.
        return Response(
            {
                "code": exc.code,
                "detail": str(exc),
                "change_given": f"{exc.change_given:.2f}",
                "cash_tendered": f"{exc.cash_tendered:.2f}",
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
                "code": InvalidSale.code,
                "detail": str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, InvalidPaymentMethod):
        # The {code, detail} shape the client branches on, for the same reason as
        # InvalidSale: a label is a client bug, not a server fault, and the message
        # names the four codes so the answer is obvious.
        return Response(
            {
                "code": InvalidPaymentMethod.code,
                "detail": str(exc),
            },
            status=status.HTTP_400_BAD_REQUEST,
        )
    if isinstance(exc, CreditLimitForbidden):
        # 403, not 400: the request is well formed and the caller is allowed to use
        # `/customers/` - what they may not do is set this one money field. Same
        # {code, detail} shape as the other refusals so the client branches on `code`.
        return Response(
            {
                "code": CreditLimitForbidden.code,
                "detail": str(exc.detail),
            },
            status=status.HTTP_403_FORBIDDEN,
        )
    return drf_exception_handler(exc, context)
