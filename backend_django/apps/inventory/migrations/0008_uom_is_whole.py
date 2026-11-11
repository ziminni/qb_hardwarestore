# pyright: reportArgumentType=false
#
# Same directive and reason as apps/requisitions/migrations/0003_store_review.py: this
# checker runs without django-stubs, so `models.BooleanField(default=False)` in a
# migration's frozen field state reads as a type error on valid Django. The test run is
# the authority.
"""The whole-number flag, and the standard unit list in every database (Phase 1d Task 1).

Decision 16 moves two pieces of knowledge from the Flutter client onto the server:

* each unit SAYS whether it is counted in whole numbers (`is_whole`), so a refusal is the
  server's answer rather than a hard-coded list the app ships; and
* every database gets the same twelve standard units, so a shop never has to create one
  by hand and a CPMS material code always resolves to a known unit.

Existing rows are LEFT AS THEY ARE apart from the flag: their code and their name are
what screens and past documents already say, and re-casing a stored `kg` into `KG` would
be an edit nobody asked for. Lookups are case-insensitive for that reason (codes are
unique only case-SENSITIVELY, so `kg` and `KG` could otherwise both exist), and several
matches means several flags: creating a rival spelling is the one thing this must not do.

`RL` is the Roll unit in every database seeded before this phase (decision 16's Q3), so a
canonical `ROLL` settles on an existing `ROLL` or else on `RL`, in that order, and never
creates a second Roll.

Reverse is deliberately a noop: it clears the flag with the column, but deleting the
standard units would delete units that selling units and past lines may point at.
"""

from django.db import migrations, models

# (code, name, is_whole) — the order is the order a fresh database gets them in.
STANDARD_UNITS = [
    ('PC', 'Piece', True),
    ('BAG', 'Bag', True),
    ('BOX', 'Box', True),
    ('PACK', 'Pack', True),
    ('ROLL', 'Roll', True),
    ('SHEET', 'Sheet', True),
    ('KG', 'Kilogram', False),
    ('G', 'Gram', False),
    ('M', 'Metre', False),
    ('CM', 'Centimetre', False),
    ('L', 'Litre', False),
    ('ML', 'Millilitre', False),
]

# The seed spells Roll `RL`; it IS the Roll row, so no second one is created.
ALIASES = {'ROLL': ('RL',)}


def add_standard_units(apps, schema_editor):
    UnitOfMeasure = apps.get_model('inventory', 'UnitOfMeasure')
    for code, name, is_whole in STANDARD_UNITS:
        rows = list(UnitOfMeasure.objects.filter(code__iexact=code))
        for alias in ALIASES.get(code, ()):
            rows += [
                row for row in UnitOfMeasure.objects.filter(code__iexact=alias)
                if row.pk not in {found.pk for found in rows}
            ]
        if rows:
            UnitOfMeasure.objects.filter(
                pk__in=[row.pk for row in rows]).update(is_whole=is_whole)
            continue
        UnitOfMeasure.objects.create(code=code, name=name, is_whole=is_whole)


def reverse_noop(apps, schema_editor):
    """Nothing to undo: the column removal clears the flags, the rows stay."""


class Migration(migrations.Migration):

    dependencies = [
        ('inventory', '0007_backfill_variantuom_barcodes'),
    ]

    operations = [
        migrations.AddField(
            model_name='unitofmeasure',
            name='is_whole',
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(add_standard_units, reverse_noop),
    ]
