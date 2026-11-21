from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("pos", "0022_salesitemdeduction_unit_cost"),
    ]

    operations = [
        migrations.AddField(
            model_name="heldcartitem",
            name="discount_kind",
            field=models.CharField(blank=True, default="", max_length=10),
        ),
        migrations.AddField(
            model_name="heldcartitem",
            name="discount_reason",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddField(
            model_name="heldcartitem",
            name="discount_value",
            field=models.DecimalField(
                blank=True, decimal_places=2, max_digits=12, null=True
            ),
        ),
    ]
