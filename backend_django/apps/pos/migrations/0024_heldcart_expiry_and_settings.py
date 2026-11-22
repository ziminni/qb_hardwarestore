from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pos", "0023_heldcartitem_discount_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="heldcart",
            name="expires_at",
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name="storesettings",
            name="held_cart_expiry_minutes",
            field=models.PositiveIntegerField(default=120),
        ),
    ]
