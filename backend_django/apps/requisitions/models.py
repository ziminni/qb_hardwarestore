# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/requisitions/services.py: this checker runs with a
# working directory outside the repo, so the root pyrightconfig.json is not found. Without
# django-stubs every `models.BooleanField(default=...)` and every FK attribute access
# reads as a type error on valid Django. The test run is the authority.
"""
Requisitions Module — Construction Material Requests (Phase 3).

CPMS creates a material request and its project manager approves it; the POS keeps a
read-only copy, the cashier releases it with a digital token, stock is FIFO-deducted,
and the amount posts to Collectibles. Decision 01 removed the POS-side request and
approval, so the requester and the approver here are NAMES, not accounts.

ERD extension (not in original ERD):
    PROJECT           → Project
    REQUISITION       → Requisition
    REQUISITION_ITEM  → RequisitionItem
    MATERIAL_TOKEN    → MaterialToken
"""

import uuid
from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class Project(models.Model):
    """A construction project linked to a contractor/construction-firm Customer."""

    name = models.CharField(max_length=255, db_index=True)
    # Decision 03: CPMS owns the project list. The id is how a second push finds the same
    # row again; legacy rows created in the POS have none.
    cpms_project_id = models.CharField(
        max_length=100, unique=True, null=True, blank=True)
    customer = models.ForeignKey(
        'pos.Customer',
        on_delete=models.PROTECT,
        related_name='projects',
        limit_choices_to={'customer_type__in': ['CONTRACTOR', 'CONSTRUCTION_FIRM']},
        help_text='The contractor / construction firm for this project.',
    )
    location = models.CharField(max_length=255, blank=True, default='')
    start_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True, db_index=True)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'requisitions_project'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.customer.name})'


class Requisition(models.Model):
    """An approved material request CPMS pushed, released by token at the POS."""

    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        SUBMITTED = 'SUBMITTED', 'Submitted'
        APPROVED = 'APPROVED', 'Approved'
        REJECTED = 'REJECTED', 'Rejected'
        PARTIAL = 'PARTIAL', 'Partially Released'
        RELEASED = 'RELEASED', 'Fully Released'
        CANCELLED = 'CANCELLED', 'Cancelled'
        # Decision 06: CPMS can close an open remainder. The token dies with it.
        CLOSED = 'CLOSED', 'Closed'

    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='requisitions',
    )
    # Decision 08: the POS has no foreman and no approver accounts any more, and the two
    # people are what CPMS reports, not who can log in here — so they are plain names.
    requester_name = models.CharField(max_length=255, blank=True, default='')
    approver_name = models.CharField(max_length=255, blank=True, default='')
    # Decision 04: CPMS's own id for this request, so a retried push finds the same copy.
    cpms_request_id = models.CharField(
        max_length=100, unique=True, null=True, blank=True)
    req_number = models.CharField(max_length=50, unique=True, db_index=True)
    status = models.CharField(
        max_length=12,
        choices=Status.choices,
        default=Status.DRAFT,
        db_index=True,
    )
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'requisitions_req'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['project', '-created_at']),
            models.Index(fields=['status']),
        ]

    def __str__(self):
        return f'REQ #{self.req_number} — {self.project.name} ({self.status})'


class RequisitionItem(models.Model):
    """Line item on a material requisition."""
    requisition = models.ForeignKey(
        Requisition,
        on_delete=models.CASCADE,
        related_name='items',
    )
    # Decision 04: a line keys on the SELLING unit CPMS was shown, so the till can release
    # it with one scan; `quantity` / `released_qty` are counted in that unit.
    variant_uom = models.ForeignKey(
        'inventory.VariantUOM',
        on_delete=models.PROTECT,
        related_name='requisition_items',
    )
    quantity = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal('0.01'))],
    )
    released_qty = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        validators=[MinValueValidator(Decimal('0'))],
    )
    notes = models.CharField(max_length=255, blank=True, default='')

    class Meta:
        db_table = 'requisitions_item'

    def __str__(self):
        return f'{self.variant_uom} × {self.quantity}'


class MaterialToken(models.Model):
    """One-time digital token (QR code) for POS material release.

    Minted by the CPMS push, with the request it belongs to (decision 02).
    Scanned by cashier at the hardware store POS to verify and release materials.
    """
    requisition = models.OneToOneField(
        Requisition,
        on_delete=models.CASCADE,
        related_name='token',
    )
    token = models.UUIDField(
        default=uuid.uuid4,
        unique=True,
        db_index=True,
    )
    is_used = models.BooleanField(default=False, db_index=True)
    used_at = models.DateTimeField(null=True, blank=True)
    used_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='+',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'requisitions_token'
        ordering = ['-created_at']

    def __str__(self):
        return f'Token {self.token} — REQ #{self.requisition.req_number}'
