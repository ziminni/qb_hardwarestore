from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("inventory", "0024_supplierbill_optional_due_date"),
    ]

    operations = [
        migrations.AddField(
            model_name="supplierpayment",
            name="proof_attachment",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
    ]
