from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("collectibles", "0005_collectiblepayment_payment_receipt"),
    ]

    operations = [
        migrations.AlterField(
            model_name="collectibleledger",
            name="due_date",
            field=models.DateField(blank=True, null=True),
        ),
    ]
