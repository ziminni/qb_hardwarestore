from decimal import Decimal

import django.core.validators
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('collectibles', '0003_alter_collectiblepayment_payment_method'),
        ('requisitions', '0003_store_review'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ProjectPaymentReceipt',
            fields=[
                (
                    'id',
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name='ID',
                    ),
                ),
                ('cpms_payment_id', models.CharField(max_length=100, unique=True)),
                (
                    'amount',
                    models.DecimalField(
                        decimal_places=2,
                        max_digits=12,
                        validators=[
                            django.core.validators.MinValueValidator(Decimal('0.01')),
                        ],
                    ),
                ),
                (
                    'payment_method',
                    models.CharField(
                        choices=[
                            ('CASH', 'Cash'),
                            ('CARD', 'Card'),
                            ('GCASH', 'GCash'),
                            ('BANK_TRANSFER', 'Bank Transfer'),
                            ('CHEQUE', 'Cheque'),
                        ],
                        default='BANK_TRANSFER',
                        max_length=50,
                    ),
                ),
                ('reference_no', models.CharField(max_length=100)),
                ('notes', models.TextField(blank=True, default='')),
                (
                    'submitted_by_name',
                    models.CharField(blank=True, default='', max_length=150),
                ),
                (
                    'status',
                    models.CharField(
                        choices=[
                            ('WAITING', 'Waiting for Verification'),
                            ('APPROVED', 'Approved'),
                            ('DECLINED', 'Declined'),
                        ],
                        db_index=True,
                        default='WAITING',
                        max_length=16,
                    ),
                ),
                (
                    'approved_amount',
                    models.DecimalField(
                        blank=True, decimal_places=2, max_digits=12, null=True
                    ),
                ),
                ('decline_reason', models.TextField(blank=True, default='')),
                ('decided_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                (
                    'decided_by',
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='+',
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    'project',
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name='payment_receipts',
                        to='requisitions.project',
                    ),
                ),
            ],
            options={
                'verbose_name': 'project payment receipt',
                'verbose_name_plural': 'project payment receipts',
                'db_table': 'collectibles_project_payment_receipt',
                'ordering': ['-created_at', '-id'],
            },
        ),
    ]
