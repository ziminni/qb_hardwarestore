# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directives and reasons as apps/inventory/tests_purchase_orders.py: this checker
# runs from a working directory outside the repo, so Django/DRF imports and `Model.objects`
# are false positives on valid code, and `**auth` splats HTTP_AUTHORIZATION into the test
# client. The test run and `manage.py check` remain the authority.

"""Phase 5 B1 — a purchase-order line names the selling unit it is counted in.

Decision 18 ("PO by package"): a supplier sells "10 BAG at P250/bag" and the shop counts
its stock in kilos. This file pins every wire and stock consequence of that:

* the line carries `variant_uom` (id) plus the unit's code, factor and whole flag, and
  OMITTING it defaults to the variant's REAL base row (`uom == base_uom`, factor 1);
* a unit from another variant, an unknown id, or a missing base row is `INVALID_PO`;
* whole/measured quantities are decided by the LINE's unit (1.5 bags refused, 2.5 kg OK);
* receiving 2 bags stocks 50 kg at P10/kg (250 / 25), a second receipt respects the
  running cap without re-batching, and a legacy no-lines receipt compares base units;
* a referenced unit is `in_use`, frozen in identity/factor and cannot be removed;
* migration 0009 points every historical line at its base row without changing a number,
  and fails loudly on a variant that has no base row instead of guessing.
"""

from decimal import Decimal
from importlib import import_module

from django.apps import apps as django_apps
from django.contrib.auth import get_user_model
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TestCase, TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .exceptions import ReceiptQuantityUnrepresentable
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from .services import process_goods_receipt

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
PO_URL = "/api/v1/purchase-orders/"
RECEIPTS_URL = "/api/v1/goods-receipts/"
VARIANT_UOMS_URL = "/api/v1/variant-uoms/"

KG = "KG"
BAG = "BAG"
PRECISION_CODE = "RECEIPT_QUANTITY_UNREPRESENTABLE"


