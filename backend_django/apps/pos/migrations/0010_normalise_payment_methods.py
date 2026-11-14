# C2 (2026-10-24): normalise legacy payment method LABELS to wire CODES.
#
# Before Phase 1 (`3c2349e`) the till sent the label it displays ('Cash'), and the
# server stored it verbatim, so the live database carries sales whose `Payment.method`
# is a label. `compute_z_reading` keys `by_method` on the code, so those payments are
# absent from `cash_sales` - the drawer total on a Z-reading is short by money the till
# actually took. `CollectiblePayment.payment_method` has the same history: the
# receivables screens posted 'CASH' but nothing stopped a label.
#
# The mapping is by LABEL, case- and space-insensitive, and it is deliberately a frozen
# copy rather than an import from `apps.pos.models`: a migration must keep behaving the
# same after the models change (the next rename of a choice would silently rewrite this
# one's meaning).
#
# `RETURN_CREDIT` and any value this map does not know are LEFT ALONE. RETURN_CREDIT is
# the server's own marker for "this debt was settled by a return" - it is not a tender and
# has no code to normalise to - and an unknown method is a fact about the data, not
# something to guess at.
#
# Idempotent: a row already holding its code maps to itself and is not updated. Reverse is
# a no-op on purpose - once labels have become codes there is no honest way to tell which
# rows were originally mislabelled, and inventing one would corrupt good rows.

from django.db import migrations

# Label (normalised: trimmed, collapsed spaces, uppercased, spaces -> underscores) -> code.
LABEL_TO_CODE = {
    'CASH': 'CASH',
    'CARD': 'CARD',
    'GCASH': 'GCASH',
    'BANK_TRANSFER': 'BANK_TRANSFER',
    # The label the app shows for BANK_TRANSFER is 'Bank transfer'; the raw form without
    # the underscore collapses to the same key above. This entry covers the historical
    # 'BankTransfer' spelling some imports used.
    'BANKTRANSFER': 'BANK_TRANSFER',
}


def normalise(value):
    """The wire code for [value], or [value] unchanged when it is not a known label."""
    key = ' '.join(str(value or '').split()).upper().replace(' ', '_')
    return LABEL_TO_CODE.get(key, value)


def normalise_payment_methods(apps, schema_editor):
    """Rewrite every label-valued method on both payment tables, in place."""
    payment = apps.get_model('pos', 'Payment')
    collectible_payment = apps.get_model('collectibles', 'CollectiblePayment')

    for model, field in ((payment, 'method'), (collectible_payment, 'payment_method')):
        for stored in model.objects.values_list(field, flat=True).distinct():
            code = normalise(stored)
            if code != stored:
                model.objects.filter(**{field: stored}).update(**{field: code})


class Migration(migrations.Migration):

    dependencies = [
        ('pos', '0009_document_counter_and_idempotency'),
        ('collectibles', '0001_initial'),
    ]

    operations = [
        migrations.RunPython(normalise_payment_methods, migrations.RunPython.noop),
    ]
