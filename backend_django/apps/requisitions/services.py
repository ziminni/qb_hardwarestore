# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directive and reason as apps/pos/tests.py and seed_demo.py: this checker runs
# with a working directory outside the repo, so the root pyrightconfig.json (which
# already sets both rules to "warning") is not found and they escalate to errors.
# Without django-stubs, `Model.objects`, FK-attribute assignment and
# `transaction.atomic()` are all false positives on valid Django. The test run is the
# authority.
"""Requisitions services — token verification, material release, the CPMS import.

Decision 01: the POS no longer requests or approves material (CPMS does both), so the
submit/approve/reject transitions and their separation-of-duties guard are gone. What is
left here is what the till and the CPMS push need: `generate_req_number`, `verify_token`,
`release_materials`, `import_request`, and — from Phase 1 Task 6 — `close_requisition`,
`request_read_back` and `project_payables` (decisions 06 and 07).
"""

from datetime import date
from decimal import ROUND_DOWN, Decimal
from uuid import UUID

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import InventoryBatch, VariantUOM, normalise_barcode
from apps.inventory.services import allocate_fifo, check_low_stock_after_stock_out
from apps.pos.exceptions import NoOpenShift
from apps.pos.models import (
    Customer,
    OfficialReceipt,
    SalesItem,
    SalesTransaction,
    Shift,
)
from apps.pos.services import generate_or_number, generate_transaction_no
from common.numbering import generate_document_number

from .exceptions import (
    DuplicateMaterial,
    NothingToRelease,
    RequestCancelled,
    RequisitionNotReleasable,
    TokenTaken,
    UnknownMaterial,
    UnknownPayer,
    UnknownProject,
    UnknownRequest,
)
from .models import MaterialToken, Project, Requisition, RequisitionItem

# The customers a project may bill: the same pair as `Project.customer`'s
# `limit_choices_to` and as `PAYER_CUSTOMER_TYPES` in `apps/integration/views.py`. Restated
# as data here because `limit_choices_to` is a form/admin hint a service cannot ask.
PAYER_CUSTOMER_TYPES = ('CONTRACTOR', 'CONSTRUCTION_FIRM')


def generate_req_number():
    """Kept as the Requisition-specific name; the pattern itself lives in common.numbering."""
    return generate_document_number(Requisition, 'req_number', 'REQ')


# Units sold only in whole counts. Mirrors `wholeUnitCodes` in
# flutter/lib/core/units/whole_units.dart (Phase 6 decision 17): keep the two in step.
WHOLE_UNIT_CODES = frozenset({'pc', 'piece', 'bag', 'box', 'sheet', 'roll', 'pack'})


def releasable_qty(*, remaining: Decimal, available_base: Decimal,
                   conversion_factor: Decimal, unit_code: str) -> Decimal:
    """How much of one requested line can leave the store now, in the line's selling unit.

    Decision 05: release what is there, never more than is still outstanding.
    - `remaining`: still outstanding on the line, in its selling unit (e.g. 3 boxes).
    - `available_base`: stock on hand in BASE units across the variant's batches.
    - `conversion_factor`: base units per one selling unit (a box of 12 -> 12).
    - `unit_code`: the selling unit's code; whole units (WHOLE_UNIT_CODES, any case,
      surrounding spaces ignored) only release whole counts, measured units release to
      2 decimal places. Always round DOWN, never past what is on the shelf.
    Returns a Decimal with 2 decimal places, 0.00 when nothing can go.
    """
    on_shelf = max(available_base, Decimal('0')) / conversion_factor
    step = Decimal('1') if unit_code.strip().lower() in WHOLE_UNIT_CODES else Decimal('0.01')
    return min(remaining, on_shelf).quantize(step, rounding=ROUND_DOWN).quantize(Decimal('0.01'))


class Availability:
    """What the till shows next to one requested line before the cashier confirms.

    Decision 05: the cashier sees each line as full, short (with what is available) or
    unavailable, so a short shelf is a fact on screen instead of a refused release.
    """

    FULL = 'FULL'                # everything still outstanding can leave now
    SHORT = 'SHORT'              # some of it can
    UNAVAILABLE = 'UNAVAILABLE'  # nothing can: archived, or nothing on the shelf
    DONE = 'DONE'                # nothing left to release: an earlier scan took it all