class PoUnitTestBase(TestCase):
    """A KG-based variant sold loose (KG x1) and by the bag (BAG x25).

    Stock is counted in KG, so a line naming the BAG unit is exactly the package case
    decision 18 describes.
    """

    def setUp(self):
        self.password = get_random_string(16)
        self.user = User.objects.create_superuser(
            username="po_unit_admin", email="po_unit@x.com", password=self.password
        )
        self.category = Category.objects.create(name="Adhesives")
        self.brand = Brand.objects.create(name="ABC")
        self.kg, _ = UnitOfMeasure.objects.get_or_create(
            code=KG, defaults={"name": "Kilogram", "is_whole": False}
        )
        self.bag, _ = UnitOfMeasure.objects.get_or_create(
            code=BAG, defaults={"name": "Bag", "is_whole": True}
        )
        self.product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Tile Adhesive"
        )
        self.variant = ProductVariant.objects.create(
            product=self.product, variant_name="standard", base_uom=self.kg
        )
        self.base = self._unit(self.variant, self.kg, "1", "100")
        self.bag25 = self._unit(self.variant, self.bag, "25", "250")
        self.supplier = Supplier.objects.create(company_name="Cebu Building Supply")
        self.client = APIClient()
        self._login(self.client)

    # -- fixture helpers ---------------------------------------------------
    def _unit(self, variant, uom, factor, price):
        return VariantUOM.objects.create(
            variant=variant,
            uom=uom,
            conversion_factor=Decimal(factor),
            default_selling_price=Decimal(price),
        )

    def _login(self, client):
        response = client.post(
            LOGIN_URL,
            {"username": self.user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")

    def _line(self, qty="10", cost="250.00", variant=None, **extra):
        line = {
            "variant": (variant or self.variant).pk,
            "ordered_qty": qty,
            "unit_cost": cost,
        }
        line.update(extra)
        return line

    def _create(self, lines):
        return self.client.post(
            PO_URL, {"supplier": self.supplier.pk, "items": lines}, format="json"
        )

    def _place(self, po_id):
        return self.client.post(f"{PO_URL}{po_id}/place/", {}, format="json")

    def _receive(self, po_id, item_id, qty):
        return self.client.post(
            RECEIPTS_URL,
            {"po": po_id, "items": [{"po_item": item_id, "qty": str(qty)}]},
            format="json",
        )

    def _process(self, receipt_id):
        return self.client.post(
            f"{RECEIPTS_URL}{receipt_id}/process/", {}, format="json"
        )

    def _ordered_po(self, line):
        """Create + place one line through the API; returns (po, item)."""
        created = self._create([line])
        self.assertEqual(created.status_code, 201, created.data)
        placed = self._place(created.data["id"])
        self.assertEqual(placed.status_code, 200, placed.data)
        po = PurchaseOrder.objects.get(pk=created.data["id"])
        return po, po.items.get()


class PoLineUnitWriteTests(PoUnitTestBase):
    """What the PO body may say, and what the server persists and returns."""

    def test_omitting_the_unit_defaults_to_the_real_base_row(self):
        created = self._create([self._line(qty="2.5", cost="100")])

        self.assertEqual(created.status_code, 201, created.data)
        line = created.data["items"][0]
        self.assertEqual(line["variant_uom"], self.base.pk)
        self.assertEqual(line["uom_code"], KG)
        self.assertEqual(line["conversion_factor"], "1.00")
        self.assertFalse(line["uom_is_whole"])
        self.assertEqual(POItem.objects.get(pk=line["id"]).variant_uom_id, self.base.pk)

    def test_a_line_naming_the_package_unit_persists_and_reports_it(self):
        created = self._create(
            [self._line(qty="10", cost="250", variant_uom=self.bag25.pk)]
        )

        self.assertEqual(created.status_code, 201, created.data)
        line = created.data["items"][0]
        self.assertEqual(line["variant_uom"], self.bag25.pk)
        self.assertEqual(line["uom_code"], BAG)
        self.assertEqual(line["conversion_factor"], "25.00")
        self.assertTrue(line["uom_is_whole"])
        self.assertEqual(line["ordered_qty"], "10.00")
        self.assertEqual(line["unit_cost"], "250.00")
        self.assertEqual(
            POItem.objects.get(pk=line["id"]).variant_uom_id, self.bag25.pk
        )

    def test_a_unit_of_another_variant_is_refused(self):
        other_product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Washed Sand"
        )
        other_variant = ProductVariant.objects.create(
            product=other_product, variant_name="standard", base_uom=self.kg
        )
        other_unit = self._unit(other_variant, self.bag, "25", "300")

        response = self._create([self._line(variant_uom=other_unit.pk)])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), "INVALID_PO", response.data)
        self.assertEqual(PurchaseOrder.objects.count(), 0)
        self.assertEqual(POItem.objects.count(), 0)

    def test_an_unknown_unit_id_is_refused(self):
        response = self._create([self._line(variant_uom=999999)])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), "INVALID_PO", response.data)
        self.assertEqual(POItem.objects.count(), 0)

    def test_a_variant_without_a_base_row_cannot_have_its_unit_omitted(self):
        no_base_product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Grout"
        )
        no_base = ProductVariant.objects.create(
            product=no_base_product, variant_name="standard", base_uom=self.kg
        )
        self._unit(no_base, self.bag, "25", "300")

        response = self._create([self._line(variant=no_base, qty="1")])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), "INVALID_PO", response.data)
        self.assertIn("no base selling unit", response.data.get("detail", ""))
        self.assertEqual(POItem.objects.count(), 0)

    def test_a_fractional_quantity_on_a_whole_package_unit_is_refused(self):
        response = self._create([self._line(qty="1.5", variant_uom=self.bag25.pk)])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data.get("code"), "WHOLE_UNIT_QUANTITY", response.data
        )
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_a_measured_unit_still_accepts_a_fraction(self):
        response = self._create(
            [self._line(qty="2.5", cost="100", variant_uom=self.base.pk)]
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["items"][0]["ordered_qty"], "2.50")


