from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("pos", "0025_customer_store_credit_and_exchange"),
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
