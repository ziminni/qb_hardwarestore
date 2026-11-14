# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/inventory/tests_storage_locations.py: this checker
# runs from a working directory outside the repo, so `Model.objects` is a false positive
# on valid Django.

"""Phase 9 task B1 (decision 21 §1, plan Design 1 and 5) — stock knows WHERE it sits.

Decision 21 §1: every existing batch is placed at its product's **Stored at** location,
which from then on is the product's HOME location. That is a data migration, so the first
class below rolls `inventory` back to the pre-B1 schema, writes a batch and an adjustment
the way that schema allowed (no location at all), migrates forward and reads the result:
each row must carry its product's shelf, and the column must be NOT NULL afterwards - a
nullable column would let the next writer mint stock with no location and the per-location
sums would silently split stock between "Store" and "nowhere".

The second class pins the read the clients will use instead of summing `/batches/` by
hand: `GET /api/v1/stock-on-hand/` is ONE query (a per-batch fan-out would make the till's
size of the shop cost grow with the shipment count) and it answers the location's NAME and
whether it is the product's home, so no client has to join products to locations itself.

Real JWT logins are not needed here: both permissions under test are `IsAuthenticated`
(the `/batches/` rule decision 21 §5 keeps), so `force_authenticate` keeps the one-query
count about the endpoint and not about token decoding.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase
from django.test.utils import CaptureQueriesContext
from rest_framework.test import APIClient

from .models import (
    InventoryBatch,
    Product,
    ProductVariant,
    StorageLocation,
)
from .tests import InventoryTestBase

User = get_user_model()

ON_HAND_URL = "/api/v1/stock-on-hand/"
BATCHES_URL = "/api/v1/batches/"


class BatchAndAdjustmentLocationBackfillTests(TransactionTestCase):
    """Migration 0015 over rows written by the PRE-B1 schema, the way production runs it.

    The rows are created with the HISTORICAL models after rolling `inventory` back to
    0014, because the current models cannot write a batch without a location once 0015 is
    applied.
    """

    OLD_INVENTORY_LEAF = "0014_supplier_credit_notes"

    def _migrate(self, targets):
        executor = MigrationExecutor(connection)
        executor.loader.build_graph()
        executor.migrate(targets)
        return executor

    def _latest_targets(self):
        return MigrationExecutor(connection).loader.graph.leaf_nodes()

    def _old_targets(self):
        return [
            (app, name) for app, name in self._latest_targets() if app != "inventory"
        ] + [("inventory", self.OLD_INVENTORY_LEAF)]

    def tearDown(self):
        # Leave the shared test database at head even when an assertion failed.
        self._migrate(self._latest_targets())

    def _is_nullable(self, table, column):
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT is_nullable FROM information_schema.columns "
                "WHERE table_name = %s AND column_name = %s",
                [table, column],
            )
            row = cursor.fetchone()
        self.assertIsNotNone(row, f"column {table}.{column} must exist after 0015")
        return row[0] == "YES"

    def test_the_forward_migration_places_every_batch_and_adjustment_at_its_home(self):
        old_targets = self._old_targets()
        executor = self._migrate(old_targets)
        old = executor.loader.project_state(old_targets).apps

        old_storage = old.get_model("inventory", "StorageLocation")
        old_category = old.get_model("inventory", "Category")
        old_brand = old.get_model("inventory", "Brand")
        old_uom = old.get_model("inventory", "UnitOfMeasure")
        old_product = old.get_model("inventory", "Product")
        old_variant = old.get_model("inventory", "ProductVariant")
        old_supplier = old.get_model("inventory", "Supplier")
        old_po = old.get_model("inventory", "PurchaseOrder")
        old_receipt = old.get_model("inventory", "GoodsReceipt")
        old_batch = old.get_model("inventory", "InventoryBatch")
        old_adjustment = old.get_model("inventory", "StockAdjustment")

        # Both shelves should exist by 0014 (0011 seeded them), but a flush in an earlier
        # TransactionTestCase removes seeded rows and data migrations do not re-run, so the
        # test creates them if missing instead of assuming the seed survived.
        old_storage.objects.get_or_create(name="Store")
        bodega_id = old_storage.objects.get_or_create(name="Bodega")[0].pk
        user = User.objects.create_user(
            username="backfill",
            email="b@x.com",
            password="pass12345",
            full_name="Stock Manager",
        )
        category = old_category.objects.create(name="Cement")
        brand = old_brand.objects.create(name="Rhino")
        uom = old_uom.objects.get_or_create(code="BAG", defaults={"name": "Bag"})[0]
        product = old_product.objects.create(
            category=category,
            brand=brand,
            base_name="Portland Cement",
            stored_at_id=bodega_id,
        )
        variant = old_variant.objects.create(
            product=product,
            variant_name="40kg",
            base_uom=uom,
            min_stock_threshold=Decimal(5),
        )
        supplier = old_supplier.objects.create(company_name="Acme Supply")
        po = old_po.objects.create(
            supplier=supplier, created_by_id=user.pk, status="ORDERED"
        )
        receipt = old_receipt.objects.create(po=po, received_by_id=user.pk)
        batch_ids = [
            old_batch.objects.create(
                variant=variant,
                receipt=receipt,
                initial_qty=Decimal(qty),
                current_qty=Decimal(qty),
                unit_cost_landed=Decimal(50),
                markup_percentage=Decimal(0),
                batch_selling_price=Decimal(50),
            ).pk
            for qty in ("10", "4")
        ]
        adjustment = old_adjustment.objects.create(
            variant=variant,
            user_id=user.pk,
            adjustment_type="SHRINKAGE",
            qty_adjusted=Decimal(-1),
        )

        self._migrate(self._latest_targets())

        for batch in InventoryBatch.objects.filter(pk__in=batch_ids):
            self.assertEqual(
                batch.location_id,
                bodega_id,
                "every pre-B1 batch must sit at its product's Stored at location",
            )
        adjustment_now = InventoryBatch._meta.apps.get_model(
            "inventory", "StockAdjustment"
        ).objects.get(pk=adjustment.pk)
        self.assertEqual(adjustment_now.location_id, bodega_id)

        self.assertFalse(
            self._is_nullable("inventory_batch", "location_id"),
            "0015 must leave the batch location column NOT NULL",
        )
        self.assertFalse(
            self._is_nullable("inventory_stock_adjustment", "location_id"),
            "0015 must leave the adjustment location column NOT NULL",
        )


class StockOnHandTests(InventoryTestBase):
    """`GET /api/v1/stock-on-hand/` — the per-location read the clients stop deriving."""

    def setUp(self):
        super().setUp()
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.cashier = User.objects.create_user(
            username="on_hand_cashier",
            email="c@x.com",
            password="pass12345",
            full_name="Cashier",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.cashier)

    def _batch(self, location, qty, **overrides):
        supplier = Supplier_fixture()
        po = PurchaseOrder_fixture(supplier=supplier, user=self.user)
        receipt = GoodsReceipt_fixture(po=po, user=self.user)
        return InventoryBatch.objects.create(
            variant=overrides.pop("variant", self.variant),
            receipt=receipt,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(50),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(50),
            location=location,
            **overrides,
        )

    def test_the_read_is_one_query_for_the_whole_shop(self):
        self._batch(self.store, "5")
        self._batch(self.bodega, "3")

        with CaptureQueriesContext(connection) as captured:
            response = self.client.get(ON_HAND_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            len(captured.captured_queries),
            1,
            [q["sql"] for q in captured.captured_queries],
        )

    def test_a_row_is_variant_plus_location_with_its_name_and_home_flag(self):
        self.product.stored_at = self.store
        self.product.save(update_fields=["stored_at"])
        self._batch(self.store, "5")
        self._batch(self.bodega, "3")
        # An exhausted batch is not stock: it must not add a 0.00 row.
        self._batch(self.bodega, "0")

        response = self.client.get(ON_HAND_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = sorted(response.data, key=lambda row: row["location"])
        self.assertEqual(len(rows), 2, response.data)
        self.assertEqual(
            rows[0],
            {
                "variant": self.variant.pk,
                "location": self.store.pk,
                "location_name": "Store",
                "location_active": True,
                "is_home": True,
                "qty": "5.00",
            },
        )
        self.assertEqual(rows[1]["location"], self.bodega.pk)
        self.assertEqual(rows[1]["location_name"], "Bodega")
        self.assertFalse(rows[1]["is_home"])
        self.assertEqual(rows[1]["qty"], "3.00")

    def test_the_location_flag_follows_the_product_not_the_default(self):
        # The variant's product lives in the BODEGA (the column default is Store), and its
        # stock sits there: `is_home` must come from the product, not from the default.
        other = Product.objects.create(
            category=self.category,
            brand=self.brand,
            base_name="PVC Pipe",
            stored_at=self.bodega,
        )
        other_variant = ProductVariant.objects.create(
            product=other,
            variant_name="2in",
            base_uom=self.uom,
            min_stock_threshold=Decimal(1),
        )
        self.product.stored_at = self.store
        self.product.save(update_fields=["stored_at"])
        self._batch(self.bodega, "2", variant=other_variant)

        response = self.client.get(ON_HAND_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data), 1, response.data)
        self.assertTrue(response.data[0]["is_home"], response.data)

    def test_the_variant_filter_narrows_the_rows(self):
        other = Product.objects.create(
            category=self.category, brand=self.brand, base_name="PVC Pipe"
        )
        other_variant = ProductVariant.objects.create(
            product=other,
            variant_name="2in",
            base_uom=self.uom,
            min_stock_threshold=Decimal(1),
        )
        self._batch(self.store, "5")
        self._batch(self.bodega, "7", variant=other_variant)

        response = self.client.get(f"{ON_HAND_URL}?variant={self.variant.pk}")

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row["variant"] for row in response.data], [self.variant.pk], response.data
        )

    def test_an_anonymous_read_is_refused(self):
        anonymous = APIClient()

        response = anonymous.get(ON_HAND_URL)

        self.assertEqual(response.status_code, 401, response.data)


class BatchSerializerLocationTests(StockOnHandTests):
    """`/batches/` gains the location, its name, and the batch it was copied from."""

    def test_the_batch_list_carries_location_and_source_batch(self):
        source = self._batch(self.store, "5")
        derived = self._batch(self.bodega, "2", source_batch=source)

        response = self.client.get(BATCHES_URL)

        self.assertEqual(response.status_code, 200, response.data)
        # `/batches/` is paginated like every list this API serves: the rows are under
        # `results`.
        rows = {row["id"]: row for row in response.data["results"]}
        self.assertEqual(rows[source.pk]["location"], self.store.pk)
        self.assertEqual(rows[source.pk]["location_name"], "Store")
        self.assertIsNone(rows[source.pk]["source_batch"])
        self.assertEqual(rows[derived.pk]["location"], self.bodega.pk)
        self.assertEqual(rows[derived.pk]["source_batch"], source.pk)


# -- tiny fixture helpers, kept out of the class bodies ----------------------


def Supplier_fixture():
    from .models import Supplier

    return Supplier.objects.create(company_name="Acme Supply")


def PurchaseOrder_fixture(*, supplier, user):
    from .models import PurchaseOrder

    return PurchaseOrder.objects.create(
        supplier=supplier, created_by=user, status=PurchaseOrder.Status.ORDERED
    )


def GoodsReceipt_fixture(*, po, user):
    from .models import GoodsReceipt

    return GoodsReceipt.objects.create(po=po, received_by=user)
