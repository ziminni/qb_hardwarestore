# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/reports/tests.py: the checker runs with a working
# directory outside the repo, so every `Model.objects` access reads as a type error on
# valid Django. The test run is the authority.

"""P2 inventory reports, batch B (reports-suite MAP).

Four reads, all computed from existing rows, no models:

* reorder lists every variant whose on-hand quantity is at or below its own
  `min_stock_threshold`, with the shelf split so a manager knows WHERE to look;
* dead stock is decision 03's rule: zero completed sales quantity in a trailing window
  (default 90 days), on-hand > 0, never-stocked variants left out;
* fast/slow splits the range's sold SKUs into the top 20% and the bottom 20% by base
  units, each row carrying its quantity and net merchandise;
* cycle count is the CORRECTION ledger (date, product, shelf, user, signed qty and peso
  variance at newest-batch landed cost) plus the shrinkage % KPI.

The locked numbers (window, percentiles, landed cost) are pinned here so a change to any
of them is a visible test change, not a silently different report.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils import timezone
from rest_framework.test import APIClient

from apps.inventory.models import (
    GoodsReceipt,
    InventoryBatch,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    VariantUOM,
)
from apps.pos.models import SalesItem, SalesTransaction
from apps.reports.tests_inventory_a import InventoryReportTestBase

User = get_user_model()

REORDER_URL = "/api/v1/reports/reorder/"
DEAD_STOCK_URL = "/api/v1/reports/dead-stock/"
FAST_SLOW_URL = "/api/v1/reports/fast-slow/"
CYCLE_COUNT_URL = "/api/v1/reports/cycle-count/"

TODAY = timezone.localdate()
RANGE = f"from={TODAY}&to={TODAY}"


class InventoryReportBTestBase(InventoryReportTestBase):
    """Batch A's fixtures plus the ones these four reports need: many variants."""

    def _variant(self, name, *, sku, threshold=0):
        variant = ProductVariant.objects.create(
            product=self.product,
            variant_name=name,
            base_uom=self.uom,
            sku=sku,
            min_stock_threshold=Decimal(threshold),
        )
        uom = VariantUOM.objects.create(
            variant=variant,
            uom=self.uom,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal("280.00"),
        )
        return variant, uom

    def _cashier(self):
        # No password: `force_authenticate` never checks one, and a fixture that cannot
        # sign in is one less credential in the repo.
        user = User.objects.create_user(
            username="b_cashier",
            email="bc@x.com",
            full_name="Cashier Bee",
        )
        user.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        return user

    def _receipt_for(self, *, receive_date=None):
        po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        if receive_date is not None:
            # receive_date is auto_now_add, so the only way to age a delivery is an UPDATE.
            GoodsReceipt.objects.filter(pk=receipt.pk).update(receive_date=receive_date)
            receipt.receive_date = receive_date
        return receipt

    def _stock(self, variant, qty, *, cost="10", location=None, receive_date=None):
        """One batch of `variant` sitting on a shelf, at a landed cost per base unit."""
        return InventoryBatch.objects.create(
            variant=variant,
            receipt=self._receipt_for(receive_date=receive_date),
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(cost),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(cost),
            location=location or self.store,
        )

    def _sale(self, variant_uom, selling_qty, *, days_ago=0, price="280"):
        """One completed sale of `selling_qty` selling units, dated `days_ago` back."""
        qty = Decimal(selling_qty)
        unit_price = Decimal(price)
        tx = SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.manager,
            transaction_no=f"B-{SalesTransaction.objects.count() + 1}",
            grand_total=qty * unit_price,
            vat_registered=False,
        )
        when = timezone.now() - timedelta(days=days_ago)
        SalesTransaction.objects.filter(pk=tx.pk).update(trans_date=when)
        SalesItem.objects.create(
            transaction=tx,
            variant_uom=variant_uom,
            qty=qty,
            unit_price=unit_price,
            subtotal=qty * unit_price,
        )
        return tx