class PackageReceivingTests(PoUnitTestBase):
    """Receiving counts in the line's unit; stock and cost convert to base units."""

    def test_two_bags_stock_fifty_base_units_at_ten_each(self):
        po, item = self._ordered_po(
            self._line(qty="10", cost="250", variant_uom=self.bag25.pk)
        )

        receipt = self._receive(po.pk, item.pk, "2")
        self.assertEqual(receipt.status_code, 201, receipt.data)
        processed = self._process(receipt.data["id"])
        self.assertEqual(processed.status_code, 200, processed.data)

        batches = InventoryBatch.objects.filter(variant=self.variant)
        self.assertEqual(batches.count(), 1)
        batch = batches.get()
        self.assertEqual(batch.initial_qty, Decimal("50.00"))
        self.assertEqual(batch.current_qty, Decimal("50.00"))
        self.assertEqual(batch.unit_cost_landed, Decimal("10.00"))
        self.assertEqual(batch.batch_selling_price, Decimal("10.00"))
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal(2))
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.PARTIAL)

    def test_a_second_receipt_respects_the_running_cap_without_double_batching(self):
        po, item = self._ordered_po(
            self._line(qty="10", cost="250", variant_uom=self.bag25.pk)
        )
        first = self._receive(po.pk, item.pk, "2")
        self.assertEqual(self._process(first.data["id"]).status_code, 200)

        second = self._receive(po.pk, item.pk, "3")
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(self._process(second.data["id"]).status_code, 200)

        quantities = sorted(
            InventoryBatch.objects.filter(variant=self.variant).values_list(
                "initial_qty", flat=True
            )
        )
        self.assertEqual(quantities, [Decimal("50.00"), Decimal("75.00")])
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal(5))

        over = self._receive(po.pk, item.pk, "6")

        self.assertEqual(over.status_code, 400, over.data)
        self.assertIn("would exceed", over.data.get("detail", ""))
        item.refresh_from_db()
        self.assertEqual(
            item.received_qty, Decimal(5), "a refused delivery must not accumulate"
        )
        self.assertEqual(
            InventoryBatch.objects.filter(variant=self.variant).count(),
            2,
            "and it must not mint a third batch",
        )

    def test_a_fractional_bag_receipt_is_refused_on_the_line_unit(self):
        po, item = self._ordered_po(
            self._line(qty="10", cost="250", variant_uom=self.bag25.pk)
        )

        response = self._receive(po.pk, item.pk, "1.5")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            response.data.get("code"), "WHOLE_UNIT_QUANTITY", response.data
        )
        self.assertFalse(GoodsReceipt.objects.filter(po=po).exists())
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal(0))

    def test_a_fractional_measured_receipt_is_accepted(self):
        po, item = self._ordered_po(
            self._line(qty="10", cost="100", variant_uom=self.base.pk)
        )

        receipt = self._receive(po.pk, item.pk, "2.5")

        self.assertEqual(receipt.status_code, 201, receipt.data)
        self.assertEqual(self._process(receipt.data["id"]).status_code, 200)
        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.initial_qty, Decimal("2.50"))
        self.assertEqual(batch.unit_cost_landed, Decimal("100.00"))


class LegacyDeltaInBaseUnitsTests(PoUnitTestBase):
    """The no-lines (legacy/seed) path compares base quantities, never mixed units."""

    def test_a_legacy_delta_on_a_package_line_stocks_the_base_difference(self):
        po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        item = POItem.objects.create(
            po=po,
            variant=self.variant,
            variant_uom=self.bag25,
            ordered_qty=Decimal(10),
            unit_cost=Decimal(250),
            received_qty=Decimal(2),
        )

        first = process_goods_receipt(
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.user),
            user=self.user,
        )
        self.assertEqual([b.initial_qty for b in first], [Decimal("50.00")])
        self.assertEqual([b.unit_cost_landed for b in first], [Decimal("10.00")])

        item.received_qty = Decimal(3)
        item.save(update_fields=["received_qty"])
        second = process_goods_receipt(
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.user),
            user=self.user,
        )

        self.assertEqual(
            [b.initial_qty for b in second],
            [Decimal("25.00")],
            "3 bags = 75 base, 50 already stocked, so the delta is 25 base - never "
            "3 - 2 = 1, and never 3 bags restocked as 3 base units",
        )
        self.assertEqual(InventoryBatch.objects.filter(variant=self.variant).count(), 2)


