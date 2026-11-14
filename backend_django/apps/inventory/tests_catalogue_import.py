# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/inventory/tests_transfers.py: the checker runs from
# a working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into the test client. The test run is the
# authority.

"""Phase 3 B1 (decision 23, plan B1) — the catalogue import PREVIEW.

`POST /api/v1/catalogue-import/preview/` takes the rows Flutter parsed out of the edited
`.xlsx` and answers what the import WOULD do. It is the server trust boundary for the
round trip, so every rule lives here and reuses the existing serializers instead of a
second copy of them:

* one row is one **selling unit** (decision 23's sheet), carrying its product and variant
  columns with it;
* a row with a `Unit ID` runs `ProductSerializer` / `ProductVariantSerializer` /
  `VariantUOMSerializer` with `partial=True`, so barcode normalisation, GS1 check digits,
  barcode uniqueness, the one-base-unit rule, the in-use freeze and the active-location
  rule all fire exactly as they do on the per-row endpoints;
* a row with blank ids is grouped with its siblings by name into a NEW product and
  variant, and each unit row is its own new selling unit, validated as a create;
* every row error names the row, the sheet column and what to type instead.

**Nothing is written.** `InventoryBatch` rows, their quantities and the audit trail are
identical before and after a preview, which is what makes "preview, then apply" safe.
"""

import threading
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import IntegrityError, connection, connections
from django.test import TransactionTestCase
from django.test.utils import CaptureQueriesContext
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.pos.models import Customer, SalesItem, SalesTransaction
from apps.users.models import AuditLog

from .models import (
    Brand,
    Category,
    GoodsReceipt,
    InventoryBatch,
    Product,
    ProductVariant,
    PurchaseOrder,
    StorageLocation,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from .serializers import VariantUOMSerializer
from .services import process_goods_receipt
from .tests_storage_locations import StorageTestBase

User = get_user_model()

PREVIEW_URL = "/api/v1/catalogue-import/preview/"


class CatalogueImportTestBase(StorageTestBase):
    """Two selling units on the seeded variant, and real stock, so nothing is phantom.

    StorageTestBase already gives the roles (real JWT logins), Store + Bodega and a
    factor-1 `BAG` unit on "Portland Cement 40kg". This base adds a `SACK` (10 per base
    column, 50 base units) unit and one processed goods receipt, so a preview can be
    checked against stock and batches that exist.
    """

    def setUp(self):
        super().setUp()
        # The migration seeds the standard units, so every one of these already exists.
        self.sack, _ = UnitOfMeasure.objects.get_or_create(
            code="SACK", defaults={"name": "Sack"}
        )
        self.pc = UnitOfMeasure.objects.get(code="PC")
        self.sack_unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.sack,
            conversion_factor=Decimal(50),
            default_selling_price=Decimal(500),
            barcode_qr="0012345678905",
        )
        # One JWT per user, reused: a second login writes its own audit row, which would
        # make the "preview writes nothing" counts differ for a reason that is not the
        # preview.
        self._headers = {self.stocker.pk: self._auth(self.stocker)}
        self._receive_stock()

    def _receive_stock(self, qty="10"):
        _, _, receipt = self._receive(qty)
        return process_goods_receipt(receipt=receipt, user=self.user)

    # -- row builders ------------------------------------------------------
    def _row(self, **overrides):
        """One export row: the sheet's columns as the cells Flutter sends."""
        row = {
            "product_id": self.product.pk,
            "variant_id": self.variant.pk,
            "unit_id": self.vuom.pk,
            "category": self.category.name,
            "product_name": self.product.base_name,
            "variant": self.variant.variant_name,
            "unit_code": self.uom.code,
            "units_per_base": "1",
            "price": "10",
            "barcode": self.vuom.barcode_qr,
            "low_stock_threshold": "5",
            "stored_at": self.store.name,
            "active": "Yes",
            "brand": self.brand.name,
        }
        row.update(overrides)
        return row

    def _new_row(self, **overrides):
        """A blank-ID row: the sheet line that CREATES a product, variant and unit."""
        row = {
            "category": self.category.name,
            "product_name": "Mixing Tub",
            "variant": "Large",
            "unit_code": "BAG",
            "units_per_base": "1",
            "price": "300",
            "barcode": "",
            "low_stock_threshold": "0",
            "stored_at": self.store.name,
            "active": "Yes",
            "brand": self.brand.name,
        }
        row.update(overrides)
        return row

    def _sack_row(self, **overrides):
        row = self._row(
            unit_id=self.sack_unit.pk,
            unit_code=self.sack.code,
            units_per_base="50",
            price="500",
            barcode=self.sack_unit.barcode_qr,
        )
        row.update(overrides)
        return row

    # -- requests ----------------------------------------------------------
    def _headers_of(self, user):
        if user.pk not in self._headers:
            self._headers[user.pk] = self._auth(user)
        return self._headers[user.pk]

    def _preview(self, rows, user=None):
        client = APIClient()
        client.credentials(**self._headers_of(user or self.stocker))
        return client.post(PREVIEW_URL, {"rows": rows}, format="json")

    def _preview_ok(self, rows, user=None):
        response = self._preview(rows, user=user)
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    @staticmethod
    def _codes(body):
        return [error["code"] for error in body["errors"]]

    def _counts(self):
        return {
            "products": Product.objects.count(),
            "variants": ProductVariant.objects.count(),
            "units": VariantUOM.objects.count(),
            "batches": InventoryBatch.objects.count(),
            "stock": str(
                sum(batch.current_qty for batch in InventoryBatch.objects.all())
            ),
            "audit": AuditLog.objects.count(),
        }


