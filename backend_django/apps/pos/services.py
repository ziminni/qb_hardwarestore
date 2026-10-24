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
from decimal import Decimal, InvalidOperation
from django.db import transaction
from apps.collectibles.models import CollectibleLedger
from apps.inventory.services import allocate_fifo

from .exceptions import CreditLimitExceeded, InvalidSale, WalkInCannotOwe
from .models import Customer, SalesTransaction, SalesItem, Payment, OfficialReceipt

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


def _parse_decimal(raw, *, field, line_no):
    """Parse a client-supplied number, or refuse the sale.

    `Decimal(str(None))` raises ConversionSyntax, `Decimal('NaN')` and
    `Decimal('Infinity')` parse happily and then poison the arithmetic (`min(stock,
    Infinity)` empties the shelf). Both are 400s, not 500s.
    """
    try:
        value = Decimal(str(raw))
    except (InvalidOperation, TypeError, ValueError):
        raise InvalidSale(f'Line {line_no}: {field} must be a number.') from None
    if not value.is_finite():
        raise InvalidSale(f'Line {line_no}: {field} must be a finite number.')
    return value


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
        raise InvalidSale('A sale needs at least one item.')
    if len(items_data) > MAX_SALE_LINES:
        raise InvalidSale(
            f'A sale cannot carry more than {MAX_SALE_LINES} items.')

    lines = []
    for index, item in enumerate(items_data, start=1):
        if not isinstance(item, dict):
            raise InvalidSale(f'Line {index}: each item must be an object.')
        raw_uom_id = item.get('variant_id')
        try:
            vuom = (
                VariantUOM.objects
                .select_related('variant', 'variant__product')
                .filter(pk=raw_uom_id)
                .first()
            )
        except (TypeError, ValueError):
            vuom = None
        if vuom is None:
            raise InvalidSale(
                f'Line {index}: {raw_uom_id!r} is not a selling unit of any product.')
        if not vuom.variant.is_active:
            raise InvalidSale(
                f'Line {index}: {vuom.variant} is no longer available for sale.')
        if not vuom.variant.product.is_active:
            raise InvalidSale(
                f'Line {index}: {vuom.variant.product} is no longer available for '
                'sale.')
        qty = _parse_decimal(item.get('qty'), field='qty', line_no=index)
        if qty <= 0:
            raise InvalidSale(f'Line {index}: qty must be greater than zero.')
        lines.append((vuom, qty))
    return lines


def _validated_payments(payments_data):
    """Validate the tender before any write: method known, amount non-negative.

    An EMPTY list stays valid - a cash sale with nothing tendered is the walk-in shortfall
    path, which decision 14 answers with its own 400 (WalkInCannotOwe) or a ledger row for
    a named customer. `amount_tendered` is never trusted to equal the total; it is what the
    cashier took, and the shortfall is computed from the server's price.
    """
    if payments_data is None:
        payments_data = []
    if not isinstance(payments_data, (list, tuple)):
        raise InvalidSale('payments must be a list.')
    methods = dict(Payment.Method.choices)
    payments = []
    for index, pdata in enumerate(payments_data, start=1):
        if not isinstance(pdata, dict):
            raise InvalidSale(f'Payment {index}: each payment must be an object.')
        method = pdata.get('method', Payment.Method.CASH)
        if method not in methods:
            raise InvalidSale(
                f'Payment {index}: {method!r} is not a payment method this till takes.')
        amount = _parse_decimal(
            pdata.get('amount_tendered', 0), field='amount_tendered', line_no=index)
        if amount < 0:
            raise InvalidSale(
                f'Payment {index}: amount_tendered cannot be negative.')
        payments.append({
            'method': method,
            'amount_tendered': amount,
            'reference_no': pdata.get('reference_no') or '',
        })
    return payments


def _outstanding_credit(customer_id):
    """What the customer already owes, as the credit limit counts it (decision 08).

    Only OPEN/PARTIAL/OVERDUE balances_due count - a PAID ledger is settled, so summing
    it would count history instead of debt. Read AFTER the caller has locked the
    customer row, so concurrent credit sales see each other's ledgers rather than both
    reading the same total and both passing the check.
    """
    from django.db.models import Sum

    total = (
        CollectibleLedger.objects
        .filter(customer_id=customer_id, status__in=OUTSTANDING_LEDGER_STATUSES)
        .aggregate(total=Sum('balance_due'))['total']
    )
    return total or Decimal('0')


