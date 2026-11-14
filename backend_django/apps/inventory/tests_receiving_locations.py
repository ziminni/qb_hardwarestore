# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/inventory/tests_storage_locations.py: the checker
# runs from a working directory outside the repo, so `Model.objects` is a false positive
# on valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client. The test
# run is the authority.

"""Phase 9 B3 (decision 21, plan Design 7/8/11) — receiving and adjusting on a shelf.

Two writers learn WHERE the stock goes, and one of them learns what a deactivated shelf
means:

* a goods receipt line carries an optional `location` (default: the variant's home). The
  batch it becomes lands THERE, so a delivery to the Bodega is Bodega stock - not Store
  stock with a different label. An inactive location cannot receive: the POST answers
  **400** `INVALID_STORAGE_LOCATION` with no receipt row, no `received_qty` change and no
  batch.
* a stock adjustment names a shelf too (default: home). A removal takes stock off THAT
  shelf only, so a count correction at the Store cannot silently eat the Bodega's goods.
  An addition reopens the newest batch on that shelf; when the shelf has never held the
  variant, a NEW batch is minted copying the variant's newest batch (receipt, landed
  cost, selling price, markup, expiry) with `source_batch` set, so cost and age travel
  and no "what did this receipt bring in" sum counts the copy twice. A variant with no
  batch anywhere keeps the old `NO_BATCH_HISTORY` refusal.
* an INACTIVE shelf refuses additions (nothing may be put into a place the shop closed)
  but still allows removals - stock that is already there must stay manageable out.
"""

from decimal import Decimal

from rest_framework.test import APIClient

from .models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    PurchaseOrder,
    StockAdjustment,
    StorageLocation,
    Supplier,
)
from .services import process_goods_receipt
from .tests_storage_locations import StorageTestBase

RECEIPTS_URL = "/api/v1/goods-receipts/"
ADJUSTMENTS_URL = "/api/v1/adjustments/"


class LocationWarehouseTestBase(StorageTestBase):
    """A placed PO with one delivered line, and a helper that puts stock on a shelf."""

    def setUp(self):
        super().setUp()
        # The auth helper logs in through the real JWT endpoint; these tests post real
        # payloads to the real routes.
        self.auth = self._auth(self.stocker)
        supplier = Supplier.objects.create(company_name="Acme Supply")
        self.po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        self.po_item = POItem.objects.create(
            po=self.po,
            variant=self.variant,
            ordered_qty=Decimal(10),
            unit_cost=Decimal(50),
        )

    def _stock_on(self, qty, location):
        """Stock `qty` base units on `location` the way a delivery does it."""
        receipt = GoodsReceipt.objects.create(po=self.po, received_by=self.user)
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            location=location,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal("50.00"),
            markup_percentage=Decimal("10.00"),
            batch_selling_price=Decimal("55.00"),
        )

    def _deactivate(self, location):
        StorageLocation.objects.filter(pk=location.pk).update(is_active=False)
        location.refresh_from_db()
        return location


