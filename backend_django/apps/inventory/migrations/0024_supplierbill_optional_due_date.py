from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inventory", "0023_product_allow_discount"),
    ]

    operations = [
        migrations.AlterField(
            model_name="supplierbill",
            name="due_date",
            field=models.DateField(blank=True, db_index=True, null=True),
        ),
    ]
