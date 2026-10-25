# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directive and reason as apps/pos/tests.py and seed_demo.py: this checker runs
# with a working directory outside the repo, so the root pyrightconfig.json (which
# already sets both rules to "warning") is not found and they escalate to errors.
# Without django-stubs, `Model.objects`, FK-attribute assignment and
# `transaction.atomic()` are all false positives on valid Django. The test run is the
# authority.
"""Requisitions services â€” approval, token generation, material release."""

from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from common.numbering import generate_document_number
from django.db import transaction
from django.utils import timezone

from apps.collectibles.models import CollectibleLedger
from apps.inventory.services import allocate_fifo, check_low_stock_after_stock_out
from apps.pos.exceptions import NoOpenShift
from apps.pos.models import OfficialReceipt, SalesItem, SalesTransaction, Shift
from apps.pos.services import generate_or_number, generate_transaction_no

from .exceptions import NoBaseUom, SelfApproval
from .models import MaterialToken, Requisition, RequisitionItem


def generate_req_number():
    """Kept as the Requisition-specific name; the pattern itself lives in common.numbering."""
    return generate_document_number(Requisition, 'req_number', 'REQ')


def submit_requisition(*, requisition: Requisition) -> None:
    if requisition.status != Requisition.Status.DRAFT:
        raise ValueError(f'Cannot submit a {requisition.status} requisition.')
    requisition.status = Requisition.Status.SUBMITTED
    requisition.save(update_fields=['status', 'updated_at'])


def approve_requisition(*, requisition: Requisition, approver) -> MaterialToken:
    """Approve a SUBMITTED requisition and mint its one-time material token.

    Separation of duties (decision 04 / NFR): the approver may not be the requester,
    superusers included. Without the guard a Site Foreman who also holds Store Manager
    could approve their own request and the bearer token would release goods on credit
    with no second person involved. Refused before the first write, so the requisition
    stays SUBMITTED and no token row exists (a token row is a credential).

    Rejection is deliberately NOT guarded — P2 ruling: a requester withdrawing their own
    request harms nobody.
    """
    if requisition.status != Requisition.Status.SUBMITTED:
        raise ValueError(f'Cannot approve a {requisition.status} requisition.')
    if requisition.requested_by_id == getattr(approver, 'pk', approver):
        raise SelfApproval()
    with transaction.atomic():
        requisition.status = Requisition.Status.APPROVED
        requisition.approved_by = approver
        requisition.save(update_fields=['status', 'approved_by', 'updated_at'])
        token = MaterialToken.objects.create(requisition=requisition)
    return token


def reject_requisition(*, requisition: Requisition, approver) -> None:
    if requisition.status != Requisition.Status.SUBMITTED:
        raise ValueError(f'Cannot reject a {requisition.status} requisition.')
    requisition.status = Requisition.Status.REJECTED
    requisition.approved_by = approver
    requisition.save(update_fields=['status', 'approved_by', 'updated_at'])
def verify_token(*, token_value: str) -> dict:
    """Validate a material token and return requisition details for POS display."""
    try:
        uuid_val = UUID(token_value)
    except ValueError:
        raise ValueError('Invalid token format.')
    try:
        token_obj = MaterialToken.objects.select_related(
            'requisition__project__customer').get(token=uuid_val)
    except MaterialToken.DoesNotExist:
        raise ValueError('Token not found.')
    if token_obj.is_used:
        raise ValueError('Token has already been used.')
    req = token_obj.requisition
    if req.status != Requisition.Status.APPROVED:
        raise ValueError(f'Requisition is {req.status}, not APPROVED.')
    items = RequisitionItem.objects.select_related(
        'variant__product', 'variant__base_uom'
    ).prefetch_related('variant__selling_uoms__uom').filter(requisition=req)
    return {
        'token': str(token_obj.token),
        'requisition': {
            'id': req.id, 'req_number': req.req_number,
            'project': req.project.name, 'customer': req.project.customer.name,
        },
        'items': [
            {'id': it.id, 'variant_id': it.variant_id,
             'variant_name': str(it.variant), 'quantity': str(it.quantity),
             'remaining': str(it.quantity - it.released_qty)}
            for it in items
        ],
    }
def _base_uoms_for(items: list) -> dict:
    """Map variant_id -> the factor-1 VariantUOM, refusing any line that has none.

    Requisition quantities are base units, so the factor-1 selling unit is the only one
    whose `default_selling_price` prices a base unit directly; a CF=12 row would charge 12
    base units' worth per base unit. One query for the whole release, `pk` order so a
    catalog with a duplicate CF=1 row resolves the same way on every call.

    Raises `NoBaseUom` — before the caller writes anything (decision 09 item 6).
    """
    from apps.inventory.models import VariantUOM

    by_variant = {}
    for row in VariantUOM.objects.filter(conversion_factor=1).order_by('pk'):
        by_variant.setdefault(row.variant_id, row)

    for item_info in items:
        if Decimal(item_info['remaining']) <= 0:
            continue
        if item_info['variant_id'] not in by_variant:
            raise NoBaseUom(
                item_info['variant_id'],
                message=(
                    f"Variant {item_info['variant_name']} "
                    f"(#{item_info['variant_id']}) has no base-unit selling price: "
                    'add a selling unit with conversion factor 1 before releasing it.'),
            )
    return by_variant


