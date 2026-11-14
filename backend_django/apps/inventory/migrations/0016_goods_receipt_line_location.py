# pyright: reportArgumentType=false
#
# Same directive and reason as apps/inventory/migrations/0015_stock_location.py: this
# checker runs without django-stubs, so a migration's frozen field state reads as a type
# error on valid Django. The test run is the authority.
"""Phase 9 B3 (decision 21, plan Design 7): a receipt LINE carries its destination.

B1 gave the BATCH a location and had every delivery land at home. This adds the choice
to the document the receiver fills in, so a delivery to the Bodega is Bodega stock.

Nullable on purpose: every line recorded before Phase 9 (and every script that writes a
line straight through the ORM) has no destination, and NULL means "the variant's home" -
exactly where those deliveries went. No backfill, so upgrading cannot move stock.
"""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [  # noqa: RUF012 - Django-canonical, never mutated
        ("inventory", "0015_stock_location"),
    ]

    operations = [  # noqa: RUF012 - Django-canonical, never mutated
        migrations.AddField(
            model_name="goodsreceiptitem",
            name="location",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="receipt_lines",
                to="inventory.storagelocation",
            ),
        ),
    ]