class ReorderReportTests(InventoryReportBTestBase):
    def test_variants_at_or_below_their_threshold_with_the_shelf_split(self):
        # At the threshold counts: 10 on hand against a threshold of 12 is short by 2.
        ProductVariant.objects.filter(pk=self.variant.pk).update(
            min_stock_threshold=Decimal(12)
        )
        self._stock(self.variant, "6")
        self._stock(self.variant, "4", location=self.bodega)
        # Exactly AT the threshold is still a reorder: the shelf is already empty enough.
        at_threshold, _ = self._variant("50kg", sku="CEM-50", threshold=10)
        self._stock(at_threshold, "10")
        # Above the threshold: nothing to buy.
        comfortable, _ = self._variant("25kg", sku="CEM-25", threshold=5)
        self._stock(comfortable, "20")

        response = self.client.get(REORDER_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 2, rows)
        short = rows[0]
        self.assertEqual(short["variant_id"], self.variant.pk)
        self.assertEqual(short["sku"], "CEM-40")
        self.assertEqual(short["product"], "Portland Cement")
        self.assertEqual(short["variant"], "40kg")
        self.assertEqual(short["uom"], "BAG")
        self.assertEqual(short["on_hand"], Decimal(10))
        self.assertEqual(short["threshold"], Decimal(12))
        self.assertEqual(short["gap"], Decimal(2))
        self.assertEqual(
            short["locations"],
            [
                {
                    "location": self.store.pk,
                    "location_name": "Store",
                    "qty": Decimal(6),
                },
                {
                    "location": self.bodega.pk,
                    "location_name": "Bodega",
                    "qty": Decimal(4),
                },
            ],
        )
        self.assertEqual(rows[1]["sku"], "CEM-50")
        self.assertEqual(rows[1]["gap"], Decimal(0))
        self.assertNotIn(
            "CEM-25", [row["sku"] for row in rows], "stock above threshold reordered"
        )
        totals = response.data["totals"]
        self.assertEqual(totals["variants"], 2)
        self.assertEqual(totals["on_hand"], Decimal(20))
        self.assertEqual(totals["threshold"], Decimal(22))
        self.assertEqual(totals["gap"], Decimal(2))


class DeadStockReportTests(InventoryReportBTestBase):
    def _fixture(self):
        # Sold 100 days ago and still on the shelf: dead under the default 90 days.
        self._stock(self.variant, "10", cost="10")
        self._sale(self.vuom, "4", days_ago=100)
        # Sold 60 days ago: inside the 90-day window, so not dead yet.
        alive, alive_uom = self._variant("50kg", sku="CEM-50")
        self._stock(alive, "5")
        self._sale(alive_uom, "2", days_ago=60)
        # Never sold, but stock is sitting there: dead, with no last-sale date.
        never_sold, _ = self._variant("25kg", sku="CEM-25")
        self._stock(never_sold, "3", cost="20")
        # Sold long ago and now empty: no money tied up, so not dead stock.
        emptied, emptied_uom = self._variant("20kg", sku="CEM-20")
        self._stock(emptied, "0")
        self._sale(emptied_uom, "1", days_ago=200)
        # Never stocked at all: nothing to report.
        self._variant("10kg", sku="CEM-10")

    def test_zero_sales_in_the_trailing_90_days_with_stock_on_hand(self):
        self._fixture()

        response = self.client.get(DEAD_STOCK_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["days"], 90)
        rows = response.data["results"]
        self.assertEqual([row["sku"] for row in rows], ["CEM-40", "CEM-25"], rows)
        first = rows[0]
        self.assertEqual(first["on_hand"], Decimal(10))
        self.assertEqual(first["days_since_last_sale"], 100)
        self.assertEqual(first["landed_value"], Decimal("100.00"))
        # Never sold is not the same fact as sold long ago.
        self.assertIsNone(rows[1]["days_since_last_sale"])
        self.assertEqual(rows[1]["landed_value"], Decimal("60.00"))
        totals = response.data["totals"]
        self.assertEqual(totals["variants"], 2)
        self.assertEqual(totals["on_hand"], Decimal(13))
        self.assertEqual(totals["landed_value"], Decimal("160.00"))

    def test_the_days_parameter_moves_the_window(self):
        self._fixture()

        response = self.client.get(f"{DEAD_STOCK_URL}?days=31")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["days"], 31)
        rows = response.data["results"]
        # Sorted by the money sitting idle: 100.00, 60.00, 50.00.
        self.assertEqual(
            [row["sku"] for row in rows], ["CEM-40", "CEM-25", "CEM-50"], rows
        )
        # 60 days since the sale is now outside a 31-day window.
        self.assertEqual(rows[2]["days_since_last_sale"], 60)

    def test_a_non_numeric_days_parameter_is_a_400(self):
        response = self.client.get(f"{DEAD_STOCK_URL}?days=soon")

        self.assertEqual(response.status_code, 400, response.data)


