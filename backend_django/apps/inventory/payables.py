# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/inventory/services.py: this checker runs with a
# working directory outside the repo, so it finds neither pyrightconfig.json nor
# django-stubs, and `Model.objects` / `select_for_update()` read as false positives on
# valid Django. `manage.py check` and the test run remain the authority.
"""Supplier payables — the money side of buying (Phase 5 B2, decision 18).

Kept beside `services.py` (which owns STOCK) rather than inside it, because the two
answer different questions about a delivery: `services.process_goods_receipt` moves
quantity into the rack, and this module turns that same delivery into what the shop owes.

The three facts this file owns:

1. **PO money** (`vat_split`, the properties on `PurchaseOrder`): gross from the lines,
   the header's discount subtracted, VAT extracted (inclusive) or added (exclusive) on
   the discounted net, every figure rounded HALF_UP to two decimals exactly once.
2. **The bill a receipt creates** (`create_bill_for_receipt`): the delivered PACKAGE
   quantity × the package cost - never base quantity × cost, which would bill a 4-bag
   delivery of 2.5 kg bags at ten times the price - less that receipt's proportional
   share of the order discount, with the PO's snapshot VAT rate.
3. **Payments** (`record_supplier_payment`): partial allowed, never above the balance,
   taken under the bill's row lock so two clerks cannot both spend the same balance.
4. **Credit notes** (Phase 8 B3, decision 20 #1): `create_credit_note_for_return` prices
   what a supplier return is worth and numbers it, and `apply_credit_to_source_bill`
   spends that credit on the bill the goods came in on - as a real `CREDIT` payment -
   leaving whatever the bill cannot absorb as supplier credit.

Both writers MUST be called inside the caller's `transaction.atomic()` block: the view
wraps the write and its audit row together, and a service that committed on its own would
leave a payment behind after a failed audit row.
"""

from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from django.db.models import Sum

from .exceptions import (
    BillPaid,
    CreditExceedsRemaining,
    CreditNoteSupplierMismatch,
    InvalidSupplierPayment,
    Overpayment,
)
from .models import (
    PurchaseOrder,
    SupplierBill,
    SupplierCreditNote,
    SupplierPayment,
)

CENT = Decimal("0.01")
# The money columns hold `max_digits=12, decimal_places=2`; anything at or above this
# would fail on INSERT with a database error instead of a readable refusal.
MONEY_LIMIT = Decimal(10000000000)


def money(value) -> Decimal:
    """Two decimals, `ROUND_HALF_UP` - the project's one money rounding (decision 18).

    Banker's rounding is not what a shop does with half a centavo: it rounds up, the way
    a hand calculator and a BIR receipt do. Called ONCE per figure; rounding twice drifts.
    """
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def vat_split(net, *, rate, inclusive) -> tuple[Decimal, Decimal]:
    """`(vatable_amount, vat_amount)` for a VAT-able net. Mirrors `pos.services.vat_split`.

    **Inclusive** (shelf/quoted prices already carry the tax):

        vatable = round(net / (1 + rate/100));  vat = net - vatable

    the remainder trick that makes the two always add back to the net, so no centavo is
    invented or lost.

    **Exclusive** (the supplier quotes net of VAT): `vat = round(net x rate/100)`, and
    the caller adds it to the total. `vatable` is then simply the net.

    A rate of 0 is the non-registered shop (and every pre-B2 row): no VAT is claimed.
    """
    net = money(net)
    rate = Decimal(rate or 0)
    if rate <= 0:
        return net, Decimal("0.00")
    if inclusive:
        divisor = 1 + (rate / 100)
        if divisor <= 0:
            # A rate of -100% or below would divide by zero or flip the sign. Only a
            # settings write could get there and it refuses it; this is a belt.
            return net, Decimal("0.00")
        vatable = money(net / divisor)
        return vatable, money(net - vatable)
    return net, money(net * rate / 100)


