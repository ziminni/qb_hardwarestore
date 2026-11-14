# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/tests.py, apps/inventory/views.py and
# seed_demo.py: the checker runs with a working directory outside the repo, so it
# resolves no config, and `Model.objects` is a false positive on valid Django.
# `transaction.atomic()` and relative imports are flagged for the same class of
# reason and are settled by the test run, which is the authority.
#
# `reportGeneralTypeIssues` is named explicitly because `with transaction.atomic():`
# reads as a function instead of a context manager without django-stubs - the exact
# false positive this comment has described since the file was written.

"""POS services — checkout, FIFO allocation, receipt generation."""

import hashlib
import json
import uuid
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from django.core import signing
from django.db import transaction
from django.utils import timezone

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import StockTransfer, SupplierCreditNote
from apps.inventory.services import (
    allocate_fifo,
    check_low_stock_after_stock_out,
    lock_selling_unit_lines,
)
from common.exceptions import (
    refuse_fractional_whole_unit,
    refuse_inactive_selling_unit,
)

from .exceptions import (
    CreditLimitExceeded,
    DeliveryReasonRequired,
    DeliveryTransitionInvalid,
    DiscountApprovalInvalid,
    DiscountOverCap,
    DiscountReasonRequired,
    IdempotencyKeyReused,
    InvalidDelivery,
    InvalidDiscount,
    InvalidIdempotencyKey,
    InvalidSale,
    SalesOrderCancelBlocked,
    SalesOrderDeliveryNotAccepted,
    SalesOrderFulfilRefused,
    SalesOrderTransitionInvalid,
    WalkInCannotOwe,
)
from .models import (
    Customer,
    Delivery,
    DiscountApproval,
    DocumentCounter,
    OfficialReceipt,
    Payment,
    SalesItem,
    SalesOrder,
    SalesTransaction,
    StoreSettings,
)

# Decision 08: a ledger in one of these states is credit still in use. PAID is not -
# summing settled rows too would count history instead of debt, and the customer's
# available headroom would ratchet down forever with every past sale.
OUTSTANDING_LEDGER_STATUSES = (
    CollectibleLedger.Status.OPEN,
    CollectibleLedger.Status.PARTIAL,
    CollectibleLedger.Status.OVERDUE,
)

# A cart this long is not a cart, it is a mistake (or a probe). One number, checked in
# both directions by `_validated_sale_lines`.
MAX_SALE_LINES = 200

# Decision 05 (Phase 3): a return has to say why. Long enough for a sentence a cashier
# would actually type ("3 bags soaked in the rain, customer brought them back"), short
# enough that the audit trail stays a note and not a document.
MAX_RETURN_REASON_LENGTH = 255

# Decision 09 item 2, and the width of `SalesTransaction.idempotency_key`. A longer key
# would be truncated by the database and stop identifying the attempt it names.
MAX_IDEMPOTENCY_KEY_LENGTH = 64

# Money is two decimal places, and it is rounded HALF_UP exactly ONCE per document
# (decision 18). Every total in this module goes through `money_round` so a sale, its
# receipt and its return cannot disagree by a cent.
CENT = Decimal("0.01")

# Phase 4 task B1 (decision 18): a whole-sale discount is either a peso amount or a
# percentage of the sale. The wire codes are the client's enum, so they are checked here
# rather than trusted.
DISCOUNT_KIND_AMOUNT = "AMOUNT"
DISCOUNT_KIND_PERCENT = "PERCENT"
DISCOUNT_KINDS = (DISCOUNT_KIND_AMOUNT, DISCOUNT_KIND_PERCENT)

# Long enough for the sentence a cashier would actually type, short enough that the
# column (and the audit trail) stays a note. Same rule as MAX_RETURN_REASON_LENGTH.
MAX_DISCOUNT_REASON_LENGTH = 255

# A discount approval is a manager standing at the till, not a standing permission: five
# minutes is long enough to finish the sale in front of them and short enough that a
# forgot token cannot be spent on tomorrow's cart.
# Phase 5 task B3 (decision 18): the delivery state machine, written as DATA so a jump
# that is not in here is impossible rather than merely unhandled. Terminal states
# (DELIVERED, FAILED) are absent on purpose - nothing moves out of them.
DELIVERY_TRANSITIONS = {
    (Delivery.Status.SCHEDULED, "start"): Delivery.Status.OUT_FOR_DELIVERY,
    (Delivery.Status.SCHEDULED, "fail"): Delivery.Status.FAILED,
    (Delivery.Status.OUT_FOR_DELIVERY, "deliver"): Delivery.Status.DELIVERED,
    (Delivery.Status.OUT_FOR_DELIVERY, "fail"): Delivery.Status.FAILED,
}

# Phase 7 B1 (decision 19): the sales-order lifecycle, written as DATA for the same
# reason as the delivery machine - a move that is not listed here cannot happen, so B3's
# cancel and B4's fulfil read this instead of each deciding for themselves. Keyed by the
# status the rules ask about, which is ALWAYS `SalesOrder.effective_status`: the legacy
# PROCESSING/READY rows therefore arrive as CONFIRMED and need no branch here.
# Terminal statuses (COMPLETED, CANCELLED) are absent on purpose.
SALES_ORDER_TRANSITIONS = {
    SalesOrder.Status.CONFIRMED: (
        SalesOrder.Status.PARTIAL,
        SalesOrder.Status.COMPLETED,
        SalesOrder.Status.CANCELLED,
    ),
    SalesOrder.Status.PARTIAL: (SalesOrder.Status.COMPLETED,),
}

# Same reason as MAX_RETURN_REASON_LENGTH: long enough for what actually happened, short
# enough that the column (255) and the audit trail stay a note.
MAX_DELIVERY_REASON_LENGTH = 255
# Phase 7 B3 (decision 19 #4): a sales-order edit or cancel reason goes into the same kind
# of column (`SalesOrder.cancel_reason`, 255), so it gets the same ceiling.
MAX_SALES_ORDER_REASON_LENGTH = 255
# The delivery slip's free-text fields, sized to the columns that hold them.
MAX_DELIVERY_ADDRESS_LENGTH = 255
MAX_DELIVERY_CONTACT_LENGTH = 150
MAX_DELIVERY_PHONE_LENGTH = 50

DISCOUNT_APPROVAL_TTL = timedelta(minutes=5)
# Salt for the signature, so a token minted here cannot be confused with any other
# signed value this app might hand out.
DISCOUNT_APPROVAL_SALT = "pos.discount-approval"

# Which model+field owns each counter prefix. The prefix is the counter's identity, so
# the mapping is the one place that knows a `TRX` row counts `SalesTransaction`s.
COUNTER_SOURCES = {
    "TRX": ("transaction_no", SalesTransaction),
    "OR": ("or_number", OfficialReceipt),
    # Phase 8 B3 (decision 20 #1): a supplier return mints ONE numbered credit note, so
    # the CN counter counts `SupplierCreditNote.number`. Inventory reaches this module
    # lazily (see `payables.create_credit_note_for_return`), so this name is already
    # resolved by the time a return asks for a number.
    "CN": ("number", SupplierCreditNote),
    # Phase 9 B4 (decision 21 §3): the numbered transfer slip. `inventory.transfers`
    # reserves it LAST inside the transfer's own atomic block (plan Design 12 d), so a
    # refused transfer never consumes a number.
    "TR": ("number", StockTransfer),
}


def money_round(value):
    """Two decimal places, `ROUND_HALF_UP`, called ONCE per figure (decision 18).

    Banker's rounding is not what a till does: a total ending in half a centavo rounds
    UP, the way every hand calculator and BIR receipt in the country rounds it. Every
    money figure in this module goes through here exactly once - rounding twice drifts.
    """
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def vat_split(net, *, rate, registered):
    """`(vatable_sales, vat_amount)` for a VAT-INCLUSIVE net (decision 18).

    Shelf prices include VAT, so the tax is taken OUT of the total, never added on top:

        vatable_sales = round(net / (1 + rate/100))
        vat_amount    = net - vatable_sales      (the remainder, so the two always add
                                                  back to the net - no lost centavo)

    A non-VAT store answers `(0, 0)`: it charges no tax, and a rate on a receipt would
    be a claim to the BIR the shop cannot make. Negative `net` (a return) splits the same
    way, so a refund takes its VAT share back out of the reports.
    """
    net = money_round(net)
    if not registered:
        return Decimal("0.00"), Decimal("0.00")
    divisor = 1 + (Decimal(rate) / 100)
    if divisor <= 0:
        # A rate of -100% or below would divide by zero or flip the sign. Only an Admin
        # can set it, and the settings serializer refuses it, so this is a belt.
        return Decimal("0.00"), Decimal("0.00")
    vatable = money_round(net / divisor)
    return vatable, money_round(net - vatable)


def _validated_discount(discount_data, *, gross):
    """Resolve a client's discount to `{kind, value, amount, percent, reason}`, or None.

    Everything a discount CAN be wrong about is refused here, before the sale writes
    anything: an unknown kind, a value that is not a positive finite number, a
    percentage over 100, an amount bigger than the sale itself, a reason that is blank
    or too long. `percent` is the discount's share of the GROSS - the number the Admin's
    cap and a manager's approval are both compared against, whether the cashier typed a
    peso amount or a percentage.

    Money is rounded here (the one place the discount becomes an amount), so the cap
    comparison, the net and the stored `discount_amount` are the same number.
    """
    if discount_data is None or discount_data == "" or discount_data == {}:
        return None
    if not isinstance(discount_data, dict):
        raise InvalidDiscount("discount must be an object with kind, value and reason.")

    kind = str(discount_data.get("kind") or "").strip().upper()
    if kind not in DISCOUNT_KINDS:
        raise InvalidDiscount("discount kind must be AMOUNT or PERCENT.")
    try:
        value = Decimal(str(discount_data.get("value")))
    except (InvalidOperation, TypeError, ValueError):
        raise InvalidDiscount("discount value must be a number.") from None
    if not value.is_finite() or value < 0:
        raise InvalidDiscount("discount value must be zero or more.")

    if kind == DISCOUNT_KIND_PERCENT:
        if value > 100:
            raise InvalidDiscount("A discount cannot be more than 100 percent.")
        amount = money_round(gross * value / 100)
    else:
        amount = money_round(value)

    if amount > gross:
        raise InvalidDiscount(
            f"A discount of {amount:.2f} is more than the sale total of "
            f"{gross:.2f}. Lower the discount, or lower the prices on the cart."
        )

    raw_reason = discount_data.get("reason")
    reason = raw_reason.strip() if isinstance(raw_reason, str) else ""
    if amount > 0 and not reason:
        raise DiscountReasonRequired(
            "A discount needs a reason. Write why the discount is being given."
        )
    if len(reason) > MAX_DISCOUNT_REASON_LENGTH:
        raise InvalidDiscount(
            f"discount reason must be at most {MAX_DISCOUNT_REASON_LENGTH} characters."
        )

    # Unrounded on purpose: comparing a rounded percent against the cap would let
    # 10.004% through a 10.00% cap, and comparing the rounded amount would do the same
    # for a peso discount. `gross` is positive here (a sale always has priced lines).
    percent = (amount / gross * 100) if gross > 0 else Decimal(0)
    return {
        "kind": kind,
        "value": value,
        "amount": amount,
        "percent": percent,
        "reason": reason,
    }