class FastSlowReportTests(InventoryReportBTestBase):
    def test_top_and_bottom_20_percent_by_base_units_with_quantity_and_net(self):
        # Base units sold: 100, 60, 40, 20, 5. One selling unit is 2 base units.
        specs = [
            ("A", "100", "50"),
            ("B", "60", "30"),
            ("C", "40", "20"),
            ("D", "20", "10"),
            ("E", "5", "2.5"),
        ]
        for name, _base, selling in specs:
            _variant, uom = self._variant(f"Mover {name}", sku=f"MOV-{name}")
            self._sale(uom, selling)

        response = self.client.get(f"{FAST_SLOW_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        # 5 SKUs, 20% -> one fast, one slow; the middle three are neither.
        self.assertEqual(len(rows), 2, rows)
        fast, slow = rows
        self.assertEqual(fast["band"], "FAST")
        self.assertEqual(fast["sku"], "MOV-A")
        self.assertEqual(fast["qty_base"], Decimal(100))
        self.assertEqual(fast["net_merchandise"], Decimal("14000.00"))
        self.assertEqual(slow["band"], "SLOW")
        self.assertEqual(slow["sku"], "MOV-E")
        self.assertEqual(slow["qty_base"], Decimal(5))
        self.assertEqual(slow["net_merchandise"], Decimal("700.00"))
        totals = response.data["totals"]
        self.assertEqual(totals["skus_sold"], 5)
        self.assertEqual(totals["fast"], 1)
        self.assertEqual(totals["slow"], 1)
        self.assertEqual(totals["qty_base"], Decimal(225))
        self.assertEqual(totals["net_merchandise"], Decimal("31500.00"))


class CycleCountReportTests(InventoryReportBTestBase):
    def test_corrections_with_signed_peso_variance_and_the_shrinkage_kpi(self):
        self._stock(self.variant, "45", cost="10")
        self._adjustment("-6", StockAdjustment.AdjustmentType.CORRECTION)
        self._adjustment("1", StockAdjustment.AdjustmentType.CORRECTION)
        # Not count corrections: a supplier return and a loss live in their own reports.
        self._adjustment("-2", StockAdjustment.AdjustmentType.RETURN)
        self._adjustment("-1", StockAdjustment.AdjustmentType.SHRINKAGE)

        response = self.client.get(f"{CYCLE_COUNT_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 2, rows)
        found, shortage = rows
        self.assertEqual(found["qty"], Decimal(1))
        self.assertEqual(found["value"], Decimal("10.00"))
        self.assertEqual(shortage["qty"], Decimal(-6))
        self.assertEqual(shortage["value"], Decimal("-60.00"))
        self.assertEqual(shortage["product"], "Portland Cement")
        self.assertEqual(shortage["variant"], "40kg")
        self.assertEqual(shortage["location_name"], "Store")
        self.assertEqual(shortage["user"], "Nena Cruz")
        self.assertEqual(shortage["date"][:10], str(TODAY))
        totals = response.data["totals"]
        self.assertEqual(totals["adjustments"], 2)
        self.assertEqual(totals["qty"], Decimal(-5))
        self.assertEqual(totals["value"], Decimal("-50.00"))
        # The count saw 50 (45 left + the 5 the count found missing), so 5/50 = 10%.
        self.assertEqual(totals["on_hand_qty"], Decimal(45))
        self.assertEqual(totals["shrinkage_percent"], Decimal("10.00"))
        self.assertEqual(totals["missing_cost_lines"], 0)

    def test_a_correction_on_a_variant_with_no_batch_history_is_uncosted(self):
        self._stock(self.variant, "45", cost="10")
        self._adjustment("-6", StockAdjustment.AdjustmentType.CORRECTION)
        # Never delivered, so there is no landed cost to book the variance against.
        uncosted, _ = self._variant("Bulk", sku="CEM-BULK")
        StockAdjustment.objects.create(
            variant=uncosted,
            location=self.store,
            user=self.stocker,
            adjustment_type=StockAdjustment.AdjustmentType.CORRECTION,
            qty_adjusted=Decimal(-2),
        )

        response = self.client.get(f"{CYCLE_COUNT_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = {row["variant"]: row for row in response.data["results"]}
        self.assertEqual(rows["40kg"]["value"], Decimal("-60.00"))
        self.assertIsNone(rows["Bulk"]["value"])
        totals = response.data["totals"]
        self.assertEqual(totals["value"], Decimal("-60.00"))
        self.assertEqual(totals["missing_cost_lines"], 1)


class ReportBPermissionTests(InventoryReportBTestBase):
    URLS = (
        REORDER_URL,
        DEAD_STOCK_URL,
        FAST_SLOW_URL,
        f"{CYCLE_COUNT_URL}?{RANGE}",
    )

    def _client_for(self, user):
        client = APIClient()
        client.force_authenticate(user)
        return client

    def test_a_stock_manager_can_read_every_batch_b_report(self):
        # The stocker's demo opens the inventory catalogue: these four reads are part of
        # that area, so IsInventoryRole (Stock Manager / Store Manager / Admin) guards
        # them, not the manager-only fence.
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        client = self._client_for(self.stocker)

        for url in self.URLS:
            self.assertEqual(client.get(url).status_code, 200, url)

    def test_a_cashier_cannot_read_any_batch_b_report(self):
        client = self._client_for(self._cashier())

        for url in self.URLS:
            self.assertEqual(client.get(url).status_code, 403, url)
