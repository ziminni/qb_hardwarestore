from decimal import Decimal

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pos", "0024_salestransaction_invoice_no"),
    ]

    operations = [
        migrations.AddField(
            model_name="customer",
            name="store_credit_balance",
            field=models.DecimalField(
                decimal_places=2, default=Decimal("0.00"), max_digits=12
            ),
        ),
        migrations.AlterField(
            model_name="salestransaction",
            name="source",
            field=models.CharField(
                choices=[
                    ("WALK_IN", "Walk-in"),
                    ("REQUISITION", "Requisition"),
                    ("RETURN", "Return"),
                    ("EXCHANGE", "Exchange"),
                ],
                default="WALK_IN",
                max_length=15,
            ),
        ),
    ]