class CataloguePreviewShapeTests(CatalogueImportTestBase):
    """The response the F2 preview dialog renders: creates, changes, unchanged, errors."""

    def test_an_unchanged_export_previews_as_nothing_to_do(self):
        body = self._preview_ok([self._row(), self._sack_row()])

        self.assertEqual(body["errors"], [])
        self.assertEqual(body["changes"], [])
        self.assertEqual(body["unchanged"], 2)
        self.assertEqual(body["creates"], {"products": 0, "variants": 0, "units": 0})
        self.assertEqual(len(body["fingerprint"]), 64)

    def test_a_price_change_is_one_change_with_before_and_after(self):
        body = self._preview_ok([self._row(price="12.50")])

        self.assertEqual(body["errors"], [])
        self.assertEqual(
            body["changes"],
            [
                {
                    "row": 1,
                    "field": "Price",
                    "before": "10.00",
                    "after": "12.50",
                }
            ],
        )
        self.assertEqual(body["unchanged"], 0)

    def test_a_product_field_change_is_reported_once_for_the_whole_product(self):
        rows = [
            self._row(product_name="Portland Cement 40kg"),
            self._sack_row(product_name="Portland Cement 40kg"),
        ]

        body = self._preview_ok(rows)

        self.assertEqual(body["errors"], [])
        self.assertEqual(
            body["changes"],
            [
                {
                    "row": 1,
                    "field": "Product name",
                    "before": "Portland Cement",
                    "after": "Portland Cement 40kg",
                }
            ],
        )
        # Both rows belong to the one product that changes, so neither is "unchanged".
        self.assertEqual(body["unchanged"], 0)

    def test_blank_ids_are_counted_as_creates(self):
        rows = [
            self._new_row(),
            self._new_row(unit_code="SACK", units_per_base="10", price="2500"),
        ]

        body = self._preview_ok(rows)

        self.assertEqual(body["errors"], [])
        self.assertEqual(body["changes"], [])
        self.assertEqual(body["creates"], {"products": 1, "variants": 1, "units": 2})

    def test_names_and_codes_match_ignoring_case(self):
        body = self._preview_ok(
            [
                self._row(
                    category="cement",
                    brand="RHINO",
                    unit_code="bag",
                    stored_at="store",
                    active="yes",
                )
            ]
        )

        self.assertEqual(body["errors"], [])
        # The resolved rows are the SAME ones, so nothing is reported as a change.
        self.assertEqual(body["changes"], [])
        self.assertEqual(body["unchanged"], 1)


