# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/inventory/tests_catalog_writes.py: this checker runs
# from a working directory outside the repo, so `Model.objects` is a false positive on
# valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which pyright
# reads as `follow=`.

"""Phase 5 task B4 (decision 18) — "Bodega lite": where a product is stored.

Decision 18 ruled the SERVER side of the shop's short list of places a product is kept:
`StorageLocation` (Admin-managed, seeded **Store** and **Bodega**) and `Product.stored_at`
(default **Store**, `PROTECT`), read back as `stored_at` + `stored_at_name` on products,
variants, selling units, sale lines and delivery slips.

What this module pins down, and why each one is money or stock meaning:

* the migration seeds exactly two locations and BACKFILLS every product that existed
  before it, so an upgraded database has no product without a shelf;
* the list is Admin-managed but READABLE by everyone logged in (the till shows the label),
  and an Admin also sees the deactivated ones;
* an INACTIVE location cannot be given to a product (**400** `INVALID_STORAGE_LOCATION`),
  while a product already labelled with one keeps that label - deactivating tidies the
  picker, it does not relabel history;
* the till's own reads (selling-unit list, `?barcode=` lookup, the sale line and the
  delivery slip) carry the label, and a LIST costs a bounded number of queries.

Real JWT logins (no ``force_authenticate``): the permission classes read GROUP
membership, so the login path is part of what is under test.
"""

from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import IntegrityError, connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import (
    Category,
    Product,
    ProductVariant,
    StorageLocation,
    UnitOfMeasure,
    VariantUOM,
)
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
PRODUCTS_URL = "/api/v1/products/"
VARIANTS_URL = "/api/v1/variants/"
VARIANT_UOMS_URL = "/api/v1/variant-uoms/"
LOCATIONS_URL = "/api/v1/storage-locations/"


