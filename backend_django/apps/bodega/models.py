# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Bodega module (decision 25): hand-overs against a paid claim, and checker counts.

A claim is NOT a table. When the till sells goods that sit on a Bodega shelf, the sale's
`SalesItemDeduction` rows already say which Bodega batch each unit came from, and a linked
return writes negative rows against the same batches. So "what this receipt may still
collect" is always:

    taken from the Bodega by the sale  -  given back by its returns  -  released here

computed in `services.claim_lines`. Only the two facts nothing else records are stored:

* `BodegaRelease` - the checker handed goods over (who, which truck, how much);
* `BodegaDelivery` - a supplier delivery to the Bodega the checker must confirm (good
                     and damaged quantities) before it becomes stock.

Quantities are BASE units (the unit stock is kept in), the same as every batch column.
"""

from decimal import Decimal

from django.conf import settings
from django.core.validators import MinValueValidator
from django.db import models


class BodegaRelease(models.Model):
    """One hand-over at the Bodega against one sale's claim (`BR-YYYYMMDD-NNNN`)."""

    number = models.CharField(max_length=30, unique=True, db_index=True)
    sale = models.ForeignKey(
        "pos.SalesTransaction",
        on_delete=models.PROTECT,
        related_name="bodega_releases",
    )
    checker = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="+"
    )
    received_by = models.CharField(max_length=150)
    plate_no = models.CharField(max_length=30, blank=True, default="")
    notes = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "bodega_release"
        ordering = ("-created_at", "-id")

    def __str__(self):
        return f"{self.number} ({self.sale.transaction_no})"


class BodegaReleaseLine(models.Model):
    release = models.ForeignKey(
        BodegaRelease, on_delete=models.CASCADE, related_name="lines"
    )
    variant = models.ForeignKey(
        "inventory.ProductVariant", on_delete=models.PROTECT, related_name="+"
    )
    location = models.ForeignKey(
        "inventory.StorageLocation", on_delete=models.PROTECT, related_name="+"
    )
    qty = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(Decimal("0.01"))],
    )

    class Meta:
        db_table = "bodega_release_line"


class BodegaDelivery(models.Model):
    """A supplier delivery to a Bodega shelf, waiting for the checker (`BD-YYYYMMDD-NNNN`).

    Decision 25 (rev. 2026-11-18): the stocker records every delivery, but a line bound
    for the Bodega is not stock until the Bodega Checker confirms it. The checker enters
    how much arrived good and how much is damaged; damaged and missing pieces are
    written off (stock adjustments) at once. The bill and the PO follow what the stocker
    recorded, untouched by the check.
    """

    class Status(models.TextChoices):
        PENDING = "PENDING", "For checking"
        CHECKED = "CHECKED", "Checked"

    number = models.CharField(max_length=30, unique=True, db_index=True)
    receipt = models.ForeignKey(
        "inventory.GoodsReceipt", on_delete=models.PROTECT, related_name="bodega_checks"
    )
    location = models.ForeignKey(
        "inventory.StorageLocation", on_delete=models.PROTECT, related_name="+"
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True
    )
    checked_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    checked_at = models.DateTimeField(null=True, blank=True)
    notes = models.CharField(max_length=255, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "bodega_delivery"
        ordering = ("-created_at", "-id")

    def __str__(self):
        return f"{self.number} ({self.status})"


class BodegaDeliveryLine(models.Model):
    """One delivered product. Base units. `good + damaged + missing == delivered`."""

    delivery = models.ForeignKey(
        BodegaDelivery, on_delete=models.CASCADE, related_name="lines"
    )
    po_item = models.ForeignKey(
        "inventory.POItem", on_delete=models.PROTECT, related_name="+"
    )
    variant = models.ForeignKey(
        "inventory.ProductVariant", on_delete=models.PROTECT, related_name="+"
    )
    delivered_qty = models.DecimalField(max_digits=12, decimal_places=2)
    good_qty = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    damaged_qty = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    remarks = models.CharField(max_length=255, blank=True, default="")
    # The checker's phone photo of this item as it arrived: proof that it is there
    # (and of any damage). Taken before the verdict; kept with the line after.
    photo = models.ImageField(upload_to="bodega-deliveries/", blank=True)
    batch = models.ForeignKey(
        "inventory.InventoryBatch",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )

    class Meta:
        db_table = "bodega_delivery_line"

    @property
    def missing_qty(self):
        if self.good_qty is None or self.damaged_qty is None:
            return None
        return self.delivered_qty - self.good_qty - self.damaged_qty