class CataloguePreviewRowRuleTests(CatalogueImportTestBase):
    """Every rule the plan puts on a row, each pinned to its own code and column."""

    def test_more_than_2000_rows_refuses_the_whole_request(self):
        before = self._counts()

        response = self._preview([self._row()] * 2001)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "CATALOGUE_IMPORT_TOO_LARGE")
        self.assertIn("2,000", response.data["detail"])
        self.assertEqual(self._counts(), before)

    def test_a_body_without_a_rows_list_is_refused(self):
        for body in ({"nope": []}, [self._row()], {"rows": "not a list"}):
            with self.subTest(body=type(body).__name__):
                client = APIClient()
                client.credentials(**self._headers_of(self.stocker))
                response = client.post(PREVIEW_URL, body, format="json")

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data["code"], "INVALID_CATALOGUE_IMPORT")

    def test_a_row_that_is_not_a_set_of_cells_is_a_row_error(self):
        body = self._preview_ok([self._row(), "not a row"])

        self.assertEqual(self._codes(body), ["INVALID_ROW"])
        self.assertEqual(body["errors"][0]["row"], 2)

    def test_unknown_ids_are_row_errors(self):
        cases = [
            ("Product ID", {"product_id": 987654}, "UNKNOWN_PRODUCT"),
            ("Variant ID", {"variant_id": 987654}, "UNKNOWN_VARIANT"),
            ("Unit ID", {"unit_id": 987654}, "UNKNOWN_UNIT"),
        ]
        for column, override, code in cases:
            with self.subTest(column=column):
                body = self._preview_ok([self._row(**override)])
                self.assertEqual(len(body["errors"]), 1, body["errors"])
                error = body["errors"][0]
                self.assertEqual(error["row"], 1)
                self.assertEqual(error["column"], column)
                self.assertEqual(error["code"], code)
                self.assertIn("987654", error["message"])

    def test_a_variant_under_another_product_is_a_row_error(self):
        other = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Sand"
        )
        other_variant = ProductVariant.objects.create(
            product=other, variant_name="Sack", base_uom=self.uom
        )

        body = self._preview_ok([self._row(variant_id=other_variant.pk)])

        self.assertIn("VARIANT_NOT_IN_PRODUCT", self._codes(body))
        self.assertIn("Variant ID", [error["column"] for error in body["errors"]])

    def test_a_unit_under_another_variant_is_a_row_error(self):
        other = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Sand"
        )
        other_variant = ProductVariant.objects.create(
            product=other, variant_name="Sack", base_uom=self.uom
        )
        other_unit = VariantUOM.objects.create(
            variant=other_variant,
            uom=self.pc,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(30),
        )

        body = self._preview_ok([self._row(unit_id=other_unit.pk)])

        self.assertIn("UNIT_NOT_IN_VARIANT", self._codes(body))
        self.assertIn("Unit ID", [error["column"] for error in body["errors"]])

    def test_unknown_names_are_row_errors(self):
        cases = [
            ("Category", {"category": "Cemnet"}, "UNKNOWN_CATEGORY"),
            ("Brand", {"brand": "Rhinno"}, "UNKNOWN_BRAND"),
            ("Stored at", {"stored_at": "Garage"}, "UNKNOWN_STORED_AT"),
            ("Unit code", {"unit_code": "BAGG"}, "UNKNOWN_UNIT_CODE"),
        ]
        for column, override, code in cases:
            with self.subTest(column=column):
                body = self._preview_ok([self._row(**override)])
                self.assertEqual(self._codes(body), [code], body["errors"])
                self.assertEqual(body["errors"][0]["column"], column)

    def test_row_error_copy_names_the_column_and_says_what_to_type(self):
        body = self._preview_ok([self._row(category="Cemnet")])
        message = body["errors"][0]["message"]

        self.assertIn("Category", message)
        self.assertIn("Cemnet", message)
        self.assertIn("Cement", message)  # the value that IS accepted
        self.assertTrue(message.rstrip().endswith("."))
        self.assertNotIn("\u2014", message)  # no em dashes in copy, ever

    def test_an_inactive_stored_at_is_refused_when_a_row_moves_a_product(self):
        garage = StorageLocation.objects.create(name="Garage", is_active=False)

        body = self._preview_ok([self._row(stored_at=garage.name)])

        self.assertEqual(self._codes(body), ["INVALID_STORAGE_LOCATION"])
        self.assertEqual(body["errors"][0]["column"], "Stored at")

    def test_a_product_already_labelled_with_a_deactivated_location_is_kept(self):
        StorageLocation.objects.filter(pk=self.store.pk).update(is_active=False)

        body = self._preview_ok([self._row(), self._sack_row()])

        self.assertEqual(body["errors"], [])
        self.assertEqual(body["unchanged"], 2)

    def test_a_sold_units_factor_change_is_refused_but_its_price_is_not(self):
        transaction = SalesTransaction.objects.create(
            cashier=self.user,
            customer=Customer.objects.create(name="Walk-in Customer"),
            transaction_no="T-B1",
        )
        # The sold unit is the SACK, so the file still carries its variant's one base row:
        # the refusal under test is the freeze, not a missing base unit.
        SalesItem.objects.create(
            transaction=transaction,
            variant_uom=self.sack_unit,
            qty=Decimal(1),
            unit_price=Decimal(500),
            subtotal=Decimal(500),
        )

        refused = self._preview_ok([self._row(), self._sack_row(units_per_base="10")])
        self.assertEqual(self._codes(refused), ["SELLING_UNIT_IN_USE"])
        self.assertEqual(refused["errors"][0]["column"], "Units per base")

        allowed = self._preview_ok([self._row(), self._sack_row(price="550")])
        self.assertEqual(allowed["errors"], [])
        self.assertEqual([change["field"] for change in allowed["changes"]], ["Price"])

    def test_a_negative_threshold_is_a_row_error(self):
        body = self._preview_ok([self._row(low_stock_threshold="-1")])

        self.assertEqual(self._codes(body), ["INVALID_VARIANT"])
        self.assertEqual(body["errors"][0]["column"], "Low-stock threshold")

    def test_a_barcode_that_fails_the_check_digit_is_a_row_error(self):
        body = self._preview_ok([self._row(barcode="4800016123459")])

        self.assertEqual(self._codes(body), ["BARCODE_INVALID"])
        self.assertEqual(body["errors"][0]["column"], "Barcode")

    def test_a_barcode_another_unit_holds_is_a_row_error(self):
        body = self._preview_ok([self._row(barcode=self.sack_unit.barcode_qr)])

        self.assertEqual(self._codes(body), ["BARCODE_TAKEN"])
        self.assertEqual(body["errors"][0]["column"], "Barcode")

    def test_a_barcode_twice_in_the_file_is_a_row_error(self):
        rows = [
            self._row(barcode="5550001112"),
            self._sack_row(barcode="5550001112"),
        ]

        body = self._preview_ok(rows)

        self.assertEqual(self._codes(body), ["DUPLICATE_BARCODE_IN_FILE"])
        self.assertEqual(body["errors"][0]["row"], 2)
        self.assertEqual(body["errors"][0]["column"], "Barcode")
        self.assertIn("row 1", body["errors"][0]["message"])

    def test_a_variant_needs_exactly_one_base_unit_row(self):
        missing = self._preview_ok([self._sack_row(units_per_base="50")])
        self.assertEqual(self._codes(missing), ["BASE_UNIT_ROW_MISSING"])
        self.assertEqual(missing["errors"][0]["column"], "Units per base")

        second_base = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.pc,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        duplicate = self._preview_ok(
            [
                self._row(),
                self._row(
                    unit_id=second_base.pk,
                    unit_code=self.pc.code,
                    units_per_base="1",
                    price="10",
                    barcode=second_base.barcode_qr,
                ),
            ]
        )
        self.assertEqual(self._codes(duplicate), ["BASE_UNIT_ROW_DUPLICATE"])
        self.assertEqual(duplicate["errors"][0]["row"], 2)
        self.assertEqual(duplicate["errors"][0]["column"], "Units per base")

    def test_two_rows_cannot_create_the_same_unit_twice(self):
        rows = [self._new_row(), self._new_row(units_per_base="2")]

        body = self._preview_ok(rows)

        self.assertEqual(self._codes(body), ["DUPLICATE_UNIT_IN_FILE"])
        self.assertEqual(body["errors"][0]["row"], 2)
        self.assertEqual(body["errors"][0]["column"], "Unit code")

    def test_rows_of_one_product_have_to_agree(self):
        hardware = Category.objects.create(name="Hardware")
        other_brand = Brand.objects.create(name="Winsor")
        garage = StorageLocation.objects.create(name="Garage")
        cases = [
            ("Category", {"category": hardware.name}),
            ("Product name", {"product_name": "Portland Cement 40kg"}),
            ("Brand", {"brand": other_brand.name}),
            ("Stored at", {"stored_at": garage.name}),
            ("Active", {"active": "No"}),
        ]
        for column, override in cases:
            with self.subTest(column=column):
                body = self._preview_ok([self._row(), self._sack_row(**override)])
                self.assertEqual(self._codes(body), ["PRODUCT_ROWS_DISAGREE"])
                self.assertEqual(body["errors"][0]["row"], 2)
                self.assertEqual(body["errors"][0]["column"], column)
                self.assertIn("row 1", body["errors"][0]["message"])

    def test_an_active_cell_that_is_neither_yes_nor_no_is_a_row_error(self):
        body = self._preview_ok([self._row(active="maybe")])

        self.assertEqual(self._codes(body), ["INVALID_BOOLEAN"])
        self.assertEqual(body["errors"][0]["column"], "Active")

    def test_a_cell_that_should_be_a_number_is_a_row_error(self):
        body = self._preview_ok([self._row(price="ten")])

        self.assertEqual(self._codes(body), ["INVALID_NUMBER"])
        self.assertEqual(body["errors"][0]["column"], "Price")

    def test_a_new_product_needs_its_own_columns_filled(self):
        rows = [
            {
                "category": "",
                "product_name": "",
                "variant": "Large",
                "unit_code": "",
                "units_per_base": "",
                "price": "",
                "brand": "",
            }
        ]

        body = self._preview_ok(rows)

        self.assertEqual(set(self._codes(body)), {"MISSING_VALUE"})
        self.assertEqual(
            {error["column"] for error in body["errors"]},
            {
                "Category",
                "Product name",
                "Unit code",
                "Units per base",
                "Price",
                "Brand",
            },
        )
        self.assertEqual(body["creates"], {"products": 0, "variants": 0, "units": 0})


