# pyright: reportArgumentType=false
#
# Same directive and reason as apps/inventory/migrations/0011_product_stored_at.py: this
# checker runs without django-stubs, so a migration's frozen field state reads as a type
# error on valid Django. The test run is the authority.
"""Phase 9 B1 (decision 21 §1): stock knows which shelf it sits on.

Decision 21 §1 rules where existing stock goes: **the product's Stored at location**, and
`Stored at` is from now on the product's HOME location. This migration is the data half of
that rule, in three steps:

1. add `location` nullable on `InventoryBatch` and `StockAdjustment` (and `source_batch`
   on the batch, decision 21 §2's "copied, not received" marker);
2. `RunPython` fills every existing row from `variant.product.stored_at` - NOT from a
   column default, because two products in the same shop can live in different places and
   a hard-coded "Store" would move every Bodega product on the way in;
3. alter both `location` columns to NOT NULL, so a writer that forgets the shelf fails at
   the database instead of minting stock that belongs to nowhere.

Reverse is a noop for the data step: going back drops the columns entirely (there is
nothing to restore them from), and guessing a location again on the way back would be
inventing history.

`source_batch` stays NULL for every pre-Phase-9 row, which is correct by definition: every
batch that exists today was minted by a delivery, never copied by a move.
"""

import django.db.models.deletion
from django.db import migrations, models


def place_stock_at_home(apps, schema_editor):
    """`location = variant.product.stored_at` for every batch and adjustment."""
    InventoryBatch = apps.get_model("inventory", "InventoryBatch")
    StockAdjustment = apps.get_model("inventory", "StockAdjustment")

    for model in (InventoryBatch, StockAdjustment):
        for row in model.objects.select_related("variant__product").iterator():
            row.location_id = row.variant.product.stored_at_id
            row.save(update_fields=["location"])


class Migration(migrations.Migration):
    dependencies = [  # noqa: RUF012 - Django-canonical, never mutated
        ("inventory", "0014_supplier_credit_notes"),
    ]

    operations = [  # noqa: RUF012 - Django-canonical, never mutated
        migrations.AddField(
            model_name="inventorybatch",
            name="location",
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="batches",
                to="inventory.storagelocation",
            ),
        ),
        migrations.AddField(
            model_name="inventorybatch",
            name="source_batch",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="derived_batches",
                to="inventory.inventorybatch",
            ),
        ),
        migrations.AddField(
            model_name="stockadjustment",
            name="location",
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="adjustments",
                to="inventory.storagelocation",
            ),
        ),
        migrations.RunPython(place_stock_at_home, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="inventorybatch",
            name="location",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="batches",
                to="inventory.storagelocation",
            ),
        ),
        migrations.AlterField(
            model_name="stockadjustment",
            name="location",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name="adjustments",
                to="inventory.storagelocation",
            ),
        ),
    ]
