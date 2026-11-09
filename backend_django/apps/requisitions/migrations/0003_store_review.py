# pyright: reportArgumentType=false
#
# Same directive and reason as apps/requisitions/models.py: this checker runs without
# django-stubs, so `models.BooleanField(default=None, null=True)` — the explicit
# "nobody answered yet" value a migration state must carry — reads as a type error on a
# valid Django field. The test run is the authority.
"""Phase 1b decision 13/14 — the store reviews a pushed request.

Hand-written, like 0002, so the data steps run in the ONLY order that is safe: every new
column exists before `RunPython` writes to it, and no historical financial row is touched.

What changes and what must not:

* Stored `APPROVED` becomes `ACCEPTED` (CPMS' approval is not the store's acceptance).
  Every other stored status, and every quantity, stays exactly as it is.
* Lines of a request that could already leave the store (`ACCEPTED` / `PARTIAL` /
  `RELEASED` / `CLOSED`) become `available=True`, preserving prior release eligibility.
  Legacy states the store never answered keep `available=NULL`, which is NOT `false`.
* `released_amount` is `0.00` only where nothing has left the store. A request with any
  released quantity gets `NULL` (unknown): no sale row names its requisition, so the
  historical total cannot be computed and 0.00 would read as "nothing owed".
* No token, sale, ledger, payment or audit row is read or written.

Reverse is a no-op, matching 0002: the newer schema cannot be mapped back without losing
the store's answers, so a deploy rollback is a forward fix, not a reverse migration.
"""

from decimal import Decimal

from django.db import migrations, models


def rename_approved_and_seed_store_answers(apps, schema_editor):
    Requisition = apps.get_model('requisitions', 'Requisition')
    RequisitionItem = apps.get_model('requisitions', 'RequisitionItem')

    # Decision 13. `update()` on purpose: no `auto_now` field may move, and this is a
    # rename of what already happened, not a new decision.
    Requisition.objects.filter(status='APPROVED').update(status='ACCEPTED')

    # Decision 13: these requests could already be released before this migration, so
    # their lines stay releasable instead of waiting for a review that never happened.
    RequisitionItem.objects.filter(
        requisition__status__in=['ACCEPTED', 'PARTIAL', 'RELEASED', 'CLOSED'],
    ).update(available=True)

    # Decision 14: released goods with no identifiable sale = unknown money, never zero.
    Requisition.objects.filter(items__released_qty__gt=0).update(released_amount=None)


class Migration(migrations.Migration):

    dependencies = [
        ('requisitions', '0002_selling_unit_and_cpms_ids'),
    ]

    operations = [
        # The columns first: the `RunPython` above writes into them.
        migrations.AddField(
            model_name='requisition',
            name='decline_reason',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AddField(
            model_name='requisition',
            name='released_amount',
            field=models.DecimalField(
                decimal_places=2, default=Decimal('0.00'),
                help_text='Cumulative released sale value; NULL when the history is '
                          'unknown.',
                max_digits=20, null=True),
        ),
        migrations.AddField(
            model_name='requisitionitem',
            name='available',
            field=models.BooleanField(default=None, null=True),
        ),
        migrations.AddField(
            model_name='requisitionitem',
            name='decline_reason',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.RunPython(
            rename_approved_and_seed_store_answers,
            migrations.RunPython.noop,
        ),
        # Choices are state, not a database constraint: this only tells new rows which
        # status is the default and stops `APPROVED` being offered again.
        migrations.AlterField(
            model_name='requisition',
            name='status',
            field=models.CharField(
                choices=[
                    ('DRAFT', 'Draft'),
                    ('SUBMITTED', 'Submitted'),
                    ('WAITING', 'Waiting for store'),
                    ('ACCEPTED', 'Accepted'),
                    ('DECLINED', 'Declined'),
                    ('REJECTED', 'Rejected'),
                    ('PARTIAL', 'Partially Released'),
                    ('RELEASED', 'Fully Released'),
                    ('CANCELLED', 'Cancelled'),
                    ('CLOSED', 'Closed'),
                ],
                db_index=True, default='WAITING', max_length=12),
        ),
    ]