class CataloguePreviewWritesNothingTests(CatalogueImportTestBase):
    """A preview is a read: rows, stock, batches and the audit trail are untouched."""

    def test_a_preview_writes_nothing_at_all(self):
        before = self._counts()
        rows = [
            self._row(price="12.50"),  # a change
            self._sack_row(),  # unchanged
            self._new_row(),  # a create
            self._row(price="99", category="Cemnet"),  # an error
        ]

        body = self._preview_ok(rows)

        self.assertEqual(self._counts(), before)
        self.assertEqual(body["creates"], {"products": 1, "variants": 1, "units": 1})
        self.assertEqual(len(body["changes"]), 1)
        self.assertEqual(self._codes(body), ["UNKNOWN_CATEGORY"])
        self.assertEqual(
            str(sum(batch.current_qty for batch in InventoryBatch.objects.all())),
            before["stock"],
        )


class CataloguePreviewFingerprintTests(CatalogueImportTestBase):
    """The fingerprint is what makes Apply refuse a preview the catalogue outgrew."""

    def test_the_same_rows_and_rows_again_hash_the_same(self):
        rows = [self._row(), self._sack_row()]

        first = self._preview_ok(rows)["fingerprint"]
        second = self._preview_ok(rows)["fingerprint"]

        self.assertEqual(first, second)

    def test_another_payload_hashes_differently(self):
        first = self._preview_ok([self._row()])["fingerprint"]
        second = self._preview_ok([self._row(price="12")])["fingerprint"]

        self.assertNotEqual(first, second)

    def test_a_referenced_row_that_moved_since_the_preview_changes_the_hash(self):
        rows = [self._row()]
        first = self._preview_ok(rows)["fingerprint"]

        Product.objects.filter(pk=self.product.pk).update(
            updated_at=timezone.now() + timedelta(hours=1)
        )

        self.assertNotEqual(first, self._preview_ok(rows)["fingerprint"])


class CataloguePreviewAccessTests(CatalogueImportTestBase):
    """Stock Manager, Store Manager and Admin may preview; the till may not."""

    def test_missing_credentials_are_refused(self):
        response = APIClient().post(PREVIEW_URL, {"rows": []}, format="json")

        self.assertEqual(response.status_code, 401, response.data)

    def test_a_cashier_is_forbidden(self):
        response = self._preview([self._row()], user=self.cashier)

        self.assertEqual(response.status_code, 403, response.data)

    def test_the_inventory_roles_may_preview(self):
        for user in (self.stocker, self.admin):
            with self.subTest(user=user.username):
                response = self._preview([self._row()], user=user)
                self.assertEqual(response.status_code, 200, response.data)


APPLY_URL = "/api/v1/catalogue-import/apply/"


class CatalogueApplyTestBase(CatalogueImportTestBase):
    """`_apply` posts the rows back with the fingerprint the preview just returned."""

    def _apply(self, rows, fingerprint=None, user=None):
        if fingerprint is None:
            fingerprint = self._preview_ok(rows)["fingerprint"]
        client = APIClient()
        client.credentials(**self._headers_of(user or self.stocker))
        return client.post(
            APPLY_URL, {"rows": rows, "fingerprint": fingerprint}, format="json"
        )

    def _apply_ok(self, rows, fingerprint=None, user=None):
        response = self._apply(rows, fingerprint=fingerprint, user=user)
        self.assertEqual(response.status_code, 200, response.data)
        return response.data

    def _new_audit_rows(self, before):
        return list(
            AuditLog.objects.filter(pk__gt=before)
            .order_by("pk")
            .values_list("action_type", "description")
        )

    def _latest_audit_pk(self):
        return (
            AuditLog.objects.order_by("-pk").values_list("pk", flat=True).first() or 0
        )


