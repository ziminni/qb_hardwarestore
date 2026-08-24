"""Requisitions services â€” approval, token generation, material release."""

from datetime import date, datetime
from decimal import Decimal
from uuid import UUID

from django.db import transaction
from django.utils import timezone

from apps.inventory.services import allocate_fifo
from apps.pos.models import SalesTransaction, SalesItem, OfficialReceipt
from apps.pos.services import generate_transaction_no, generate_or_number
from apps.collectibles.models import CollectibleLedger

from .models import MaterialToken, Requisition, RequisitionItem


def generate_req_number():
    today = date.today().strftime('%Y%m%d')
    last = Requisition.objects.filter(
        req_number__startswith=f'REQ-{today}').order_by('-req_number').first()
    seq = int(last.req_number.split('-')[-1]) + 1 if last else 1
    return f'REQ-{today}-{seq:04d}'


def submit_requisition(*, requisition: Requisition) -> None:
    if requisition.status != Requisition.Status.DRAFT:
        raise ValueError(f'Cannot submit a {requisition.status} requisition.')
    requisition.status = Requisition.Status.SUBMITTED
    requisition.save(update_fields=['status', 'updated_at'])


def approve_requisition(*, requisition: Requisition, approver) -> MaterialToken:
    if requisition.status != Requisition.Status.SUBMITTED:
        raise ValueError(f'Cannot approve a {requisition.status} requisition.')
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
def release_materials(*, token_value: str, cashier) -> dict:
    """Process material release at POS (UC-21 + UC-22).

    FIFO-deducts stock, creates SalesTransaction (source=REQUISITION),
    posts to CollectiblesLedger (construction firm pays later),
    marks token used and requisition RELEASED.
    """
    info = verify_token(token_value=token_value)
    token_obj = (
        MaterialToken.objects.select_related('requisition__project__customer')
        .get(token=UUID(token_value))
    )
    req = token_obj.requisition
    customer = req.project.customer

    with transaction.atomic():
        token_obj = (
            MaterialToken.objects.select_for_update().get(pk=token_obj.pk)
        )
        if token_obj.is_used:
            raise ValueError('Token has already been used.')

        txn = SalesTransaction.objects.create(
            customer=customer,
            cashier=cashier,
            transaction_no=generate_transaction_no(),
            source=SalesTransaction.Source.REQUISITION,
            vatable_sales=Decimal('0'),
            vat_amount=Decimal('0'),
            discount_amount=Decimal('0'),
            grand_total=Decimal('0'),
        )

        from apps.inventory.models import VariantUOM
        grand_total = Decimal('0')

        for item_info in info['items']:
            item = RequisitionItem.objects.select_related('variant').get(
                pk=item_info['id'])
            remaining = item.quantity - item.released_qty
            if remaining <= 0:
                continue

            vuom = VariantUOM.objects.filter(
                variant=item.variant, conversion_factor=1).first()
            unit_price = vuom.default_selling_price if vuom else Decimal('0')

            allocate_fifo(variant_id=item.variant_id, qty_needed=remaining)

            subtotal = remaining * unit_price
            SalesItem.objects.create(
                transaction=txn, variant_uom=vuom,
                qty=remaining, unit_price=unit_price, subtotal=subtotal)
            grand_total += subtotal
            item.released_qty = item.quantity
            item.save(update_fields=['released_qty'])

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
        'grand_total': str(grand_total),
        'ledger_id': ledger.id,
        'balance_due': str(ledger.balance_due),
    }