# Messages for the statuses that can never be released (decision 05/06). Spelled per
# status because "CLOSED" tells the cashier to call CPMS, and "already RELEASED" tells
# them somebody has already been served with this token.
_REFUSED_STATUSES = {
    Requisition.Status.CLOSED:
        'Requisition is CLOSED: its request was closed and the token is dead.',
    Requisition.Status.RELEASED:
        'Requisition is already RELEASED: nothing is outstanding on it.',
    Requisition.Status.CANCELLED:
        'Requisition is CANCELLED: nothing may be released for it.',
}


def _refuse_status(status):
    """Raise for a request no release may touch (decision 05: APPROVED/PARTIAL only)."""
    if status in _REFUSED_STATUSES:
        raise RequisitionNotReleasable(status, _REFUSED_STATUSES[status])
    raise ValueError(f'Requisition is {status}, not APPROVED or PARTIAL.')


def _token_for_release(token_value: str):
    """The scanned token, with every refusal the till must answer by name."""
    try:
        uuid_val = UUID(token_value)
    except ValueError:
        raise ValueError('Invalid token format.') from None
    try:
        token_obj = MaterialToken.objects.select_related(
            'requisition__project__customer').get(token=uuid_val)
    except MaterialToken.DoesNotExist:
        raise ValueError('Token not found.') from None
    if token_obj.is_used:
        raise ValueError('Token has already been used.')
    if token_obj.requisition.status not in (
            Requisition.Status.APPROVED, Requisition.Status.PARTIAL):
        _refuse_status(token_obj.requisition.status)
    return token_obj


def _on_hand_base(variant_ids) -> dict:
    """Base units on the shelf per variant — the same batches `allocate_fifo` takes.

    `current_qty__gt=0`, like the allocator: an emptied batch is history, not stock.
    """
    rows = (
        InventoryBatch.objects
        .filter(variant_id__in=variant_ids, current_qty__gt=0)
        .values('variant_id')
        .annotate(total=Sum('current_qty'))
    )
    return {row['variant_id']: row['total'] for row in rows}


def _release_plan(requisition) -> list:
    """Per-line plan for what can leave the store NOW, in line order.

    Decision 05: `releasable` is capped by the line's own outstanding quantity and by the
    shelf, and two lines on ONE variant share that shelf — the second is told what the
    first will take, so the plan can never promise the same stock twice. A line whose
    variant or product is archived takes nothing, whatever its batches still hold.

    Read by `verify_token` (what the cashier sees) and again by `release_materials` under
    the token's row lock (what is written), so both use one rule.
    """
    items = list(
        RequisitionItem.objects
        .select_related('variant_uom__variant__product', 'variant_uom__uom')
        .filter(requisition=requisition)
        .order_by('pk')
    )
    on_hand = _on_hand_base({item.variant_uom.variant_id for item in items})
    plan = []
    for item in items:
        variant = item.variant_uom.variant
        remaining = item.quantity - item.released_qty
        archived = not variant.is_active or not variant.product.is_active
        if archived or remaining <= 0:
            releasable = Decimal('0.00')
        else:
            available = on_hand.get(variant.pk, Decimal(0))
            releasable = releasable_qty(
                remaining=remaining,
                available_base=available,
                conversion_factor=item.variant_uom.conversion_factor,
                unit_code=item.variant_uom.uom.code,
            )
            on_hand[variant.pk] = available - releasable * item.variant_uom.conversion_factor
        plan.append({'item': item, 'remaining': remaining,
                     'releasable': releasable, 'archived': archived})
    return plan


def _availability(line) -> str:
    """Decision 05's three words for one planned line, plus DONE for a finished one."""
    if line['remaining'] <= 0:
        return Availability.DONE
    if line['archived'] or line['releasable'] <= 0 < line['remaining']:
        return Availability.UNAVAILABLE
    if line['releasable'] < line['remaining']:
        return Availability.SHORT
    return Availability.FULL


