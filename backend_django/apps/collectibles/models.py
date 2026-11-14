"""Collectibles (Accounts Receivable / Utang Management).

ERD mapping:
    COLLECTIBLE_LEDGER   → CollectibleLedger
    COLLECTIBLE_PAYMENT  → CollectiblePayment
"""

from datetime import date
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models

# Referencing the POS enum rather than copying it: the utang dialog and the till must
# offer the same tenders, and two lists would drift. `apps.pos.models` does not import
# this module at module level (it names the ledger by string), so there is no cycle.
from apps.pos.models import Payment


class CollectibleLedger(models.Model):
    """An outstanding receivable entry tied to a POS sales transaction."""

    class Status(models.TextChoices):
        OPEN = 'OPEN', 'Open'
        PARTIAL = 'PARTIAL', 'Partial'
        PAID = 'PAID', 'Paid'
        OVERDUE = 'OVERDUE', 'Overdue'

    customer = models.ForeignKey(
        'pos.Customer',
        on_delete=models.PROTECT,
        related_name='collectible_ledgers',
    )
    transaction = models.ForeignKey(
        'pos.SalesTransaction',
        on_delete=models.PROTECT,
        related_name='collectible_ledgers',
    )
    # Decision 03: the contractor stays the payer, but the utang has to say WHICH project
    # owes it. Set by `release_materials` only, so walk-in sales carry none.
    project = models.ForeignKey(
        'requisitions.Project',
        on_delete=models.PROTECT,
        related_name='ledger_entries',
        null=True,
        blank=True,
    )
    original_amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    balance_due = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.00'))],
    )
    due_date = models.DateField()
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.OPEN,
        db_index=True,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'collectibles_ledger'
        verbose_name = 'collectible ledger'
        verbose_name_plural = 'collectible ledgers'
        ordering = ['-due_date']
        indexes = [
            models.Index(fields=['status']),
            models.Index(fields=['customer']),
            models.Index(fields=['customer', 'status']),
        ]

    def __str__(self):
        return (
            f'Ledger #{self.pk} — {self.customer} '
            f'(Bal: {self.balance_due}, {self.status})'
        )

    @property
    def is_overdue(self) -> bool:
        """Return True when the balance is unpaid past the due date."""
        return self.balance_due > 0 and self.due_date < date.today()


class CollectiblePayment(models.Model):
    """A payment posted against a collectible ledger entry."""

    collectible = models.ForeignKey(
        CollectibleLedger,
        on_delete=models.PROTECT,
        related_name='payments',
    )
    processed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='+',
    )
    amount_paid = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    payment_method = models.CharField(
        max_length=50,
        # Phase 4 task B2 (decision 18): the utang payment dialog offers the SAME methods
        # the till does, so the shared `Payment.Method` list is the contract rather than a
        # second copy of it. The column stays varchar(50) - unchanged, so rows written
        # before Phase 1 keep their value and stay readable; adding choices does not
        # rewrite or constrain stored data, and the server's own `RETURN_CREDIT` marker
        # (decision 05) is written by `process_return`, not by a client.
        choices=Payment.Method.choices,
    )
    payment_date = models.DateTimeField(auto_now_add=True)
    official_receipt_no = models.CharField(
        max_length=100,
        blank=True,
        default='',
    )

    class Meta:
        db_table = 'collectibles_payment'
        verbose_name = 'collectible payment'
        verbose_name_plural = 'collectible payments'
        ordering = ['-payment_date']
        indexes = [
            models.Index(fields=['collectible', '-payment_date']),
        ]

    def __str__(self):
        return (
            f'Payment #{self.pk} — Ledger #{self.collectible_id} '
            f'({self.amount_paid})'
        )