class CatalogueApplyHappyPathTests(CatalogueApplyTestBase):
    """Apply writes what the preview described, in one transaction, and audits each record."""

    def test_creates_and_changes_are_applied_and_counted(self):
        rows = [
            self._row(price="12.50"),  # one selling unit changes
            self._new_row(),  # one product + variant + unit created
        ]

        body = self._apply_ok(rows)

        self.assertEqual(body["creates"], {"products": 1, "variants": 1, "units": 1})
        self.assertEqual(body["updates"], {"products": 0, "variants": 0, "units": 1})
        self.assertEqual(body["unchanged"], 0)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal("12.50"))
        self.assertTrue(Product.objects.filter(base_name="Mixing Tub").exists())
        created = ProductVariant.objects.get(variant_name="Large")
        self.assertEqual(created.selling_uoms.count(), 1)

    def test_one_summary_audit_row_names_the_import_and_the_counts(self):
        before = self._latest_audit_pk()

        self._apply_ok([self._row(price="12.50"), self._new_row()])

        rows = self._new_audit_rows(before)
        summaries = [text for action, text in rows if action == "CATALOGUE_IMPORT"]
        self.assertEqual(len(summaries), 1, rows)
        self.assertIn("Catalogue import applied", summaries[0])
        self.assertIn("1 product", summaries[0])
        self.assertIn("1 selling unit updated", summaries[0])

    def test_every_created_or_changed_record_gets_its_own_audit_row(self):
        before = self._latest_audit_pk()

        self._apply_ok([self._row(price="12.50"), self._new_row()])

        rows = self._new_audit_rows(before)
        record_rows = [r for r in rows if r[0] != "CATALOGUE_IMPORT"]
        # 1 product CREATE + 1 variant CREATE + 1 unit CREATE + 1 unit UPDATE.
        self.assertEqual(
            sorted(action for action, _ in record_rows),
            ["CREATE", "CREATE", "CREATE", "UPDATE"],
            record_rows,
        )
        price_row = next(text for action, text in record_rows if "price" in text)
        # The audit row reads EXACTLY like the one PATCH /variant-uoms/{id}/ writes, down
        # to the record label: the trail must not describe the same edit two ways. The
        # em dash in the label is the model's own `__str__` (the per-row endpoint's
        # wording), not dialog copy - the no-em-dash rule is about the error messages the
        # clerk reads next to a cell.
        self.assertEqual(
            price_row,
            "Selling unit Portland Cement \u2014 40kg @ BAG (\u00d71.00) updated: "
            "price 10.00 -> 12.50.",
        )

    def test_an_unchanged_sheet_writes_nothing_and_says_so(self):
        before = self._counts()
        audit_before = self._latest_audit_pk()

        body = self._apply_ok([self._row(), self._sack_row()])

        self.assertEqual(body["creates"], {"products": 0, "variants": 0, "units": 0})
        self.assertEqual(body["updates"], {"products": 0, "variants": 0, "units": 0})
        self.assertEqual(body["unchanged"], 2)
        self.assertEqual(self._counts(), before)
        self.assertEqual(self._new_audit_rows(audit_before), [])

    def test_stock_and_batches_are_identical_before_and_after(self):
        before = self._counts()

        self._apply_ok([self._row(price="12.50"), self._new_row()])

        after = self._counts()
        self.assertEqual(after["batches"], before["batches"])
        self.assertEqual(after["stock"], before["stock"])


class CatalogueApplyRefusalTests(CatalogueApplyTestBase):
    """A refusal writes NOTHING: no record, no audit row, no stock move."""

    def test_a_row_error_refuses_the_file_and_writes_nothing(self):
        before = self._counts()
        audit_before = self._latest_audit_pk()
        rows = [self._row(price="12.50"), self._row(price="99", category="Cemnet")]

        response = self._apply(rows)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "CATALOGUE_IMPORT_ROW_ERRORS")
        self.assertEqual(
            [error["code"] for error in response.data["errors"]], ["UNKNOWN_CATEGORY"]
        )
        self.assertEqual(self._counts(), before)
        self.assertEqual(self._new_audit_rows(audit_before), [])
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal(10))

    def test_a_stale_preview_is_a_409_and_writes_nothing(self):
        before = self._counts()
        rows = [self._row(price="12.50")]
        fingerprint = self._preview_ok(rows)["fingerprint"]
        # The catalogue moves between the preview and the apply.
        Product.objects.filter(pk=self.product.pk).update(
            updated_at=timezone.now() + timedelta(hours=1)
        )

        response = self._apply(rows, fingerprint=fingerprint)

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data["code"], "CATALOGUE_PREVIEW_STALE")
        self.assertIn("Run the preview again", response.data["detail"])
        self.assertEqual(self._counts(), before)

    def test_a_lost_barcode_race_refuses_the_whole_import(self):
        # Another writer takes the code between the serializer's read and its insert: the
        # pre-check sees nothing free (patched), so only the DB constraint can refuse.
        rival = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.pc,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal(20),
            barcode_qr="5550001112",
        )
        rows = [self._row(price="12.50"), self._sack_row(barcode=rival.barcode_qr)]
        fingerprint = self._preview_ok(rows)["fingerprint"]
        before = self._counts()

        with mock.patch.object(
            VariantUOMSerializer, "_barcode_holder", return_value=None
        ):
            response = self._apply(rows, fingerprint=fingerprint)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "BARCODE_TAKEN")
        self.assertEqual(self._counts(), before)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal(10))

    def test_a_sold_units_factor_change_is_refused_but_its_price_change_applies(self):
        transaction = SalesTransaction.objects.create(
            cashier=self.user,
            customer=Customer.objects.create(name="Walk-in Customer"),
            transaction_no="T-B2",
        )
        SalesItem.objects.create(
            transaction=transaction,
            variant_uom=self.sack_unit,
            qty=Decimal(1),
            unit_price=Decimal(500),
            subtotal=Decimal(500),
        )
        before = self._counts()

        refused = self._apply([self._row(), self._sack_row(units_per_base="10")])
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(
            [error["code"] for error in refused.data["errors"]], ["SELLING_UNIT_IN_USE"]
        )
        self.assertEqual(self._counts(), before)

        applied = self._apply_ok([self._row(), self._sack_row(price="550")])
        self.assertEqual(applied["updates"], {"products": 0, "variants": 0, "units": 1})
        self.sack_unit.refresh_from_db()
        self.assertEqual(self.sack_unit.default_selling_price, Decimal(550))

    def test_a_second_apply_of_the_same_fingerprint_is_refused_as_stale(self):
        rows = [self._row(price="12.50")]
        fingerprint = self._preview_ok(rows)["fingerprint"]
        self._apply_ok(rows, fingerprint=fingerprint)

        second = self._apply(rows, fingerprint=fingerprint)

        self.assertEqual(second.status_code, 409, second.data)
        self.assertEqual(second.data["code"], "CATALOGUE_PREVIEW_STALE")


