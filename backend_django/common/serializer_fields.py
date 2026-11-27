"""API representation of stock quantities (sell by measure).

Quantity columns hold 6 decimals, but the API keeps the shape every client already
reads: "10.00", not "10.000000". Only a value that needs more decimals shows them
("0.075"). Money fields (2 decimals) are untouched.
"""

from rest_framework import serializers

from common.quantities import format_qty


class QtyDecimalField(serializers.DecimalField):
    """A `DecimalField` that prints a 6-decimal quantity without trailing noise."""

    def to_representation(self, value):
        if (
            value is not None
            and self.decimal_places == 6
            and getattr(self, "coerce_to_string", True) is not False
        ):
            return format_qty(value)
        return super().to_representation(value)


def install():
    """Make every ModelSerializer map model DecimalFields to `QtyDecimalField`.

    Called once from `InventoryConfig.ready`. A 2-decimal (money) field behaves exactly
    like DRF's own `DecimalField`; only 6-decimal quantity fields change.
    """
    from django.db import models

    serializers.ModelSerializer.serializer_field_mapping[models.DecimalField] = (
        QtyDecimalField
    )