def issue_discount_approval(*, approver, percent, reason=""):
    """Record one approval row and its signed, one-time token (decision 18).

    The token is a `django.core.signing` signature over this row's `token_id`, the
    approver's id and the percent - so it cannot be edited into a bigger discount, and
    `loads(..., max_age=...)` refuses it once its five minutes are up. The ROW is what
    makes it one-time: `_consume_approval` locks it and the sale that spends it stamps
    `used_at`, so a replayed token is refused rather than discounting a second sale.
    """
    percent = money_round(percent)
    row = DiscountApproval.objects.create(
        token_id=uuid.uuid4(),
        approver=approver,
        percent=percent,
        reason=reason,
        expires_at=timezone.now() + DISCOUNT_APPROVAL_TTL,
    )
    token = signing.dumps(
        {"tid": str(row.token_id), "pct": f"{percent:.2f}", "uid": approver.pk},
        salt=DISCOUNT_APPROVAL_SALT,
    )
    return row, token


def _consume_approval(token, *, percent_needed):
    """The approval ROW behind `token`, locked and verified, or `DiscountApprovalInvalid`.

    Called INSIDE the sale's atomic block and before its first write, so a refused token
    leaves nothing behind and the row lock is what makes two concurrent sales holding the
    same token serialize: the loser sees `used_at` set and is refused. Every failure -
    missing, forged, expired, spent, minted for a smaller discount, or a row whose
    percent no longer matches the signed payload - answers the same code, because the
    cashier's next step is the same in every case: ask the manager to approve again.
    """
    if not token:
        raise DiscountApprovalInvalid(
            "This discount needs a Store Manager or Admin to approve it. Ask them for "
            "their username and password."
        )
    if not isinstance(token, str):
        raise DiscountApprovalInvalid("That discount approval is not valid.")
    try:
        payload = signing.loads(
            token,
            salt=DISCOUNT_APPROVAL_SALT,
            max_age=int(DISCOUNT_APPROVAL_TTL.total_seconds()),
        )
    except signing.BadSignature:
        # Covers a forged token, a token signed for something else, and one older than
        # the five-minute window - all of which `loads` reports the same way.
        raise DiscountApprovalInvalid(
            "That discount approval is not valid or has expired. Ask the manager to "
            "approve again."
        ) from None

    row = (
        DiscountApproval.objects.select_for_update()
        .select_related("approver")
        .filter(token_id=payload.get("tid"))
        .first()
    )
    if row is None:
        raise DiscountApprovalInvalid(
            "That discount approval was not issued by this store. Ask the manager to "
            "approve again."
        )
    if row.used_at is not None:
        raise DiscountApprovalInvalid(
            "That discount approval was already used for another sale. Ask the manager "
            "to approve again."
        )
    if row.expires_at <= timezone.now():
        raise DiscountApprovalInvalid(
            "That discount approval has expired. Ask the manager to approve again."
        )
    # The signature binds the payload; the ROW is the server's own record. They must
    # agree, or a value was edited on one side of the fence only.
    if (
        str(payload.get("tid")) != str(row.token_id)
        or payload.get("uid") != row.approver_id
        or payload.get("pct") != f"{row.percent:.2f}"
    ):
        raise DiscountApprovalInvalid(
            "That discount approval is not valid. Ask the manager to approve again."
        )
    if row.percent < percent_needed:
        raise DiscountApprovalInvalid(
            f"That approval covers {row.percent:.2f} percent and this discount is "
            f"{percent_needed:.2f} percent. Ask the manager to approve the larger "
            "discount."
        )
    return row


def guard_order_line_prices(*, lines, discount_approval=None):
    """Refuse - or park - the largest PER-LINE discount a sales order asks for.

    Phase 7 B2 (decision 19 #1 and its follow-up ruling): an order's agreed line price
    may sit below the catalogue price, and a line below the catalogue IS a discount of
    `(catalogue - agreed) / catalogue`. The catalogue price is the selling unit's own
    `default_selling_price`, and the LARGEST line percent decides - no whole-order
    averaging, so one deeply discounted line cannot hide behind nine full-price ones.

    Above the Admin's cap the rule is the till's, unchanged: no token at all is
    `DISCOUNT_OVER_CAP` (carrying the cap and the requested percent so the client opens
    the approval dialog already knowing what it is asking for), a token that is forged,
    expired, spent or too small is `DISCOUNT_APPROVAL_INVALID`. A price ABOVE the
    catalogue is a markup, not a discount, and needs nothing.

    `lines` is `((VariantUOM, agreed_unit_price), ...)` - the shape both the order create
    and the B3 edit already hold. Returns the approved `DiscountApproval` row (LOCKED but
    not yet spent: the caller stamps `used_at` and `sales_order` in its own transaction,
    so a save that fails later returns the manager's token unused) or None when every
    line is within the cap.

    Called from inside the saving transaction and before its first write, so a refusal
    leaves no order, no lines, no audit row and no spent approval.
    """
    cap_percent = StoreSettings.load().discount_cap_percent
    largest = Decimal(0)
    for unit, agreed_price in lines:
        catalogue = Decimal(unit.default_selling_price)
        agreed = Decimal(agreed_price)
        # `catalogue <= 0` would divide by zero, and a free catalogue row has no share to
        # discount; a price at or above the catalogue is not a discount at all.
        if catalogue <= 0 or agreed >= catalogue:
            continue
        percent = money_round((catalogue - agreed) / catalogue * 100)
        largest = max(largest, percent)

    if largest <= cap_percent:
        return None
    if not discount_approval:
        raise DiscountOverCap(cap_percent, largest)
    return _consume_approval(discount_approval, percent_needed=largest)


def highest_existing_sequence(model, field_name, stamp):
    """The highest numeric suffix already used for `stamp`, or 0.

    Public because `common.numbering` seeds its own counters with it too (Phase 6 B4):
    QT/SO/DEL/REQ and TRX/OR must not disagree about what "already used" means.

    Parsed in PYTHON rather than with `ORDER BY field DESC`: the suffix is zero-padded to
    four digits, so a five-digit day (`-10000`) sorts BEFORE `-9999` lexically and the
    counter would be seeded too low - which is exactly the collision this whole change
    exists to prevent. Runs once per (prefix, day): only the row's first creation seeds.
    """
    used = model.objects.filter(**{f"{field_name}__startswith": stamp}).values_list(
        field_name, flat=True
    )
    highest = 0
    for value in used:
        suffix = str(value).rsplit("-", 1)[-1]
        if suffix.isdigit():
            highest = max(highest, int(suffix))
    return highest


def next_number(prefix, day=None):
    """Reserve the next ``<prefix>-YYYYMMDD-NNNN`` for `day` (default: today).

    Decision 09 item 3: the sequence is a `DocumentCounter` row locked with
    `select_for_update`, NOT "read the newest document and add one". Two tills ringing at
    the same instant used to read the same number and the loser died on the unique
    constraint as a 500 - a lost sale, not a slow one.

    The lock is taken inside the CALLER's atomic block (`process_sale`, `process_return`
    and `requisitions.release_materials` all have one), so the reservation commits or
    rolls back with the sale that asked for it. A caller without one gets a block of its
    own here: still collision-free, but a failed sale then leaves a gap rather than
    reusing the number. Gaps are fine; duplicates are not.
    """
    field_name, model = COUNTER_SOURCES[prefix]
    day = day or date.today()
    stamp = f"{prefix}-{day.strftime('%Y%m%d')}-"
    with transaction.atomic():
        counter, _ = DocumentCounter.objects.select_for_update().get_or_create(
            prefix=prefix,
            day=day,
            defaults={
                "last": highest_existing_sequence(model, field_name, stamp),
            },
        )
        counter.last += 1
        counter.save(update_fields=["last"])
    return f"{stamp}{counter.last:04d}"


def generate_transaction_no():
    return next_number("TRX")


def generate_or_number():
    return next_number("OR")


def parse_idempotency_key(raw):
    """Validate the optional `Idempotency-Key` header value (decision 09 item 2).

    No header -> None, and the request is simply not retry-protected (the behaviour
    before this change). An empty or over-long key is refused rather than stored: an
    empty one makes every retry look like the same request, and a truncated one stops
    identifying the attempt it names, so both fail open in the worst possible way.
    """
    if raw is None:
        return None
    if not isinstance(raw, str):
        raise InvalidIdempotencyKey("Idempotency-Key must be a string.")
    key = raw.strip()
    if not key:
        raise InvalidIdempotencyKey("Idempotency-Key must not be empty.")
    if len(key) > MAX_IDEMPOTENCY_KEY_LENGTH:
        raise InvalidIdempotencyKey(
            f"Idempotency-Key must be at most {MAX_IDEMPOTENCY_KEY_LENGTH} characters."
        )
    return key