def verify_token(*, token_value: str) -> dict:
    """Validate a material token and describe what could leave the store right now.

    Decision 05: an APPROVED request and a PARTIAL one are both releasable (the token
    stays alive until every line is out); CLOSED, RELEASED and CANCELLED are refused by
    name. Each line carries its `availability` and the `releasable` quantity, which is
    what the cashier confirms against.
    """
    token_obj = _token_for_release(token_value)
    req = token_obj.requisition
    return {
        'token': str(token_obj.token),
        'requisition': {
            'id': req.id, 'req_number': req.req_number,
            'project': req.project.name, 'customer': req.project.customer.name,
        },
        # Wire shape unchanged for the till (decision 04 changed the column, not the
        # screen): `variant_id` is still the PRODUCT VARIANT id and `variant_name` the
        # same label; the quantity is now counted in the line's own selling unit.
        'items': [
            {'id': line['item'].id,
             'variant_id': line['item'].variant_uom.variant_id,
             'variant_name': str(line['item'].variant_uom.variant),
             'quantity': str(line['item'].quantity),
             'remaining': str(line['remaining']),
             'availability': _availability(line),
             'releasable': str(line['releasable'])}
            for line in _release_plan(req)
        ],
    }


def release_materials(*, token_value: str, cashier) -> dict:
    """Release what the shelf holds for this token (UC-21 + UC-22, decision 05).

    FIFO-deducts stock, creates ONE SalesTransaction (source=REQUISITION) with ONE
    receipt and ONE CollectibleLedger tagged with the request's project, for exactly what
    left the store.

    Decision 05: a short, out-of-stock or archived line no longer fails the whole
    release. `_release_plan` is recomputed under the token's row lock and only lines with
    `releasable > 0` are written; the rest keep their outstanding quantity. Nothing
    releasable anywhere raises `NothingToRelease` before the first write (400
    `NOTHING_TO_RELEASE`, no rows at all). Every line finished -> status RELEASED and the
    token is spent; otherwise PARTIAL and the same token works again after a restock.

    Decision 04: a line carries its own SELLING unit (`RequisitionItem.variant_uom`), so
    the price is that unit's `default_selling_price` with no lookup and no fallback — the
    "no base unit to price with" failure mode (400 `NO_BASE_UOM`) cannot happen any more.
    FIFO deducts `released x conversion_factor` BASE units while `SalesItem.qty` keeps the
    selling quantity — the same rule `process_sale` follows, and the reason the receipt
    reads "2 boxes" while the shelf loses 24 pieces.

    Decision 03: a release is a SALE for accountability purposes — it moves stock and
    books money owed — so the releasing cashier needs their OPEN shift, exactly like
    `process_sale`. The gate sits inside the atomic block, after the token row lock and
    BEFORE the first write, so a refused release leaves no transaction, no receipt, no
    ledger, no moved stock, no consumed token and no RELEASE audit row (the view writes
    that row in the same transaction). The shift is then attached to the resulting
    `SalesTransaction`, which is what puts the release inside the Z-reading.
    """
    token_obj = _token_for_release(token_value)
    req = token_obj.requisition
    customer = req.project.customer

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

        # Decision 05: recomputed UNDER the token lock, so two scans of one token (or
        # two tills holding the same token) cannot promise the same stock twice.
        plan = _release_plan(req)
        releasing = [line for line in plan if line['releasable'] > 0]
        if not releasing:
            raise NothingToRelease()

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

        for line in releasing:
            item = line['item']
            qty = line['releasable']
            vuom = item.variant_uom
            unit_price = vuom.default_selling_price

            allocate_fifo(
                variant_id=vuom.variant_id,
                qty_needed=qty * vuom.conversion_factor)
            affected_variant_ids.add(vuom.variant_id)

            subtotal = qty * unit_price
            SalesItem.objects.create(
                transaction=txn, variant_uom=vuom,
                qty=qty, unit_price=unit_price, subtotal=subtotal)
            grand_total += subtotal
            item.released_qty += qty
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
            # Decision 03: the utang of a release always carries its project, so
            # receivables can be totalled per project as well as per contractor.
            project=req.project,
            original_amount=grand_total, balance_due=grand_total,
            due_date=date.today() + date.resolution * 30,
            status=CollectibleLedger.Status.OPEN,
        )

        # Decision 05: the token dies only when every line is out. A PARTIAL request keeps
        # it alive, because that is how the project comes back for the rest.
        fully_released = all(
            line['remaining'] - line['releasable'] <= 0 for line in plan)
        if fully_released:
            token_obj.is_used = True
            token_obj.used_at = timezone.now()
            token_obj.used_by = cashier
            token_obj.save(update_fields=['is_used', 'used_at', 'used_by'])
            req.status = Requisition.Status.RELEASED
        else:
            req.status = Requisition.Status.PARTIAL
        req.save(update_fields=['status', 'updated_at'])

    return {
        'transaction_id': txn.id,
        'transaction_no': txn.transaction_no,
        # The audit row (written by the view, inside this same transaction) names the
        # requisition by its DOCUMENT NUMBER - never by the token UUID, which is a bearer
        # credential (decision 07).
        'req_number': req.req_number,
        # Decision 05: the REQUEST's new status (PARTIAL or RELEASED) plus what this visit
        # moved and what is still owed on each line.
        'status': req.status,
        'items': [
            {'code': line['item'].variant_uom.barcode_qr,
             'released_now': str(line['releasable']),
             'outstanding': str(line['remaining'] - line['releasable'])}
            for line in plan
        ],
        'grand_total': str(grand_total),
        'ledger_id': ledger.id,
        'balance_due': str(ledger.balance_due),
    }