class ReferencedUnitProtectionTests(PoUnitTestBase):
    """A unit on a purchase order joins the in-use list and the freeze."""

    def test_the_referenced_unit_is_in_use_frozen_and_not_removable(self):
        created = self._create(
            [self._line(qty="10", cost="250", variant_uom=self.bag25.pk)]
        )
        self.assertEqual(created.status_code, 201, created.data)

        listing = self.client.get(VARIANT_UOMS_URL)
        self.assertEqual(listing.status_code, 200, listing.data)
        row = next(
            entry for entry in listing.data["results"] if entry["id"] == self.bag25.pk
        )
        self.assertTrue(row["in_use"])

        factor = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.bag25.pk}/",
            {"conversion_factor": "20"},
            format="json",
        )
        self.assertEqual(factor.status_code, 400, factor.data)
        self.assertEqual(factor.data.get("code"), "SELLING_UNIT_IN_USE", factor.data)

        removed = self.client.delete(f"{VARIANT_UOMS_URL}{self.bag25.pk}/")
        self.assertEqual(removed.status_code, 400, removed.data)
        self.assertEqual(removed.data.get("code"), "SELLING_UNIT_IN_USE", removed.data)
        self.assertTrue(VariantUOM.objects.filter(pk=self.bag25.pk).exists())

        priced = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.bag25.pk}/",
            {"default_selling_price": "260.00"},
            format="json",
        )
        self.assertEqual(priced.status_code, 200, priced.data)
        self.bag25.refresh_from_db()
        self.assertEqual(self.bag25.conversion_factor, Decimal(25))
        self.assertEqual(self.bag25.default_selling_price, Decimal(260))


class BackfillIrreconcilableTests(PoUnitTestBase):
    """The data function that 0009 runs: preserve numbers, refuse to guess."""

    def _module(self):
        return import_module("apps.inventory.migrations.0009_poitem_variant_uom")

    def test_the_backfill_points_each_line_at_its_base_row_without_changing_numbers(
        self,
    ):
        po = PurchaseOrder.objects.create(supplier=self.supplier, created_by=self.user)
        item = POItem.objects.create(
            po=po,
            variant=self.variant,
            ordered_qty=Decimal("7.50"),
            unit_cost=Decimal("123.45"),
            received_qty=Decimal("2.25"),
        )

        self._module().backfill_po_item_units(django_apps, None)

        item.refresh_from_db()
        self.assertEqual(item.variant_uom_id, self.base.pk)
        self.assertEqual(item.ordered_qty, Decimal("7.50"))
        self.assertEqual(item.unit_cost, Decimal("123.45"))
        self.assertEqual(item.received_qty, Decimal("2.25"))

        self._module().backfill_po_item_units(django_apps, None)
        item.refresh_from_db()
        self.assertEqual(item.variant_uom_id, self.base.pk, "a second run is a no-op")

    def test_a_variant_with_no_base_row_fails_loudly_and_changes_nothing(self):
        orphan_product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Orphan"
        )
        orphan = ProductVariant.objects.create(
            product=orphan_product, variant_name="standard", base_uom=self.kg
        )
        self._unit(orphan, self.bag, "25", "300")
        po = PurchaseOrder.objects.create(supplier=self.supplier, created_by=self.user)
        item = POItem.objects.create(
            po=po,
            variant=orphan,
            ordered_qty=Decimal(4),
            unit_cost=Decimal(50),
            received_qty=Decimal(0),
        )

        with self.assertRaises(RuntimeError) as caught:
            self._module().backfill_po_item_units(django_apps, None)

        self.assertIn(str(item.pk), str(caught.exception))
        self.assertIn("no base selling unit", str(caught.exception))
        item.refresh_from_db()
        self.assertIsNone(item.variant_uom_id)
        self.assertEqual(item.ordered_qty, Decimal(4))
        self.assertEqual(item.unit_cost, Decimal(50))


