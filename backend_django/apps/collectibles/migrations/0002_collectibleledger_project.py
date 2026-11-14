"""Decision 03 — an utang row can name the project that owes it.

Nullable because walk-in and counter sales have no project, and because every ledger row
written before this migration was raised without one. `release_materials` starts filling
it in Task 5.
"""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('collectibles', '0001_initial'),
        ('requisitions', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='collectibleledger',
            name='project',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='ledger_entries',
                to='requisitions.project',
            ),
        ),
    ]
