# pyright: reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/inventory/migrations/0008_uom_is_whole.py: this
# checker runs without django-stubs, so a frozen `ForeignKey(...)` in a migration's field
# state reads as a type error on valid Django. The test run is the authority.
"""A purchase-order line names the selling unit it is counted in (Phase 5 B1).

Before this migration `POItem.ordered_qty` / `unit_cost` / `received_qty` meant BASE
units; after it they mean the line's SELLING unit (decision 18, "PO by package"). The two
only agree for a factor-1 line, so every existing line is pointed at its variant's REAL
base row: `uom == variant.base_uom` with `conversion_factor == 1`. Never "the first row"
and never "the lowest pk" - `VariantUOM` is ordered by `uom`, so list order would point a
cement line at its BAG package and silently re-measure every quantity on it.

No quantity and no money is rewritten. A factor-1 line keeps its meaning exactly, so this
migration cannot change a received quantity, a unit cost or a stock batch.

The column stays nullable because rows written by fixtures/older tooling straight through
the ORM carry no unit and are READ as the variant's base unit (factor 1). The API always
persists the unit it validated.

A variant with NO such base row cannot be given a unit without guessing, so this migration
FAILS loudly and names the PO items instead of inventing a factor, picking a package or
deleting lines.
"""

import django.db.models.deletion
from django.db import migrations, models


def backfill_po_item_units(apps, schema_editor):
    """Point every existing line at its variant's base row, or fail naming the lines."""
    POItem = apps.get_model("inventory", "POItem")
    VariantUOM = apps.get_model("inventory", "VariantUOM")

    base_by_variant = {}
    unresolved = []
    for item in POItem.objects.select_related("variant").order_by("pk"):
        variant = item.variant
        base_id = base_by_variant.get(variant.pk)
        if base_id is None:
            base = (
                VariantUOM.objects.filter(
                    variant_id=variant.pk,
                    uom_id=variant.base_uom_id,
                    conversion_factor=1,
                )
                .order_by("pk")
                .first()
            )
            if base is None:
                unresolved.append(item.pk)
                continue
            base_id = base.pk
            base_by_variant[variant.pk] = base_id
        POItem.objects.filter(pk=item.pk).update(variant_uom_id=base_id)

    if unresolved:
        raise RuntimeError(
            "Cannot backfill POItem.variant_uom: these purchase-order lines belong to "
            "variants with no base selling unit (uom == variant.base_uom and "
            f"conversion_factor == 1): PO items {unresolved}. Create each variant's "
            "base selling unit and re-run the migration; no line, quantity or cost was "
            "changed."
        )


def reverse_noop(apps, schema_editor):
    """Nothing to undo: the column is dropped by the reverse of AddField."""


class Migration(migrations.Migration):
    dependencies = [
        ("inventory", "0008_uom_is_whole"),
    ]

    operations = [
        migrations.AddField(
            model_name="poitem",
            name="variant_uom",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="po_items",
                to="inventory.variantuom",
            ),
        ),
        migrations.RunPython(backfill_po_item_units, reverse_noop),
    ]
