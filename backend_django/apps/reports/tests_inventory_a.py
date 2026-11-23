# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/reports/tests.py: the checker runs with a working
# directory outside the repo, so every `Model.objects` access reads as a type error on
# valid Django. The test run is the authority.

"""P2 inventory reports, batch A (reports-suite MAP).

Six reads, all computed from existing rows, no models:

* the movement report learns the three outflows it was missing (sales, transfers,
  supplier returns) and keeps its deliveries/adjustments sections intact;
* GRN and STN list one row per receiving document and one per transfer slip;
* batch age buckets on-hand quantity by how long it has sat there;
* shrinkage is the SHRINKAGE + DAMAGE adjustment ledger per day plus the % KPI;
* adjustments lists CORRECTION + RETURN with the peso variance at landed cost.

The landed cost comes from the variant's NEWEST batch: `StockAdjustment` stores no batch
link, and the newest delivery is the cost a correction is booked against. That is an
approximation, pinned here so a change to it is a visible test change.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    StockTransfer,
    StockTransferLine,
    StockTransferMove,
    StorageLocation,
    Supplier,
    SupplierBill,
    SupplierReturn,
    SupplierReturnDeduction,
    SupplierReturnLine,
    UnitOfMeasure,
    VariantUOM,
)
from apps.pos.models import Customer, SalesItem, SalesTransaction

User = get_user_model()

VALUATION_URL = "/api/v1/reports/inventory-valuation/"
MOVEMENTS_URL = "/api/v1/reports/stock-movements/"
GRN_URL = "/api/v1/reports/grn/"
STN_URL = "/api/v1/reports/stn/"
AGE_URL = "/api/v1/reports/batch-age/"
SHRINKAGE_URL = "/api/v1/reports/shrinkage/"
ADJUSTMENTS_URL = "/api/v1/reports/adjustments/"

TODAY = timezone.localdate()
RANGE = f"from={TODAY}&to={TODAY}"


class InventoryReportTestBase(TestCase):
    def setUp(self):
        self.manager = User.objects.create_user(
            username="inv_manager",
            email="im@x.com",
            password="pass12345",
            full_name="Store Manager",
        )
        self.manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.stocker = User.objects.create_user(
            username="inv_stocker",
            email="is@x.com",
            password="pass12345",
            full_name="Nena Cruz",
        )
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.category = Category.objects.create(name="Cement")
        self.brand = Brand.objects.create(name="Rhino")
        self.uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
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
            sku="CEM-40",
        )
        # One selling unit is 2 base units, so a row that forgot the conversion factor
        # shows up as a halved quantity instead of the real one.
        self.vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.uom,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal("280.00"),
        )
        self.supplier = Supplier.objects.create(company_name="Acme Supply")
        self.customer = Customer.objects.create(name="Juan Dela Cruz")
        self.client = APIClient()
        self.client.force_authenticate(self.manager)

    # --- fixtures ---------------------------------------------------------
    def _receipt(self, qtys, *, receive_date=None):
        """A received delivery with one line per qty, dated `receive_date` if given."""
        po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        for qty in qtys:
            po_item = POItem.objects.create(
                po=po,
                variant=self.variant,
                ordered_qty=Decimal(qty),
                unit_cost=Decimal(10),
                received_qty=Decimal(qty),
            )
            GoodsReceiptItem.objects.create(
                receipt=receipt, po_item=po_item, qty=Decimal(qty)
            )
        if receive_date is not None:
            # receive_date is auto_now_add, so the only way to age a delivery is an UPDATE.
            GoodsReceipt.objects.filter(pk=receipt.pk).update(receive_date=receive_date)
            receipt.receive_date = receive_date
        return receipt

    def _batch(self, receipt, qty, *, location=None, source_batch=None, cost="10"):
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(cost),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(cost),
            location=location or self.store,
            source_batch=source_batch,
        )

    def _adjustment(self, qty, adjustment_type):
        return StockAdjustment.objects.create(
            variant=self.variant,
            location=self.store,
            user=self.stocker,
            adjustment_type=adjustment_type,
            qty_adjusted=Decimal(qty),
        )


class MovementOutflowsTests(InventoryReportTestBase):
    """The report must say where stock WENT, not only what the count corrections took."""

    def test_outflows_are_counted_per_source_and_never_double_count_a_move(self):
        receipt = self._receipt([10])
        received = self._batch(receipt, "10")
        # A transfer-born batch on the SAME receipt: the goods arrived once, moved once.
        moved = self._batch(receipt, "4", location=self.bodega, source_batch=received)

        # 3 selling units of 2 base units = 6 base units sold.
        tx = SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.manager,
            transaction_no="T-1",
            grand_total=Decimal("840.00"),
            vat_registered=False,
        )
        SalesItem.objects.create(
            transaction=tx,
            variant_uom=self.vuom,
            qty=Decimal(3),
            unit_price=Decimal("280.00"),
            subtotal=Decimal("840.00"),
        )

        transfer = StockTransfer.objects.create(
            number="TR-20260101-0001",
            from_location=self.store,
            to_location=self.bodega,
            user=self.stocker,
        )
        line = StockTransferLine.objects.create(
            transfer=transfer,
            variant_uom=self.vuom,
            qty=Decimal(2),
            base_qty=Decimal(4),
        )
        StockTransferMove.objects.create(
            line=line, source_batch=received, dest_batch=moved, qty=Decimal(4)
        )

        supplier_return = SupplierReturn.objects.create(
            receipt=receipt,
            supplier=self.supplier,
            purchase_order=receipt.po,
            reason="damaged in transit",
            created_by=self.stocker,
        )
        return_line = SupplierReturnLine.objects.create(
            supplier_return=supplier_return,
            receipt_line=receipt.lines.first(),
            qty=Decimal(1),
            base_qty=Decimal(2),
            credit_value=Decimal(20),
        )
        SupplierReturnDeduction.objects.create(
            line=return_line,
            batch=received,
            qty=Decimal(2),
            unit_cost_landed=Decimal(10),
        )

        response = self.client.get(f"{MOVEMENTS_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        data = response.data
        # Deliveries still count what the DELIVERY brought in, not the moved copy.
        self.assertEqual(data["total_qty_in"], Decimal(10))
        self.assertEqual(data["total_sales_out"], Decimal(6))
        self.assertEqual(data["total_transfers_in"], Decimal(4))
        self.assertEqual(data["total_transfers_out"], Decimal(4))
        self.assertEqual(data["total_supplier_returns_out"], Decimal(2))
        self.assertEqual(len(data["sales_out_by_day"]), 1)
        self.assertEqual(data["sales_out_by_day"][0]["qty_out"], Decimal(6))
        self.assertEqual(data["transfers_in_by_day"][0]["qty_in"], Decimal(4))
        self.assertEqual(data["transfers_out_by_day"][0]["qty_out"], Decimal(4))
        self.assertEqual(data["supplier_returns_by_day"][0]["qty_out"], Decimal(2))
        # The old sections are untouched.
        self.assertEqual(data["receipts_by_day"][0]["qty_in"], Decimal(10))


class GrnReportTests(InventoryReportTestBase):
    def test_one_row_per_receipt_with_its_lines_and_bill(self):
        receipt = self._receipt([3, 5], receive_date=TODAY)
        bill = SupplierBill.objects.create(
            receipt=receipt,
            supplier=self.supplier,
            purchase_order=receipt.po,
            received_date=TODAY,
            terms_days=0,
            due_date=TODAY,
            gross_amount=Decimal("400.00"),
            discount_amount=Decimal(0),
            net_amount=Decimal("400.00"),
            vat_amount=Decimal(0),
            vat_rate=Decimal(0),
            total_amount=Decimal("400.00"),
            balance_amount=Decimal("400.00"),
        )

        response = self.client.get(f"{GRN_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["id"], receipt.pk)
        self.assertEqual(row["date"], str(TODAY))
        self.assertEqual(row["supplier"], "Acme Supply")
        self.assertEqual(row["items"], 2)
        self.assertEqual(row["qty"], Decimal(8))
        self.assertEqual(row["bill_id"], bill.pk)
        self.assertEqual(row["bill_total"], Decimal("400.00"))
        self.assertEqual(row["bill_status"], "UNPAID")
        self.assertEqual(response.data["totals"]["receipts"], 1)
        self.assertEqual(response.data["totals"]["qty"], Decimal(8))
        self.assertEqual(response.data["totals"]["billed"], 1)

    def test_a_receipt_without_a_bill_reads_unbilled(self):
        self._receipt([4], receive_date=TODAY)

        response = self.client.get(f"{GRN_URL}?{RANGE}")

        row = response.data["results"][0]
        self.assertIsNone(row["bill_id"])
        self.assertIsNone(row["bill_status"])
        self.assertEqual(response.data["totals"]["billed"], 0)
        self.assertEqual(response.data["totals"]["unbilled"], 1)


class StnReportTests(InventoryReportTestBase):
    def test_one_row_per_transfer_with_line_and_base_quantity(self):
        receipt = self._receipt([10])
        source = self._batch(receipt, "10")
        dest = self._batch(receipt, "8", location=self.bodega, source_batch=source)
        transfer = StockTransfer.objects.create(
            number="TR-20260101-0002",
            from_location=self.store,
            to_location=self.bodega,
            user=self.stocker,
        )
        for qty, base in (("2", "4"), ("2", "4")):
            line = StockTransferLine.objects.create(
                transfer=transfer,
                variant_uom=self.vuom,
                qty=Decimal(qty),
                base_qty=Decimal(base),
            )
            StockTransferMove.objects.create(
                line=line, source_batch=source, dest_batch=dest, qty=Decimal(base)
            )

        response = self.client.get(f"{STN_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["number"], "TR-20260101-0002")
        self.assertEqual(row["from_location"], self.store.pk)
        self.assertEqual(row["from_location_name"], "Store")
        self.assertEqual(row["to_location"], self.bodega.pk)
        self.assertEqual(row["to_location_name"], "Bodega")
        self.assertEqual(row["lines"], 2)
        self.assertEqual(row["qty"], Decimal(8))
        self.assertEqual(row["status"], "COMPLETED")
        self.assertEqual(response.data["totals"]["transfers"], 1)
        self.assertEqual(response.data["totals"]["qty"], Decimal(8))


class BatchAgeReportTests(InventoryReportTestBase):
    def test_quantity_is_bucketed_by_the_age_of_its_batch(self):
        old = self._receipt([5], receive_date=TODAY - timedelta(days=120))
        mid = self._receipt([4], receive_date=TODAY - timedelta(days=45))
        new = self._receipt([3], receive_date=TODAY - timedelta(days=5))
        self._batch(old, "5")
        self._batch(mid, "4")
        self._batch(new, "3")
        # An emptied batch has no quantity to age.
        self._batch(new, "0")

        response = self.client.get(AGE_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["variant_id"], self.variant.pk)
        self.assertEqual(row["product"], "Portland Cement")
        self.assertEqual(row["oldest_batch_age_days"], 120)
        self.assertEqual(row["qty_0_30"], Decimal(3))
        self.assertEqual(row["qty_30_90"], Decimal(4))
        self.assertEqual(row["qty_90_plus"], Decimal(5))
        self.assertEqual(row["total_qty"], Decimal(12))
        self.assertEqual(response.data["totals"]["variants"], 1)
        self.assertEqual(response.data["totals"]["total_qty"], Decimal(12))
        self.assertEqual(response.data["as_of"], str(TODAY))


class ShrinkageReportTests(InventoryReportTestBase):
    def test_losses_per_day_and_the_percent_against_opening_plus_received(self):
        # Opening: 100 base units delivered before the period, never sold or adjusted.
        self._batch(
            self._receipt([100], receive_date=TODAY - timedelta(days=10)), "100"
        )
        # Received inside the period: 50.
        self._batch(self._receipt([50], receive_date=TODAY), "50")
        self._adjustment("-5", StockAdjustment.AdjustmentType.SHRINKAGE)
        self._adjustment("-5", StockAdjustment.AdjustmentType.DAMAGE)
        self._adjustment("1", StockAdjustment.AdjustmentType.CORRECTION)

        response = self.client.get(f"{SHRINKAGE_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        totals = response.data["totals"]
        self.assertEqual(totals["qty"], Decimal(10))
        self.assertEqual(totals["value"], Decimal("100.00"))
        self.assertEqual(totals["opening_qty"], Decimal(100))
        self.assertEqual(totals["received_qty"], Decimal(50))
        # 10 / (100 + 50) = 6.666...% -> one rounding, to the centavo.
        self.assertEqual(totals["shrinkage_percent"], Decimal("6.67"))
        self.assertEqual(totals["adjustments"], 2)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["date"], str(TODAY))
        self.assertEqual(rows[0]["qty"], Decimal(10))
        self.assertEqual(rows[0]["value"], Decimal("100.00"))


class AdjustmentsReportTests(InventoryReportTestBase):
    def test_corrections_and_returns_only_with_signed_peso_variance(self):
        self._batch(self._receipt([10], receive_date=TODAY), "10", cost="10")
        self._adjustment("4", StockAdjustment.AdjustmentType.CORRECTION)
        self._adjustment("-2", StockAdjustment.AdjustmentType.RETURN)
        self._adjustment("-1", StockAdjustment.AdjustmentType.SHRINKAGE)

        response = self.client.get(f"{ADJUSTMENTS_URL}?{RANGE}")

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual(len(rows), 2)
        by_type = {row["type"]: row for row in rows}
        self.assertEqual(sorted(by_type), ["CORRECTION", "RETURN"])
        correction = by_type["CORRECTION"]
        self.assertEqual(correction["qty"], Decimal(4))
        self.assertEqual(correction["value"], Decimal("40.00"))
        self.assertEqual(correction["product"], "Portland Cement")
        self.assertEqual(correction["location_name"], "Store")
        self.assertEqual(correction["user"], "Nena Cruz")
        self.assertEqual(correction["date"][:10], str(TODAY))
        self.assertEqual(by_type["RETURN"]["qty"], Decimal(-2))
        self.assertEqual(by_type["RETURN"]["value"], Decimal("-20.00"))
        self.assertEqual(response.data["totals"]["adjustments"], 2)
        self.assertEqual(response.data["totals"]["qty"], Decimal(2))
        self.assertEqual(response.data["totals"]["value"], Decimal("20.00"))


class BatchAInventoryReadPermissionTests(InventoryReportTestBase):
    """Batch A's six reads plus inventory valuation belong to the INVENTORY area.

    A Stock Manager opens them off the inventory catalogue; sales money stays behind
    `IsManagerRole`, so a Cashier is refused here and a Store Manager is not missed.
    """

    URLS = (
        VALUATION_URL,
        f"{MOVEMENTS_URL}?{RANGE}",
        f"{GRN_URL}?{RANGE}",
        f"{STN_URL}?{RANGE}",
        AGE_URL,
        f"{SHRINKAGE_URL}?{RANGE}",
        f"{ADJUSTMENTS_URL}?{RANGE}",
    )

    def _client_for(self, user):
        client = APIClient()
        client.force_authenticate(user)
        return client

    def _cashier(self):
        cashier = User.objects.create_user(
            username="a_cashier",
            email="ac@x.com",
            password="pass12345",
            full_name="Till One",
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        return cashier

    def test_a_stock_manager_can_read_every_batch_a_inventory_report(self):
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        client = self._client_for(self.stocker)

        for url in self.URLS:
            self.assertEqual(client.get(url).status_code, 200, url)

    def test_a_cashier_cannot_read_any_batch_a_inventory_report(self):
        client = self._client_for(self._cashier())

        for url in self.URLS:
            self.assertEqual(client.get(url).status_code, 403, url)
