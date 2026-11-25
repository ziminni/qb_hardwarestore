# Generated manually to backfill missing GoodsReceiptItem rows on legacy/seeded
# processed receipts that already minted InventoryBatch rows without lines.

from decimal import Decimal, ROUND_HALF_UP

from django.db import migrations


CENT = Decimal("0.01")


def backfill_legacy_receipt_items(apps, schema_editor):
    GoodsReceipt = apps.get_model("inventory", "GoodsReceipt")
    GoodsReceiptItem = apps.get_model("inventory", "GoodsReceiptItem")
    InventoryBatch = apps.get_model("inventory", "InventoryBatch")
    POItem = apps.get_model("inventory", "POItem")

    for receipt in GoodsReceipt.objects.filter(processed_at__isnull=False):
        if GoodsReceiptItem.objects.filter(receipt=receipt).exists():
            continue

        batches = list(
            InventoryBatch.objects.filter(
                receipt=receipt, source_batch__isnull=True
            ).order_by("id")
        )
        if not batches:
            continue

        po_items_by_variant = {
            item.variant_id: item
            for item in POItem.objects.filter(po_id=receipt.po_id).select_related(
                "variant_uom"
            )
        }
        for batch in batches:
            po_item = po_items_by_variant.get(batch.variant_id)
            if po_item is None:
                continue
            factor = (
                Decimal(po_item.variant_uom.conversion_factor)
                if po_item.variant_uom_id
                and po_item.variant_uom.conversion_factor > 0
                else Decimal("1")
            )
            package_qty = (Decimal(batch.initial_qty) / factor).quantize(
                CENT, rounding=ROUND_HALF_UP
            )
            if package_qty <= 0:
                continue
            GoodsReceiptItem.objects.create(
                receipt=receipt,
                po_item=po_item,
                qty=package_qty,
                unit_cost=po_item.unit_cost,
                location_id=batch.location_id,
                expiration_date=batch.expiration_date,
            )


class Migration(migrations.Migration):

    dependencies = [
        ("inventory", "0027_goodsreceiptitem_unit_cost"),
    ]

    operations = [
        migrations.RunPython(
            backfill_legacy_receipt_items,
            migrations.RunPython.noop,
        ),
    ]
