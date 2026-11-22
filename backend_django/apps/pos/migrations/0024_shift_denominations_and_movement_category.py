from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pos", "0023_heldcartitem_discount_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="shift",
            name="denomination_counts",
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name="shiftcashmovement",
            name="category",
            field=models.CharField(
                choices=[
                    ("LUNCH", "Lunch"),
                    ("FUEL", "Fuel"),
                    ("SUPPLIES", "Supplies"),
                    ("SAFE_DROP", "Safe Drop"),
                    ("CHANGE_FLOAT", "Change Float"),
                    ("OTHER", "Other"),
                ],
                default="OTHER",
                max_length=20,
            ),
        ),
    ]