class CatalogueApplyAccessTests(CatalogueApplyTestBase):
    """Inventory roles may apply; the till may not; nobody anonymous may."""

    def test_missing_credentials_are_refused(self):
        before = self._counts()

        response = APIClient().post(APPLY_URL, {"rows": []}, format="json")

        self.assertEqual(response.status_code, 401, response.data)
        self.assertEqual(self._counts(), before)

    def test_a_cashier_is_forbidden(self):
        # The JWT login itself writes a LOGIN audit row, so the baseline is taken AFTER
        # it: the count under test is the apply's, not the login's.
        self._headers_of(self.cashier)
        before = self._counts()

        response = self._apply([self._row(price="12.50")], user=self.cashier)

        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(self._counts(), before)

    def test_the_inventory_roles_may_apply(self):
        for user in (self.stocker, self.admin):
            with self.subTest(user=user.username):
                rows = [self._row(price="12.50" if user == self.stocker else "13.50")]
                response = self._apply(rows, user=user)
                self.assertEqual(response.status_code, 200, response.data)


class CatalogueApplyLockOrderTests(CatalogueApplyTestBase):
    """The locks are taken units -> variants -> products: Phase 9's writer order.

    Every Phase 9 writer (`transfers.record_stock_transfer` step (0), plus the receipt,
    adjustment and sale paths through `_check_low_stock`) takes the SELLING UNIT first
    and the `ProductVariant` LATER. An apply that took them the other way round could
    hold the variant while a sale held the unit and waited for the variant - a real
    deadlock, one aborted transaction per busy afternoon. This pins the ONE order.
    """

    def test_referenced_rows_are_locked_units_then_variants_then_products(self):
        rows = [self._row(price="12.50"), self._sack_row(), self._new_row()]
        fingerprint = self._preview_ok(rows)["fingerprint"]

        with CaptureQueriesContext(connection) as captured:
            self._apply_ok(rows, fingerprint=fingerprint)

        locked = [
            query["sql"]
            for query in captured.captured_queries
            if "FOR UPDATE" in query["sql"].upper()
        ]
        # One statement per model, in the order the apply takes them.
        self.assertEqual(len(locked), 3, locked)
        # The SELLING UNIT first: the row `lock_selling_unit_lines` takes before anything
        # else, so an apply and a sale queue behind each other instead of deadlocking.
        self.assertIn("inventory_variant_uom", locked[0])
        self.assertNotIn("inventory_product_variant", locked[0])
        # Then the variant, then the product - the order `_check_low_stock` reaches them.
        self.assertIn("inventory_product_variant", locked[1])
        self.assertIn("inventory_product", locked[2])
        self.assertNotIn("inventory_variant_uom", locked[2])
        for statement in locked:
            # Each lock is ordered by the model's own PK, so concurrent applies take the
            # same rows in the same order.
            self.assertIn("ORDER BY", statement)
            self.assertRegex(statement, r'ORDER BY "[a-z_]+"\."id" ASC FOR UPDATE$')


class CatalogueCopyCarryForwardTests(CatalogueApplyTestBase):
    """B1 review warnings 1-3, pinned so they cannot come back."""

    def test_unit_not_in_variant_names_both_variants_without_an_em_dash(self):
        other = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Sand"
        )
        other_variant = ProductVariant.objects.create(
            product=other, variant_name="Sack", base_uom=self.uom
        )
        other_unit = VariantUOM.objects.create(
            variant=other_variant,
            uom=self.pc,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(30),
        )

        body = self._preview_ok([self._row(unit_id=other_unit.pk)])
        message = next(
            error["message"]
            for error in body["errors"]
            if error["code"] == "UNIT_NOT_IN_VARIANT"
        )

        # Built from the fields, so the two records are still named...
        self.assertIn("Sand", message)
        self.assertIn("Sack", message)
        self.assertIn("Portland Cement", message)
        # ...and the sentence carries no em dash.
        self.assertNotIn("\u2014", message)

    def test_inherited_serializer_refusals_are_normalised_for_the_import_path(self):
        """SELLING_UNIT_IN_USE / DUPLICATE_BASE_UNIT are shared with the per-row endpoints.

        Their wording is pinned there, so the import normalises the em dash out on its own
        path instead of changing what a PATCH answers.
        """
        transaction = SalesTransaction.objects.create(
            cashier=self.user,
            customer=Customer.objects.create(name="Walk-in Customer"),
            transaction_no="T-CARRY",
        )
        SalesItem.objects.create(
            transaction=transaction,
            variant_uom=self.sack_unit,
            qty=Decimal(1),
            unit_price=Decimal(500),
            subtotal=Decimal(500),
        )

        frozen = self._preview_ok([self._row(), self._sack_row(units_per_base="10")])
        frozen_message = frozen["errors"][0]["message"]
        self.assertEqual(frozen["errors"][0]["code"], "SELLING_UNIT_IN_USE")
        self.assertNotIn("\u2014", frozen_message)
        self.assertIn("Portland Cement", frozen_message)

        second_base = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.pc,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal(10),
        )
        duplicate = self._preview_ok(
            [
                self._row(
                    unit_id=second_base.pk,
                    unit_code=self.pc.code,
                    units_per_base="1",
                    price="10",
                    barcode=second_base.barcode_qr,
                ),
            ]
        )
        self.assertEqual(self._codes(duplicate), ["DUPLICATE_BASE_UNIT"], duplicate)
        duplicate_message = duplicate["errors"][0]["message"]
        self.assertNotIn("\u2014", duplicate_message)

        # BARCODE_TAKEN is the third inherited sentence: it already joins fields with an
        # interpunct, and the import path keeps it that way.
        taken = self._preview_ok([self._row(barcode=self.sack_unit.barcode_qr)])
        self.assertEqual(self._codes(taken), ["BARCODE_TAKEN"], taken)
        self.assertNotIn("\u2014", taken["errors"][0]["message"])

    def test_the_per_row_endpoints_keep_their_own_wording(self):
        """The normalisation is the IMPORT's: a PATCH still reads the serializer's sentence."""
        second_base = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.pc,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal(10),
        )

        response = self.client.patch(
            f"/api/v1/variant-uoms/{second_base.pk}/",
            {"conversion_factor": "1"},
            format="json",
            **self._headers_of(self.stocker),
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DUPLICATE_BASE_UNIT")
        # The em dash is STILL there on the per-row endpoint: B1's wording is untouched.
        self.assertIn("\u2014", response.data["detail"])

    def test_rows_of_one_variant_have_to_agree_on_the_low_stock_threshold(self):
        body = self._preview_ok([self._row(), self._sack_row(low_stock_threshold="9")])

        self.assertEqual(self._codes(body), ["VARIANT_ROWS_DISAGREE"])
        self.assertEqual(body["errors"][0]["row"], 2)
        self.assertEqual(body["errors"][0]["column"], "Low-stock threshold")
        self.assertIn("row 1", body["errors"][0]["message"])

    def test_a_blank_threshold_agrees_with_a_row_naming_the_stored_one(self):
        body = self._preview_ok([self._row(), self._sack_row(low_stock_threshold="")])

        self.assertEqual(body["errors"], [])
        self.assertEqual(body["unchanged"], 2)

    def test_the_fingerprint_pins_the_raw_row_count(self):
        first = self._preview_ok([self._row()])["fingerprint"]
        second = self._preview_ok([self._row(), self._sack_row()])["fingerprint"]

        self.assertNotEqual(first, second)

    def test_two_different_malformed_bodies_do_not_share_a_fingerprint(self):
        first = self._preview_ok([self._row(), "not a row"])["fingerprint"]
        second = self._preview_ok([self._row(), "another bad row"])["fingerprint"]

        self.assertNotEqual(first, second)

    def test_a_sheet_that_creates_rows_changes_the_catalogue_count_in_the_hash(self):
        """A file of CREATES touches no referenced row, so the counts are what go stale."""
        rows = [self._new_row()]
        before = self._preview_ok(rows)["fingerprint"]

        self._apply_ok(rows)

        self.assertNotEqual(before, self._preview_ok(rows)["fingerprint"])


class CatalogueApplyFingerprintGuardTests(CatalogueApplyTestBase):
    """Warning 4: the apply needs the preview's fingerprint, and says so with a 400."""

    def test_a_missing_or_blank_fingerprint_is_refused_with_nothing_written(self):
        rows = [self._row(price="12.50")]
        before = self._counts()

        for body in (
            {"rows": rows},
            {"rows": rows, "fingerprint": None},
            {"rows": rows, "fingerprint": ""},
            {"rows": rows, "fingerprint": "   "},
        ):
            with self.subTest(body=body):
                client = APIClient()
                client.credentials(**self._headers_of(self.stocker))
                response = client.post(APPLY_URL, body, format="json")

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data["code"], "INVALID_CATALOGUE_IMPORT")
                self.assertEqual(self._counts(), before)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal(10))