def discount_share(
    *, header_discount, order_gross, received_gross, allocated_so_far
) -> Decimal:
    """This delivery's proportional slice of the PO header discount.

    `header_discount x received_gross / order_gross`, rounded HALF_UP to the cent, minus
    what earlier bills of the same order already took. Two properties follow from
    dividing the CUMULATIVE received value by the order's own gross and subtracting the
    cumulative allocation:

    * **Exactness.** When the order is fully received the cumulative share is the whole
      discount, so the last bill takes the remainder and the bills sum to the header
      discount to the centavo - no rounding leak (three receipts of 1.00 against a 1.00
      discount on a 3.00 order allocate 0.33 / 0.34 / 0.33).
    * **No negative or oversized share.** A guard for a zero-gross order (nothing was
      ever worth anything, so nothing is discounted), a cap at the header discount when
      the receipts are worth more than the order (over-receipt), and a clamp at the
      slice's own gross for pathological data.
    """
    header_discount = money(header_discount or 0)
    if header_discount <= 0 or order_gross <= 0 or received_gross <= 0:
        return Decimal("0.00")
    cumulative = money(
        Decimal(header_discount) * Decimal(received_gross) / Decimal(order_gross)
    )
    # Phase 6 B2: over-receipt (received_gross above the order gross) would push the
    # cumulative share past the discount the header actually granted.
    cumulative = min(cumulative, header_discount)
    share = cumulative - money(allocated_so_far or 0)
    if share <= 0:
        return Decimal("0.00")
    return min(share, money(received_gross))


def order_gross(po: PurchaseOrder) -> Decimal:
    """The order's own gross (ordered quantity × package cost, summed)."""
    return money(
        sum(
            (item.ordered_qty * item.unit_cost for item in po.items.all()),
            Decimal(0),
        )
    )


def create_bill_for_receipt(*, receipt, delivered):
    """Create the ONE bill a processed receipt stands for, or None when nothing is owed.

    `delivered` is `[(POItem, package_qty), ...]` - the quantity of the LINE'S SELLING
    UNIT this receipt delivered (the same numbers `process_goods_receipt` turns into base
    stock). The value is therefore `package_qty x item.unit_cost`: the price the shop
    agreed to per package.

    **Never base quantity × package cost.** A line of "1 BAG at 250" whose bag is 2.5 kg
    stocks 2.5 base units; multiplying THAT by 250 would claim the shop owes 625 for one
    bag. Stock and money are converted from the same package count, in opposite
    directions.

    A zero-value delivery (free goods, or an order priced at 0) creates NO bill: there is
    nothing to owe, and a 0.00 bill would only add noise to the payables list. The stock
    still moves - the bill is about money, not about the rack.

    Must run inside the caller's transaction (which holds the PO row lock, so two
    receipts of the same order cannot both allocate against the same stale totals).
    """
    po = receipt.po
    gross = money(
        sum((Decimal(qty) * item.unit_cost for item, qty in delivered), Decimal(0))
    )
    if gross <= 0:
        return None

    already = SupplierBill.objects.filter(purchase_order=po).aggregate(
        gross=Sum("gross_amount"), discount=Sum("discount_amount")
    )
    allocated_so_far = already["discount"] or Decimal(0)
    received_gross = (already["gross"] or Decimal(0)) + gross

    discount = discount_share(
        header_discount=po.discount_amount,
        order_gross=order_gross(po),
        received_gross=received_gross,
        allocated_so_far=allocated_so_far,
    )
    net = money(gross - discount)
    _vatable, vat = vat_split(net, rate=po.vat_rate, inclusive=po.vat_inclusive)
    total = net if po.vat_inclusive else money(net + vat)

    supplier = po.supplier
    terms_days = supplier.terms_days or 0
    received_date = receipt.receive_date
    return SupplierBill.objects.create(
        receipt=receipt,
        supplier=supplier,
        purchase_order=po,
        received_date=received_date,
        terms_days=terms_days,
        due_date=received_date + timedelta(days=terms_days),
        gross_amount=gross,
        discount_amount=discount,
        net_amount=net,
        vat_amount=vat,
        vat_rate=po.vat_rate,
        total_amount=total,
        balance_amount=total,
    )