# ---------------------------------------------------------------------------
# CPMS push (Phase 1, Task 3 — decisions 02 and 04)
# ---------------------------------------------------------------------------

def _existing_requisition(cpms_request_id):
    """The copy a retried push found, or None — the ONE lookup the retry rule hangs on.

    Module level (not nested) so a test can blind it once and exercise the insert race.
    """
    return (
        Requisition.objects
        .filter(cpms_request_id=cpms_request_id)
        .prefetch_related('items__variant_uom')
        .first()
    )


def _request_copy(requisition):
    """The answer body for one stored request: identity, status and its lines."""
    return {
        'id': requisition.id,
        'req_number': requisition.req_number,
        'cpms_request_id': requisition.cpms_request_id,
        'status': requisition.status,
        'items': [
            {'code': item.variant_uom.barcode_qr, 'quantity': str(item.quantity)}
            for item in requisition.items.order_by('pk')
        ],
    }


def _payer(payer_id):
    """The POS customer a project bills, or 400 UNKNOWN_PAYER (P1, decision 03)."""
    payer = Customer.objects.filter(
        pk=payer_id,
        is_active=True,
        customer_type__in=PAYER_CUSTOMER_TYPES,
    ).first()
    if payer is None:
        raise UnknownPayer(payer_id)
    return payer


def _resolved_lines(items):
    """`[{code, quantity}]` -> `[(VariantUOM, quantity)]`, or a refusal naming the codes.

    A code is compared exactly as the till compares a scan (`normalise_barcode`), so a
    padded or lower-case code from CPMS still names its unit. Only units CPMS was SHOWN
    are accepted — active variant of an active product — because a code outside the
    material list is a code CPMS should never have held.
    """
    codes = [normalise_barcode(item['code']) for item in items]
    duplicated = sorted({code for code in codes if codes.count(code) > 1})
    if duplicated:
        raise DuplicateMaterial(duplicated)
    units = VariantUOM.objects.filter(
        barcode_qr__in=codes,
        variant__is_active=True,
        variant__product__is_active=True,
    )
    by_code = {unit.barcode_qr: unit for unit in units}
    unknown = [code for code in codes if code not in by_code]
    if unknown:
        raise UnknownMaterial(unknown)
    return [(by_code[code], item['quantity']) for code, item in zip(codes, items, strict=True)]


