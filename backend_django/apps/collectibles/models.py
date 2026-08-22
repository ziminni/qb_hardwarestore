"""Collectibles (Accounts Receivable / Utang Management).

ERD mapping:
    COLLECTIBLE_LEDGER   → CollectibleLedger
    COLLECTIBLE_PAYMENT  → CollectiblePayment
"""

from datetime import date

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from decimal import Decimal


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
    payment_method = models.CharField(max_length=50)
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
