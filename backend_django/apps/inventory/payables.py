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

Both writers MUST be called inside the caller's `transaction.atomic()` block: the view
wraps the write and its audit row together, and a service that committed on its own would
leave a payment behind after a failed audit row.
"""

from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal, InvalidOperation

from django.db.models import Sum

from .exceptions import (
    BillPaid,
    InvalidSupplierPayment,
    Overpayment,
)
from .models import PurchaseOrder, SupplierBill, SupplierPayment

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
    """
    amount = _validated_amount(amount)
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
    )
    bill.balance_amount = money(bill.balance_amount - amount)
    bill.save(update_fields=["balance_amount"])
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