class CatalogueApplyConstraintRefusalTests(CatalogueApplyTestBase):
    """Warning 5: a NON-barcode constraint failure is a clean refusal, never a 500.

    The barcode race has its own 400 (`BARCODE_TAKEN`). Any other `IntegrityError` while
    the apply writes means the catalogue moved under the file, so the answer is the same
    "run the preview again": a coded 409 with the transaction rolled back. Before this,
    the `IntegrityError` fell through `_refuse_lost_barcode_race`'s re-raise and reached
    the client as an unhandled 500.
    """

    def test_a_non_barcode_constraint_failure_is_a_409_and_writes_nothing(self):
        rows = [self._row(price="12.50")]
        fingerprint = self._preview_ok(rows)["fingerprint"]
        before = self._counts()

        # Another writer claims a unique value this apply is about to insert. The DB is
        # the only thing that can refuse it, and it is NOT the barcode constraint.
        with mock.patch.object(
            VariantUOMSerializer,
            "save",
            side_effect=IntegrityError(
                'duplicate key value violates unique constraint "uq_variant_uom"'
            ),
        ):
            response = self._apply(rows, fingerprint=fingerprint)

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data["code"], "CATALOGUE_IMPORT_NOT_SAVED")
        self.assertEqual(
            response.data["detail"],
            "The import could not be saved. Run the preview again.",
        )
        # The whole transaction rolled back: no write, no audit row, price untouched.
        self.assertEqual(self._counts(), before)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal(10))


