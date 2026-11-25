from decimal import Decimal
import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inventory", "0026_product_tracks_expiry"),
    ]

    operations = [
        migrations.AddField(
            model_name="goodsreceiptitem",
            name="unit_cost",
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                max_digits=12,
                null=True,
                validators=[django.core.validators.MinValueValidator(Decimal("0.00"))],
            ),
        ),
    ]