class StorageTestBase(InventoryTestBase):
    """One user per role, real logins, one factor-1 selling unit to read the label from."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.password = get_random_string(16)
        self.admin = self._make_user("loc_admin", "Admin")
        self.stocker = self._make_user("loc_stocker", "Stock Manager")
        self.cashier = self._make_user("loc_cashier", "Cashier")
        # A user who holds TWO roles: the wider one decides what they see.
        self.multi = self._make_user("loc_multi", "Cashier", "Admin")
        self.store = self._location("Store")
        self.bodega = self._location("Bodega")
        self.vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )

    # -- fixture helpers ---------------------------------------------------
    @staticmethod
    def _location(name, active=True):
        location, _ = StorageLocation.objects.get_or_create(
            name=name, defaults={"is_active": active}
        )
        return location

    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@example.com",
            password=self.password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self, user):
        login = APIClient().post(
            LOGIN_URL,
            {"username": user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200, login.data)
        return {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}

    def _product_body(self, **overrides):
        body = {
            "category": self.category.pk,
            "brand": self.brand.pk,
            "base_name": "Mixing Tub",
        }
        body.update(overrides)
        return body


class MigrationSeedTests(TransactionTestCase):
    """Migration 0011 over rows written by the PRE-B4 schema, the way production runs it.

    Two things must be true of a database that already has products: the two locations
    exist exactly once, and every product that predates the column has a shelf. The rows
    are created with the HISTORICAL models after rolling the inventory app back to 0010,
    because the current `Product` cannot even be written without `stored_at`.
    """

    OLD_INVENTORY_LEAF = "0010_supplier_payables"

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

    def test_the_forward_migration_seeds_two_locations_and_backfills_every_product(
        self,
    ):
        old_targets = self._old_targets()
        executor = self._migrate(old_targets)
        old = executor.loader.project_state(old_targets).apps

        old_category = old.get_model("inventory", "Category")
        old_brand = old.get_model("inventory", "Brand")
        old_product = old.get_model("inventory", "Product")
        category = old_category.objects.create(name="Cement")
        brand = old_brand.objects.create(name="Rhino")
        legacy = [
            old_product.objects.create(
                category=category, brand=brand, base_name=name
            ).pk
            for name in ("Portland Cement", "PVC Pipe")
        ]

        self._migrate(self._latest_targets())

        names = list(StorageLocation.objects.values_list("name", flat=True))
        self.assertEqual(sorted(names), ["Bodega", "Store"])
        store = StorageLocation.objects.get(name="Store")
        self.assertEqual(
            Product.objects.filter(stored_at=store).count(),
            2,
            "every product that existed before B4 must have a shelf",
        )
        self.assertEqual(
            sorted(Product.objects.values_list("pk", flat=True)), sorted(legacy)
        )


class LocationSeedDataTests(StorageTestBase):
    """A fresh database has the two locations decision 18 names, and a Store default."""

    def test_a_new_product_is_stored_at_store(self):
        product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Mixing Tub"
        )

        self.assertEqual(product.stored_at.name, "Store")

    def test_a_created_product_reads_back_its_location_name(self):
        response = self.client.post(
            PRODUCTS_URL,
            self._product_body(),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            response.data["stored_at"], StorageLocation.objects.get(name="Store").pk
        )
        self.assertEqual(response.data["stored_at_name"], "Store")


class LocationAdminTests(StorageTestBase):
    """The list is Admin-managed: everyone reads it, only an Admin writes it."""

    def test_an_admin_creates_a_location_and_leaves_one_audit_row(self):
        response = self.client.post(
            LOCATIONS_URL,
            {"name": "Container"},
            format="json",
            **self._auth(self.admin),
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(StorageLocation.objects.filter(name="Container").exists())
        self.assertEqual(
            AuditLogActionRows.create_rows("Container"), 1, "one CREATE audit row"
        )

    def test_an_admin_renames_and_deactivates(self):
        response = self.client.patch(
            f"{LOCATIONS_URL}{self.bodega.pk}/",
            {"name": "Warehouse", "is_active": False},
            format="json",
            **self._auth(self.admin),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.bodega.refresh_from_db()
        self.assertEqual(self.bodega.name, "Warehouse")
        self.assertFalse(self.bodega.is_active)

    def test_a_stock_manager_may_not_write_the_list(self):
        for method, path, body in (
            ("post", LOCATIONS_URL, {"name": "Container"}),
            ("patch", f"{LOCATIONS_URL}{self.bodega.pk}/", {"name": "Warehouse"}),
        ):
            with self.subTest(method=method):
                response = getattr(self.client, method)(
                    path, body, format="json", **self._auth(self.stocker)
                )

                self.assertEqual(response.status_code, 403, response.data)
        self.assertFalse(StorageLocation.objects.filter(name="Container").exists())
        self.assertEqual(StorageLocation.objects.get(pk=self.bodega.pk).name, "Bodega")

    def test_a_cashier_reads_the_active_list_and_an_admin_also_sees_inactive_ones(self):
        StorageLocation.objects.filter(pk=self.bodega.pk).update(is_active=False)

        cashier = self.client.get(LOCATIONS_URL, **self._auth(self.cashier))
        admin = self.client.get(LOCATIONS_URL, **self._auth(self.admin))

        self.assertEqual(cashier.status_code, 200, cashier.data)
        self.assertEqual([row["name"] for row in cashier.data["results"]], ["Store"])
        self.assertEqual(admin.status_code, 200, admin.data)
        self.assertEqual(
            sorted(row["name"] for row in admin.data["results"]), ["Bodega", "Store"]
        )

    def test_a_multi_role_admin_sees_the_inactive_ones_too(self):
        StorageLocation.objects.filter(pk=self.bodega.pk).update(is_active=False)

        response = self.client.get(LOCATIONS_URL, **self._auth(self.multi))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            sorted(row["name"] for row in response.data["results"]),
            ["Bodega", "Store"],
        )

    def test_a_duplicate_name_is_refused_case_insensitively(self):
        response = self.client.post(
            LOCATIONS_URL,
            {"name": "  bodega "},
            format="json",
            **self._auth(self.admin),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertEqual(
            StorageLocation.objects.filter(name__iexact="bodega").count(), 1
        )

    def test_there_is_no_delete(self):
        response = self.client.delete(
            f"{LOCATIONS_URL}{self.bodega.pk}/", **self._auth(self.admin)
        )

        self.assertEqual(response.status_code, 405, response.data)
        self.assertTrue(StorageLocation.objects.filter(pk=self.bodega.pk).exists())

    def test_an_unauthenticated_read_is_refused(self):
        response = self.client.get(LOCATIONS_URL)

        self.assertIn(response.status_code, (401, 403), response.data)


class ProductStoredAtWriteTests(StorageTestBase):
    """The label is writable on the product, and an INACTIVE location is refused."""

    def test_a_product_may_be_moved_to_bodega(self):
        response = self.client.patch(
            f"{PRODUCTS_URL}{self.product.pk}/",
            {"stored_at": self.bodega.pk},
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["stored_at"], self.bodega.pk)
        self.assertEqual(response.data["stored_at_name"], "Bodega")
        self.product.refresh_from_db()
        self.assertEqual(self.product.stored_at_id, self.bodega.pk)

    def test_an_inactive_location_cannot_be_given_to_a_product(self):
        StorageLocation.objects.filter(pk=self.bodega.pk).update(is_active=False)

        response = self.client.patch(
            f"{PRODUCTS_URL}{self.product.pk}/",
            {"stored_at": self.bodega.pk},
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.product.refresh_from_db()
        self.assertEqual(self.product.stored_at.name, "Store")

    def test_deactivating_a_location_keeps_the_label_a_product_already_has(self):
        # The rule chosen (and stated in ENDPOINTS.md): deactivating tidies the PICKER.
        # It does not relabel anything, because the label is where the goods are today.
        Product.objects.filter(pk=self.product.pk).update(stored_at=self.bodega)

        deactivate = self.client.patch(
            f"{LOCATIONS_URL}{self.bodega.pk}/",
            {"is_active": False},
            format="json",
            **self._auth(self.admin),
        )

        self.assertEqual(deactivate.status_code, 200, deactivate.data)
        detail = self.client.get(
            f"{PRODUCTS_URL}{self.product.pk}/",
            **self._auth(self.cashier),
        )
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(detail.data["stored_at_name"], "Bodega")

    def test_an_existing_label_survives_a_patch_that_does_not_name_it(self):
        Product.objects.filter(pk=self.product.pk).update(stored_at=self.bodega)

        response = self.client.patch(
            f"{PRODUCTS_URL}{self.product.pk}/",
            {"description": "Now with a lid"},
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["stored_at_name"], "Bodega")

    def test_a_create_without_a_location_defaults_to_the_active_store(self):
        response = self.client.post(
            PRODUCTS_URL,
            self._product_body(base_name="Steel Bar"),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["stored_at_name"], "Store")
        self.assertEqual(
            Product.objects.get(base_name="Steel Bar").stored_at.name, "Store"
        )

    def test_a_create_without_a_location_is_refused_when_the_default_store_is_off(
        self,
    ):
        # The model default would silently point the new product at a place the shop has
        # just taken out of the picker. A CREATE that omits `stored_at` names no location,
        # so the refusal has to come from the location the write would LEAVE it at.
        from apps.users.models import AuditLog

        StorageLocation.objects.filter(name="Store").update(is_active=False)
        products_before = Product.objects.count()
        audits_before = AuditLog.objects.filter(
            action_type=AuditLog.ActionType.CREATE,
            description__contains="Steel Bar",
        ).count()

        response = self.client.post(
            PRODUCTS_URL,
            self._product_body(base_name="Steel Bar"),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertEqual(Product.objects.count(), products_before)
        self.assertFalse(Product.objects.filter(base_name="Steel Bar").exists())
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.CREATE,
                description__contains="Steel Bar",
            ).count(),
            audits_before,
            "a refused create leaves no audit row claiming it happened",
        )

    def test_a_create_may_name_an_active_location_while_the_default_is_off(self):
        StorageLocation.objects.filter(name="Store").update(is_active=False)

        response = self.client.post(
            PRODUCTS_URL,
            self._product_body(base_name="Steel Bar", stored_at=self.bodega.pk),
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["stored_at_name"], "Bodega")
        self.assertEqual(
            Product.objects.get(base_name="Steel Bar").stored_at_id, self.bodega.pk
        )

    def test_an_inactive_existing_label_survives_an_unrelated_patch(self):
        Product.objects.filter(pk=self.product.pk).update(stored_at=self.bodega)
        StorageLocation.objects.filter(pk=self.bodega.pk).update(is_active=False)

        response = self.client.patch(
            f"{PRODUCTS_URL}{self.product.pk}/",
            {"description": "Now with a lid"},
            format="json",
            **self._auth(self.stocker),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["stored_at_name"], "Bodega")
        self.product.refresh_from_db()
        self.assertEqual(self.product.stored_at_id, self.bodega.pk)


class AdminNameRaceTests(StorageTestBase):
    """Two Admins naming one location at the same instant answer 400, never a 500.

    The serializer's pre-check is a read and the insert a write, so both callers can read
    "free" and only the PostgreSQL unique constraint can refuse the loser (`IntegrityError`
    is a 500). The race is made deterministic by inserting the rival row from inside the
    save that is about to violate the constraint - a real constraint violation, not a
    mocked exception - and the viewset's `atomic` block rolls both writes back.
    """

    def _racing_save(self, winner_name):
        original = StorageLocation.save

        def save(instance, *args, **kwargs):
            # bulk_create does not call save(), so this cannot recurse.
            StorageLocation.objects.bulk_create([StorageLocation(name=winner_name)])
            return original(instance, *args, **kwargs)

        return mock.patch.object(StorageLocation, "save", save)

    def test_a_create_that_loses_the_name_race_is_a_readable_400(self):
        from apps.users.models import AuditLog

        self.client.raise_request_exception = False
        audits_before = AuditLog.objects.filter(
            action_type=AuditLog.ActionType.CREATE,
            description__startswith="Storage location",
        ).count()

        with self._racing_save("warehouse"):
            response = self.client.post(
                LOCATIONS_URL,
                {"name": "Warehouse"},
                format="json",
                **self._auth(self.admin),
            )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.assertFalse(
            StorageLocation.objects.filter(name__iexact="warehouse").exists(),
            "the losing write and its rival are both rolled back in this fixture",
        )
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.CREATE,
                description__startswith="Storage location",
            ).count(),
            audits_before,
        )

    def test_a_rename_that_loses_the_name_race_is_a_readable_400(self):
        from apps.users.models import AuditLog

        self.client.raise_request_exception = False
        audits_before = AuditLog.objects.filter(
            action_type=AuditLog.ActionType.UPDATE,
            description__startswith="Storage location",
        ).count()

        with self._racing_save("overflow"):
            response = self.client.patch(
                f"{LOCATIONS_URL}{self.bodega.pk}/",
                {"name": "Overflow"},
                format="json",
                **self._auth(self.admin),
            )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self.bodega.refresh_from_db()
        self.assertEqual(self.bodega.name, "Bodega")
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.UPDATE,
                description__startswith="Storage location",
            ).count(),
            audits_before,
        )

    def test_an_unrelated_integrity_error_is_not_disguised(self):
        # The handler explains ONE fact (a same-name collision). Any other constraint
        # failure is not this endpoint's to turn into a location message.
        def other_constraint(instance, *args, **kwargs):
            raise IntegrityError(
                'duplicate key value violates unique constraint "other_constraint"'
            )

        self.client.raise_request_exception = False
        with mock.patch.object(StorageLocation, "save", other_constraint):
            response = self.client.post(
                LOCATIONS_URL,
                {"name": "Warehouse"},
                format="json",
                **self._auth(self.admin),
            )

        self.assertEqual(response.status_code, 500)
        self.assertFalse(StorageLocation.objects.filter(name="Warehouse").exists())


class TillCatalogueStoredAtTests(StorageTestBase):
    """The till's reads carry the label: units, variants, and the scan lookup."""

    def setUp(self):
        super().setUp()
        Product.objects.filter(pk=self.product.pk).update(stored_at=self.bodega)

    def test_the_selling_unit_list_carries_the_label(self):
        response = self.client.get(VARIANT_UOMS_URL, **self._auth(self.cashier))

        self.assertEqual(response.status_code, 200, response.data)
        row = next(
            item for item in response.data["results"] if item["id"] == self.vuom.pk
        )
        self.assertEqual(row["stored_at"], self.bodega.pk)
        self.assertEqual(row["stored_at_name"], "Bodega")

    def test_the_barcode_lookup_carries_the_label(self):
        response = self.client.get(
            VARIANT_UOMS_URL,
            {"barcode": self.vuom.barcode_qr},
            **self._auth(self.cashier),
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["stored_at_name"], "Bodega")

    def test_the_variant_list_carries_the_label(self):
        response = self.client.get(VARIANTS_URL, **self._auth(self.cashier))

        self.assertEqual(response.status_code, 200, response.data)
        row = next(
            item for item in response.data["results"] if item["id"] == self.variant.pk
        )
        self.assertEqual(row["stored_at_name"], "Bodega")

    def test_the_product_list_carries_the_label(self):
        response = self.client.get(PRODUCTS_URL, **self._auth(self.cashier))

        self.assertEqual(response.status_code, 200, response.data)
        row = next(
            item for item in response.data["results"] if item["id"] == self.product.pk
        )
        self.assertEqual(row["stored_at_name"], "Bodega")