class CatalogueApplyConcurrencyBase(TransactionTestCase):
    """Committed catalogue rows both a lock holder and an apply can see.

    `TransactionTestCase` because a SECOND connection must be able to lock a row the
    apply will then wait on, and two worker threads must see each other's COMMITTED
    rows. The wrapped transaction a `TestCase` uses hides both, so the busy and deadlock
    tests would pass on timing rather than on row locks (same reason
    `tests_transfers.ConcurrentTransferTests` is one).
    """

    TRANSFERS_URL = "/api/v1/stock-transfers/"

    def setUp(self):
        self.password = get_random_string(16)
        self.store = StorageLocation.objects.get_or_create(name="Store")[0]
        self.bodega = StorageLocation.objects.get_or_create(name="Bodega")[0]
        supplier = Supplier.objects.create(company_name="Concurrency Supply")
        self.stocker = self._user("cc_stocker", "Stock Manager")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.stocker,
            status=PurchaseOrder.Status.ORDERED,
        )
        category = Category.objects.create(name="Concurrency Cement")
        brand = Brand.objects.create(name="Concurrency Brand")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="CCKG", defaults={"name": "Concurrency Kilogram"}
        )
        self.product = Product.objects.create(
            category=category,
            brand=brand,
            base_name="Concurrency Cement",
            stored_at=self.store,
        )
        self.variant = ProductVariant.objects.create(
            product=self.product, variant_name="40kg", base_uom=uom
        )
        self.vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        InventoryBatch.objects.create(
            variant=self.variant,
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.stocker),
            location=self.store,
            initial_qty=Decimal(10),
            current_qty=Decimal(10),
            unit_cost_landed=Decimal("50.00"),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal("55.00"),
        )
        self.auth = self._auth()

    def _user(self, username, *groups):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@example.com",
            password=self.password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self):
        client = APIClient()
        login = client.post(
            "/api/v1/auth/login/",
            {"username": "cc_stocker", "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200, login.data)
        return {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}

    def _row(self, **overrides):
        row = {
            "product_id": self.product.pk,
            "variant_id": self.variant.pk,
            "unit_id": self.vuom.pk,
            "category": self.product.category.name,
            "product_name": self.product.base_name,
            "variant": self.variant.variant_name,
            "unit_code": self.vuom.uom.code,
            "units_per_base": "1",
            "price": "10",
            "barcode": self.vuom.barcode_qr,
            "low_stock_threshold": "0",
            "stored_at": self.store.name,
            "active": "Yes",
            "brand": self.product.brand.name,
        }
        row.update(overrides)
        return row

    def _fingerprint(self, rows):
        client = APIClient()
        client.credentials(**self.auth)
        response = client.post(PREVIEW_URL, {"rows": rows}, format="json")
        self.assertEqual(response.status_code, 200, response.data)
        return response.data["fingerprint"]

    def _apply(self, rows, fingerprint):
        client = APIClient()
        client.credentials(**self.auth)
        return client.post(
            APPLY_URL, {"rows": rows, "fingerprint": fingerprint}, format="json"
        )

    def _counts(self):
        return {
            "products": Product.objects.count(),
            "variants": ProductVariant.objects.count(),
            "units": VariantUOM.objects.count(),
            "batches": InventoryBatch.objects.count(),
            "stock": str(
                sum(batch.current_qty for batch in InventoryBatch.objects.all())
            ),
            "audit": AuditLog.objects.count(),
        }


class CatalogueApplyBusyTests(CatalogueApplyConcurrencyBase):
    """Warning 1: a lock held past the apply's own cap is a retryable 503, not a hang."""

    def test_a_blocked_apply_answers_busy_and_writes_nothing(self):
        from . import catalogue_import

        rows = [self._row(price="12.50")]
        fingerprint = self._fingerprint(rows)
        before = self._counts()

        # Hold the selling unit from a SECOND connection, exactly like a sale or a
        # receipt mid-transaction would, and shrink the cap so the test does not wait
        # the production five seconds.
        holder = connections.create_connection("default")
        try:
            holder.ensure_connection()
            with holder.cursor() as cursor:
                cursor.execute("BEGIN")
                cursor.execute(
                    "SELECT id FROM inventory_variant_uom WHERE id = %s FOR UPDATE",
                    [self.vuom.pk],
                )

            with mock.patch.object(catalogue_import, "LOCK_TIMEOUT", "250ms"):
                response = self._apply(rows, fingerprint=fingerprint)
        finally:
            holder.rollback()
            holder.close()

        self.assertEqual(response.status_code, 503, response.data)
        self.assertEqual(response.data["code"], "CATALOGUE_IMPORT_BUSY")
        self.assertEqual(
            response.data["detail"], "The catalogue is busy. Try again in a moment."
        )
        self.assertEqual(self._counts(), before)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal(10))


class CatalogueApplyDeadlockTests(CatalogueApplyConcurrencyBase):
    """Blocker 1: an apply racing a stock transfer on one unit must not deadlock.

    `TransactionTestCase` because the two worker threads must see each other's COMMITTED
    rows - the wrapped transaction a `TestCase` uses hides them, and the test would then
    pass or fail on timing rather than on the row locks (same reason
    `tests_transfers.ConcurrentTransferTests` is one).

    Before the fix `_lock_referenced` took Product -> ProductVariant -> VariantUOM while
    every Phase 9 writer takes the SELLING UNIT first and the variant later, so this pair
    could each hold one row and wait for the other. PostgreSQL aborts one side with
    "deadlock detected". The fix makes the apply take the same order the transfer does.
    """

    def test_an_apply_and_a_transfer_on_one_unit_do_not_deadlock(self):
        rows = [self._row(price="12.50")]
        fingerprint = self._fingerprint(rows)

        barrier = threading.Barrier(2, timeout=20)
        results = {}
        lock = threading.Lock()

        def apply_worker():
            client = APIClient()
            client.credentials(**self.auth)
            try:
                barrier.wait()
                response = client.post(
                    APPLY_URL,
                    {"rows": rows, "fingerprint": fingerprint},
                    format="json",
                )
                with lock:
                    results["apply"] = response.status_code
                    results["apply_body"] = response.data
            except Exception as exc:  # noqa: BLE001 - a crash here IS the failure
                with lock:
                    results["apply"] = f"ERROR {exc!r}"
            finally:
                connections.close_all()

        def transfer_worker():
            client = APIClient()
            client.credentials(**self.auth)
            try:
                barrier.wait()
                response = client.post(
                    self.TRANSFERS_URL,
                    {
                        "from_location": self.store.pk,
                        "to_location": self.bodega.pk,
                        "lines": [{"variant_uom": self.vuom.pk, "qty": "1"}],
                    },
                    format="json",
                )
                with lock:
                    results["transfer"] = response.status_code
                    results["transfer_body"] = response.data
            except Exception as exc:  # noqa: BLE001
                with lock:
                    results["transfer"] = f"ERROR {exc!r}"
            finally:
                connections.close_all()

        threads = [
            threading.Thread(target=apply_worker),
            threading.Thread(target=transfer_worker),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=40)

        # The deadlock is what this test exists to rule out: PostgreSQL reports it as a
        # 55P03/40P01 OperationalError, which surfaced as a 500 before the fix.
        for side in ("apply", "transfer"):
            self.assertIn(side, results, results)
            self.assertNotIn("deadlock detected", str(results[side]).lower(), results)
            self.assertNotIn("ERROR", str(results[side]), results)

        # Both may legitimately succeed: the transfer moves 1 of 10 and the apply only
        # reprices. Neither may fail with a 500.
        self.assertEqual(results["apply"], 200, results)
        self.assertEqual(results["transfer"], 201, results)

        # The unit was repriced and the transfer moved stock - both committed.
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal("12.50"))
        total = sum(
            (
                batch.current_qty
                for batch in InventoryBatch.objects.filter(variant=self.variant)
            ),
            Decimal(0),
        )
        self.assertEqual(total, Decimal(10))
