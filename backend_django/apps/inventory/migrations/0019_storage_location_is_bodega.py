from django.db import migrations, models


def mark_bodega(apps, schema_editor):
    """The shelf the shop already calls "Bodega" is the checker's shelf (decision 25 §1)."""
    StorageLocation = apps.get_model("inventory", "StorageLocation")
    StorageLocation.objects.filter(name__iexact="Bodega").update(is_bodega=True)


class Migration(migrations.Migration):
    dependencies = [
        ("inventory", "0018_product_image"),
    ]

    operations = [
        migrations.AddField(
            model_name="storagelocation",
            name="is_bodega",
            field=models.BooleanField(db_index=True, default=False),
        ),
        migrations.RunPython(mark_bodega, migrations.RunPython.noop),
    ]
