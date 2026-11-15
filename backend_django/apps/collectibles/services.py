"""Business logic for the collectibles (accounts receivable) module.

Posting a payment must MOVE THE LEDGER. Until 2026-10-17 it did not: the viewset
saved the `CollectiblePayment` and left `balance_due` and `status` untouched, so
every consumer of a receivable - the aging report, the till's utang panel, the
sales receivables screen - reported a balance that ignored every payment ever
made. A customer who had paid in full still read as owing the full amount.

The two tests that appeared to cover this did the arithmetic THEMSELVES
(`tests.py`, old `test_payment_records_against_ledger` and
`test_full_payment_pays_ledger` each assigned `balance_due` by hand after
creating the payment). They therefore passed against the broken code and could
not have caught it: they asserted that the test could subtract.
"""

from decimal import Decimal

from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.requisitions.exceptions import UnknownProject
from apps.requisitions.models import Project

from .models import CollectibleLedger, CollectiblePayment, ProjectPaymentReceipt


class ReceiptDecisionError(Exception):
    """Raised when a payment receipt decision (approve/decline) is invalid."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


class Overpayment(Exception):
    """A payment larger than the balance still owed.

    Refused rather than accepted-and-clamped: silently keeping the difference
    would either invent a credit the books do not hold or swallow money the
    customer handed over, and neither is recoverable after the fact.
    """

    code = 'PAYMENT_EXCEEDS_BALANCE'

    def __init__(self, balance_due, amount):
        self.balance_due = balance_due
        self.amount = amount
        super().__init__(
            f'That payment of {amount:.2f} is more than the {balance_due:.2f} '
            f'still owed on this account.'
        )


def apply_payment_to_ledger(ledger, amount_paid):
    """Move one ledger by one payment, and return it.

    The CALLER owns the transaction: this must not be wrapped here, or a payment
    could be committed without the balance moving (or the reverse). It also must
    not be called without the ledger locked, which is why the viewset takes
    `select_for_update` before calling it - two terminals paying the last few
    pesos at the same moment would otherwise both see the old balance and one
    payment would vanish.
    """
    amount = Decimal(amount_paid)
    if amount > ledger.balance_due:
        raise Overpayment(ledger.balance_due, amount)

    ledger.balance_due = ledger.balance_due - amount
    ledger.status = (
        CollectibleLedger.Status.PAID
        if ledger.balance_due == 0
        else CollectibleLedger.Status.PARTIAL
    )
    ledger.save(update_fields=['balance_due', 'status', 'updated_at'])
    return ledger


def receipt_wire(receipt: ProjectPaymentReceipt) -> dict:
    """Serialize a ProjectPaymentReceipt for the CPMS boundary or staff API."""
    return {
        'id': receipt.pk,
        'cpms_payment_id': receipt.cpms_payment_id,
        'cpms_project_id': receipt.project.cpms_project_id,
        'project_name': receipt.project.name,
        'customer_name': receipt.project.customer.name,
        'amount': f'{receipt.amount:.2f}',
        'approved_amount': (
            None if receipt.approved_amount is None else f'{receipt.approved_amount:.2f}'
        ),
        'payment_method': receipt.payment_method,
        'reference_no': receipt.reference_no,
        'notes': receipt.notes,
        'submitted_by_name': receipt.submitted_by_name,
        'status': receipt.status,
        'decline_reason': receipt.decline_reason,
        'decided_at': receipt.decided_at.isoformat() if receipt.decided_at else None,
        'created_at': receipt.created_at.isoformat(),
    }


def list_cpms_payment_receipts(*, cpms_project_id: str) -> list[dict]:
    """List all payment receipts submitted for a CPMS project."""
    project = (
        Project.objects.select_related('customer')
        .filter(cpms_project_id=cpms_project_id)
        .first()
    )
    if project is None:
        raise UnknownProject(cpms_project_id)
    receipts = (
        ProjectPaymentReceipt.objects.select_related('project__customer')
        .filter(project=project)
        .order_by('-created_at', '-id')
    )
    return [receipt_wire(r) for r in receipts]


def submit_cpms_payment_receipt(
    *,
    cpms_project_id: str,
    cpms_payment_id: str,
    amount: Decimal,
    payment_method: str,
    reference_no: str,
    notes: str = '',
    submitted_by_name: str = '',
) -> dict:
    """Idempotently record a CPMS online payment receipt in WAITING state."""
    existing = (
        ProjectPaymentReceipt.objects.select_related('project__customer')
        .filter(cpms_payment_id=cpms_payment_id)
        .first()
    )
    if existing is not None:
        return {'created': False, 'receipt': receipt_wire(existing)}

    project = (
        Project.objects.select_related('customer')
        .filter(cpms_project_id=cpms_project_id)
        .first()
    )
    if project is None:
        raise UnknownProject(cpms_project_id)

    try:
        with transaction.atomic():
            receipt = ProjectPaymentReceipt.objects.create(
                project=project,
                cpms_payment_id=cpms_payment_id,
                amount=Decimal(amount),
                payment_method=payment_method,
                reference_no=reference_no.strip(),
                notes=(notes or '').strip(),
                submitted_by_name=(submitted_by_name or '').strip(),
                status=ProjectPaymentReceipt.Status.WAITING,
            )
    except IntegrityError:
        winner = (
            ProjectPaymentReceipt.objects.select_related('project__customer')
            .filter(cpms_payment_id=cpms_payment_id)
            .first()
        )
        if winner is not None:
            return {'created': False, 'receipt': receipt_wire(winner)}
        raise

    return {'created': True, 'receipt': receipt_wire(receipt)}


def approve_payment_receipt(
    *,
    receipt_id: int,
    actor,
    approved_amount: Decimal | None = None,
) -> ProjectPaymentReceipt:
    """Approve a WAITING payment receipt (full or partial) and post ledger payments oldest-first."""
    with transaction.atomic():
        receipt = (
            ProjectPaymentReceipt.objects.select_for_update()
            .select_related('project__customer')
            .filter(pk=receipt_id)
            .first()
        )
        if receipt is None:
            raise ReceiptDecisionError('RECEIPT_NOT_FOUND', 'Payment receipt not found.')
        if receipt.status != ProjectPaymentReceipt.Status.WAITING:
            raise ReceiptDecisionError(
                'RECEIPT_ALREADY_DECIDED',
                f'This payment receipt is already {receipt.status}.',
            )
        target_amount = (
            Decimal(approved_amount) if approved_amount is not None else receipt.amount
        )
        if target_amount <= Decimal('0.00'):
            raise ReceiptDecisionError(
                'INVALID_APPROVED_AMOUNT',
                'Approved amount must be greater than zero.',
            )
        if target_amount > receipt.amount:
            raise ReceiptDecisionError(
                'APPROVED_EXCEEDS_SUBMITTED',
                'Approved amount cannot exceed the submitted receipt amount.',
            )

        ledgers = list(
            CollectibleLedger.objects.select_for_update()
            .select_related('transaction')
            .filter(project=receipt.project, balance_due__gt=Decimal('0.00'))
            .order_by('due_date', 'id')
        )
        total_owed = sum((l.balance_due for l in ledgers), Decimal('0.00'))
        if target_amount > total_owed:
            raise Overpayment(total_owed, target_amount)

        remaining = target_amount
        for ledger in ledgers:
            if remaining <= Decimal('0.00'):
                break
            chunk = min(ledger.balance_due, remaining)
            apply_payment_to_ledger(ledger, chunk)
            CollectiblePayment.objects.create(
                collectible=ledger,
                processed_by=actor,
                payment_receipt=receipt,
                amount_paid=chunk,
                payment_method=receipt.payment_method,
                official_receipt_no=receipt.reference_no,
            )
            remaining -= chunk

        receipt.status = ProjectPaymentReceipt.Status.APPROVED
        receipt.approved_amount = target_amount
        receipt.decided_by = actor
        receipt.decided_at = timezone.now()
        receipt.save(
            update_fields=[
                'status',
                'approved_amount',
                'decided_by',
                'decided_at',
                'updated_at',
            ]
        )
        return receipt


def decline_payment_receipt(
    *,
    receipt_id: int,
    actor,
    reason: str,
) -> ProjectPaymentReceipt:
    """Decline a WAITING payment receipt with a required reason."""
    cleaned_reason = (reason or '').strip()
    if not cleaned_reason:
        raise ReceiptDecisionError(
            'REASON_REQUIRED',
            'Give a reason for declining this payment receipt.',
        )
    with transaction.atomic():
        receipt = (
            ProjectPaymentReceipt.objects.select_for_update()
            .select_related('project__customer')
            .filter(pk=receipt_id)
            .first()
        )
        if receipt is None:
            raise ReceiptDecisionError('RECEIPT_NOT_FOUND', 'Payment receipt not found.')
        if receipt.status != ProjectPaymentReceipt.Status.WAITING:
            raise ReceiptDecisionError(
                'RECEIPT_ALREADY_DECIDED',
                f'This payment receipt is already {receipt.status}.',
            )
        receipt.status = ProjectPaymentReceipt.Status.DECLINED
        receipt.decline_reason = cleaned_reason
        receipt.decided_by = actor
        receipt.decided_at = timezone.now()
        receipt.save(
            update_fields=[
                'status',
                'decline_reason',
                'decided_by',
                'decided_at',
                'updated_at',
            ]
        )
        return receipt