def request_body_hash(data):
    """Canonical fingerprint of a request body, for "is this the same request?".

    `sort_keys` makes key order irrelevant (JSON objects have none), and `default=str`
    keeps a value the encoder does not know from turning a retry into a 500. Two bodies
    that differ in any value - a 3-piece cart retried as 2 - hash differently, which is
    what lets a replayed key be refused with a 409 instead of silently selling the
    second cart under the first one's receipt.
    """
    canonical = json.dumps(data, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def replayed_transaction(*, cashier, idempotency_key, request_hash):
    """The transaction already recorded for this (cashier, key), or None.

    Returns None when no key was sent or the key is unused, so both call sites read
    "nothing to replay". Raises `IdempotencyKeyReused` when the key belongs to a DIFFERENT
    body: replaying that would hand back a receipt for goods the cashier is not holding.

    Called twice per checkout on purpose - once as the pre-check, and once after an
    `IntegrityError` from the unique constraint, which is how a race between two
    genuinely concurrent retries is settled (`select_for_update` cannot help: the row
    does not exist yet for either of them).
    """
    if not idempotency_key:
        return None
    existing = SalesTransaction.objects.filter(
        cashier=cashier, idempotency_key=idempotency_key
    ).first()
    if existing is None:
        return None
    if existing.request_hash != request_hash:
        raise IdempotencyKeyReused(idempotency_key)
    return existing


def _parse_decimal(raw, *, field, line_no):
    """Parse a client-supplied number, or refuse the sale.

    `Decimal(str(None))` raises ConversionSyntax, `Decimal('NaN')` and
    `Decimal('Infinity')` parse happily and then poison the arithmetic (`min(stock,
    Infinity)` empties the shelf). Both are 400s, not 500s.
    """
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise InvalidSale(f"Line {line_no}: {field} must be a number.") from None
    if not value.is_finite():
        raise InvalidSale(f"Line {line_no}: {field} must be a finite number.")
    return value


def _priced_sale_lines(lines, items_data, order_lines):
    """Pair every validated line with the price it is charged (Phase 7 B4).

    On the till that is the catalogue's `default_selling_price` and no order line, so the
    list is the same `(vuom, qty)` cart read back with the price decision 01 always used.

    On a FULFILMENT (`order_lines` = `{order_line_id: SalesOrderItem}`) each entry of
    `items_data` names the order line it rings and the price comes from THAT row - the
    price the manager agreed, which is why a fulfilment needs no new discount approval.
    A line that names no order line the caller resolved is refused here, before anything
    is written, because a fulfilment line without an order line has no price to charge.

    `items_data` and `lines` are index-aligned: `_validated_sale_lines` builds exactly one
    tuple per item it accepts.
    """
    if order_lines is None:
        return [(vuom, qty, vuom.default_selling_price, None) for vuom, qty in lines]
    priced = []
    for index, ((vuom, qty), raw) in enumerate(zip(lines, items_data), start=1):
        order_line = order_lines.get(raw.get("order_line"))
        if order_line is None:
            raise InvalidSale(f"Line {index}: this fulfilment names no order line.")
        priced.append((vuom, qty, order_line.unit_price, order_line))
    return priced


def _validated_sale_lines(items_data):
    """Resolve and validate every cart line BEFORE anything is written.

    Decision 01: a line names a **VariantUOM** (the selling unit - a box, a metre, a
    bag). There is deliberately no fallback to a `ProductVariant` id any more: that
    ambiguous resolution is what turned a swapped id into a sale of the wrong thing at
    a conversion factor nobody chose. Unknown, inactive or product-inactive all fail
    here, so `allocate_fifo` can never be handed a variant id it cannot price.

    Returns `[(VariantUOM, qty)]`, where `qty` is the SELLING quantity. The caller
    multiplies by `conversion_factor` for the base-unit deduction - one place does the
    conversion, so a sale and its return cannot disagree about what a box is.
    """
    from apps.inventory.models import VariantUOM

    if not isinstance(items_data, (list, tuple)) or not items_data:
        raise InvalidSale("A sale needs at least one item.")
    if len(items_data) > MAX_SALE_LINES:
        raise InvalidSale(f"A sale cannot carry more than {MAX_SALE_LINES} items.")

    lines = []
    for index, item in enumerate(items_data, start=1):
        if not isinstance(item, dict):
            raise InvalidSale(f"Line {index}: each item must be an object.")
        raw_uom_id = item.get("variant_id")
        try:
            vuom = (
                VariantUOM.objects.select_related("variant", "variant__product", "uom")
                .filter(pk=raw_uom_id)
                .first()
            )
        except (TypeError, ValueError):
            vuom = None
        if vuom is None:
            raise InvalidSale(
                f"Line {index}: {raw_uom_id!r} is not a selling unit of any product."
            )
        if not vuom.variant.is_active:
            raise InvalidSale(
                f"Line {index}: {vuom.variant} is no longer available for sale."
            )
        if not vuom.variant.product.is_active:
            raise InvalidSale(
                f"Line {index}: {vuom.variant.product} is no longer available for sale."
            )
        qty = _parse_decimal(item.get("qty"), field="qty", line_no=index)
        if qty <= 0:
            raise InvalidSale(f"Line {index}: qty must be greater than zero.")
        # Phase 1d Task 2 (decision 16): a bag, box or roll is counted in ones only. This
        # ONE check covers every caller of the shared validator - `process_sale`, a held
        # cart's `complete/` (which rings a sale) and `process_return` - so the till, the
        # shelf and a refund can never disagree about what 1.5 bags means.
        refuse_fractional_whole_unit(
            is_whole=vuom.uom.is_whole,
            qty=qty,
            what=f"Line {index} ({vuom.variant}, {vuom.uom.code})",
        )
        lines.append((vuom, qty))
    return lines


def _validated_payments(payments_data):
    """Validate the tender before any write: method known, amount non-negative.

    An EMPTY list stays valid - a cash sale with nothing tendered is the walk-in shortfall
    path, which decision 14 answers with its own 400 (WalkInCannotOwe) or a ledger row for
    a named customer. `amount_tendered` is never trusted to equal the total; it is what the
    cashier took, and the shortfall is computed from the server's price.

    Phase 4 task B2 (decision 18): a CHEQUE carries its number, bank and cheque date, and
    the shop cannot collect on one without them. Checked HERE, with the rest of the tender
    shape, so a refused cheque leaves no sale, no moved stock and no ledger behind.
    """
    if payments_data is None:
        payments_data = []
    if not isinstance(payments_data, (list, tuple)):
        raise InvalidSale("payments must be a list.")
    methods = dict(Payment.Method.choices)
    payments = []
    for index, pdata in enumerate(payments_data, start=1):
        if not isinstance(pdata, dict):
            raise InvalidSale(f"Payment {index}: each payment must be an object.")
        method = pdata.get("method", Payment.Method.CASH)
        if method not in methods:
            raise InvalidSale(
                f"Payment {index}: {method!r} is not a payment method this till takes."
            )
        amount = _parse_decimal(
            pdata.get("amount_tendered", 0), field="amount_tendered", line_no=index
        )
        if amount < 0:
            raise InvalidSale(f"Payment {index}: amount_tendered cannot be negative.")
        tender = {
            "method": method,
            "amount_tendered": amount,
            "reference_no": pdata.get("reference_no") or "",
            # Every tender that is not a cheque is money in hand the moment it is
            # recorded. A cheque starts PENDING and is decided by a manager later.
            "status": Payment.Status.CLEARED,
            "cheque_number": "",
            "bank": "",
            "cheque_date": None,
        }
        if method == Payment.Method.CHEQUE:
            tender.update(_validated_cheque(pdata, line_no=index))
        payments.append(tender)
    return payments


def _validated_cheque(pdata, *, line_no):
    """The three facts a cheque must carry, or a refusal naming the missing ones."""
    from django.utils.dateparse import parse_date

    from .exceptions import ChequeDetailsRequired

    missing = [
        label
        for field, label in (
            ("cheque_number", "cheque number"),
            ("bank", "bank"),
            ("cheque_date", "cheque date"),
        )
        if not str(pdata.get(field) or "").strip()
    ]
    cheque_date = None
    if "cheque date" not in missing:
        cheque_date = parse_date(str(pdata["cheque_date"]).strip())
        if cheque_date is None:
            # A date the server cannot read is the same problem to the cashier as a date
            # that is not there: write it again, in the form the field asks for.
            missing.append("cheque date in YYYY-MM-DD")
    if missing:
        raise ChequeDetailsRequired(missing)
    return {
        "status": Payment.Status.PENDING,
        "cheque_number": str(pdata["cheque_number"]).strip()[:50],
        "bank": str(pdata["bank"]).strip()[:100],
        "cheque_date": cheque_date,
    }


def _outstanding_credit(customer_id):
    """What the customer already owes, as the credit limit counts it (decision 08).

    Only OPEN/PARTIAL/OVERDUE balances_due count - a PAID ledger is settled, so summing
    it would count history instead of debt. Read AFTER the caller has locked the
    customer row, so concurrent credit sales see each other's ledgers rather than both
    reading the same total and both passing the check.
    """
    from django.db.models import Sum

    total = CollectibleLedger.objects.filter(
        customer_id=customer_id, status__in=OUTSTANDING_LEDGER_STATUSES
    ).aggregate(total=Sum("balance_due"))["total"]
    return total or Decimal(0)


def _validated_delivery(data):
    """Resolve the optional `delivery` object on a checkout or an order.

    Decision 18: a delivery is a trip somebody has to MAKE, so the slip is refused until
    it says where (address), who (contact name and phone) and when (scheduled date). The
    fee is money the customer pays, VAT-inclusive and priced from no stock, so it must be
    a non-negative amount of whole centavos - `10.005` is refused rather than rounded,
    because the till would otherwise show a charge the customer never agreed to.

    Returns a dict of ready-to-write field values, or None when no delivery was asked
    for. Called BEFORE the sale's atomic block, so a bad slip leaves no sale, no moved
    stock and no fee behind.
    """
    from django.utils.dateparse import parse_date

    if data is None:
        return None
    if not isinstance(data, dict):
        raise InvalidDelivery("delivery must be an object.")

    def _text(field, label, limit):
        value = data.get(field)
        value = value.strip() if isinstance(value, str) else ""
        if not value:
            raise InvalidDelivery(f"A delivery needs {label}.")
        if len(value) > limit:
            raise InvalidDelivery(f"{label.capitalize()} is too long (max {limit}).")
        return value

    address = _text("address", "an address", MAX_DELIVERY_ADDRESS_LENGTH)
    contact_name = _text("contact_name", "a contact name", MAX_DELIVERY_CONTACT_LENGTH)
    contact_phone = _text("contact_phone", "a contact phone", MAX_DELIVERY_PHONE_LENGTH)

    raw_date = data.get("scheduled_date")
    scheduled_date = parse_date(str(raw_date).strip()) if raw_date else None
    if scheduled_date is None:
        raise InvalidDelivery(
            "A delivery needs a scheduled date in YYYY-MM-DD (the day it goes out)."
        )

    raw_fee = data.get("fee", 0)
    try:
        fee = Decimal(str(raw_fee or 0))
    except (InvalidOperation, TypeError, ValueError):
        raise InvalidDelivery("The delivery charge must be a number.") from None
    if not fee.is_finite():
        raise InvalidDelivery("The delivery charge must be a finite number.")
    if fee < 0:
        raise InvalidDelivery("The delivery charge cannot be negative.")
    if fee != fee.quantize(CENT):
        raise InvalidDelivery(
            "The delivery charge must be in whole centavos (two decimal places)."
        )

    return {
        "address": address,
        "contact_name": contact_name,
        "contact_phone": contact_phone,
        "scheduled_date": scheduled_date,
        "fee": money_round(fee),
    }


def create_delivery(*, data, created_by, sale=None, sales_order=None):
    """Write ONE delivery row for exactly one document (B3, decision 18).

    The exclusive-or is the model's own `CheckConstraint`, so this constructor is simply
    the one place that fills the slip. It is called INSIDE the sale's atomic block (and
    inside the order's), which is what makes "a refused sale leaves no delivery" true
    without a cleanup path.
    """
    fields = _validated_delivery(data)
    if fields is None:
        return None
    return Delivery.objects.create(
        sale=sale, sales_order=sales_order, created_by=created_by, **fields
    )


def transition_delivery(*, delivery_id, action, reason=""):
    """Move ONE delivery forward, or refuse (B3, decision 18).

    The row is locked and RE-READ under the lock, so two role-holders pressing `start`
    together serialize: the loser sees `OUT_FOR_DELIVERY` and is refused with a 409
    instead of writing a second audit row and the same status twice.

    `FAILED` needs its reason stored with it (the trip happened and did not land the
    goods); every other target keeps the field empty, so a row that was never failed
    cannot read as if it was.
    """
    with transaction.atomic():
        delivery = Delivery.objects.select_for_update().get(pk=delivery_id)
        current = delivery.status
        target = DELIVERY_TRANSITIONS.get((current, action))
        if target is None:
            raise DeliveryTransitionInvalid(current, action)
        if target == Delivery.Status.FAILED:
            reason = reason.strip() if isinstance(reason, str) else ""
            if not reason or len(reason) > MAX_DELIVERY_REASON_LENGTH:
                raise DeliveryReasonRequired()
        delivery.status = target
        if target == Delivery.Status.FAILED:
            delivery.failure_reason = reason
        delivery.save(update_fields=["status", "failure_reason", "updated_at"])
    return delivery


def cancel_sales_order(*, order_id, reason, actor):
    """Write off an order the shop is not going to keep (Phase 7 B3, decision 19).

    Two moves, both read from `SALES_ORDER_TRANSITIONS` rather than decided here:

    * **CONFIRMED -> CANCELLED** - nothing was rung, so the whole promise is written off
      and every line's remaining quantity moves into `cancelled_qty`.
    * **PARTIAL -> COMPLETED** - some of it was sold, so the order CLOSES and only the
      remainder is written off. The fulfilled quantity is left exactly as the till wrote
      it: a sale that happened cannot be un-happened (decision 19 #3).

    The order row is LOCKED and re-read first, so a cancel and a fulfilment arriving
    together serialize instead of both believing they were last. Lines, status, the
    delivery and the caller's audit row are one transaction.

    A delivery still SCHEDULED on an unfulfilled order goes FAILED with
    "Order cancelled: <reason>" (delegated default in decision 19): nobody is making that
    trip, and a slip left Scheduled would sit on the dispatch queue for ever. Only a slip
    the driver is HOLDING blocks the cancel - OUT_FOR_DELIVERY or DELIVERED, where the
    goods may still arrive, so the manager must wait for the trip to land (B3 review: a
    slip already FAILED is a closed fact and does not block, nor is it rewritten). On a
    PARTIAL order the slip belongs to the SALE the fulfilment created (B4 re-links it), so
    it is left alone and cannot block closing the remainder.

    Raises `SalesOrderTransitionInvalid` (the order is already over) or
    `SalesOrderCancelBlocked` (the goods are out) before any write, so a refusal changes
    nothing.

    Returns `(order, previous_status)` - the caller names both ends of the move in the
    audit row it writes in this same transaction.
    """
    reason = reason.strip() if isinstance(reason, str) else ""
    with transaction.atomic():
        order = SalesOrder.objects.select_for_update().get(pk=order_id)
        current = order.effective_status
        target = (
            SalesOrder.Status.COMPLETED
            if current == SalesOrder.Status.PARTIAL
            else SalesOrder.Status.CANCELLED
        )
        if target not in SALES_ORDER_TRANSITIONS.get(current, ()):
            raise SalesOrderTransitionInvalid(
                f"Sales order {order.order_no} is {current}: it is already over, so "
                "there is nothing left to cancel.",
                status=current,
            )
        if target == SalesOrder.Status.CANCELLED:
            for delivery in order.deliveries.all():
                # Decision 19 refuses exactly TWO states: the slip the driver is holding.
                # A FAILED trip is over - the order can still be written off, and the
                # slip keeps the reason it already carries.
                if delivery.status in (
                    Delivery.Status.OUT_FOR_DELIVERY,
                    Delivery.Status.DELIVERED,
                ):
                    raise SalesOrderCancelBlocked(
                        f"Delivery {delivery.delivery_no} for {order.order_no} is "
                        f"{delivery.status}: the goods may still arrive, so the order "
                        "cannot be cancelled. Wait for the trip to land first.",
                        delivery_no=delivery.delivery_no,
                        delivery_status=delivery.status,
                    )
                if delivery.status != Delivery.Status.SCHEDULED:
                    continue
                # Reused, not re-implemented: the delivery machine validates the move,
                # stores the reason and keeps its own row lock.
                transition_delivery(
                    delivery_id=delivery.pk,
                    action="fail",
                    reason=f"Order cancelled: {reason}",
                )
        for line in order.items.select_for_update():
            line.cancelled_qty += line.remaining_qty
            line.save(update_fields=["cancelled_qty"])
        order.status = target
        order.cancel_reason = reason
        order.cancelled_by = actor
        order.cancelled_at = timezone.now()
        order.save(
            update_fields=[
                "status",
                "cancel_reason",
                "cancelled_by",
                "cancelled_at",
                "updated_at",
            ]
        )
    return order, current


def order_line_available_qty(lines):
    """`{line pk: sellable quantity}` per order line, in that line's OWN selling unit.

    Phase 7 B5 (decision 19 #2): the order screen shows a live per-line "enough / short"
    hint, so the order read carries `available_qty`. It is a HINT, not a reservation -
    nothing is held, and a short shelf is refused by `process_sale` at fulfilment time,
    never here.

    The arithmetic is not restated: `releasable_qty` (decision 05) already answers "how
    much can leave the store now, in this line's selling unit", whole-unit rounding
    included. It is capped by the line's own remaining quantity, so a client reads the
    shortfall as `remaining_qty - available_qty`. Imported INSIDE the function because
    `apps.requisitions.services` imports this module at import time.

    ONE stock query for every line given, never one query per line. The batch filter is
    the allocator's (`current_qty__gt=0`): an emptied batch is history, not stock.
    """
    from django.db.models import Sum

    from apps.inventory.models import InventoryBatch
    from apps.requisitions.services import releasable_qty

    lines = list(lines)
    if not lines:
        return {}
    on_hand = {
        row["variant_id"]: row["total"]
        for row in InventoryBatch.objects.filter(
            variant_id__in={line.variant_uom.variant_id for line in lines},
            current_qty__gt=0,
        )
        .values("variant_id")
        .annotate(total=Sum("current_qty"))
    }
    return {
        line.pk: releasable_qty(
            remaining=line.remaining_qty,
            available_base=on_hand.get(line.variant_uom.variant_id, Decimal(0)),
            conversion_factor=line.variant_uom.conversion_factor,
            is_whole=line.variant_uom.uom.is_whole,
        )
        for line in lines
    }


def fulfil_sales_order(
    *,
    order_id,
    cashier,
    lines_data,
    payments_data,
    delivery_data=None,
    idempotency_key=None,
    request_hash="",
):
    """Ring a sales order's remaining lines into a real sale (Phase 7 B4, decision 19).

    The order row is LOCKED and re-read first, which is the whole concurrency story: two
    tills fulfilling the same order serialize on that lock, so the second one re-reads the
    quantities the first one wrote and is refused instead of selling the same goods twice.
    The same lock is the one B3's edit and cancel take, so an edit and a fulfilment can
    never both believe they were last. `select_for_update` is taken on the BARE row (no
    `select_related`): Postgres refuses FOR UPDATE on the nullable side of an outer join,
    which is why B3 reads the row again here rather than locking the viewset's queryset.

    Everything else is `process_sale`'s, deliberately UNCHANGED: an open shift, the unit
    locks, FIFO in base units (short stock raises `InsufficientStock` and refuses the WHOLE
    fulfilment - nothing is written, the order stays where it was), the VAT split, the
    split/cheque/utang tender rules, the credit limit and the change arithmetic. This
    function only supplies the two things a fulfilment does differently:

    * the price source - each line is charged its ORDER line's agreed price and records
      `SalesItem.order_line` (decision 19 #1). No sale-level discount is passed: the
      manager's approval was spent when the order was SAVED, and re-taking it here would
      charge the discount twice or demand a second approval nobody owes;
    * the delivery fee - the order's own `Delivery` row is re-linked to the FIRST
      fulfilment sale and its fee lands in that sale's `grand_total`, once.

    Then, in the same transaction, each line's `fulfilled_qty` grows and the order becomes
    PARTIAL or COMPLETED (`SALES_ORDER_TRANSITIONS` still decides whether that move
    exists). The caller writes the audit rows inside the same atomic block.

    Returns the sale. Raises `SalesOrderTransitionInvalid` for an order that is already
    over, `SalesOrderFulfilRefused` for a line that cannot be rung, and
    `SalesOrderDeliveryNotAccepted` for a `delivery` object on the body - all before the
    first write, so a refusal always means "nothing changed".
    """
    with transaction.atomic():
        order = SalesOrder.objects.select_for_update().get(pk=order_id)
        current = order.effective_status
        # Terminal statuses have no entry in the table, so this is the one test that
        # refuses a CANCELLED or COMPLETED order (decision 19: 400, not 500).
        if current not in SALES_ORDER_TRANSITIONS:
            raise SalesOrderTransitionInvalid(
                f"Sales order {order.order_no} is {current}: it is already over, so "
                "nothing can be fulfilled from it.",
                status=current,
            )
        if delivery_data is not None:
            raise SalesOrderDeliveryNotAccepted(
                "A fulfilment carries no delivery of its own: the order's slip already "
                "holds the charge, and the first sale bills it once. Edit the slip on "
                "the order instead.",
            )

        # Locked like B3's cancel does, and AFTER the order row, so the two paths take
        # their locks in the same order.
        order_lines = {line.pk: line for line in order.items.select_for_update().all()}
        chosen = _validated_fulfil_lines(order, order_lines, lines_data)

        # Fee once (delegated default in decision 19): the slip is billed by the first
        # fulfilment and the link to that sale is the record that it was. A slip already
        # carrying a sale - or an order whose lines are already partly rung - means this
        # is a later fulfilment and it carries no fee at all.
        delivery_link = None
        slip = (
            Delivery.objects.select_for_update().filter(sales_order_id=order.pk).first()
        )
        if slip is not None and slip.sale_id is None:
            delivery_link = slip

        items_data = [
            {"variant_id": line.variant_uom_id, "qty": qty, "order_line": line.pk}
            for line, qty in chosen
        ]
        txn = process_sale(
            customer_id=order.customer_id,
            cashier=cashier,
            items_data=items_data,
            payments_data=payments_data,
            idempotency_key=idempotency_key,
            request_hash=request_hash,
            order_lines={line.pk: line for line, _qty in chosen},
            delivery_link=delivery_link,
        )

        for line, qty in chosen:
            line.fulfilled_qty += qty
            line.save(update_fields=["fulfilled_qty"])
        # Read the remaining quantities back from the database, not from the values above:
        # a line the payload did not name may still have been moved by an earlier
        # fulfilment, and "nothing remains" is a question about every line.
        target = (
            SalesOrder.Status.COMPLETED
            if all(line.remaining_qty <= 0 for line in order.items.all())
            else SalesOrder.Status.PARTIAL
        )
        if target != current and target not in SALES_ORDER_TRANSITIONS.get(current, ()):
            raise SalesOrderTransitionInvalid(
                f"Sales order {order.order_no} is {current} and cannot become "
                f"{target}.",
                status=current,
            )
        order.status = target
        order.save(update_fields=["status", "updated_at"])
    return txn


def _validated_fulfil_lines(order, order_lines, lines_data):
    """The payload's lines, resolved against the order's own lines (B4).

    Every refusal here happens before the sale starts, so a bad fulfilment leaves no
    transaction, no moved stock and an unchanged `fulfilled_qty`. Each check is a rule the
    plan names:

    * the line must BELONG to this order (else a cart could ring another order's price);
    * `qty` must be positive and at most ``remaining_qty`` - what is left after everything
      already fulfilled and cancelled;
    * a unit counted in whole numbers takes whole numbers only
      (`refuse_fractional_whole_unit`, reuse not copy);
    * an archived unit is refused (`refuse_inactive_selling_unit`, the Phase 6 B3 helper).
    """
    if not isinstance(lines_data, (list, tuple)) or not lines_data:
        raise SalesOrderFulfilRefused(
            "A fulfilment needs at least one line: name the order line and the qty "
            "being rung."
        )
    chosen = []
    seen = set()
    for index, entry in enumerate(lines_data, start=1):
        if not isinstance(entry, dict):
            raise SalesOrderFulfilRefused(f"Line {index}: each line must be an object.")
        raw_id = entry.get("order_line")
        line = order_lines.get(raw_id)
        if line is None:
            raise SalesOrderFulfilRefused(
                f"Line {index}: {raw_id!r} is not a line of {order.order_no}."
            )
        if line.pk in seen:
            raise SalesOrderFulfilRefused(
                f"Line {index}: order line {line.pk} appears twice. Send each line once."
            )
        seen.add(line.pk)
        qty = _parse_decimal(entry.get("qty"), field="qty", line_no=index)
        if qty <= 0:
            raise SalesOrderFulfilRefused(
                f"Line {index}: qty must be greater than zero."
            )
        remaining = line.remaining_qty
        if qty > remaining:
            raise SalesOrderFulfilRefused(
                f"Line {index}: only {remaining} of {line.variant_uom} is left to "
                f"fulfil, and {qty} was asked for.",
            )
        vuom = line.variant_uom
        refuse_inactive_selling_unit(variant_uom=vuom, what=str(vuom.variant))
        refuse_fractional_whole_unit(
            is_whole=vuom.uom.is_whole,
            qty=qty,
            what=f"Line {index} ({vuom.variant}, {vuom.uom.code})",
        )
        chosen.append((line, qty))
    return chosen


def process_sale(
    *,
    customer_id,
    cashier,
    items_data,
    payments_data,
    source="WALK_IN",
    idempotency_key=None,
    request_hash="",
    discount_data=None,
    discount_approval=None,
    delivery_data=None,
    order_lines=None,
    delivery_link=None,
):
    """Process a complete walk-in sale or requisition release.

    items_data: [{'variant_id': <VariantUOM id>, 'qty': 5}]
    payments_data: [{'method': 'CASH', 'amount_tendered': Decimal('750')}]

    Decision 01 (uom-and-price-authority):

    * the SELLING unit is a `VariantUOM` id, never a bare product-variant id;
    * `unit_price` is `VariantUOM.default_selling_price` - a client-sent `unit_price`
      is ignored, not rejected, so an older client keeps working;
    * FIFO deducts `qty x conversion_factor` BASE units while `SalesItem.qty` keeps the
      selling quantity, so the receipt reads "1 box" and the shelf loses 12 pieces.

    Phase 7 task B4 (decision 19 #1/#3): a sales-order FULFILMENT calls this same
    function, because every checkout guard - open shift, unit locks, FIFO in base units,
    VAT split, split/cheque/utang tender, credit limit, change, OR, low-stock, idempotency
    - has to run unchanged on it. Exactly two inputs differ:

    * `order_lines` is `{order_line_id: SalesOrderItem}`, and each `items_data` entry names
      the order line it rings (`'order_line': <id>`). The line's AGREED price is then
      charged instead of the catalogue price, and `SalesItem.order_line` records where it
      came from. No sale-level discount is taken: the manager's approval was spent when
      the order was saved, so passing `discount_data` here would spend it twice.
    * `delivery_link` is the order's existing `Delivery` row. Its fee is already ON that
      row, so it is charged into THIS sale's `grand_total` (VAT, change and utang all
      measure the money the customer actually owes) and the row is re-linked to the sale
      while keeping its order - this is what bills a delivery exactly once (decision 19:
      the first fulfilment carries it, later ones have no fee at all).

    `InvalidSale` is raised before the atomic block: a refused cart must leave no
    transaction, no receipt, no payment and no moved stock, and raising before the first
    `create()` makes that true by construction rather than by rollback.

    Phase 5 task B3 (decision 18): `delivery_data` is the optional `delivery` object
    (address, contact name/phone, scheduled date, fee). The fee is a "Delivery charge":
    VAT-INCLUSIVE, priced from no stock, and charged ON TOP of the goods net. It is
    deliberately OUTSIDE the discount - `discount_amount` and its cap are computed on the
    goods gross, so a percentage never eats the delivery charge - and it is part of
    `grand_total`, which is what makes VAT, change, the utang shortfall and the cheque
    check all measure the money the customer actually owes. The charge is stored on the
    sale (`delivery_fee`) as well as on the `Delivery` row, because receipts, the
    Z-reading and the return arithmetic read the SALE.

    `idempotency_key` / `request_hash` are the client's retry token and the fingerprint of
    the body that carried it (decision 09 item 2). Stored ON the row at creation, because
    the unique constraint on (cashier, idempotency_key) is what settles two concurrent
    retries - a check-then-insert in the view cannot, since the row does not exist yet for
    either request.
    """
    lines = _validated_sale_lines(items_data)
    # Phase 7 B4: every line now carries the price THIS sale charges and the order line it
    # rings (None/None on the till). Done once, before the atomic block, so the gross - and
    # with it the discount, the VAT, the change and the utang check - is computed from the
    # money the customer actually owes.
    priced_lines = _priced_sale_lines(lines, items_data, order_lines)
    payments = _validated_payments(payments_data)
    # Phase 4 task B2 (decision 18): a cheque is the one tender that is not money yet.
    # Everything below treats it as a CLAIM against the utang it will settle, never as
    # payment: it does not reduce `total_paid`, it must be covered by what the sale still
    # owes, and it is linked to the ledger that debt goes on.
    pending_cheques = [p for p in payments if p["method"] == Payment.Method.CHEQUE]

    # Phase 4 task B1 (decision 18): the gross is pure arithmetic over the lines the
    # server just priced, so a discount can be checked against it BEFORE anything is
    # written. `money_round` once here, which is the number the net and the VAT split
    # are then computed from - rounding again lower down would drift a centavo.
    gross = money_round(
        sum(
            (qty * unit_price for _vuom, qty, unit_price, _line in priced_lines),
            Decimal(0),
        )
    )
    discount_info = _validated_discount(discount_data, gross=gross)
    # Phase 5 task B3: the slip is validated HERE, with the rest of the payload, so a
    # delivery missing its address or carrying a negative charge leaves no sale behind.
    delivery_fields = _validated_delivery(delivery_data)
    # Phase 7 B4: a fulfilment bills the fee already sitting on the ORDER's slip, so the
    # free-text fields are not re-validated - the row was written by `create_delivery`.
    if delivery_fields is not None:
        delivery_fee = delivery_fields["fee"]
    elif delivery_link is not None:
        delivery_fee = money_round(delivery_link.fee)
    else:
        delivery_fee = Decimal(0)

    with transaction.atomic():
        # Decision 06, ruling 2: a sale belongs to a shift, and there is no such thing as
        # a sale outside one - an orphan sale is money the cashier is accountable for that
        # the Z-reading never counts. Looked up INSIDE the atomic block and before the
        # transaction row is written, so a cashier with no open shift leaves nothing behind
        # (the enclosing rollback covers the whole sale).
        from .exceptions import NoOpenShift
        from .models import Shift

        try:
            shift = Shift.objects.get(cashier=cashier, status=Shift.Status.OPEN)
        except Shift.DoesNotExist:
            # `from None`: the DoesNotExist is the EXPECTED miss, not context worth
            # chaining. A client reading the error should see "no open shift", not a
            # traceback about a lookup that did exactly what it was asked to.
            raise NoOpenShift() from None

        # Phase 1d Task 3: `_validated_sale_lines` ran BEFORE this transaction, so a
        # selling unit it accepted can be DELETED between that read and the first line.
        # The removal takes the same row lock, so one of the two waits - and a cart that
        # lost its unit is refused as a 400 `SELLING_UNIT_IN_USE` instead of failing on
        # the foreign key as a 500. Locked before the transaction row is written, so a
        # refusal leaves no sale, receipt, ledger or moved stock behind.
        lock_selling_unit_lines(lines, document="sale")

        if pending_cheques:
            # Decision 14's rule, applied to the tender that CREATES debt: a pending
            # cheque posts to the customer's utang, and the walk-in record is a
            # placeholder nobody owes. Locked like every other read of this customer in
            # this function, so the type cannot change under the check.
            from .exceptions import ChequeNeedsCustomer

            cheque_customer = (
                Customer.objects.select_for_update()
                .only("customer_type", "name")
                .get(pk=customer_id)
            )
            if cheque_customer.customer_type == Customer.Type.WALK_IN:
                raise ChequeNeedsCustomer(cheque_customer.name)

        # Decision 18: the shop's own policy, read under the same block that writes the
        # sale so the rate, the flag and the cap on the receipt are one consistent fact.
        store = StoreSettings.load()
        discount_amount = Decimal(0)
        approval = None
        if discount_info is not None:
            discount_amount = discount_info["amount"]
            if (
                discount_amount > 0
                and discount_info["percent"] > store.discount_cap_percent
            ):
                # Above the Admin's cap. NO token at all gets `DISCOUNT_OVER_CAP`, which is
                # the code the till acts on by opening the approval dialog; a token that is
                # present but unusable gets `DISCOUNT_APPROVAL_INVALID`, which tells the
                # cashier to ask the manager again. `_consume_approval` locks the approval
                # row, refuses a token that is forged, expired, spent or too small, and the
                # row is spent by THIS sale - so a replayed token discounts nothing.
                if not discount_approval:
                    raise DiscountOverCap(
                        store.discount_cap_percent, discount_info["percent"]
                    )
                approval = _consume_approval(
                    discount_approval, percent_needed=discount_info["percent"]
                )

        txn = SalesTransaction.objects.create(
            customer_id=customer_id,
            cashier=cashier,
            shift=shift,
            transaction_no=generate_transaction_no(),
            source=source,
            vat_registered=store.vat_registered,
            vat_rate=store.vat_rate,
            vatable_sales=0,
            vat_amount=0,
            discount_amount=discount_amount,
            discount_reason=("" if discount_info is None else discount_info["reason"]),
            grand_total=0,
            idempotency_key=idempotency_key,
            request_hash=request_hash,
        )

        # Task 4.3: the variants that lose stock in THIS sale, collected so the
        # low-stock check runs once per variant after the lines are deducted, not once
        # per line.
        affected_variant_ids = set()

        for vuom, qty, unit_price, order_line in priced_lines:
            # Decision 01: the server prices the line - from the catalogue, or (Phase 7 B4)
            # from the order line's agreed price. `item.get('unit_price')` is never read
            # again: a forged or stale price is not an error, it is simply not input.
            subtotal = qty * unit_price

            item_row = SalesItem.objects.create(
                transaction=txn,
                variant_uom=vuom,
                qty=qty,
                unit_price=unit_price,
                subtotal=subtotal,
                order_line=order_line,
            )

            # Decision 01: FIFO works in BASE units. Selling 1 box of 12 must remove 12
            # pieces from the shelf while `SalesItem.qty` above keeps the 1 for the
            # receipt - the two numbers answer different questions.
            base_qty = qty * vuom.conversion_factor
            # Raises InsufficientStock on short stock → whole sale rolls back.
            allocations = allocate_fifo(variant_id=vuom.variant_id, qty_needed=base_qty)
            # Task 6A.4: persist which batches this item drew from. Without these
            # rows a linked return cannot know "the original batch it left from".
            from .models import SalesItemDeduction

            SalesItemDeduction.objects.bulk_create(
                [
                    SalesItemDeduction(sales_item=item_row, batch=batch, qty=take)
                    for batch, take in allocations
                ]
            )

            affected_variant_ids.add(vuom.variant_id)
        # Task 4.3: every line has now been deducted, so re-evaluate the low-stock
        # threshold ONCE per affected variant, inside this transaction. A sale taking the
        # shelf below its minimum is the commonest way a shop runs out, and until now the
        # low-stock screen never heard about it; a held-cart completion comes through
        # this same function, so it is covered too. Alerts written here roll back with a
        # sale that fails later (payment, credit limit), so no alert claims a sale that
        # never happened.
        check_low_stock_after_stock_out(variant_ids=affected_variant_ids)

        # Decision 18: shelf prices INCLUDE VAT, so the tax comes out of the net that is
        # actually being paid - gross minus the discount, not the gross the customer was
        # never charged. `gross` was rounded once above, which makes the net exact.
        goods_net = money_round(gross - discount_amount)
        # Phase 5 task B3 (decision 18): the delivery charge joins the total AFTER the
        # discount, so it is never discounted, and the VAT split is taken out of the sum
        # the customer is actually paying - which is what the receipt has to add up to.
        grand_total = money_round(goods_net + delivery_fee)
        vatable_sales, vat_amount = vat_split(
            grand_total, rate=store.vat_rate, registered=store.vat_registered
        )
        txn.vatable_sales = vatable_sales
        txn.vat_amount = vat_amount
        txn.delivery_fee = delivery_fee
        txn.grand_total = grand_total
        txn.save(
            update_fields=[
                "vatable_sales",
                "vat_amount",
                "delivery_fee",
                "grand_total",
            ]
        )

        if delivery_fields is not None:
            # Inside THIS atomic block, so a sale that fails later (change, shortfall,
            # credit limit) takes the delivery with it - a slip for a sale that never
            # happened would schedule a trip nobody ordered.
            txn.delivery = create_delivery(
                data=delivery_data, created_by=cashier, sale=txn
            )
        elif delivery_link is not None:
            # Phase 7 B4: the order's own slip moves to the first fulfilment sale and
            # KEEPS its order (`sales_order` is untouched), which is the record that the
            # charge on it has now been billed - a second fulfilment finds it linked and
            # carries no fee.
            delivery_link.sale = txn
            delivery_link.save(update_fields=["sale", "updated_at"])
            txn.delivery = delivery_link

        # The approval is spent by THIS sale, inside its own transaction: a sale that
        # fails later (short stock, credit limit) rolls the stamp back and the manager's
        # token survives to be used on the cart that eventually goes through.
        if approval is not None:
            approval.used_at = timezone.now()
            approval.transaction = txn
            approval.save(update_fields=["used_at", "transaction"])

        # Payments (already validated above: method known, amount non-negative).
        #
        # Phase 4 task B2: what counts as PAID is money in hand. A pending cheque is money
        # the shop has not received, so it is excluded from `total_paid` - which is what
        # makes the shortfall below the cheques' business, and what keeps a pending cheque
        # out of the drawer count on the Z-reading.
        total_paid = Decimal(0)
        cash_tendered = Decimal(0)
        cheque_rows = []
        for pdata in payments:
            row = Payment.objects.create(
                transaction=txn,
                method=pdata["method"],
                amount_tendered=pdata["amount_tendered"],
                reference_no=pdata["reference_no"],
                status=pdata["status"],
                cheque_number=pdata["cheque_number"],
                bank=pdata["bank"],
                cheque_date=pdata["cheque_date"],
            )
            if pdata["method"] == Payment.Method.CHEQUE:
                cheque_rows.append(row)
            else:
                total_paid += pdata["amount_tendered"]
                if pdata["method"] == Payment.Method.CASH:
                    cash_tendered += pdata["amount_tendered"]

        # OA High (Phase 4 close): change is money OUT of the drawer, so the sale records
        # it instead of leaving the Z-reading to count the whole cash tender as takings.
        # Money in hand is every non-cheque tender (a pending cheque is not money, B2),
        # and anything above the net is change. It must be payable in CASH: the shop
        # cannot hand back money that went to a card or a GCash wallet, so a sale asking
        # for more change than the cash taken is refused and the whole sale rolls back.
        change_given = money_round(max(total_paid - grand_total, Decimal(0)))
        if change_given > cash_tendered:
            from .exceptions import PaymentExceedsTotal

            raise PaymentExceedsTotal(
                change_given=change_given, cash_tendered=cash_tendered
            )
        txn.change_given = change_given
        txn.save(update_fields=["change_given"])

        # Official receipt
        OfficialReceipt.objects.create(
            transaction=txn,
            or_number=generate_or_number(),
            terminal_no="POS-01",
        )

        # Underpaid sale -> post the shortfall to Collectibles (utang).
        #
        # Decision 14: only a NAMED customer may owe. The seeded Walk-in Customer is a
        # placeholder, so a balance against it is money owed by nobody - it inflates
        # receivables, makes the aging report a fiction, and hides the real signal that
        # the till came up short. Raising here rather than validating up front is
        # deliberate: the shortfall is only known after the items are totalled, and the
        # enclosing `transaction.atomic()` rolls the sale back wholesale, so a refused
        # walk-in leaves no transaction, no ledger and no moved stock.
        shortfall = grand_total - total_paid
        if cheque_rows:
            # Change comes from the DRAWER. A cheque may only cover what is still owed;
            # anything above that would mean paying out cash for funds the shop has not
            # received, so it is refused (and the whole sale rolls back with it).
            from .exceptions import ChequeExceedsBalance

            cheque_total = money_round(
                sum((row.amount_tendered for row in cheque_rows), Decimal(0))
            )
            if cheque_total > shortfall:
                raise ChequeExceedsBalance(
                    cheque_total=cheque_total, owed=max(shortfall, Decimal(0))
                )
        if shortfall > 0 and customer_id:
            # Decision 08: lock the customer row BEFORE reading their outstanding
            # balances. Two tills ringing credit sales for the same customer at the
            # same moment would otherwise both read the same outstanding, both pass
            # the check and both write - and the customer ends up over the limit by a
            # whole sale. The lock serializes them; the second one re-reads the first
            # one's ledger. Released by the enclosing atomic block.
            customer = (
                Customer.objects.select_for_update()
                .only("customer_type", "name", "total_credit_limit")
                .get(pk=customer_id)
            )
            if customer.customer_type == Customer.Type.WALK_IN:
                raise WalkInCannotOwe(shortfall, customer.name)
            # Decision 08: NULL limit = unlimited (the legacy rows the data migration
            # converted), 0 = no credit at all. Only a real number is enforced.
            if customer.total_credit_limit is not None:
                outstanding = _outstanding_credit(customer_id)
                if outstanding + shortfall > customer.total_credit_limit:
                    raise CreditLimitExceeded(
                        limit=customer.total_credit_limit,
                        outstanding=outstanding,
                        shortfall=shortfall,
                        customer_name=customer.name,
                    )
            ledger = CollectibleLedger.objects.create(
                customer_id=customer_id,
                transaction=txn,
                original_amount=shortfall,
                balance_due=shortfall,
                due_date=date.today() + timedelta(days=30),
                status=CollectibleLedger.Status.OPEN,
            )
            # A pending cheque now knows WHICH utang it answers for, which is what clear/
            # pays and bounce/ leaves standing. Written here, inside the sale's own atomic
            # block: a sale that fails later takes the link with it.
            for row in cheque_rows:
                row.ledger = ledger
                row.save(update_fields=["ledger"])

    return txn


def decide_cheque(*, cheque_id, decision, decided_by, reason=""):
    """Clear or bounce ONE pending cheque (Phase 4 task B2, decision 18).

    The owner's ruling has three parts and they all live here rather than in the view:

    * CLEARED means the bank honoured it, so the utang it was holding open is paid by
      `apply_payment_to_ledger` - the SAME arithmetic every other payment uses, and the
      reason a cleared cheque writes a `CollectiblePayment` row (`payment_method=CHEQUE`,
      `official_receipt_no` = the cheque number) instead of inventing a second way to
      move a balance;
    * BOUNCED means the money never came, so the ledger is untouched and the customer
      still owes it; the bank's reason is recorded;
    * either way it happens ONCE. The cheque row is locked and re-read under the lock, so
      two managers clicking together cannot both pay the ledger.

    This opens its own atomic block: the cheque stamp, the ledger movement and the
    payment row must commit together or not at all. `cheque_id` is expected to have been
    resolved through the caller's own queryset already (so a bad id is a 404), and is
    re-read under the lock here - that second read is what makes the decision once-only.
    """
    from apps.collectibles.models import CollectiblePayment
    from apps.collectibles.services import apply_payment_to_ledger

    from .exceptions import (
        ChequeAlreadyDecided,
        ChequeError,
        ChequeReasonRequired,
    )

    if decision not in (Payment.Status.CLEARED, Payment.Status.BOUNCED):
        raise ChequeError(f"{decision!r} is not a cheque decision.")
    reason = reason.strip() if isinstance(reason, str) else ""
    if decision == Payment.Status.BOUNCED and not reason:
        raise ChequeReasonRequired()

    with transaction.atomic():
        cheque = Payment.objects.select_for_update().get(pk=cheque_id)
        if cheque.status != Payment.Status.PENDING:
            raise ChequeAlreadyDecided(cheque.status, cheque.cheque_number)

        if decision == Payment.Status.CLEARED:
            if cheque.ledger_id is None:
                # A pending cheque always carries its ledger (process_sale and the utang
                # path both set it), so this is a data fault rather than a client error -
                # answered as one instead of crashing on a NULL lookup.
                raise ChequeError(
                    "This cheque is not linked to an utang, so there is nothing to "
                    "settle. Record the payment against the customer instead."
                )
            ledger = CollectibleLedger.objects.select_for_update().get(
                pk=cheque.ledger_id
            )
            # Raises Overpayment if that debt was already settled another way (a payment
            # taken at the counter today, or a return credit). Refused, not clamped: the
            # difference would be money the books do not hold.
            apply_payment_to_ledger(ledger, cheque.amount_tendered)
            CollectiblePayment.objects.create(
                collectible=ledger,
                processed_by=decided_by,
                amount_paid=cheque.amount_tendered,
                payment_method=Payment.Method.CHEQUE,
                official_receipt_no=cheque.cheque_number,
            )

        cheque.status = decision
        cheque.decided_by = decided_by
        cheque.decided_at = timezone.now()
        cheque.decision_reason = reason
        cheque.save(
            update_fields=["status", "decided_by", "decided_at", "decision_reason"]
        )
    return cheque


def record_cheque_against_ledger(
    *, ledger_id, amount, cheque_number, bank, cheque_date, reference_no=""
):
    """Record a PENDING cheque against an utang that already exists (B2, decision 18).

    The till's cheque and this one are the same object: a `Payment` row with
    `method=CHEQUE`, `status=PENDING` and the ledger it is waiting on, so ONE queue
    (`GET /api/v1/cheques/`) lists every cheque the shop is owed and ONE action
    (`clear/`) turns any of them into money.

    The ledger is NOT touched here. Clearing is what moves a balance, because until the
    bank honours the cheque the customer still owes the shop - and an utang payment
    screen that quietly reduced the balance would be recording money nobody received.

    The caller owns the transaction (the view opens it), and the ledger is locked before
    it is read so two counters cannot each take a cheque for the same last peso.
    """
    from apps.collectibles.services import Overpayment

    amount = money_round(Decimal(amount))
    ledger = CollectibleLedger.objects.select_for_update().get(pk=ledger_id)
    if amount > ledger.balance_due:
        raise Overpayment(ledger.balance_due, amount)
    return Payment.objects.create(
        transaction_id=ledger.transaction_id,
        method=Payment.Method.CHEQUE,
        amount_tendered=amount,
        reference_no=reference_no or "",
        status=Payment.Status.PENDING,
        cheque_number=cheque_number,
        bank=bank,
        cheque_date=cheque_date,
        ledger=ledger,
    )


def _restock_returned(*, variant_id, qty_needed, original_id, return_item):
    """Add returned stock back, per decision 15's two branches.

    Linked (original_id set): back into the batches the original sale drew from,
    oldest-drawn first, capped by cumulative accounting — every linked return writes
    NEGATIVE deduction rows on its own items, so a second call sees what the first
    already gave back and the "more-than-drew" guard fires across calls, across
    partials, and across the lines of one call (same-transaction writes are visible
    to the later lines). Pre-linkage sales left no deduction rows, so those fall
    back to the home-first branch — the only honest answer when history was
    never recorded. Unlinked (Phase 9 B2, decision 21 §9): the newest batch at the
    product's HOME shelf first, then the newest batch with stock elsewhere, and only
    when nothing has stock at all the newest batch overall is reopened. That is the
    allocator's order read backwards: it keeps stocked the shelf the next sale reaches
    for first, instead of topping up a Bodega shelf nobody will walk to.
    Reads are row-locked, matching allocate_fifo's discipline on the way out.
    """
    from django.db.models import F, Sum

    from apps.inventory.models import InventoryBatch

    from .exceptions import ReturnError
    from .models import SalesItemDeduction

    def _newest(*, with_stock: bool, at_home: bool):
        """The newest batch on the shelf this step asks for, or None.

        `-id` breaks a receive-date tie so "the newest" means the latest DELIVERY even
        when two arrived on one day — without it the answer was whatever order the
        database felt like, which is a test that passes today and fails tomorrow.
        """
        batches = InventoryBatch.objects.select_for_update().filter(
            variant_id=variant_id
        )
        if with_stock:
            batches = batches.filter(current_qty__gt=0)
        if at_home:
            # F() rather than a second query: the home shelf is a COLUMN on the product,
            # not a fact this function was handed.
            batches = batches.filter(location_id=F("variant__product__stored_at_id"))
        return batches.order_by("-receipt__receive_date", "-id").first()

    remaining = qty_needed
    if original_id is not None:
        rows = list(
            SalesItemDeduction.objects.select_related("batch")
            .select_for_update()
            .filter(
                sales_item__transaction_id=original_id,
                sales_item__variant_uom__variant_id=variant_id,
                qty__gt=0,
            )
            .order_by("batch__receipt__receive_date")
        )
        if rows:
            touched = []
            planned = []
            for row in rows:
                if remaining <= 0:
                    break
                returned = SalesItemDeduction.objects.filter(
                    sales_item__transaction__original_transaction_id=original_id,
                    batch_id=row.batch_id,
                    qty__lt=0,
                ).aggregate(total=Sum("qty"))["total"] or Decimal(0)
                available = row.qty + returned
                if available <= 0:
                    continue
                add = min(available, remaining)
                row.batch.current_qty += add
                touched.append(row.batch)
                planned.append(
                    SalesItemDeduction(
                        sales_item=return_item, batch=row.batch, qty=-add
                    )
                )
                remaining -= add
            if touched:
                InventoryBatch.objects.bulk_update(touched, ["current_qty"])
                SalesItemDeduction.objects.bulk_create(planned)
            if remaining > 0:
                raise ReturnError("Cannot return more than the original sale drew.")
            return
    newest = (
        _newest(with_stock=True, at_home=True)
        or _newest(with_stock=True, at_home=False)
        or _newest(with_stock=False, at_home=False)
    )
    if newest is None:
        raise ReturnError("No batches exist for this variant.")
    newest.current_qty += remaining
    newest.save(update_fields=["current_qty"])


def _money(value):
    """Render a total as the two-decimal string the API has always used.

    `None` from an empty aggregate becomes '0.00' - a shift with no sales has a zero
    drawer total, not a missing one. Strings, never floats: this is money.
    """
    return f"{value or Decimal(0):.2f}"


def held_cart_count(shift):
    """How many parked carts still belong to this shift's cashier (Phase 3 Task 3).

    A held cart is a sale the cashier parked, not one the shift owns: `HeldCart` has a
    `cashier` FK and no shift FK, because a cart can be resumed on a later shift. So the
    count is per CASHIER, and it is ADVISORY - decision 06 record-and-warn. Refusing the
    close over a parked cart would strand the till open over a sale somebody may settle
    tomorrow, and deleting the carts would destroy a cart the cashier still wants.

    One helper rather than two copies: the shift serializer and the Z-reading both
    publish this number, and a printout that disagrees with the screen is worse than no
    number at all.
    """
    from .models import HeldCart

    return HeldCart.objects.filter(cashier_id=shift.cashier_id).count()


def compute_z_reading(shift):
    """The end-of-shift (Z) summary for one shift, derived - never stored.

    Decision 06 specifies the shape and the arithmetic:

        gross_sales      sum of the shift's COMPLETED transactions' grand_total
        vat, discounts   likewise, summed
        *_sales          payments taken in each method, for SALES only
        cash_refunds     cash paid back on the shift's COMPLETED returns (positive)
        expected_drawer  opening_float + cash_sales - cash_refunds
        variance         closing_count - expected_drawer

    Two deliberate details:

    * Returns are already negative rows (decision 15), so they NET OUT of gross_sales -
      the shift's takings are what it actually took, not the sum of its receipts.
    * `cash_sales` here is money IN (sales only) and `cash_refunds` is money OUT, i.e. the
      two halves the formula names. A single netted cash figure would double-count if it
      were also subtracted; splitting them keeps each number meaningful on the printout
      and leaves the drawer arithmetic identical.
    * Change handed back is money OUT of the same drawer, so `cash_sales` is the cash
      TENDERED less every `change_given` on those sales (QA High, Phase 4 close). A
      till that takes 230.00 for a 225.00 sale and hands 15.00 back has 215.00 more in
      the drawer, not 230.00 - before this subtraction the expected drawer was
      overstated by every centavo of change.

    Recomputed from the same query on every call, so a closed shift's Z-reading is
    idempotent - asking twice can never show two different days.

    Everything comes back as a string: it lands straight in JSON, and a client that gets
    a JSON number for money loses the trailing zero and rounds badly.
    """
    from django.db.models import Count, Sum

    completed = shift.transactions.filter(status=SalesTransaction.Status.COMPLETED)
    sales = completed.exclude(source=SalesTransaction.Source.RETURN)
    returns = completed.filter(source=SalesTransaction.Source.RETURN)

    totals = completed.aggregate(
        transaction_count=Count("id"),
        gross_sales=Sum("grand_total"),
        vat=Sum("vat_amount"),
        discounts=Sum("discount_amount"),
    )

    # One query for every method, then read the four the till knows. A method the client
    # invents later shows up in neither total and the drawer still balances on cash.
    by_method = {
        row["method"]: row["total"] or Decimal(0)
        for row in (
            Payment.objects.filter(transaction__in=sales)
            .values("method")
            .annotate(total=Sum("amount_tendered"))
        )
    }
    cash_refunds = Payment.objects.filter(
        transaction__in=returns, method=Payment.Method.CASH
    ).aggregate(total=Sum("amount_tendered"))["total"] or Decimal(0)
    change_total = sales.aggregate(total=Sum("change_given"))["total"] or Decimal(0)

    cash_sales = by_method.get(Payment.Method.CASH, Decimal(0)) - change_total
    expected_drawer = shift.opening_float + cash_sales - abs(cash_refunds)
    variance = (
        None if shift.closing_count is None else shift.closing_count - expected_drawer
    )

    return {
        "shift_id": shift.id,
        "opening_float": _money(shift.opening_float),
        "closing_count": (
            None if shift.closing_count is None else _money(shift.closing_count)
        ),
        "transaction_count": totals["transaction_count"] or 0,
        "gross_sales": _money(totals["gross_sales"]),
        "vat": _money(totals["vat"]),
        "discounts": _money(totals["discounts"]),
        "cash_sales": _money(cash_sales),
        # QA High (Phase 4 close): shown on its own so the printout explains WHY
        # cash_sales is less than the cash tendered.
        "change_given": _money(change_total),
        "card_sales": _money(by_method.get(Payment.Method.CARD)),
        "gcash_sales": _money(by_method.get(Payment.Method.GCASH)),
        "bank_sales": _money(by_method.get(Payment.Method.BANK_TRANSFER)),
        "cash_refunds": _money(abs(cash_refunds)),
        "expected_drawer": _money(expected_drawer),
        "variance": None if variance is None else _money(variance),
        # Advisory, not a blocker: `close_shift` records the count and closes anyway.
        "held_cart_count": held_cart_count(shift),
    }


def _return_unit_price(*, original, vuom):
    """The refund price for ONE return line (decision 01 + the ledger ruling).

    Linked: the price the line actually sold at, looked up on the original transaction
    by SELLING UNIT. A UOM that was never on that sale cannot be priced from it, so it is
    refused - otherwise "return a box against a bag sale" would refund whatever the box
    happens to be worth today.

    Unlinked: the selling unit's `default_selling_price`, the only honest answer when the
    original receipt is not to hand.

    Either way the client's `unit_price` is never read: a refund the client can price is a
    refund the client can inflate.
    """
    from .exceptions import ReturnError

    if original is None:
        return vuom.default_selling_price
    original_line = (
        SalesItem.objects.filter(transaction=original, variant_uom=vuom)
        .order_by("id")
        .first()
    )
    if original_line is None:
        raise ReturnError(
            f"{vuom} was not on the original sale, so it cannot be refunded against it."
        )
    return original_line.unit_price


def _returned_so_far(original, vuom):
    """(sold, already_returned) for ONE selling unit on `original` (Phase 3, decision 05).

    Read from `SalesItem` rows, NOT from `SalesItemDeduction`: a sale rung before those
    rows existed has none, and the cap that used to rely on them was therefore blind - a
    hand-written request could return 100 bags against a sale of 10.

    Only COMPLETED returns are counted: a voided return gave nothing back, so its
    quantity must be returnable again. `SalesItem.qty` is negative on a return row
    (direction), hence the sign flip.
    """
    from django.db.models import Sum

    def _sum(queryset):
        return queryset.aggregate(total=Sum("qty"))["total"] or Decimal(0)

    sold = _sum(SalesItem.objects.filter(transaction=original, variant_uom=vuom))
    returned = _sum(
        SalesItem.objects.filter(
            transaction__original_transaction=original,
            transaction__source=SalesTransaction.Source.RETURN,
            transaction__status=SalesTransaction.Status.COMPLETED,
            variant_uom=vuom,
        )
    )
    return sold, -returned


def _return_net_share(*, original, returned_gross):
    """What a return actually gives back: its share of what the sale was PAID (B1).

    Decision 18: a discounted sale refunds the NET share, so the shop never hands back
    money it never took.

        refund = returned_gross x (sale net / sale gross)

    Rounded ONCE here, which is what makes three partial returns of one sale add up to
    exactly the sale's net instead of a centavo more. `original.grand_total` IS the net
    (VAT is inclusive, so the gross was never what was charged).

    The cumulative cap is the other half of the same rule: refunds already posted
    against this sale plus this one may never exceed what the sale was paid + still owed.
    A hand-written request that prices a line expensively is clamped here rather than
    refused - the quantity cap is the guard against over-returning, and this one only
    exists so the money can never exceed the sale.

    Unlinked returns are priced from the selling unit itself, with no sale to take a
    share of, so they refund their gross - the pre-B1 behaviour.
    """
    from django.db.models import Sum

    if original is None:
        return returned_gross

    sale_gross = money_round(
        SalesItem.objects.filter(transaction=original).aggregate(total=Sum("subtotal"))[
            "total"
        ]
        or Decimal(0)
    )
    # Phase 5 task B3 (decision 18): the delivery charge is GOODS-SEPARATE, so a return
    # refunds the goods share only. A full return of a delivered sale gives back the
    # goods net and NOT the fee - the trip was still made - and a refund of the fee
    # itself is out of scope for this task. Subtracting it here is what keeps the share
    # and the cumulative cap on the same goods-only basis.
    sale_net = money_round(original.grand_total - original.delivery_fee)
    if sale_gross <= 0 or sale_net <= 0:
        # A fully discounted sale (or a zero-priced one) refunds nothing: the customer
        # paid nothing for the goods coming back.
        return Decimal("0.00")

    share = money_round(returned_gross * sale_net / sale_gross)
    # Negative: every completed return against this sale summed. `room` is what is left
    # of the sale after them.
    already = SalesTransaction.objects.filter(
        original_transaction=original,
        source=SalesTransaction.Source.RETURN,
        status=SalesTransaction.Status.COMPLETED,
    ).aggregate(total=Sum("grand_total"))["total"] or Decimal(0)
    room = money_round(sale_net + already)
    return max(min(share, room), Decimal("0.00"))


def _requested_by_selling_unit(lines):
    """Total requested per `VariantUOM`, keyed by the selling unit itself.

    Two lines of the same selling unit in one request are ONE quantity as far as the cap
    is concerned: checking them separately would let 6 + 6 pass a cap of 10.
    """
    totals = {}
    for vuom, qty in lines:
        totals[vuom] = totals.get(vuom, Decimal(0)) + qty
    return totals


def _settle_return_money(*, txn, original, cashier, payment_method, total):
    """DEBT FIRST, then the drawer (decision 05). Returns the refund summary.

    A return against a credit sale is not cash back - the customer still owes money.
    Reducing the ledger first is what makes the till honest: the sale's utang drops by
    the return value, the ledger history explains the drop as a `RETURN_CREDIT` payment,
    and only the EXCESS leaves the drawer. Without this the shop hands over cash for
    goods the customer never paid for, and the receivable stays on the books forever.

    The ledger is locked before it is read: two returns against the same sale must
    serialize, or both read the same stale balance and one reduction vanishes.

    `apply_payment_to_ledger` owns the arithmetic (balance and status, PAID at zero) so
    there is one rule for "what a payment does to a ledger" rather than a second copy.
    """
    from apps.collectibles.models import CollectiblePayment
    from apps.collectibles.services import apply_payment_to_ledger

    return_value = -total
    ledger = None
    if original is not None:
        ledger = (
            CollectibleLedger.objects.select_for_update()
            .filter(
                transaction=original,
                status__in=OUTSTANDING_LEDGER_STATUSES,
                balance_due__gt=0,
            )
            .order_by("due_date", "id")
            .first()
        )

    debt_reduced = Decimal(0)
    if ledger is not None:
        # A partial return can only settle what is still owed; the rest is cash.
        debt_reduced = min(return_value, ledger.balance_due)
        apply_payment_to_ledger(ledger, debt_reduced)
        CollectiblePayment.objects.create(
            collectible=ledger,
            processed_by=cashier,
            amount_paid=debt_reduced,
            payment_method="RETURN_CREDIT",
            # The RETURN's own number, not an OR: the document for this movement is the
            # return transaction the audit trail already names.
            official_receipt_no=txn.transaction_no,
        )

    cash_refund = return_value - debt_reduced
    if cash_refund > 0:
        # NO Payment row at all when the debt absorbed the whole return: a zero row would
        # put a zero into the Z-reading's cash_refunds and print a refund nobody made.
        Payment.objects.create(
            transaction=txn,
            method=payment_method,
            amount_tendered=-cash_refund,
            reference_no="",
        )

    return {
        "return_value": _money(return_value),
        "debt_reduced": _money(debt_reduced),
        "cash_refund": _money(cash_refund),
        "refund_method": payment_method,
        "ledger_id": None if ledger is None else ledger.id,
        "ledger_balance": None if ledger is None else _money(ledger.balance_due),
    }


def process_return(
    *,
    customer_id,
    cashier,
    items_data,
    original_transaction_id=None,
    payment_method="CASH",
    reason="",
):
    """Post a customer return: a RETURN transaction with negative amounts.

    items_data mirrors process_sale but POSITIVE (what comes back):
    [{'variant_id': <VariantUOM id>, 'qty': 5}].
    Lines store negative qty (direction) at a positive unit price. Validators do not run
    on objects.create(), and no full_clean path creates sale items — see the 6A.4 note.

    Phase 1 task 1 (decision 01, plus the ledger ruling that returns are converted and
    server-priced too):

    * the line names a `VariantUOM`, validated by the same `_validated_sale_lines` the
      sale uses - an unknown or inactive one is `InvalidSale`, before any write;
    * `_restock_returned` is given BASE units (`qty x conversion_factor`) because the
      `SalesItemDeduction` rows it reconciles against are base units. A sale that
      removed 12 pieces for one box must give 12 back, not 1;
    * the refund price is the ORIGINAL sale line's `unit_price` when the return is
      linked (and the UOM must have been on that sale), else the selling unit's
      `default_selling_price`. A client `unit_price` is ignored - a forgeable refund is
      money out of the drawer.

    Phase 3 task 2 (decision 05) added the policy, ALL of it before the first write:

    * an OPEN SHIFT is required, exactly as for a sale. A refund is money out of a
      drawer, and a drawer is a shift: an orphan refund makes the Z-reading's expected
      drawer too high by the amount paid out;
    * a REASON is required - every refund has to explain itself in the audit trail, and
      it is stored in `notes`;
    * a return from a non-manager must be LINKED to its original sale, because the link
      is what prices the line, caps the quantity and finds the utang to settle;
    * the ORIGINAL is row-locked and refused when it is a return, a requisition release,
      or not COMPLETED;
    * the returned qty per selling unit is capped by what the original SOLD;
    * every line refunds its NET share of what the sale was paid (`_return_net_share`),
      so a return of a discounted sale cannot hand the discount back as cash;
    * the money is settled DEBT FIRST (`_settle_return_money`), and the summary of that
      settlement is attached to the returned row as `txn.refund_summary` - a transient
      attribute, NOT a model field, so the 201 body can explain the refund without a
      second table to drift.
    """
    from apps.users.permissions import IsManagerRole, has_role

    from .exceptions import (
        NoOpenShift,
        OriginalNotCompleted,
        ReleaseNotReturnable,
        ReturnError,
        ReturnOfReturn,
        ReturnQtyExceeded,
        ReturnReasonRequired,
        UnlinkedReturnForbidden,
    )
    from .models import Shift

    lines = _validated_sale_lines(items_data)
    if payment_method not in dict(Payment.Method.choices):
        raise ReturnError(f"Unknown payment method: {payment_method}.")
    if payment_method == Payment.Method.CHEQUE:
        # Phase 4 task B2: a refund is money LEAVING the drawer, and the till cannot write
        # a cheque. A customer whose utang is settled by a cheque gets the ledger reduced
        # when a manager clears it (POST /cheques/{id}/clear/), not at the counter.
        raise ReturnError(
            "A refund is paid in cash or another tender the drawer holds, not by "
            "cheque. Choose cash, card, GCash or bank transfer."
        )

    reason = reason.strip() if isinstance(reason, str) else ""

    with transaction.atomic():
        # The gate first, and INSIDE the atomic block so a refusal leaves nothing behind:
        # no RETURN row, no restocked batch, no refund, no audit row.
        try:
            shift = Shift.objects.get(cashier=cashier, status=Shift.Status.OPEN)
        except Shift.DoesNotExist:
            raise NoOpenShift(
                "You have no open shift. Open a shift before posting a return."
            ) from None

        if not reason or len(reason) > MAX_RETURN_REASON_LENGTH:
            raise ReturnReasonRequired(
                "A return needs a reason of 1 to "
                f"{MAX_RETURN_REASON_LENGTH} characters."
            )

        # Phase 1d Task 3: `_validated_sale_lines` ran before this transaction, so the
        # units it accepted are locked here - the same lock the removal takes - before the
        # first write. A refund of a unit the catalogue lost is then a 400, not a
        # foreign-key 500, even for a manager's UNLINKED return against a unit no sale
        # row happens to reference.
        lock_selling_unit_lines(lines, document="return")

        original = None
        if original_transaction_id is not None:
            # Locked for the whole block: two concurrent returns against one sale must
            # serialize, or both pass the quantity cap and the shop refunds twice.
            original = SalesTransaction.objects.select_for_update().get(
                pk=original_transaction_id
            )
            if original.source == SalesTransaction.Source.RETURN:
                raise ReturnOfReturn("A return cannot reverse another return.")
            if original.source == SalesTransaction.Source.REQUISITION:
                raise ReleaseNotReturnable(
                    "A material release is not a sale and cannot be returned at the "
                    "till."
                )
            if original.status != SalesTransaction.Status.COMPLETED:
                raise OriginalNotCompleted("Only a completed sale can be reversed.")
        elif not has_role(cashier, IsManagerRole.required_roles):
            raise UnlinkedReturnForbidden()

        requested = _requested_by_selling_unit(lines)
        if original is not None:
            for vuom, want in requested.items():
                sold, already_returned = _returned_so_far(original, vuom)
                if already_returned + want > sold:
                    raise ReturnQtyExceeded(
                        variant_uom=vuom.id,
                        sold=sold,
                        already_returned=already_returned,
                        requested=want,
                    )

        txn = SalesTransaction.objects.create(
            customer_id=customer_id,
            cashier=cashier,
            shift=shift,
            transaction_no=generate_transaction_no(),
            source=SalesTransaction.Source.RETURN,
            original_transaction=original,
            vat_registered=(original.vat_registered if original is not None else True),
            vatable_sales=0,
            vat_amount=0,
            discount_amount=0,
            grand_total=0,
            notes=reason,
        )
        # Decision 18: price the lines FIRST, because the refund is a share of what the
        # customer actually paid, not of the shelf price. A discounted sale refunds its
        # net share, so a refund can never hand back the discount the shop already gave.
        priced = [
            (vuom, qty, _return_unit_price(original=original, vuom=vuom))
            for vuom, qty in lines
        ]
        returned_gross = money_round(
            sum((qty * unit_price for _, qty, unit_price in priced), Decimal(0))
        )
        refund_net = _return_net_share(original=original, returned_gross=returned_gross)

        for vuom, qty, unit_price in priced:
            item_row = SalesItem.objects.create(
                transaction=txn,
                variant_uom=vuom,
                qty=-qty,
                unit_price=unit_price,
                subtotal=-(qty * unit_price),
            )
            # Ledger ruling, applied: `_restock_returned` reconciles against
            # SalesItemDeduction rows, which are BASE units - so it must be given base
            # units. Handing it the selling qty would give 1 piece back for a 12-piece
            # box and quietly lose eleven.
            _restock_returned(
                variant_id=vuom.variant_id,
                qty_needed=qty * vuom.conversion_factor,
                original_id=original.id if original else None,
                return_item=item_row,
            )

        total = -refund_net
        # The return carries the VAT share BACK OUT of the reports, using the same split
        # the sale used: the ORIGINAL's flag and RATE, both stored on the row, so a
        # settings change between the sale and the refund cannot make the two disagree.
        # An unlinked return has no original to read and uses today's settings (the only
        # rate there is - ENDPOINTS.md says so). A legacy original has no stored rate
        # because pre-Phase-4 sales booked no VAT: its rate reads 0.00 percent, so the
        # refund books no VAT either and the pair still agrees with the receipt.
        store = StoreSettings.load()
        registered = (
            original.vat_registered if original is not None else store.vat_registered
        )
        if original is None:
            rate = store.vat_rate
        else:
            rate = (
                original.vat_rate if original.vat_rate is not None else Decimal("0.00")
            )
        vatable_sales, vat_amount = vat_split(total, rate=rate, registered=registered)
        txn.vat_registered = registered
        txn.vat_rate = rate
        txn.vatable_sales = vatable_sales
        txn.vat_amount = vat_amount
        txn.grand_total = total
        txn.save(
            update_fields=[
                "vat_registered",
                "vat_rate",
                "vatable_sales",
                "vat_amount",
                "grand_total",
            ]
        )

        txn.refund_summary = _settle_return_money(
            txn=txn,
            original=original,
            cashier=cashier,
            payment_method=payment_method,
            total=total,
        )

        OfficialReceipt.objects.create(
            transaction=txn,
            or_number=generate_or_number(),
            terminal_no="POS-01",
        )
    return txn


def returnable_payload(txn):
    """What the till must know before it lets a return through (Phase 3, decision 05).

    Three customers of the same rules, so the arithmetic lives here and not in the view:
    the `returnable/` endpoint, and - through `_returned_so_far` - `process_return`'s
    quantity cap. A screen that said "70 left" while the server refused 70 would be a
    support call, so the numbers come from one place.

    `reason_if_not` is the SAME stable code `process_return` refuses with, or None when
    the original is reversible: the client maps one set of codes, not two.
    """
    from django.db.models import Sum

    reason_if_not = None
    if txn.source == SalesTransaction.Source.RETURN:
        reason_if_not = "RETURN_OF_RETURN"
    elif txn.source == SalesTransaction.Source.REQUISITION:
        reason_if_not = "RELEASE_NOT_RETURNABLE"
    elif txn.status != SalesTransaction.Status.COMPLETED:
        reason_if_not = "ORIGINAL_NOT_COMPLETED"

    # One entry per SELLING UNIT, not per line: a sale may name the same bag twice, and
    # the cap counts them together.
    lines = {}
    rows = (
        SalesItem.objects.filter(transaction=txn)
        .select_related("variant_uom__variant__product", "variant_uom__uom")
        .order_by("id")
    )
    for row in rows:
        vuom = row.variant_uom
        if vuom.pk in lines:
            continue
        sold, returned = _returned_so_far(txn, vuom)
        lines[vuom.pk] = {
            "variant_uom": vuom.pk,
            "name": str(vuom.variant),
            "uom": vuom.uom.code,
            "sold_qty": _money(sold),
            "returned_qty": _money(returned),
            "remaining_qty": _money(max(sold - returned, Decimal(0))),
            "unit_price": _money(row.unit_price),
        }

    open_debt = CollectibleLedger.objects.filter(
        transaction=txn, status__in=OUTSTANDING_LEDGER_STATUSES
    ).aggregate(total=Sum("balance_due"))["total"] or Decimal(0)

    return {
        "transaction_no": txn.transaction_no,
        "customer": txn.customer.name,
        "source": txn.source,
        "returnable": reason_if_not is None,
        "reason_if_not": reason_if_not,
        "lines": list(lines.values()),
        "open_debt": _money(open_debt),
    }