def _upsert_project(project_data, payer):
    """Create the project a push names, or update the row its CPMS id already owns.

    Project name and payer follow CPMS (decision 03): the same `cpms_project_id` is the
    same project, even when it was renamed or re-billed since the last push.
    """
    project, created = Project.objects.get_or_create(
        cpms_project_id=project_data['cpms_project_id'],
        defaults={'name': project_data['name'], 'customer': payer},
    )
    if created:
        return project
    changed = []
    if project.name != project_data['name']:
        project.name = project_data['name']
        changed.append('name')
    if project.customer_id != payer.pk:
        project.customer = payer
        changed.append('customer')
    if changed:
        project.save(update_fields=[*changed, 'updated_at'])
    return project


def import_request(*, cpms_request_id, token, project, requester_name,
                   approver_name, notes='', items):
    """Store the POS copy of one APPROVED CPMS request (decisions 02 and 04).

    Returns `{'created': bool, 'request': <answer body>}`. The caller answers `201` on
    create and `200` on a retry, and writes the audit row itself (it needs the request
    for the actor and the IP).

    Retry-safe by `cpms_request_id` (decision 02): the same push twice — even with a
    different payload — answers the FIRST copy unchanged, so CPMS can retry blindly and
    a late duplicate can never rewrite what the till already released against.

    Everything that can refuse runs BEFORE the first write (`_payer`, `_resolved_lines`,
    the token clash), and the writes sit in one transaction, so a refusal leaves no
    project, requisition, line or token row behind. The `IntegrityError` branch covers
    the one thing a read cannot: two identical pushes at the same instant, where the
    loser answers `200` with the winner's row instead of a `500`.
    """
    existing = _existing_requisition(cpms_request_id)
    if existing is not None:
        return {'created': False, 'request': _request_copy(existing)}

    payer = _payer(project['payer'])
    lines = _resolved_lines(items)
    if MaterialToken.objects.filter(token=token).exists():
        # Look again for this request before refusing: between the retry check above and
        # here, an identical push may have landed and stored exactly this token. The
        # retry rule wins over the clash rule, so CPMS's own retries stay `200`.
        winner = _existing_requisition(cpms_request_id)
        if winner is not None:
            return {'created': False, 'request': _request_copy(winner)}
        raise TokenTaken()

    try:
        with transaction.atomic():
            project_row = _upsert_project(project, payer)
            requisition = Requisition.objects.create(
                project=project_row,
                cpms_request_id=cpms_request_id,
                req_number=generate_req_number(),
                # CPMS only pushes what its project manager already approved, and the
                # names travel as text (decision 08): the POS has no approver account.
                status=Requisition.Status.APPROVED,
                requester_name=requester_name,
                approver_name=approver_name,
                notes=notes,
            )
            for variant_uom, quantity in lines:
                RequisitionItem.objects.create(
                    requisition=requisition, variant_uom=variant_uom,
                    quantity=quantity)
            MaterialToken.objects.create(requisition=requisition, token=token)
    except IntegrityError:
        # The loser of a race. Whoever inserted first owns the id; if it was not this
        # request, the token is somebody else's.
        winner = _existing_requisition(cpms_request_id)
        if winner is not None:
            return {'created': False, 'request': _request_copy(winner)}
        if MaterialToken.objects.filter(token=token).exists():
            raise TokenTaken() from None
        raise

    return {
        'created': True,
        'request': {
            'id': requisition.id,
            'req_number': requisition.req_number,
            'cpms_request_id': cpms_request_id,
            'status': requisition.status,
            'items': [
                {'code': variant_uom.barcode_qr, 'quantity': str(quantity)}
                for variant_uom, quantity in lines
            ],
        },
    }


# ---------------------------------------------------------------------------
# CPMS close and read-back (Phase 1, Task 6 — decisions 06 and 07)
# ---------------------------------------------------------------------------

def _stored_request(cpms_request_id):
    """The POS copy CPMS names, or `404 REQUEST_NOT_FOUND`."""
    requisition = Requisition.objects.filter(cpms_request_id=cpms_request_id).first()
    if requisition is None:
        raise UnknownRequest(cpms_request_id)
    return requisition


def _order_lines(requisition):
    """The request's lines in insertion order, with the units the wire body needs."""
    return list(
        RequisitionItem.objects
        .select_related('variant_uom')
        .filter(requisition=requisition)
        .order_by('pk')
    )