def release_materials(*, token_value: str, cashier) -> dict:
    """Process material release at POS (UC-21 + UC-22).

    FIFO-deducts stock, creates SalesTransaction (source=REQUISITION),
    posts to CollectiblesLedger (construction firm pays later),
    marks token used and requisition RELEASED.

    Requires a factor-1 selling unit for every line BEFORE the first write (decision 09
    item 6). The lookup used to happen inside the write loop and, on a miss, fell back to
    a zero price while handing `variant_uom=None` to a non-null FK: the stock was deducted
    and the SalesTransaction created, then the IntegrityError escaped as a 500 with the
    token still unused — a release the cashier could retry into a second deduction. The
    resolve now happens here, so a catalog gap answers 400 `NO_BASE_UOM` and leaves the
    stock, the sale, the receipt, the ledger and the token untouched.

    Quantities stay in BASE units: `RequisitionItem.quantity` is already base-unit (the
    requisition is written against `variant`, not a selling unit), so the factor-1 price
    applies to it directly and is NOT multiplied by a conversion factor.

    Decision 03: a release is a SALE for accountability purposes — it moves stock and
    books money owed — so the releasing cashier needs their OPEN shift, exactly like
    `process_sale`. The gate sits inside the atomic block, after the token row lock and
    BEFORE the first write, so a refused release leaves no transaction, no receipt, no
    ledger, no moved stock, no consumed token and no RELEASE audit row (the view writes
    that row in the same transaction). The shift is then attached to the resulting
    `SalesTransaction`, which is what puts the release inside the Z-reading.
    """
    info = verify_token(token_value=token_value)
    token_obj = (
        MaterialToken.objects.select_related('requisition__project__customer')
        .get(token=UUID(token_value))
    )
    req = token_obj.requisition
    customer = req.project.customer

    # Resolved up front and reused by the write loop: one query for every line, and no
    # second chance for a catalog gap to appear after stock has already moved.
    base_uoms = _base_uoms_for(info['items'])

    with transaction.atomic():
        token_obj = (
            MaterialToken.objects.select_for_update().get(pk=token_obj.pk)
        )
        if token_obj.is_used:
            raise ValueError('Token has already been used.')

        # Decision 03: the same gate `process_sale` applies, and for the same reason —
        # an orphan release is a receivable the end-of-shift close never asks about.
        # Read before the first write so the refusal is total.
        shift = Shift.objects.filter(
            cashier=cashier, status=Shift.Status.OPEN).first()
        if shift is None:
            raise NoOpenShift(
                'You have no open shift. Open a shift before releasing materials.')

        txn = SalesTransaction.objects.create(
            customer=customer,
            cashier=cashier,
            shift=shift,
            transaction_no=generate_transaction_no(),
            source=SalesTransaction.Source.REQUISITION,
            vatable_sales=Decimal('0'),
            vat_amount=Decimal('0'),
            discount_amount=Decimal('0'),
            grand_total=Decimal('0'),
        )

        grand_total = Decimal('0')
        affected_variant_ids = set()

        for item_info in info['items']:
            item = RequisitionItem.objects.select_related('variant').get(
                pk=item_info['id'])
            remaining = item.quantity - item.released_qty
            if remaining <= 0:
                continue

            vuom = base_uoms[item.variant_id]
            unit_price = vuom.default_selling_price

            allocate_fifo(variant_id=item.variant_id, qty_needed=remaining)
            affected_variant_ids.add(item.variant_id)

            subtotal = remaining * unit_price
            SalesItem.objects.create(
                transaction=txn, variant_uom=vuom,
                qty=remaining, unit_price=unit_price, subtotal=subtotal)
            grand_total += subtotal
            item.released_qty = item.quantity
            item.save(update_fields=['released_qty'])

        # Task 4.3: a release takes stock off the shelf exactly like a sale (it IS a sale
        # of source REQUISITION), so it re-evaluates the low-stock threshold once per
        # affected variant, inside this transaction. Before this the only two paths that
        # raised an alert were a goods receipt and a manual adjustment - both of which ADD
        # stock - so the shelf could be issued empty and the low-stock screen stayed quiet.
        check_low_stock_after_stock_out(variant_ids=affected_variant_ids)

        txn.vatable_sales = grand_total
        txn.grand_total = grand_total
        txn.save(update_fields=['vatable_sales', 'grand_total'])

        OfficialReceipt.objects.create(
            transaction=txn,
            or_number=generate_or_number(),
            terminal_no='POS-01',
        )

        ledger = CollectibleLedger.objects.create(
            customer=customer, transaction=txn,
            original_amount=grand_total, balance_due=grand_total,
            due_date=date.today() + date.resolution * 30,
            status=CollectibleLedger.Status.OPEN,
        )

        token_obj.is_used = True
        token_obj.used_at = timezone.now()
        token_obj.used_by = cashier
        token_obj.save(update_fields=['is_used', 'used_at', 'used_by'])

        req.status = Requisition.Status.RELEASED
        req.save(update_fields=['status', 'updated_at'])

    return {
        'transaction_id': txn.id,
        'transaction_no': txn.transaction_no,
        # The audit row (written by the view, inside this same transaction) names the
        # requisition by its DOCUMENT NUMBER - never by the token UUID, which is a bearer
        # credential (decision 07).
        'req_number': req.req_number,
        'grand_total': str(grand_total),
        'ledger_id': ledger.id,
        'balance_due': str(ledger.balance_due),
    }