class PoItemUnitBackfillMigrationTests(TransactionTestCase):
    """Migration 0009 over rows written by the PRE-B1 schema, the way production runs it.

    The old shape cannot even express a unit, so the fixture is built with the historical
    models after rolling the inventory app back to `0008`. The package unit is created
    FIRST and with a lower pk than the base row: `VariantUOM` is ordered by `uom`, so
    "the first row" or "the lowest pk" would tag every line with the BAG and re-measure
    every historical quantity.
    """

    OLD_INVENTORY_LEAF = "0008_uom_is_whole"

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

    def test_every_historical_line_gets_its_base_row_and_no_number_changes(self):
        old_targets = self._old_targets()
        executor = self._migrate(old_targets)
        old = executor.loader.project_state(old_targets).apps

        old_uom = old.get_model("inventory", "UnitOfMeasure")
        old_variant = old.get_model("inventory", "ProductVariant")
        old_unit = old.get_model("inventory", "VariantUOM")
        old_item = old.get_model("inventory", "POItem")
        old_po = old.get_model("inventory", "PurchaseOrder")
        old_customer = old.get_model("apps_users", "User")
        old_category = old.get_model("inventory", "Category")
        old_brand = old.get_model("inventory", "Brand")
        old_product = old.get_model("inventory", "Product")
        old_supplier = old.get_model("inventory", "Supplier")

        # 0008's data migration already put the standard units in every database.
        kg, _ = old_uom.objects.get_or_create(
            code="KG", defaults={"name": "Kilogram", "is_whole": False}
        )
        bag, _ = old_uom.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        category = old_category.objects.create(name="Adhesives")
        brand = old_brand.objects.create(name="ABC")
        product = old_product.objects.create(
            category=category, brand=brand, base_name="Tile Adhesive"
        )
        variant = old_variant.objects.create(
            product=product, variant_name="standard", base_uom=kg
        )
        # Package first, with the lower pk: the trap this test exists for.
        old_unit.objects.create(
            variant=variant,
            uom=bag,
            conversion_factor=Decimal(25),
            default_selling_price=Decimal(250),
        )
        base = old_unit.objects.create(
            variant=variant,
            uom=kg,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(100),
        )
        user = old_customer.objects.create(
            username="legacy_manager",
            email="legacy@x.com",
            password=get_random_string(20),
        )
        supplier = old_supplier.objects.create(company_name="Legacy Supply")
        po = old_po.objects.create(supplier=supplier, created_by=user, status="ORDERED")
        first = old_item.objects.create(
            po=po,
            variant=variant,
            ordered_qty=Decimal("12.50"),
            unit_cost=Decimal("123.45"),
            received_qty=Decimal("4.25"),
        )
        second = old_item.objects.create(
            po=po,
            variant=variant,
            ordered_qty=Decimal(3),
            unit_cost=Decimal("0.99"),
            received_qty=Decimal(0),
        )

        self._migrate(self._latest_targets())

        for pk, ordered, cost, received in (
            (first.pk, Decimal("12.50"), Decimal("123.45"), Decimal("4.25")),
            (second.pk, Decimal(3), Decimal("0.99"), Decimal(0)),
        ):
            item = POItem.objects.get(pk=pk)
            self.assertEqual(
                item.variant_uom_id,
                base.pk,
                "the backfill must pick uom == base_uom with factor 1, not list order",
            )
            self.assertEqual(item.ordered_qty, ordered)
            self.assertEqual(item.unit_cost, cost)
            self.assertEqual(item.received_qty, received)