def record_supplier_payment(
    *,
    bill,
    amount,
    method,
    reference="",
    cheque_number="",
    cheque_bank="",
    cheque_date=None,
    user,
):
    """Post one payment against one bill; returns the payment row.

    MUST run inside the caller's `transaction.atomic()` block: the view wraps this and
    its audit row together, so a failed audit leaves no payment and no moved balance.

    The bill row is re-read with `select_for_update()` and the balance is decided UNDER
    that lock. Without it two clerks (or one double-clicked button) could both read
    "200.00 left" and both record 200.00 - the second would take the balance negative,
    which is exactly the state `OVERPAYMENT` exists to prevent. With it, the second
    request waits, then reads 0.00 and is refused with `BILL_PAID`.

    Order of refusals: settled bill (`BILL_PAID`), then amount (`OVERPAYMENT`). Nothing
    is written before either decision.

    If the method is `CREDIT`, refuse it: a credit application must name the note that
    funds it, and `apply_supplier_credit` is the one writer that does (Phase 8 B4).
    Without this guard an ORM caller could lower a bill against money no note records.
    """
    amount = _validated_amount(amount)
    if method == SupplierPayment.Method.CREDIT:
        raise InvalidSupplierPayment(
            "a CREDIT payment must name the credit note it spends; use "
            "apply_supplier_credit."
        )
    bill = (
        SupplierBill.objects.select_for_update()
        .select_related("supplier")
        .get(pk=bill.pk)
    )
    if bill.balance_amount <= 0:
        raise BillPaid(bill)
    if amount > bill.balance_amount:
        raise Overpayment(bill, amount)
    payment = SupplierPayment.objects.create(
        bill=bill,
        paid_by=user,
        amount=amount,
        method=method,
        reference=(reference or "").strip(),
        cheque_number=(cheque_number or "").strip(),
        cheque_bank=(cheque_bank or "").strip(),
        cheque_date=cheque_date,
        # Phase 8 B1 (decision 20 #3): a cheque is a PROMISE, so it starts ISSUED and a
        # manager decides it later; the balance still drops here, at issue. Cash and
        # transfers leave nothing to decide, so they are born settled.
        status=(
            SupplierPayment.Status.ISSUED
            if method == SupplierPayment.Method.CHEQUE
            else SupplierPayment.Status.CLEARED
        ),
    )
    bill.balance_amount = money(bill.balance_amount - amount)
    bill.save(update_fields=["balance_amount"])
    return payment


def decide_supplier_cheque(*, payment_id, decision, user, reason=""):
    """Clear or bounce ONE issued supplier cheque (Phase 8 B1, decision 20 #3).

    Copies the customer-cheque rule (`pos.services.decide_cheque`) because the question is
    the same: did the bank honour it? The difference is what moves. A supplier cheque has
    ALREADY lowered the bill at issue, so:

    * CLEARED moves no money - it only confirms what the bill already counted;
    * BOUNCED puts `amount` back on `balance_amount`, because the shop still owes it.

    Either way it happens ONCE: the payment row is locked and re-read UNDER the lock, so
    two managers clicking together cannot restore the balance twice.

    **Lock order:** payment, then bill. No cycle is possible: the only other writer of
    these two rows is `record_supplier_payment`, which locks the BILL and never locks a
    payment (it only inserts one). So a bounce and a payment can wait on each other, but
    never in opposite orders.

    Opens its own `transaction.atomic()`: the status stamp, the restored balance and the
    caller's audit row must commit together or not at all. `payment_id` is expected to
    have been resolved through the caller's CHEQUE-filtered queryset already (so a bad id
    is a 404), and is re-read under the lock here.
    """
    from django.db import transaction
    from django.utils import timezone

    # Reused, not re-invented: these are the project's two cheque refusal codes, and the
    # handler already publishes them as 400 / 409 with the `{code, detail}` shape.
    from apps.pos.exceptions import (
        ChequeAlreadyDecided,
        ChequeError,
        ChequeReasonRequired,
    )

    if decision not in (
        SupplierPayment.Status.CLEARED,
        SupplierPayment.Status.BOUNCED,
    ):
        raise ChequeError(f"{decision!r} is not a cheque decision.")
    reason = reason.strip() if isinstance(reason, str) else ""
    if decision == SupplierPayment.Status.BOUNCED and not reason:
        raise ChequeReasonRequired()

    with transaction.atomic():
        payment = SupplierPayment.objects.select_for_update().get(pk=payment_id)
        if payment.status != SupplierPayment.Status.ISSUED:
            raise ChequeAlreadyDecided(payment.status, payment.cheque_number)
        bill = SupplierBill.objects.select_for_update().get(pk=payment.bill_id)
        if decision == SupplierPayment.Status.BOUNCED:
            restored = money(bill.balance_amount + payment.amount)
            # A bounce cannot make the shop owe more than the delivery was billed for:
            # the cheque was paid out of that balance at issue. This is an invariant, not
            # a client error - if it ever fires, the ledger disagrees with itself.
            assert restored <= bill.total_amount, (
                f"Bill #{bill.pk}: bouncing payment #{payment.pk} would restore "
                f"{restored} above its total {bill.total_amount}."
            )
            bill.balance_amount = restored
            bill.save(update_fields=["balance_amount"])
        payment.status = decision
        payment.decided_by = user
        payment.decided_at = timezone.now()
        payment.decision_reason = reason
        payment.save(update_fields=list(SupplierPayment.DECISION_FIELDS))
    return payment