class ListQueryCountTests(StorageTestBase):
    """A label on a list row must not cost a query PER ROW.

    Measured as "growing the page does not grow the queries", not as a magic constant, so
    a later prefetch change cannot make this test lie about what it proves.
    """

    def test_the_selling_unit_list_does_not_query_per_row(self):
        self._add_units(2)
        first = self._measure(VARIANT_UOMS_URL)

        self._add_units(4)
        second = self._measure(VARIANT_UOMS_URL)
        self.assertEqual(
            first, second, "the selling-unit list must not query once per row"
        )

    def test_the_product_list_does_not_query_per_row(self):
        first = self._measure(PRODUCTS_URL)

        for name in ("Mixing Tub", "Steel Bar"):
            product = Product.objects.create(
                category=self.category, brand=self.brand, base_name=name
            )
            ProductVariant.objects.create(
                product=product, variant_name="Standard", base_uom=self.uom
            )
        second = self._measure(PRODUCTS_URL)

        self.assertEqual(first, second, "the product list must not query once per row")

    def _add_units(self, count):
        for _ in range(count):
            self._unit_seq = getattr(self, "_unit_seq", 0) + 1
            code = f"X{self._unit_seq}"
            VariantUOM.objects.create(
                variant=self.variant,
                uom=self._uom(code),
                conversion_factor=Decimal(2),
                default_selling_price=Decimal(10),
            )

    def _uom(self, code):
        unit, _ = UnitOfMeasure.objects.get_or_create(
            code=code, defaults={"name": code}
        )
        return unit

    def _measure(self, url):
        from django.test.utils import CaptureQueriesContext

        with CaptureQueriesContext(connection) as captured:
            response = self.client.get(url, **self._auth(self.stocker))
        self.assertEqual(response.status_code, 200, response.data)
        return len(captured)


