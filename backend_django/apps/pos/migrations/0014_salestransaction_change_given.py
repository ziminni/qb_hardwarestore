# pyright: reportMissingImports=false
#
# Same directive and reason as apps/pos/services.py and apps/inventory/views.py: the
# checker runs from a working directory outside the container, where Django is not
# importable. The migration is imported and run by Django inside buildpro_backend, which
# `apps.pos.tests_change_given` exercises.
#
# QA High (Phase 4 close): a sale now records the change it handed back.

from decimal import Decimal

from django.db import migrations, models
from django.db.models import Sum


def backfill_change_given(apps, schema_editor):
    """Give every SALE row the change it must have handed back.

    This is DERIVED truth, not a guess: at a till, money in hand (every non-cheque
    tender) above the net is change. Only SALES are touched - a RETURN row is negative
    money flowing the other way and never gave change. A row that was exactly paid or
    short pays nothing, which is the column's default.

    Cheques are excluded because a pending cheque is not money (Phase 4 B2): it can
    never be the reason a drawer paid out cash.
    """
    SalesTransaction = apps.get_model("pos", "SalesTransaction")
    Payment = apps.get_model("pos", "Payment")

    def totals(payments):
        return {
            row["transaction_id"]: row["total"] or Decimal(0)
            for row in payments.values("transaction_id").annotate(
                total=Sum("amount_tendered")
            )
        }

    money_in_hand = totals(Payment.objects.exclude(method="CHEQUE"))
    cash = totals(Payment.objects.filter(method="CASH"))

    overpaid = []
    for txn in SalesTransaction.objects.exclude(source="RETURN"):
        change = money_in_hand.get(txn.id, Decimal(0)) - txn.grand_total
        # Change leaves the drawer, so it is capped at the cash taken: a legacy GCash
        # overpay handed nothing back and must not push the Z-reading's cash negative.
        change = min(change, cash.get(txn.id, Decimal(0)))
        if change > 0:
            txn.change_given = change
            overpaid.append(txn)
    SalesTransaction.objects.bulk_update(overpaid, ["change_given"])


class Migration(migrations.Migration):
    dependencies = [
        ("pos", "0013_salestransaction_vat_rate"),
    ]

    operations = [
        migrations.AddField(
            model_name="salestransaction",
            name="change_given",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=12),
        ),
        migrations.RunPython(backfill_change_given, migrations.RunPython.noop),
    ]
