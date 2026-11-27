"""Stock quantities (planning/sell-in-parts/2026-11-27-sell-by-measure-design.md).

Quantities are stored with 6 decimals so a kilo of a 40 kg bag (0.025 BAG) or a metre
of a 150 m roll (0.006667 ROLL) fits. Money stays at 2 decimals (`CENT`) everywhere.

Every conversion from a selling unit to the variant's base unit goes through
`to_base_qty`. A measured unit (`VariantUOM.measure_per_base`, e.g. 40 kg per bag)
DIVIDES by the exact per-base amount instead of multiplying by the rounded factor,
so 1.5 m of a 150 m roll is exactly 0.01 roll.
"""

from decimal import Decimal

QTY = Decimal("0.000001")

# What a person may type for a quantity: 7.5 kg, 0.35 m. Finer amounts are refused,
# not silently rounded.
TYPED_QTY = Decimal("0.01")

# Each conversion rounds to QTY, so it can be off by at most half of QTY.
_HALF_QTY = QTY / 2


def to_base_qty(variant_uom, qty) -> Decimal:
    """`qty` of `variant_uom` expressed in the variant's base unit, rounded to QTY."""
    qty = Decimal(qty)
    per_base = getattr(variant_uom, "measure_per_base", None)
    if per_base:
        base = qty / Decimal(per_base)
    else:
        base = qty * Decimal(variant_uom.conversion_factor)
    # Same shape as a stored quantity (`QuantityField`): 12 -> 12.00, 0.075 stays.
    return Decimal(format_qty(base))


def dust_tolerance(variant_uom, prior_deductions: int = 0) -> Decimal:
    """How far a measured sale may miss what is on hand, in base units. 0 for others.

    1 m of a 150 m roll is stored as 0.006667 roll, a hair more than a 150th, so after
    149 one-metre sales the last metre looks 0.00005 roll short. The tolerance is one
    sellable step (0.01 of the unit: an amount nobody can sell on its own) plus half a
    millionth for every earlier measured sale still on the stock - the most their
    rounding can add up to. Within it, a sale takes what is left and leaves no dust.
    """
    if not getattr(variant_uom, "measure_per_base", None):
        return Decimal(0)
    return to_base_qty(variant_uom, TYPED_QTY) + _HALF_QTY * prior_deductions


def format_qty(value) -> str:
    """A quantity as text: at least 2 decimals, at most 6, no trailing noise.

    `2` -> "2.00", `9.750000` -> "9.75", `0.075000` -> "0.075". Replaces `f"{q:.2f}"`,
    which would print 3 kg of a 40 kg bag (0.075 BAG) as "0.08".
    """
    text = f"{Decimal(value).quantize(QTY):f}"
    whole, _, frac = text.partition(".")
    frac = frac.rstrip("0").ljust(2, "0")
    return f"{whole}.{frac}"


def base_qty_sql(qty_field: str = "qty", unit: str = "variant_uom"):
    """`to_base_qty` as a database expression, for sums over many rows.

    `qty_field` is the quantity column, `unit` the path to its `VariantUOM`.
    """
    from django.db.models import Case, DecimalField, F, When

    out = DecimalField(max_digits=24, decimal_places=6)
    return Case(
        When(
            **{f"{unit}__measure_per_base__isnull": False},
            then=F(qty_field) / F(f"{unit}__measure_per_base"),
        ),
        default=F(qty_field) * F(f"{unit}__conversion_factor"),
        output_field=out,
    )


def typed_qty_error(qty) -> str | None:
    """A message when a typed quantity has more than 2 decimals, else None."""
    qty = Decimal(qty)
    if qty != qty.quantize(TYPED_QTY):
        return f"{qty.normalize()} has more than 2 decimal places. Round it to 0.01."
    return None
