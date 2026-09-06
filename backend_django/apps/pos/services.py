"""POS services — checkout, FIFO allocation, receipt generation."""
from datetime import date, timedelta
from decimal import Decimal
from django.db import transaction
from apps.collectibles.models import CollectibleLedger
from apps.inventory.services import allocate_fifo
from .models import Customer, SalesTransaction, SalesItem, Payment, OfficialReceipt


def generate_transaction_no():
    today = date.today().strftime('%Y%m%d')
    last = SalesTransaction.objects.filter(transaction_no__startswith=f'TRX-{today}').order_by('-transaction_no').first()
    seq = 1
    if last:
        seq = int(last.transaction_no.split('-')[-1]) + 1
    return f'TRX-{today}-{seq:04d}'


def generate_or_number():
    today = date.today().strftime('%Y%m%d')
    last = OfficialReceipt.objects.filter(or_number__startswith=f'OR-{today}').order_by('-or_number').first()
    seq = 1
    if last:
        seq = int(last.or_number.split('-')[-1]) + 1
    return f'OR-{today}-{seq:04d}'


def process_sale(*, customer_id, cashier, items_data, payments_data, source='WALK_IN'):
    """Process a complete walk-in sale or requisition release.

    items_data: [{'variant_id': 1, 'qty': 5, 'unit_price': Decimal('150')}]
    payments_data: [{'method': 'CASH', 'amount_tendered': Decimal('750')}]
    """
    vatable_sales = Decimal('0')
    discount = Decimal('0')

    with transaction.atomic():
        txn = SalesTransaction.objects.create(
            customer_id=customer_id,
            cashier=cashier,
            transaction_no=generate_transaction_no(),
            source=source,
            vatable_sales=0,
            vat_amount=0,
            discount_amount=discount,
            grand_total=0,
        )

        for item in items_data:
            item_id = item['variant_id']
            qty = Decimal(str(item.get('qty', 0)))
            unit_price = Decimal(str(item.get('unit_price', 0)))
            subtotal = qty * unit_price

            SalesItem.objects.create(
                transaction=txn,
                variant_uom_id=item_id,
                qty=qty,
                unit_price=unit_price,
                subtotal=subtotal,
            )

            # FIFO allocation (deduct stock). item_id may be a VariantUOM id
            # (POS payload) or a ProductVariant id; resolve to the variant.
            from apps.inventory.models import VariantUOM
            variant_id = item_id
            vuom = VariantUOM.objects.filter(
                pk=item_id).select_related('variant').first()
            if vuom is not None:
                variant_id = vuom.variant_id
            # Raises ValueError on insufficient stock → whole sale rolls back.
            allocate_fifo(variant_id=variant_id, qty_needed=qty)

            vatable_sales += subtotal

        grand_total = vatable_sales - discount
        txn.vatable_sales = vatable_sales
        txn.grand_total = grand_total
        txn.save(update_fields=['vatable_sales', 'grand_total'])

        # Payments
        total_paid = Decimal('0')
        for pdata in payments_data:
            amt = Decimal(str(pdata.get('amount_tendered', 0)))
            Payment.objects.create(
                transaction=txn,
                method=pdata.get('method', 'CASH'),
                amount_tendered=amt,
                reference_no=pdata.get('reference_no', ''),
            )
            total_paid += amt

        # Official receipt
        OfficialReceipt.objects.create(
            transaction=txn,
            or_number=generate_or_number(),
            terminal_no='POS-01',
        )

        # Underpaid sale -> post the shortfall to Collectibles (utang).
        shortfall = grand_total - total_paid
        if shortfall > 0 and customer_id:
            CollectibleLedger.objects.create(
                customer_id=customer_id,
                transaction=txn,
                original_amount=shortfall,
                balance_due=shortfall,
                due_date=date.today() + timedelta(days=30),
                status=CollectibleLedger.Status.OPEN,
            )

    return txn