"""Backfill a derived code onto every selling unit that has none (Phase 6, decision 16).

Runs after the uniqueness constraint from decision 11. Safe on any database: a derived
code is built from the row's own id, so codes cannot collide with each other, and the
`QB` prefix is reserved so a hand-typed one cannot already hold it (a database that
somehow does hold one FAILS this migration loudly rather than silently re-coding a unit -
clear that code and re-run).

No-op dependencies inside the file are copies, not imports: a migration has to keep
meaning the same thing forever, so it must not call `apps.inventory.models.derived_code`,
which is free to change later.
"""

from django.db import migrations


def _gs1_check_digit(digits):
    """GS1 mod-10 over `digits`, weights 3,1,3,1… counted from the RIGHTMOST digit."""
    total = sum(
        int(char) * (3 if position % 2 == 0 else 1)
        for position, char in enumerate(reversed(digits)))
    return (10 - total % 10) % 10


def _derived_code(pk):
    digits = f'{pk:06d}'
    return f'QB{digits}-{_gs1_check_digit(digits)}'


def backfill_blank_barcodes(apps, schema_editor):
    """Give every blank-coded selling unit this unit's own `QB{id:06}-{check}` code."""
    VariantUOM = apps.get_model('inventory', 'VariantUOM')
    for unit_id in VariantUOM.objects.filter(barcode_qr='').values_list('id', flat=True):
        VariantUOM.objects.filter(pk=unit_id).update(barcode_qr=_derived_code(unit_id))


def reverse_noop(apps, schema_editor):
    """Deliberately nothing: clearing the codes would make every old unit unscannable."""


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0006_variantuom_uniq_variantuom_barcode'),
    ]

    operations = [
        migrations.RunPython(backfill_blank_barcodes, reverse_noop),
    ]