def credit_note_value(supplier_return) -> Decimal:
    """What one supplier return is worth: the landed cost of the stock that went back.

    Decision 20 #1: `SUM(base qty x batch unit_cost_landed)` over the return's deductions,
    rounded ONCE HALF_UP to the cent. `services.record_supplier_return` already rounded
    each line's `credit_value` (the same stock may have left two batches at slightly
    different costs), so the sum of those cents is exact and this `money()` call is the
    single, explicit rounding of the note's own figure.
    """
    return money(
        sum((line.credit_value for line in supplier_return.lines.all()), Decimal(0))
    )


def create_credit_note_for_return(*, supplier_return):
    """Mint the ONE numbered credit note a supplier return is worth (decision 20 #1).

    MUST run inside the caller's `transaction.atomic()` block - the return's own - so the
    note commits or rolls back with the stock, the lines and the deductions it prices.

    **VAT comes from the SOURCE BILL's snapshot, both ways round**, because the credit has
    to mirror what was billed:

    * inclusive (`total_amount = value`): the tax is EXTRACTED, `vat = value - round(value
      / (1 + rate/100))` - a 100.00 return on a 12% inclusive bill takes 10.71 of VAT back,
      because 100.00 / 1.12 = 89.29 is the net;
    * exclusive (`total_amount = value + vat`): the tax is ADDED, `vat = round(value x
      rate/100)` - the same 100.00 with a 12% exclusive rate takes 12.00, so the total is
      112.00.

    `vat_rate` is the BILL's stored rate (the PO's own rate when the receipt created no
    bill, e.g. a pre-Phase-5 receipt or a zero-value delivery), never today's settings.

    **Numbering** is `pos.services.next_number("CN")` - a locked `DocumentCounter`
    (`CN-YYYYMMDD-NNNN`), never `common.numbering`'s read-then-add. The import is
    function-local on purpose: inventory cannot import pos at module scope without an
    import cycle (`pos.services` already imports `inventory.services`), and by the time a
    return asks for a number every module is loaded.
    """
    from apps.pos.services import next_number

    bill = supplier_return.bill
    po = supplier_return.purchase_order
    rate = bill.vat_rate if bill is not None else po.vat_rate
    inclusive = po.vat_inclusive
    value = credit_note_value(supplier_return)
    _vatable, vat = vat_split(value, rate=rate, inclusive=inclusive)
    total = value if inclusive else money(value + vat)
    return SupplierCreditNote.objects.create(
        number=next_number("CN"),
        supplier_return=supplier_return,
        supplier=supplier_return.supplier,
        source_bill=bill,
        value=value,
        vat_rate=rate,
        vat_inclusive=inclusive,
        vat_amount=vat,
        total_amount=total,
        # Born owing its whole total; the application below spends what the bill can take.
        remaining_amount=total,
    )


def apply_credit_to_source_bill(*, note, user):
    """Spend one credit note on the bill its goods came in on; returns the payment or None.

    Decision 20 #1's auto rule, in ONE transaction (the caller's, which also holds the
    return): `applied = min(note.remaining_amount, bill.balance_amount)`, then a
    `SupplierPayment(method=CREDIT, credit_note=note, amount=applied, status=CLEARED)`
    lowers the bill and the note's `remaining_amount` drops by the same peso. What the
    bill cannot absorb - it was already paid, or the note is worth more than what is left
    - simply stays on the note as supplier credit, ready for a manager to apply by hand
    to a later bill (Phase 8 B4).

    A note with no `source_bill` (a receipt that never created one) or a bill with nothing
    left to pay moves NO money and writes NO payment: there is nothing to settle, and a
    0.00 payment would only be noise in the bill's history.

    **Lock order: note, then bill.** The note row is re-read under `select_for_update`
    (it is the row whose `remaining_amount` is about to move, and the one a future manual
    apply will lock first too), then the bill. No cycle is possible with the other two
    money writers: `record_supplier_payment` locks only the BILL, and
    `decide_supplier_cheque` locks a payment then its BILL - every chain ENDS at the bill,
    and none of them ever waits on a credit note. Two returns of one supplier's bills can
    therefore queue on the bill, never in opposite orders.
    """
    note = SupplierCreditNote.objects.select_for_update().get(pk=note.pk)
    if note.source_bill_id is None or note.remaining_amount <= 0:
        return None
    bill = (
        SupplierBill.objects.select_for_update()
        .select_related("supplier")
        .get(pk=note.source_bill_id)
    )
    applied = money(min(note.remaining_amount, bill.balance_amount))
    if applied <= 0:
        return None

    payment = SupplierPayment.objects.create(
        bill=bill,
        paid_by=user,
        amount=applied,
        method=SupplierPayment.Method.CREDIT,
        credit_note=note,
        # Applying credit settles immediately: there is no bank that could bounce it.
        status=SupplierPayment.Status.CLEARED,
    )
    bill.balance_amount = money(bill.balance_amount - applied)
    bill.save(update_fields=["balance_amount"])
    note.remaining_amount = money(note.remaining_amount - applied)
    note.save(update_fields=["remaining_amount"])
    return payment