def process_sale(*, customer_id, cashier, items_data, payments_data, source='WALK_IN'):
    """Process a complete walk-in sale or requisition release.

    items_data: [{'variant_id': <VariantUOM id>, 'qty': 5}]
    payments_data: [{'method': 'CASH', 'amount_tendered': Decimal('750')}]

    Decision 01 (uom-and-price-authority):

    * the SELLING unit is a `VariantUOM` id, never a bare product-variant id;
    * `unit_price` is `VariantUOM.default_selling_price` - a client-sent `unit_price`
      is ignored, not rejected, so an older client keeps working;
    * FIFO deducts `qty x conversion_factor` BASE units while `SalesItem.qty` keeps the
      selling quantity, so the receipt reads "1 box" and the shelf loses 12 pieces.

    `InvalidSale` is raised before the atomic block: a refused cart must leave no
    transaction, no receipt, no payment and no moved stock, and raising before the first
    `create()` makes that true by construction rather than by rollback.
    """
    lines = _validated_sale_lines(items_data)
    payments = _validated_payments(payments_data)

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

        for vuom, qty in lines:
            # Decision 01: the server prices the line. `item.get('unit_price')` is never
            # read again - a forged or stale price is not an error, it is simply not input.
            unit_price = vuom.default_selling_price
            subtotal = qty * unit_price

            item_row = SalesItem.objects.create(
                transaction=txn,
                variant_uom=vuom,
                qty=qty,
                unit_price=unit_price,
                subtotal=subtotal,
            )

            # Decision 01: FIFO works in BASE units. Selling 1 box of 12 must remove 12
            # pieces from the shelf while `SalesItem.qty` above keeps the 1 for the
            # receipt - the two numbers answer different questions.
            base_qty = qty * vuom.conversion_factor
            # Raises InsufficientStock on short stock → whole sale rolls back.
            allocations = allocate_fifo(
                variant_id=vuom.variant_id, qty_needed=base_qty)
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

        # Payments (already validated above: method known, amount non-negative).
        total_paid = Decimal('0')
        for pdata in payments:
            Payment.objects.create(
                transaction=txn,
                method=pdata['method'],
                amount_tendered=pdata['amount_tendered'],
                reference_no=pdata['reference_no'],
            )
            total_paid += pdata['amount_tendered']

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
            # Decision 08: lock the customer row BEFORE reading their outstanding
            # balances. Two tills ringing credit sales for the same customer at the
            # same moment would otherwise both read the same outstanding, both pass
            # the check and both write - and the customer ends up over the limit by a
            # whole sale. The lock serializes them; the second one re-reads the first
            # one's ledger. Released by the enclosing atomic block.
            customer = (
                Customer.objects.select_for_update()
                .only('customer_type', 'name', 'total_credit_limit')
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
        SalesItem.objects
        .filter(transaction=original, variant_uom=vuom)
        .order_by('id')
        .first()
    )
    if original_line is None:
        raise ReturnError(
            f'{vuom} was not on the original sale, so it cannot be refunded against it.')
    return original_line.unit_price


def process_return(*, customer_id, cashier, items_data,
                   original_transaction_id=None, payment_method='CASH'):
    """Post a customer return: a RETURN transaction with negative amounts.

    items_data mirrors process_sale but POSITIVE (what comes back):
    [{'variant_id': <VariantUOM id>, 'qty': 5}].
    Lines store negative qty (direction) at a positive unit price; the payment
    is the negative refund. Validators do not run on objects.create(), and no
    full_clean path creates sale items — see the 6A.4 ledger note.
    Collectibles are deliberately untouched (decision 15 is silent on utang).

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
    """
    from .exceptions import ReturnError

    lines = _validated_sale_lines(items_data)
    if payment_method not in dict(Payment.Method.choices):
        raise ReturnError(
            f'Unknown payment method: {payment_method}.')

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
        for vuom, qty in lines:
            unit_price = _return_unit_price(original=original, vuom=vuom)
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