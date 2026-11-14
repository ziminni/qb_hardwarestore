# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/reports/tests.py: the checker runs with a working
# directory outside the repo, so every `Model.objects` access reads as a type error on
# valid Django. The test run is the authority.

"""Phase 9 task B1 (decision 21 §1, plan Design 2 and 5) — reports that count stock.

Two sums already existed and both must ignore a batch that was **copied** off another
batch instead of arriving on a delivery:

  * the stock-movements report's `qty_in` ("what did deliveries bring in");
  * (Phase 9 B1) the inventory valuation's new `by_location` split, which is the per-shelf
    reading of the same stock the `by_category` rows total.

A transfer-born batch copies its source's `receipt` (so a supplier return still finds the
stock wherever it sits), which means a naive `Sum('batches__initial_qty')` over receipts
counts the SAME goods twice: once when they arrived and once when they moved. The marker
is `source_batch`: NULL means "minted by a delivery", set means "copied by a move".
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StorageLocation,
    Supplier,
    UnitOfMeasure,
)

User = get_user_model()

MOVEMENTS_URL = "/api/v1/reports/stock-movements/"
VALUATION_URL = "/api/v1/reports/inventory-valuation/"


class ReportStockTestBase(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="report_stocker",
            email="rs@x.com",
            password="pass12345",
            full_name="Stock Manager",
        )
        self.manager = User.objects.create_user(
            username="report_manager",
            email="rm2@x.com",
            password="pass12345",
            full_name="Store Manager",
        )
        self.manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.category = Category.objects.create(name="Cement")
        self.brand = Brand.objects.create(name="Rhino")
        self.uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        self.product = Product.objects.create(
            category=self.category,
            brand=self.brand,
            base_name="Portland Cement",
            stored_at=self.store,
        )
        self.variant = ProductVariant.objects.create(
            product=self.product,
            variant_name="40kg",
            base_uom=self.uom,
            min_stock_threshold=Decimal(5),
        )
        self.client = APIClient()
        self.client.force_authenticate(self.manager)

    def _receipt(self, received_qty):
        supplier = Supplier.objects.create(company_name="Acme Supply")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=self.variant,
            ordered_qty=Decimal(received_qty),
            unit_cost=Decimal(50),
            received_qty=Decimal(received_qty),
        )
        return GoodsReceipt.objects.create(po=po, received_by=self.user)

    def _batch(self, receipt, qty, *, location, source_batch=None, cost="50"):
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(cost),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(cost),
            location=location,
            source_batch=source_batch,
        )


class StockMovementsIgnoresCopiedBatchesTests(ReportStockTestBase):
    def test_qty_in_counts_only_what_the_delivery_brought_in(self):
        receipt = self._receipt("10")
        received = self._batch(receipt, "10", location=self.store)
        # A transfer-born batch on the SAME receipt: the goods arrived once and moved
        # once, so the delivery brought in 10 - not 14.
        self._batch(receipt, "4", location=self.bodega, source_batch=received)

        response = self.client.get(MOVEMENTS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["total_qty_in"], Decimal(10))
        self.assertEqual(response.data["receipts_by_day"][0]["qty_in"], Decimal(10))


class ValuationByLocationTests(ReportStockTestBase):
    def test_the_valuation_splits_the_same_stock_by_shelf(self):
        receipt = self._receipt("10")
        received = self._batch(receipt, "6", location=self.store, cost="50")
        self._batch(
            receipt, "4", location=self.bodega, source_batch=received, cost="50"
        )

        response = self.client.get(VALUATION_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = {row["location"]: row for row in response.data["by_location"]}
        self.assertEqual(sorted(rows), sorted([self.store.pk, self.bodega.pk]))
        self.assertEqual(rows[self.store.pk]["location_name"], "Store")
        self.assertEqual(rows[self.store.pk]["total_units"], Decimal(6))
        self.assertEqual(rows[self.store.pk]["cost_value"], Decimal("300.00"))
        self.assertEqual(rows[self.bodega.pk]["total_units"], Decimal(4))
        self.assertEqual(rows[self.bodega.pk]["cost_value"], Decimal("200.00"))
        # The per-shelf rows must add up to the totals the screen already shows.
        self.assertEqual(
            sum(row["total_units"] for row in rows.values()),
            response.data["totals"]["total_units"],
        )
        self.assertEqual(
            sum(row["cost_value"] for row in rows.values()),
            response.data["totals"]["total_cost_value"],
        )