class UnrepresentableStockQuantityTests(PoUnitTestBase):
    """Decision 18: a delivery whose converted stock cannot be KEPT is refused.

    `InventoryBatch.initial_qty`/`current_qty` hold two decimal places, and `_create_batch`
    used to quantize `qty x factor` HALF_UP into them. A legitimate measured unit of
    factor 0.01 receiving 0.01 = 0.0001 therefore stocked **0.00** (the delivery
    vanished from the shelf while `received_qty` said it arrived), and 0.50 x 0.03 =
    0.015 stocked **0.02** (the delivery minted a hundredth nobody delivered). Both are
    one defect: stock was rounded instead of refused.

    The rule is refused at the RECEIPT POST, before any row is written, and again in
    `process_goods_receipt` for the ORM callers (fixtures, `seed_demo`, the legacy
    no-lines delta), where the atomic block rolls the whole delivery back.
    """

    def _package(self, code, name, factor, price):
        """A measured selling unit of this variant with an arbitrary package factor."""
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=code, defaults={"name": name, "is_whole": False}
        )
        return self._unit(self.variant, uom, factor, price)

    def _assert_nothing_stocked(self, po, item, audit_rows_before):
        self.assertFalse(
            GoodsReceipt.objects.filter(po=po).exists(),
            "a refused delivery must leave no receipt row",
        )
        self.assertEqual(GoodsReceiptItem.objects.filter(po_item=item).count(), 0)
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal(0))
        self.assertEqual(InventoryBatch.objects.filter(variant=self.variant).count(), 0)
        self.assertEqual(AuditLog.objects.count(), audit_rows_before)

    def test_a_measured_receipt_that_rounds_to_zero_stock_is_refused(self):
        # 1 DG = 0.01 kg, so receiving 0.01 DG is exactly 0.0001 kg of stock.
        tiny = self._package("DG", "Decagram", "0.01", "1.00")
        po, item = self._ordered_po(self._line(qty="10", cost="1", variant_uom=tiny.pk))
        audit_rows_before = AuditLog.objects.count()

        response = self._receive(po.pk, item.pk, "0.01")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), PRECISION_CODE, response.data)
        self.assertIn("whole hundredth", response.data.get("detail", ""))
        self._assert_nothing_stocked(po, item, audit_rows_before)

    def test_a_receipt_that_would_mint_stock_is_refused(self):
        # 0.50 x 0.03 = 0.015 kg: HALF_UP used to stock 0.02 for a 0.015 delivery.
        odd = self._package("PK03", "Package (0.03 kg)", "0.03", "3.00")
        po, item = self._ordered_po(self._line(qty="10", cost="3", variant_uom=odd.pk))
        audit_rows_before = AuditLog.objects.count()

        response = self._receive(po.pk, item.pk, "0.50")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), PRECISION_CODE, response.data)
        self._assert_nothing_stocked(po, item, audit_rows_before)

    def test_a_representable_measured_conversion_is_accepted(self):
        # 1.50 x 0.02 = 0.03 kg exactly, so the delivery is kept, not rounded or refused.
        even = self._package("PK02", "Package (0.02 kg)", "0.02", "2.00")
        po, item = self._ordered_po(self._line(qty="10", cost="2", variant_uom=even.pk))

        receipt = self._receive(po.pk, item.pk, "1.50")
        self.assertEqual(receipt.status_code, 201, receipt.data)
        processed = self._process(receipt.data["id"])
        self.assertEqual(processed.status_code, 200, processed.data)

        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.initial_qty, Decimal("0.03"))
        self.assertEqual(batch.current_qty, Decimal("0.03"))
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal("1.50"))

    def test_processing_refuses_an_unrepresentable_delivery_line_and_writes_nothing(
        self,
    ):
        """The defensive path: a line written straight through the ORM skips the POST."""
        odd = self._package("PK03", "Package (0.03 kg)", "0.03", "3.00")
        po, item = self._ordered_po(self._line(qty="10", cost="3", variant_uom=odd.pk))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        GoodsReceiptItem.objects.create(
            receipt=receipt, po_item=item, qty=Decimal("0.50")
        )

        with self.assertRaises(ReceiptQuantityUnrepresentable):
            process_goods_receipt(receipt=receipt, user=self.user)

        self.assertEqual(InventoryBatch.objects.filter(variant=self.variant).count(), 0)
        receipt.refresh_from_db()
        self.assertIsNone(receipt.processed_at)
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)

    def test_processing_rolls_back_earlier_lines_of_the_same_delivery(self):
        """One good line + one unrepresentable line = no batch at all, not half a receipt."""
        triple = self._package("PK3", "Package (3 kg)", "3", "100.00")
        # A PO carries one line per VARIANT, so the second line needs its own variant.
        other_variant = ProductVariant.objects.create(
            product=self.product, variant_name="premium", base_uom=self.kg
        )
        self._unit(other_variant, self.kg, "1", "100")
        odd = self._unit(
            other_variant,
            UnitOfMeasure.objects.get_or_create(
                code="PK03", defaults={"name": "Package (0.03 kg)", "is_whole": False}
            )[0],
            "0.03",
            "3.00",
        )
        created = self._create(
            [
                self._line(qty="10", cost="100", variant_uom=triple.pk),
                self._line(
                    qty="10", cost="3", variant=other_variant, variant_uom=odd.pk
                ),
            ]
        )
        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(self._place(created.data["id"]).status_code, 200)
        po = PurchaseOrder.objects.get(pk=created.data["id"])
        good, bad = list(po.items.order_by("pk"))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        GoodsReceiptItem.objects.create(receipt=receipt, po_item=good, qty=Decimal(1))
        GoodsReceiptItem.objects.create(
            receipt=receipt, po_item=bad, qty=Decimal("0.50")
        )

        with self.assertRaises(ReceiptQuantityUnrepresentable):
            process_goods_receipt(receipt=receipt, user=self.user)

        self.assertEqual(
            InventoryBatch.objects.count(),
            0,
            "the representable line's 3 kg must roll back with the refused one",
        )
        receipt.refresh_from_db()
        self.assertIsNone(receipt.processed_at)

    def test_processing_refuses_an_unrepresentable_legacy_delta(self):
        """No-lines (fixture/`seed_demo`) receipts compare base units; the delta must fit."""
        odd = self._package("PK03", "Package (0.03 kg)", "0.03", "3.00")
        po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        item = POItem.objects.create(
            po=po,
            variant=self.variant,
            variant_uom=odd,
            ordered_qty=Decimal(10),
            unit_cost=Decimal(3),
            received_qty=Decimal("0.50"),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)

        with self.assertRaises(ReceiptQuantityUnrepresentable):
            process_goods_receipt(receipt=receipt, user=self.user)

        self.assertEqual(InventoryBatch.objects.filter(variant=self.variant).count(), 0)
        receipt.refresh_from_db()
        self.assertIsNone(receipt.processed_at)
        item.refresh_from_db()
        po.refresh_from_db()
        self.assertEqual(po.status, PurchaseOrder.Status.ORDERED)

    def test_a_cost_that_is_not_exact_per_base_unit_still_stocks_the_quantity(self):
        """Only STOCK is refused for precision. Cost keeps the project's cent rounding:
        P100 per 3 kg package is P33.33/kg, and the 3 kg delivery is still 3.00."""
        triple = self._package("PK3", "Package (3 kg)", "3", "100.00")
        po, item = self._ordered_po(
            self._line(qty="10", cost="100", variant_uom=triple.pk)
        )

        receipt = self._receive(po.pk, item.pk, "1")
        self.assertEqual(receipt.status_code, 201, receipt.data)
        self.assertEqual(self._process(receipt.data["id"]).status_code, 200)

        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.initial_qty, Decimal("3.00"))
        self.assertEqual(batch.unit_cost_landed, Decimal("33.33"))
        self.assertEqual(batch.batch_selling_price, Decimal("33.33"))
        item.refresh_from_db()
        self.assertEqual(item.received_qty, Decimal(1))
