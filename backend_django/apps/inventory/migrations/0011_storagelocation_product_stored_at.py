# pyright: reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as 0010: this checker runs without django-stubs, so a frozen
# `ForeignKey(...)`/`Upper(...)` in a migration's field state reads as a type error on
# valid Django. The test run is the authority.
"""Storage locations and "stored at" on every product (Phase 5 B4, decision 18).

Decision 18's "Bodega lite": a short Admin-managed list of places a product is kept,
seeded with exactly two - **Store** and **Bodega** - and one `Product.stored_at`
pointer, default Store, read back as `stored_at` + `stored_at_name` on products,
variants, selling units, sale lines and delivery slips.

**No product is left without a shelf.** The `AddField` default is the model's own
callable, so every row that existed before this migration is backfilled with the Store
row that the `RunPython` just ensured, and every row written afterwards takes it too.
The seed runs FIRST for exactly that reason, and it is idempotent and case-insensitive:
a database that already knows a place called "store" keeps that row, because names are
unique on `Upper(name)` and a second spelling would be the same place twice.

This is a LABEL, not stock: no quantity, no transfer and no batch is touched here.
"""

import django.db.models.deletion
import django.db.models.functions.text
from django.db import migrations, models

import apps.inventory.models

# The two places decision 18 names. Copied, not imported: a migration has to keep
# meaning the same thing forever, so it must not follow a later edit of the model module.
SEEDED_LOCATIONS = ("Store", "Bodega")


def seed_storage_locations(apps_, schema_editor):
    """Ensure Store and Bodega exist exactly once, case-insensitively (idempotent)."""
    StorageLocation = apps_.get_model("inventory", "StorageLocation")
    for name in SEEDED_LOCATIONS:
        if StorageLocation.objects.filter(name__iexact=name).exists():
            continue
        StorageLocation.objects.create(name=name)


def reverse_keep_locations(apps_, schema_editor):
    """Deliberately nothing: dropping the list would unlabel every product that is on it.

    The reverse of the whole migration still drops `stored_at` and the table, so this
    step adds nothing to undo - and a rollback that kept the label rows while the column
    goes away is the only non-destructive option here.
    """


class Migration(migrations.Migration):
    dependencies = [
        ("inventory", "0010_supplier_payables"),
    ]

    operations = [
        migrations.CreateModel(
            name="StorageLocation",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("name", models.CharField(db_index=True, max_length=100)),
                ("is_active", models.BooleanField(db_index=True, default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "db_table": "inventory_storage_location",
                "ordering": ("name",),
                "constraints": [
                    models.UniqueConstraint(
                        django.db.models.functions.text.Upper("name"),
                        name="uniq_storage_location_name",
                    )
                ],
            },
        ),
        migrations.RunPython(seed_storage_locations, reverse_keep_locations),
        migrations.AddField(
            model_name="product",
            name="stored_at",
            field=models.ForeignKey(
                default=apps.inventory.models.default_storage_location_pk,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="products",
                to="inventory.storagelocation",
            ),
        ),
    ]
