"""Model field for stock quantities (sell by measure)."""

from decimal import Decimal

from django.db import models

from common.quantities import format_qty


class QuantityField(models.DecimalField):
    """A stock quantity: stored with 6 decimals, read back without trailing noise.

    The column is `numeric(18, 6)` so 0.025 bag (1 kg of a 40 kg bag) or 0.006667 roll
    (1 m of a 150 m roll) is stored. A value read from the database comes back with at
    least 2 decimals and only the digits it needs - `10.00`, `0.075` - so every message,
    receipt and contract that printed a quantity keeps printing it the way it always did.
    The value itself is unchanged; only its exponent is.
    """

    def __init__(self, *args, **kwargs):
        kwargs.setdefault("max_digits", 18)
        kwargs.setdefault("decimal_places", 6)
        super().__init__(*args, **kwargs)

    def from_db_value(self, value, expression, connection):
        if value is None:
            return value
        return Decimal(format_qty(value))