class SeedLocationTests(InventoryTestBase):
    """`seed_demo` leaves the two locations and shows one product at Bodega."""

    def test_the_seed_leaves_store_and_bodega_and_one_bodega_product(self):
        from io import StringIO

        from django.core.management import call_command

        from . import models as inventory_models

        # A clean catalog is what a fresh install has: `_seed_catalog` skips itself when
        # a `Cement` category already exists.
        inventory_models.StockAdjustment.objects.all().delete()
        inventory_models.InventoryBatch.objects.all().delete()
        VariantUOM.objects.all().delete()
        inventory_models.GoodsReceiptItem.objects.all().delete()
        inventory_models.GoodsReceipt.objects.all().delete()
        inventory_models.POItem.objects.all().delete()
        inventory_models.PurchaseOrder.objects.all().delete()
        ProductVariant.objects.all().delete()
        Product.objects.all().delete()
        Category.objects.all().delete()

        call_command("seed_demo", verbosity=0, stdout=StringIO())

        self.assertEqual(
            sorted(StorageLocation.objects.values_list("name", flat=True)),
            ["Bodega", "Store"],
        )
        bodega = StorageLocation.objects.get(name="Bodega")
        self.assertEqual(
            Product.objects.filter(stored_at=bodega).count(),
            1,
            "the demo must show one product picked up from Bodega",
        )
        self.assertEqual(
            Product.objects.exclude(stored_at=bodega)
            .filter(stored_at__name="Store")
            .count(),
            Product.objects.count() - 1,
            "every other seeded product defaults to Store",
        )


class AuditLogActionRows:
    """Tiny helper: the CREATE audit rows whose text names a location."""

    @staticmethod
    def create_rows(contains):
        from apps.users.models import AuditLog

        return AuditLog.objects.filter(
            action_type=AuditLog.ActionType.CREATE, description__contains=contains
        ).count()