class ReceivingDestinationTests(LocationWarehouseTestBase):
    """Design 7: the receiver picks the shelf, and the batch lands there."""

    def test_a_line_sent_to_the_bodega_stocks_the_bodega(self):
        response = self.client.post(
            RECEIPTS_URL,
            {
                "po": self.po.pk,
                "items": [
                    {"po_item": self.po_item.pk, "qty": "4", "location": self.bodega.pk}
                ],
            },
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["lines"][0]["location"], self.bodega.pk)

        receipt_id = response.data["id"]
        processed = self.client.post(
            f"{RECEIPTS_URL}{receipt_id}/process/", {}, format="json", **self.auth
        )

        self.assertEqual(processed.status_code, 200, processed.data)
        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.location_id, self.bodega.pk)
        self.assertEqual(batch.current_qty, Decimal(4))
        self.assertFalse(
            InventoryBatch.objects.filter(
                variant=self.variant, location=self.store
            ).exists()
        )

    def test_a_line_with_no_destination_lands_at_home(self):
        response = self.client.post(
            RECEIPTS_URL,
            {"po": self.po.pk, "items": [{"po_item": self.po_item.pk, "qty": "4"}]},
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.client.post(
            f"{RECEIPTS_URL}{response.data['id']}/process/",
            {},
            format="json",
            **self.auth,
        )

        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.location_id, self.variant.product.stored_at_id)

    def test_an_inactive_destination_is_refused_and_writes_nothing(self):
        self._deactivate(self.bodega)

        response = self.client.post(
            RECEIPTS_URL,
            {
                "po": self.po.pk,
                "items": [
                    {"po_item": self.po_item.pk, "qty": "4", "location": self.bodega.pk}
                ],
            },
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertEqual(GoodsReceipt.objects.count(), 0)
        self.po_item.refresh_from_db()
        self.assertEqual(self.po_item.received_qty, Decimal(0))
        self.assertFalse(InventoryBatch.objects.exists())

    def test_processing_a_receipt_into_a_shelf_closed_since_is_refused(self):
        """The destination is re-read under a lock at process time (Design 12 a).

        A receipt recorded while the Bodega was open, processed after somebody closed it,
        must not stock a place the shop no longer uses - and must not stock at all.
        """
        response = self.client.post(
            RECEIPTS_URL,
            {
                "po": self.po.pk,
                "items": [
                    {"po_item": self.po_item.pk, "qty": "4", "location": self.bodega.pk}
                ],
            },
            format="json",
            **self.auth,
        )
        self.assertEqual(response.status_code, 201, response.data)
        self._deactivate(self.bodega)

        processed = self.client.post(
            f"{RECEIPTS_URL}{response.data['id']}/process/",
            {},
            format="json",
            **self.auth,
        )

        self.assertEqual(processed.status_code, 400, processed.data)
        self.assertEqual(processed.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertFalse(InventoryBatch.objects.exists())
        receipt = GoodsReceipt.objects.get(pk=response.data["id"])
        self.assertIsNone(receipt.processed_at)


class AdjustmentLocationTests(LocationWarehouseTestBase):
    """Design 8: an adjustment moves stock on ONE shelf, and copies a batch if needed."""

    def _post(self, qty, location=None, adjustment_type="CORRECTION"):
        body = {
            "variant": self.variant.pk,
            "adjustment_type": adjustment_type,
            "qty_adjusted": qty,
        }
        if location is not None:
            body["location"] = location.pk
        return self.client.post(ADJUSTMENTS_URL, body, format="json", **self.auth)

    def test_a_removal_only_takes_from_its_own_shelf(self):
        store_batch = self._stock_on("3", self.store)
        bodega_batch = self._stock_on("5", self.bodega)

        # 4 is on hand across the shop, but only 3 of it is at the Store.
        refused = self._post("-4", location=self.store, adjustment_type="SHRINKAGE")

        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "INSUFFICIENT_STOCK")
        self.assertEqual(StockAdjustment.objects.count(), 0)
        store_batch.refresh_from_db()
        bodega_batch.refresh_from_db()
        self.assertEqual(store_batch.current_qty, Decimal(3))
        self.assertEqual(bodega_batch.current_qty, Decimal(5))

        accepted = self._post("-2", location=self.store, adjustment_type="SHRINKAGE")

        self.assertEqual(accepted.status_code, 201, accepted.data)
        self.assertEqual(accepted.data["location"], self.store.pk)
        store_batch.refresh_from_db()
        bodega_batch.refresh_from_db()
        self.assertEqual(store_batch.current_qty, Decimal(1))
        self.assertEqual(bodega_batch.current_qty, Decimal(5))

    def test_an_addition_at_an_empty_shelf_creates_a_batch_copied_from_the_newest(self):
        source = self._stock_on("5", self.store)

        response = self._post("2", location=self.bodega)

        self.assertEqual(response.status_code, 201, response.data)
        source.refresh_from_db()
        self.assertEqual(source.current_qty, Decimal(5))
        copied = InventoryBatch.objects.get(variant=self.variant, location=self.bodega)
        self.assertEqual(copied.current_qty, Decimal(2))
        self.assertEqual(copied.initial_qty, Decimal(2))
        self.assertEqual(copied.source_batch_id, source.pk)
        # Cost and age travel with the stock, exactly as a transfer would carry them.
        self.assertEqual(copied.receipt_id, source.receipt_id)
        self.assertEqual(copied.unit_cost_landed, source.unit_cost_landed)
        self.assertEqual(copied.batch_selling_price, source.batch_selling_price)
        self.assertEqual(copied.markup_percentage, source.markup_percentage)
        self.assertEqual(copied.expiration_date, source.expiration_date)

    def test_an_addition_reopens_the_newest_batch_on_its_own_shelf(self):
        store_batch = self._stock_on("5", self.store)
        bodega_batch = self._stock_on("4", self.bodega)

        response = self._post("2", location=self.bodega)

        self.assertEqual(response.status_code, 201, response.data)
        store_batch.refresh_from_db()
        bodega_batch.refresh_from_db()
        self.assertEqual(bodega_batch.current_qty, Decimal(6))
        self.assertEqual(store_batch.current_qty, Decimal(5))
        self.assertEqual(InventoryBatch.objects.filter(variant=self.variant).count(), 2)

    def test_an_addition_with_no_batch_anywhere_keeps_the_old_refusal(self):
        response = self._post("2", location=self.bodega)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "NO_BATCH_HISTORY")
        self.assertEqual(StockAdjustment.objects.count(), 0)

    def test_an_inactive_shelf_refuses_additions_but_allows_removals(self):
        self._stock_on("5", self.store)
        bodega_batch = self._stock_on("4", self.bodega)
        self._deactivate(self.bodega)

        refused = self._post("2", location=self.bodega)

        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertEqual(StockAdjustment.objects.count(), 0)
        bodega_batch.refresh_from_db()
        self.assertEqual(bodega_batch.current_qty, Decimal(4))

        # Stock that is already in a closed place must stay manageable OUT of it.
        accepted = self._post("-1", location=self.bodega, adjustment_type="SHRINKAGE")

        self.assertEqual(accepted.status_code, 201, accepted.data)
        self.assertEqual(accepted.data["location"], self.bodega.pk)
        bodega_batch.refresh_from_db()
        self.assertEqual(bodega_batch.current_qty, Decimal(3))

    def test_an_omitted_location_means_the_variants_home(self):
        self._stock_on("5", self.store)

        response = self._post("-2", adjustment_type="SHRINKAGE")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["location"], self.variant.product.stored_at_id)
        self.assertEqual(
            InventoryBatch.objects.get(variant=self.variant).current_qty,
            Decimal(3),
        )

    def test_the_service_stamps_the_line_location_when_called_directly(self):
        """`process_goods_receipt` is also called through the ORM (seed, fixtures).

        A line that carries a destination is honoured there too, so a seed or a script
        cannot stock the wrong shelf by skipping the POST.
        """
        from .models import GoodsReceiptItem

        receipt = GoodsReceipt.objects.create(po=self.po, received_by=self.user)
        GoodsReceiptItem.objects.create(
            receipt=receipt,
            po_item=self.po_item,
            qty=Decimal(3),
            location=self.bodega,
        )
        self.po_item.received_qty = Decimal(3)
        self.po_item.save(update_fields=["received_qty"])

        process_goods_receipt(receipt=receipt, user=self.user)

        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.location_id, self.bodega.pk)


class AdjustmentsRoleFenceTests(LocationWarehouseTestBase):
    """The shelf does not widen who may write: a Cashier is still refused."""

    def test_a_cashier_cannot_adjust_a_shelf(self):
        self._stock_on("5", self.store)
        client = APIClient()

        response = client.post(
            ADJUSTMENTS_URL,
            {
                "variant": self.variant.pk,
                "adjustment_type": "SHRINKAGE",
                "qty_adjusted": "-1",
                "location": self.store.pk,
            },
            format="json",
            **self._auth(self.cashier),
        )

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(StockAdjustment.objects.count(), 0)