def request_read_back(*, cpms_request_id):
    """Decision 07: status plus each line's `requested`, `released` and `outstanding`.

    `outstanding` is the TRUE unreleased quantity even for a CLOSED request: the status
    says the remainder will never come, and the number says how much of it there was.
    Zeroing it would hide the shortfall the project manager accepted when closing.
    """
    requisition = _stored_request(cpms_request_id)
    return {
        'cpms_request_id': requisition.cpms_request_id,
        'req_number': requisition.req_number,
        'status': requisition.status,
        'items': [
            {'code': item.variant_uom.barcode_qr,
             'requested': str(item.quantity),
             'released': str(item.released_qty),
             'outstanding': str(item.quantity - item.released_qty)}
            for item in _order_lines(requisition)
        ],
    }


def _lock_request(cpms_request_id):
    """The request row, locked the way a cashier release locks it (decision 06).

    The TOKEN goes first because `release_materials` takes that lock before it touches
    anything else: a close therefore waits for a release already in flight (and then
    closes whatever that release left outstanding), or holds the lock itself so the
    release blocks and is refused by `is_used`. Locking the requisition as well keeps the
    two blockers in the same order in both paths, so neither can deadlock the other.
    """
    requisition = _stored_request(cpms_request_id)
    MaterialToken.objects.select_for_update().filter(requisition=requisition).first()
    return Requisition.objects.select_for_update().get(pk=requisition.pk)


def close_requisition(*, cpms_request_id):
    """Decision 06: CPMS closes an open remainder; the released part stays as it is.

    `APPROVED` and `PARTIAL` become `CLOSED` and their token is spent in the SAME
    transaction as the status change. `used_by` stays NULL: CPMS closed the request, no
    cashier handed anything out.

    A `RELEASED` or already `CLOSED` request is a no-op and answers the unchanged
    read-back, so a retried close is safe. `CANCELLED` is refused with `409`
    `REQUEST_CANCELLED` — cancel is a decision made here and a close must not paper over
    it. Nothing else is touched: no line, no sale, no ledger row.

    Returns `{'closed': bool, 'request': <read-back body>}`; the caller answers the body
    and writes the audit row only when `closed`.
    """
    with transaction.atomic():
        requisition = _lock_request(cpms_request_id)
        if requisition.status == Requisition.Status.CANCELLED:
            raise RequestCancelled(cpms_request_id)
        closed = requisition.status in (
            Requisition.Status.APPROVED, Requisition.Status.PARTIAL)
        if closed:
            requisition.status = Requisition.Status.CLOSED
            requisition.save(update_fields=['status', 'updated_at'])
            # `.update()` on purpose: `used_by` must stay NULL (no cashier spent it), and
            # the token is already locked by `_lock_request`, so nothing can read it
            # between the status change and this line.
            MaterialToken.objects.filter(requisition=requisition).update(
                is_used=True, used_at=timezone.now())
    return {'closed': closed,
            'request': request_read_back(cpms_request_id=cpms_request_id)}


def project_payables(*, cpms_project_id):
    """Decision 07: one project's utang — `total`, `paid`, `balance` as 2dp strings.

    Read from the project's own `CollectibleLedger` rows, which is also what the
    receivables screens read: `total` is what was ever owed (sum of `original_amount`),
    `balance` is what is still owed (`balance_due`), and `paid` is the difference. Every
    way a balance moves — a `POST ledger-payments/` payment, a return credit — is already
    reflected in `balance_due`, so no payment table is summed here and no rule can drift.
    """
    project = Project.objects.filter(cpms_project_id=cpms_project_id).first()
    if project is None:
        raise UnknownProject(cpms_project_id)
    totals = project.ledger_entries.aggregate(
        total=Sum('original_amount'), balance=Sum('balance_due'))
    total = totals['total'] or Decimal(0)
    balance = totals['balance'] or Decimal(0)
    return {
        'cpms_project_id': project.cpms_project_id,
        'total': f'{total:.2f}',
        'paid': f'{total - balance:.2f}',
        'balance': f'{balance:.2f}',
    }