def apply_supplier_credit(*, note, bill, amount, user):
    """Spend `amount` of one credit note on one bill BY HAND (Phase 8 B4, decision 20 #1).

    The auto rule (`apply_credit_to_source_bill`) can only reach the note's own bill, and
    stops at whatever that bill could absorb. What is left is supplier credit, and this
    is the manager's move: pick a later bill of the SAME supplier and spend up to
    `min(note.remaining_amount, bill.balance_amount)` of it.

    MUST run inside the caller's `transaction.atomic()` block (the view adds the `PAYMENT`
    audit row), so a failed audit rolls the credit application back with it.

    **Lock order: note, then bill** - the same order the auto rule takes, and the reason
    no cycle exists: `record_supplier_payment` locks only the BILL, `decide_supplier_cheque`
    locks a payment then its BILL, and nothing ever waits on a note from the bill side.
    Both rows move inside that one lock, so two managers spending the same note (or two
    spending one note on two bills) queue instead of overspending: the loser re-reads the
    reduced `remaining_amount` and is refused.

    Refusal order, all before any write: a note of another supplier
    (`CREDIT_NOTE_SUPPLIER_MISMATCH`), more than the note has left
    (`CREDIT_EXCEEDS_REMAINING`), then the bill's own two - settled (`BILL_PAID`) and
    amount above the balance (`OVERPAYMENT`). The bill's pair comes second on purpose:
    the note is the resource that runs out, and its message names the figure to fix.
    """
    amount = _validated_amount(amount)
    note = (
        SupplierCreditNote.objects.select_for_update()
        .select_related("supplier")
        .get(pk=note.pk)
    )
    bill = (
        SupplierBill.objects.select_for_update()
        .select_related("supplier")
        .get(pk=bill.pk)
    )
    if bill.supplier_id != note.supplier_id:
        raise CreditNoteSupplierMismatch(note, bill)
    if amount > note.remaining_amount:
        raise CreditExceedsRemaining(note, amount)
    if bill.balance_amount <= 0:
        raise BillPaid(bill)
    if amount > bill.balance_amount:
        raise Overpayment(bill, amount)

    payment = SupplierPayment.objects.create(
        bill=bill,
        paid_by=user,
        amount=amount,
        method=SupplierPayment.Method.CREDIT,
        credit_note=note,
        # Applied credit settles at once: no bank can bounce it.
        status=SupplierPayment.Status.CLEARED,
    )
    bill.balance_amount = money(bill.balance_amount - amount)
    bill.save(update_fields=["balance_amount"])
    note.remaining_amount = money(note.remaining_amount - amount)
    note.save(update_fields=["remaining_amount"])
    return payment


def _validated_amount(amount) -> Decimal:
    """The amount as a money Decimal, or `INVALID_SUPPLIER_PAYMENT`.

    `NaN` and `Infinity` are refused explicitly: a Decimal comparison with `NaN` raises,
    so letting one through would turn a bad payload into a 500. Zero and negatives are
    refused because a payment of nothing moves no money and a negative one is a refund
    this phase does not model.
    """
    try:
        value = amount if isinstance(amount, Decimal) else Decimal(str(amount))
    except (InvalidOperation, ValueError, TypeError):
        raise InvalidSupplierPayment(
            "amount must be a number in pesos, e.g. 1500.00."
        ) from None
    if not value.is_finite():
        raise InvalidSupplierPayment(
            "amount must be a real number of pesos (NaN and Infinity are not money)."
        )
    value = money(value)
    if value <= 0:
        raise InvalidSupplierPayment("amount must be greater than 0.")
    if value >= MONEY_LIMIT:
        raise InvalidSupplierPayment(
            f"amount must be below {MONEY_LIMIT}: that is the largest figure the "
            "payments ledger can hold."
        )
    return value
