"""Decision 03/04/08 — CPMS ids, name fields, lines keyed on the selling unit.

Written by hand rather than autodetected so the data steps sit in the ONLY order that is
safe: every new column exists (and every old one still exists to copy FROM) before the
`RunPython` runs, and the copy finishes before the foreign keys are dropped.
"""

import django.db.models.deletion
from django.db import migrations, models


def copy_names_and_cancel_unreachable_statuses(apps, schema_editor):
    """Decision 08 item 1 and 2: the two people become text, dead states become Cancelled.

    Reads `requested_by` / `approved_by` while the FKs still exist — the `RemoveField`
    operations below run after this.
    """
    Requisition = apps.get_model('requisitions', 'Requisition')

    for requester in Requisition.objects.select_related(
            'requested_by', 'approved_by').all():
        requester.requester_name = (
            requester.requested_by.full_name if requester.requested_by_id else '')
        requester.approver_name = (
            requester.approved_by.full_name if requester.approved_by_id else '')
        updated = ['requester_name', 'approver_name']
        # The POS can no longer produce a Draft or a Submitted request — CPMS pushes an
        # ALREADY APPROVED one — so those rows keep a status nobody can drive.
        if requester.status in ('DRAFT', 'SUBMITTED'):
            requester.status = 'CANCELLED'
            updated.append('status')
        requester.save(update_fields=updated)


def point_items_at_base_selling_unit(apps, schema_editor):
    """Decision 04: a line points at a `VariantUOM`, not a bare `ProductVariant`.

    Legacy quantities are base units, so the factor-1 row is the one that leaves the
    numbers unchanged (1 of it = 1 base unit); `pk` order settles a catalog with two of
    them. Requires no arithmetic: `quantity` / `released_qty` carry over as they are.
    """
    RequisitionItem = apps.get_model('requisitions', 'RequisitionItem')
    VariantUOM = apps.get_model('inventory', 'VariantUOM')

    base_uom_by_variant = {}
    for row in VariantUOM.objects.filter(conversion_factor=1).order_by('pk'):
        base_uom_by_variant.setdefault(row.variant_id, row.pk)

    for item in RequisitionItem.objects.select_related('variant').order_by('pk'):
        uom_pk = base_uom_by_variant.get(item.variant_id)
        if uom_pk is None:
            # shortcut: dev/demo data only — a real deployment resolves this by adding
            # the missing selling unit and re-running, not by guessing a factor.
            raise RuntimeError(
                f'Cannot migrate requisition item #{item.pk} '
                f'(requisition #{item.requisition_id}): variant #{item.variant_id} '
                f'({item.variant}) has no selling unit with conversion_factor=1. '
                'Add the base-unit selling unit, then re-run the migration.')
        item.variant_uom_id = uom_pk
        item.save(update_fields=['variant_uom'])


def retire_site_foreman_role(apps, schema_editor):
    """Decision 08 item 3: the account is deactivated and ungrouped, then the group goes.

    The row itself stays: `AuditLog.user` is PROTECT and audit is append-only, so the
    foreman's history cannot be deleted without destroying the trail.
    """
    User = apps.get_model('apps_users', 'User')
    Group = apps.get_model('auth', 'Group')

    group = Group.objects.filter(name='Site Foreman').first()
    if group is None:
        return
    for user in User.objects.filter(groups=group):
        user.is_active = False
        user.save(update_fields=['is_active'])
        user.groups.remove(group)
    group.delete()


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0007_backfill_variantuom_barcodes'),
        ('requisitions', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='cpms_project_id',
            field=models.CharField(
                blank=True, max_length=100, null=True, unique=True),
        ),
        migrations.AddField(
            model_name='requisition',
            name='cpms_request_id',
            field=models.CharField(
                blank=True, max_length=100, null=True, unique=True),
        ),
        migrations.AddField(
            model_name='requisition',
            name='requester_name',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AddField(
            model_name='requisition',
            name='approver_name',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AlterField(
            model_name='requisition',
            name='status',
            field=models.CharField(
                choices=[
                    ('DRAFT', 'Draft'),
                    ('SUBMITTED', 'Submitted'),
                    ('APPROVED', 'Approved'),
                    ('REJECTED', 'Rejected'),
                    ('PARTIAL', 'Partially Released'),
                    ('RELEASED', 'Fully Released'),
                    ('CANCELLED', 'Cancelled'),
                    ('CLOSED', 'Closed'),
                ],
                db_index=True, default='DRAFT', max_length=12),
        ),
        # Nullable first: the column has to exist before the copy can fill it.
        migrations.AddField(
            model_name='requisitionitem',
            name='variant_uom',
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name='requisition_items',
                to='inventory.variantuom',
            ),
        ),
        migrations.RunPython(
            copy_names_and_cancel_unreachable_statuses,
            migrations.RunPython.noop,
        ),
        migrations.RunPython(
            point_items_at_base_selling_unit,
            migrations.RunPython.noop,
        ),
        migrations.RunPython(
            retire_site_foreman_role,
            migrations.RunPython.noop,
        ),
        # Only now that every row has a selling unit may the column become required.
        migrations.AlterField(
            model_name='requisitionitem',
            name='variant_uom',
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.PROTECT,
                related_name='requisition_items',
                to='inventory.variantuom',
            ),
        ),
        migrations.RemoveField(
            model_name='requisitionitem',
            name='variant',
        ),
        migrations.RemoveField(
            model_name='requisition',
            name='approved_by',
        ),
        migrations.RemoveField(
            model_name='requisition',
            name='requested_by',
        ),
    ]
