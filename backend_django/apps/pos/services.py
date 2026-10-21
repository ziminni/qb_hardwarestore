# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
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
from datetime import date, timedelta
from decimal import Decimal
from django.db import transaction
from apps.collectibles.models import CollectibleLedger
from apps.inventory.services import allocate_fifo

from .exceptions import WalkInCannotOwe
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
        txn = SalesTransaction.objects.create(
            customer_id=customer_id,
            cashier=cashier,
            shift=shift,
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

            item_row = SalesItem.objects.create(
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
            allocations = allocate_fifo(variant_id=variant_id, qty_needed=qty)
            # Task 6A.4: persist which batches this item drew from. Without these
            # rows a linked return cannot know "the original batch it left from".
            from .models import SalesItemDeduction
            SalesItemDeduction.objects.bulk_create([
                SalesItemDeduction(sales_item=item_row, batch=batch, qty=take)
                for batch, take in allocations
            ])

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
        #
        # Decision 14: only a NAMED customer may owe. The seeded Walk-in Customer is a
        # placeholder, so a balance against it is money owed by nobody - it inflates
        # receivables, makes the aging report a fiction, and hides the real signal that
        # the till came up short. Raising here rather than validating up front is
        # deliberate: the shortfall is only known after the items are totalled, and the
        # enclosing `transaction.atomic()` rolls the sale back wholesale, so a refused
        # walk-in leaves no transaction, no ledger and no moved stock.
        shortfall = grand_total - total_paid
        if shortfall > 0 and customer_id:
            customer = Customer.objects.only('customer_type', 'name').get(
                pk=customer_id)
            if customer.customer_type == Customer.Type.WALK_IN:
                raise WalkInCannotOwe(shortfall, customer.name)
            CollectibleLedger.objects.create(
                customer_id=customer_id,
                transaction=txn,
                original_amount=shortfall,
                balance_due=shortfall,
                due_date=date.today() + timedelta(days=30),
                status=CollectibleLedger.Status.OPEN,
            )

    return txn


def _restock_returned(*, variant_id, qty_needed, original_id, return_item):
    """Add returned stock back, per decision 15's two branches.

    Linked (original_id set): back into the batches the original sale drew from,
    oldest-drawn first, capped by cumulative accounting — every linked return writes
    NEGATIVE deduction rows on its own items, so a second call sees what the first
    already gave back and the "more-than-drew" guard fires across calls, across
    partials, and across the lines of one call (same-transaction writes are visible
    to the later lines). Pre-linkage sales left no deduction rows, so those fall
    back to the newest-active branch — the only honest answer when history was
    never recorded. Unlinked: the newest active batch. No active batch at all
    (variant fully depleted): the newest batch overall is reopened.
    Reads are row-locked, matching allocate_fifo's discipline on the way out.
    """
    from django.db.models import Sum
    from apps.inventory.models import InventoryBatch
    from .models import SalesItemDeduction
    from .exceptions import ReturnError

    remaining = qty_needed
    if original_id is not None:
        rows = list(
            SalesItemDeduction.objects
            .select_related('batch')
            .select_for_update()
            .filter(sales_item__transaction_id=original_id,
                    sales_item__variant_uom__variant_id=variant_id,
                    qty__gt=0)
            .order_by('batch__receipt__receive_date')
        )
        if rows:
            touched = []
            planned = []
            for row in rows:
                if remaining <= 0:
                    break
                returned = (
                    SalesItemDeduction.objects
                    .filter(sales_item__transaction__original_transaction_id=original_id,
                            batch_id=row.batch_id, qty__lt=0)
                    .aggregate(total=Sum('qty'))['total']
                    or Decimal('0')
                )
                available = row.qty + returned
                if available <= 0:
                    continue
                add = min(available, remaining)
                row.batch.current_qty += add
                touched.append(row.batch)
                planned.append(SalesItemDeduction(
                    sales_item=return_item, batch=row.batch, qty=-add))
                remaining -= add
            if touched:
                InventoryBatch.objects.bulk_update(touched, ['current_qty'])
                SalesItemDeduction.objects.bulk_create(planned)
            if remaining > 0:
                raise ReturnError(
                    'Cannot return more than the original sale drew.')
            return
    newest = (
        InventoryBatch.objects
        .select_for_update()
        .filter(variant_id=variant_id, current_qty__gt=0)
        .order_by('-receipt__receive_date')
        .first()
    )
    if newest is None:
        newest = (
            InventoryBatch.objects
            .select_for_update()
            .filter(variant_id=variant_id)
            .order_by('-receipt__receive_date')
            .first()
        )
    if newest is None:
        raise ReturnError('No batches exist for this variant.')
    newest.current_qty += remaining
    newest.save(update_fields=['current_qty'])


def _money(value):
    """Render a total as the two-decimal string the API has always used.

    `None` from an empty aggregate becomes '0.00' - a shift with no sales has a zero
    drawer total, not a missing one. Strings, never floats: this is money.
    """
    return f'{value or Decimal("0"):.2f}'


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

    Recomputed from the same query on every call, so a closed shift's Z-reading is
    idempotent - asking twice can never show two different days.

    Everything comes back as a string: it lands straight in JSON, and a client that gets
    a JSON number for money loses the trailing zero and rounds badly.
    """
    from django.db.models import Count, Sum

    completed = shift.transactions.filter(
        status=SalesTransaction.Status.COMPLETED)
    sales = completed.exclude(source=SalesTransaction.Source.RETURN)
    returns = completed.filter(source=SalesTransaction.Source.RETURN)

    totals = completed.aggregate(
        transaction_count=Count('id'),
        gross_sales=Sum('grand_total'),
        vat=Sum('vat_amount'),
        discounts=Sum('discount_amount'),
    )

    # One query for every method, then read the four the till knows. A method the client
    # invents later shows up in neither total and the drawer still balances on cash.
    by_method = {
        row['method']: row['total'] or Decimal('0')
        for row in (
            Payment.objects
            .filter(transaction__in=sales)
            .values('method')
            .annotate(total=Sum('amount_tendered')))
    }
    cash_refunds = (
        Payment.objects
        .filter(transaction__in=returns, method=Payment.Method.CASH)
        .aggregate(total=Sum('amount_tendered'))['total']
        or Decimal('0'))

    cash_sales = by_method.get(Payment.Method.CASH, Decimal('0'))
    expected_drawer = shift.opening_float + cash_sales - abs(cash_refunds)
    variance = (
        None if shift.closing_count is None
        else shift.closing_count - expected_drawer)

    return {
        'shift_id': shift.id,
        'opening_float': _money(shift.opening_float),
        'closing_count': (
            None if shift.closing_count is None else _money(shift.closing_count)),
        'transaction_count': totals['transaction_count'] or 0,
        'gross_sales': _money(totals['gross_sales']),
        'vat': _money(totals['vat']),
        'discounts': _money(totals['discounts']),
        'cash_sales': _money(cash_sales),
        'card_sales': _money(by_method.get(Payment.Method.CARD)),
        'gcash_sales': _money(by_method.get(Payment.Method.GCASH)),
        'bank_sales': _money(by_method.get(Payment.Method.BANK_TRANSFER)),
        'cash_refunds': _money(abs(cash_refunds)),
        'expected_drawer': _money(expected_drawer),
        'variance': None if variance is None else _money(variance),
    }


def process_return(*, customer_id, cashier, items_data,
                   original_transaction_id=None, payment_method='CASH'):
    """Post a customer return: a RETURN transaction with negative amounts.

    items_data mirrors process_sale but POSITIVE (what comes back):
    [{'variant_id': 1, 'qty': 5, 'unit_price': Decimal('150')}].
    Lines store negative qty (direction) at a positive unit price; the payment
    is the negative refund. Validators do not run on objects.create(), and no
    full_clean path creates sale items — see the 6A.4 ledger note.
    Collectibles are deliberately untouched (decision 15 is silent on utang).
    """
    from apps.inventory.models import VariantUOM
    from .exceptions import ReturnError

    with transaction.atomic():
        original = None
        if original_transaction_id is not None:
            original = SalesTransaction.objects.get(pk=original_transaction_id)
            if original.source == SalesTransaction.Source.RETURN:
                raise ReturnError('A return cannot reverse another return.')
            if original.status != SalesTransaction.Status.COMPLETED:
                raise ReturnError(
                    'Only a completed sale can be reversed.')
        # Phase 4 (decision 06): a refund is cash OUT OF THE DRAWER, so it has to belong
        # to the shift that paid it or the Z-reading never sees the money leave and its
        # "expected drawer" is overstated by every refund of the day.
        #
        # ATTACHED, not required, unlike process_sale. The gate ruling is about ringing
        # sales; a return recorded without an open shift still has to be storable, so a
        # missing shift leaves the FK null rather than refusing the refund.
        from .models import Shift
        open_shift = Shift.objects.filter(
            cashier=cashier, status=Shift.Status.OPEN).first()
        txn = SalesTransaction.objects.create(
            customer_id=customer_id,
            cashier=cashier,
            shift=open_shift,
            transaction_no=generate_transaction_no(),
            source=SalesTransaction.Source.RETURN,
            original_transaction=original,
            vatable_sales=0,
            vat_amount=0,
            discount_amount=0,
            grand_total=0,
        )
        if payment_method not in dict(Payment.Method.choices):
            raise ReturnError(
                f'Unknown payment method: {payment_method}.')
        total = Decimal('0')
        for item in items_data:
            item_id = item['variant_id']
            qty = Decimal(str(item.get('qty', 0)))
            unit_price = Decimal(str(item.get('unit_price', 0)))
            if qty <= 0:
                raise ReturnError(
                    'Return lines carry the positive qty coming back.')
            if unit_price < 0:
                raise ReturnError(
                    'Return lines carry a non-negative unit price; the server negates.')
            item_row = SalesItem.objects.create(
                transaction=txn,
                variant_uom_id=item_id,
                qty=-qty,
                unit_price=unit_price,
                subtotal=-(qty * unit_price),
            )
            # Same vuom-or-variant resolution as process_sale.
            variant_id = item_id
            vuom = VariantUOM.objects.filter(
                pk=item_id).select_related('variant').first()
            if vuom is not None:
                variant_id = vuom.variant_id
            _restock_returned(
                variant_id=variant_id, qty_needed=qty,
                original_id=original.id if original else None,
                return_item=item_row)
            total += -(qty * unit_price)
        txn.vatable_sales = total
        txn.grand_total = total
        txn.save(update_fields=['vatable_sales', 'grand_total'])
        Payment.objects.create(
            transaction=txn,
            method=payment_method,
            amount_tendered=total,
            reference_no='',
        )
        OfficialReceipt.objects.create(
            transaction=txn,
            or_number=generate_or_number(),
            terminal_no='POS-01',
        )
    return txn