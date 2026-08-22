"""
Requisitions Module — Construction Material Requests (Phase 3).

Supports the dual-business flow: site foreman requests materials,
manager approves, cashier releases via digital token at POS,
stock is FIFO-deducted, and the amount posts to Collectibles.

ERD extension (not in original ERD):
    PROJECT           → Project
    REQUISITION       → Requisition
    REQUISITION_ITEM  → RequisitionItem
    MATERIAL_TOKEN    → MaterialToken
"""

import uuid

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models
from decimal import Decimal


class Project(models.Model):
    """A construction project linked to a contractor/construction-firm Customer."""

    name = models.CharField(max_length=255, db_index=True)
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
    """Material request submitted by a site foreman."""

    class Status(models.TextChoices):
        DRAFT = 'DRAFT', 'Draft'
        SUBMITTED = 'SUBMITTED', 'Submitted'
        APPROVED = 'APPROVED', 'Approved'
        REJECTED = 'REJECTED', 'Rejected'
        PARTIAL = 'PARTIAL', 'Partially Released'
        RELEASED = 'RELEASED', 'Fully Released'
        CANCELLED = 'CANCELLED', 'Cancelled'

    project = models.ForeignKey(
        Project,
        on_delete=models.PROTECT,
        related_name='requisitions',
    )
    requested_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name='+',
        help_text='Site foreman who requested the materials.',
    )
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='+',
        help_text='Manager who approved the request.',
    )
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
    variant = models.ForeignKey(
        'inventory.ProductVariant',
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
        return f'{self.variant} × {self.quantity}'


class MaterialToken(models.Model):
    """One-time digital token (QR code) for POS material release.

    Generated on requisition approval.  Scanned by cashier at the
    hardware store POS to verify and release materials.
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
