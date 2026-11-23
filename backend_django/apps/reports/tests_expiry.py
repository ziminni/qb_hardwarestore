# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/reports/tests.py: the checker runs with a working
# directory outside the repo, so every `Model.objects` access reads as a type error on
# valid Django. The test run is the authority.

"""Expiry tracking (reports-suite MAP, P2 inventory reports).

Three facts, one file, because they are one feature end to end:

  * `Product.tracks_expiry` — opt-in, default False. Only cement and paint care, and a
    product that does not track expiry must keep behaving exactly as before.
  * the optional Expires date a goods receipt line carries, which `process/` copies onto
    the FIFO batch it mints (`InventoryBatch.expiration_date` already existed);
  * `GET /reports/expiry/` — the stocked batches that are expired or expiring, bucketed
    0-30 / 31-60 / 61-90 days plus already-expired, with the Near-expiry % KPI.

A batch with NO date is never "expiring": absent is not a fake far-future date.
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
EXPIRY_URL = "/api/v1/reports/expiry/"
RECEIPTS_URL = "/api/v1/goods-receipts/"


class ExpiryTestBase(TestCase):
    def setUp(self):
        self.stocker = User.objects.create_user(
            username="expiry_stocker",
            email="ex@x.com",
            password="pass12345",
            full_name="Stock Manager",
        )
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.location = StorageLocation.objects.get(name="Store")
        self.category = Category.objects.create(name="Cement")
        self.brand = Brand.objects.create(name="Rhino")
        self.uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        self.product = Product.objects.create(
            category=self.category,
            brand=self.brand,
            base_name="Portland Cement",
            stored_at=self.location,
        )
        self.variant = ProductVariant.objects.create(
            product=self.product,
            variant_name="40kg",
            base_uom=self.uom,
        )
        self.supplier = Supplier.objects.create(company_name="Acme Supply")
        self.client = APIClient()
        self.client.force_authenticate(self.stocker)

    # -- helpers ---------------------------------------------------------
    def _po(self, qty="10", cost="50.00", variant=None):
        po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.stocker,
            status=PurchaseOrder.Status.ORDERED,
        )
        item = POItem.objects.create(
            po=po,
            variant=variant or self.variant,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal(cost),
        )
        return po, item

    def _record(self, po, item, qty="10", **extra):
        return self.client.post(
            RECEIPTS_URL,
            {"po": po.id, "items": [{"po_item": item.id, "qty": qty, **extra}]},
            format="json",
        )

    def _process(self, receipt_id):
        return self.client.post(
            f"{RECEIPTS_URL}{receipt_id}/process/", {}, format="json"
        )

    def _stocked_batch(self, qty, cost="50.00", days_left=None):
        """A batch already in stock, dated `days_left` from today (None = undated)."""
        po, _item = self._po(qty=qty, cost=cost)
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.stocker)
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            location=self.location,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(cost),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(cost),
            expiration_date=None
            if days_left is None
            else timezone.localdate() + timedelta(days=days_left),
        )


class TracksExpiryFlagTests(ExpiryTestBase):
    def test_a_product_does_not_track_expiry_by_default(self):
        self.assertFalse(self.product.tracks_expiry)

    def test_the_flag_can_be_set_for_cement(self):
        self.product.tracks_expiry = True
        self.product.save(update_fields=["tracks_expiry"])
        self.product.refresh_from_db()
        self.assertTrue(self.product.tracks_expiry)

    def test_a_purchase_order_line_reports_whether_its_product_tracks_expiry(self):
        po, _item = self._po()
        self.product.tracks_expiry = True
        self.product.save(update_fields=["tracks_expiry"])

        response = self.client.get(f"/api/v1/purchase-orders/{po.id}/")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data["items"][0]["tracks_expiry"])


class ReceiptExpiryDateTests(ExpiryTestBase):
    def test_the_expires_date_a_receipt_carries_reaches_its_batch(self):
        self.product.tracks_expiry = True
        self.product.save(update_fields=["tracks_expiry"])
        po, item = self._po()
        expires_on = timezone.localdate() + timedelta(days=40)

        recorded = self._record(po, item, expiration_date=str(expires_on))
        self.assertEqual(recorded.status_code, 201, recorded.data)
        receipt_id = recorded.data["id"]
        self.assertEqual(recorded.data["lines"][0]["expiration_date"], str(expires_on))

        processed = self._process(receipt_id)

        self.assertEqual(processed.status_code, 200, processed.data)
        self.assertEqual(len(processed.data), 1)
        self.assertEqual(processed.data[0]["expiration_date"], str(expires_on))
        batch = InventoryBatch.objects.get(pk=processed.data[0]["id"])
        self.assertEqual(batch.expiration_date, expires_on)

    def test_a_receipt_with_no_expires_date_leaves_the_batch_undated(self):
        po, item = self._po()

        recorded = self._record(po, item)
        self.assertEqual(recorded.status_code, 201, recorded.data)
        self.assertIsNone(recorded.data["lines"][0]["expiration_date"])

        processed = self._process(recorded.data["id"])

        self.assertEqual(processed.status_code, 200, processed.data)
        batch = InventoryBatch.objects.get(pk=processed.data[0]["id"])
        self.assertIsNone(batch.expiration_date)

    def test_a_date_that_is_not_a_date_is_refused(self):
        po, item = self._po()

        response = self._record(po, item, expiration_date="not-a-date")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(GoodsReceipt.objects.count(), 0)


class ExpiryReportTests(ExpiryTestBase):
    def _fixture(self):
        """Six batches: expired, 10, 45 and 75 days out, undated, and far out."""
        self._stocked_batch("10", "50.00", days_left=-5)  # value 500, expired
        self._stocked_batch("4", "25.00", days_left=10)  # value 100, 0-30
        self._stocked_batch("2", "50.00", days_left=45)  # value 100, 31-60
        self._stocked_batch("6", "50.00", days_left=75)  # value 300, 61-90
        self._stocked_batch("8", "10.00", days_left=None)  # value  80, undated
        self._stocked_batch("5", "100.00", days_left=200)  # value 500, beyond

    def test_rows_are_the_expiring_and_expired_batches_most_urgent_first(self):
        self._fixture()

        response = self.client.get(EXPIRY_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data["results"]
        self.assertEqual([row["days_left"] for row in rows], [-5, 10, 45, 75])
        self.assertEqual(
            [row["bucket"] for row in rows],
            ["expired", "0-30", "31-60", "61-90"],
        )
        self.assertEqual(rows[0]["location"], "Store")
        self.assertEqual(rows[0]["qty"], Decimal("10.00"))
        self.assertEqual(rows[0]["value"], Decimal("500.00"))
        self.assertEqual(rows[0]["product"], "Portland Cement")
        self.assertEqual(rows[0]["variant"], "40kg")
        self.assertEqual(response.data["count"], 4)

    def test_bucket_totals_and_the_near_expiry_kpi_use_landed_value(self):
        self._fixture()

        response = self.client.get(EXPIRY_URL)

        totals = response.data["totals"]
        self.assertEqual(totals["rows"], 4)
        self.assertEqual(totals["value_expired"], Decimal("500.00"))
        self.assertEqual(totals["value_0_30"], Decimal("100.00"))
        self.assertEqual(totals["value_31_60"], Decimal("100.00"))
        self.assertEqual(totals["value_61_90"], Decimal("300.00"))
        # Total stock is 1580: the undated and the 200-day batches count as on hand,
        # they are just not expiring.
        self.assertEqual(totals["on_hand_value"], Decimal("1580.00"))
        # Default window is 30 days: expired + 0-30 = 600 of 1580.
        self.assertEqual(totals["near_expiry_value"], Decimal("600.00"))
        self.assertEqual(totals["near_expiry_pct"], Decimal("37.97"))
        # 100 + 500 sit inside 60 days, plus the expired 500.
        self.assertEqual(response.data["days"], 30)

    def test_the_days_parameter_widens_the_window(self):
        self._fixture()

        response = self.client.get(EXPIRY_URL, {"days": 60})

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["days"], 60)
        self.assertEqual(
            response.data["totals"]["near_expiry_value"], Decimal("700.00")
        )
        self.assertEqual(response.data["totals"]["near_expiry_pct"], Decimal("44.30"))

    def test_no_stock_answers_a_null_kpi_rather_than_zero(self):
        response = self.client.get(EXPIRY_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["results"], [])
        self.assertIsNone(response.data["totals"]["near_expiry_pct"])
        self.assertEqual(response.data["totals"]["on_hand_value"], Decimal("0.00"))

    def test_a_sold_out_batch_is_not_expiring_stock(self):
        batch = self._stocked_batch("10", "50.00", days_left=5)
        InventoryBatch.objects.filter(pk=batch.pk).update(current_qty=Decimal(0))

        response = self.client.get(EXPIRY_URL)

        self.assertEqual(response.data["results"], [])
        self.assertEqual(response.data["totals"]["on_hand_value"], Decimal("0.00"))

    def test_a_bad_days_parameter_is_refused(self):
        response = self.client.get(EXPIRY_URL, {"days": "soon"})

        self.assertEqual(response.status_code, 400, response.data)

    def test_a_cashier_cannot_read_the_expiry_report(self):
        cashier = User.objects.create_user(
            username="expiry_cashier",
            email="exc@x.com",
            password="pass12345",
            full_name="Cashier",
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        client = APIClient()
        client.force_authenticate(cashier)

        self.assertEqual(client.get(EXPIRY_URL).status_code, 403)
