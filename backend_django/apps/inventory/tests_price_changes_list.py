# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
# Same directives and reasons as apps/inventory/tests_price_history.py: no django-stubs.
from datetime import timedelta
from decimal import Decimal
from typing import cast

from django.utils import timezone
from rest_framework.response import Response

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    SellingUnitPriceChange,
    UnitOfMeasure,
    VariantUOM,
)
from .tests_catalog_writes import CatalogWriteTestBase

PRICE_CHANGES_URL = "/api/v1/price-changes/"


class PriceChangesListTests(CatalogWriteTestBase):
    def setUp(self):
        super().setUp()
        self.admin = self._make_user("pc_admin", "Admin")
        self.bodega = self._make_user("pc_bodega", "Bodega Checker")

        self.box_uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box", "is_whole": True}
        )
        self.pack_vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.box_uom,
            conversion_factor=Decimal("10.00"),
            default_selling_price=Decimal("95.00"),
            barcode_qr="4800016123450",
        )

        # Second product for ?product= and ?q= filters
        cat2 = Category.objects.create(name="Paints")
        brand2 = Brand.objects.create(name="Boysen")
        self.other_product = Product.objects.create(
            category=cat2, brand=brand2, base_name="Latex Paint"
        )
        self.other_variant = ProductVariant.objects.create(
            product=self.other_product, variant_name="White 1L", base_uom=self.uom_pc
        )
        self.other_vuom = VariantUOM.objects.create(
            variant=self.other_variant,
            uom=self.uom_pc,
            conversion_factor=Decimal("1.00"),
            default_selling_price=Decimal("15.00"),
            barcode_qr="4800016123467",
        )

    def test_permissions_allow_inventory_manager_admin_and_refuse_others(self):
        unauth = cast(Response, self.client.get(PRICE_CHANGES_URL))
        self.assertEqual(unauth.status_code, 401)

        for user in (self.cashier, self.bodega):
            denied = cast(
                Response,
                self.client.get(PRICE_CHANGES_URL, **self._auth(user)),
            )
            self.assertEqual(denied.status_code, 403, f"expected 403 for {user.username}")

        for user in (self.stocker, self.manager, self.admin):
            allowed = cast(
                Response,
                self.client.get(PRICE_CHANGES_URL, **self._auth(user)),
            )
            self.assertEqual(allowed.status_code, 200, f"expected 200 for {user.username}")

    def test_lists_store_wide_newest_first_with_fields_and_pagination(self):
        c1 = SellingUnitPriceChange.objects.create(
            variant_uom=self.vuom,
            old_price=None,
            new_price=Decimal("10.00"),
            actor=self.stocker,
            source=SellingUnitPriceChange.Source.CATALOGUE,
        )
        c2 = SellingUnitPriceChange.objects.create(
            variant_uom=self.pack_vuom,
            old_price=Decimal("100.00"),
            new_price=Decimal("125.00"),
            actor=self.manager,
            source=SellingUnitPriceChange.Source.IMPORT,
        )
        c3 = SellingUnitPriceChange.objects.create(
            variant_uom=self.other_vuom,
            old_price=Decimal("20.00"),
            new_price=Decimal("15.00"),
            actor=None,
            source=SellingUnitPriceChange.Source.ADMIN,
        )

        res = cast(
            Response,
            self.client.get(PRICE_CHANGES_URL, **self._auth(self.stocker)),
        )
        self.assertEqual(res.status_code, 200, res.data)
        data = res.data
        assert data is not None
        self.assertIn("count", data)
        self.assertIn("results", data)
        self.assertEqual(data["count"], 3)
        results = data["results"]
        # Newest first: c3, c2, c1
        self.assertEqual([r["id"] for r in results], [c3.pk, c2.pk, c1.pk])

        # c2 (increase: 100 -> 125 = +25.00 / +25.00%)
        r2 = results[1]
        self.assertEqual(r2["variant_uom"], self.pack_vuom.pk)
        self.assertEqual(r2["product_id"], self.product.pk)
        self.assertEqual(r2["product_name"], self.product.base_name)
        self.assertEqual(r2["variant_name"], self.variant.variant_name)
        self.assertEqual(r2["unit_code"], "BOX")
        self.assertEqual(r2["old_price"], "100.00")
        self.assertEqual(r2["new_price"], "125.00")
        self.assertEqual(r2["change_amount"], "25.00")
        self.assertEqual(r2["change_percent"], "25.00")
        self.assertEqual(r2["changed_by_name"], self.manager.full_name)
        self.assertEqual(r2["source"], "IMPORT")
        self.assertIsNotNone(r2["changed_at"])

        # c3 (decrease: 20 -> 15 = -5.00 / -25.00%, null actor)
        r3 = results[0]
        self.assertEqual(r3["change_amount"], "-5.00")
        self.assertEqual(r3["change_percent"], "-25.00")
        self.assertIsNone(r3["changed_by_name"])

        # c1 (initial price: old_price is None -> amount & percent None)
        r1 = results[2]
        self.assertIsNone(r1["old_price"])
        self.assertEqual(r1["new_price"], "10.00")
        self.assertIsNone(r1["change_amount"])
        self.assertIsNone(r1["change_percent"])

    def test_filters_by_product_since_and_query(self):
        old_dt = timezone.now() - timedelta(days=10)
        recent_dt = timezone.now() - timedelta(days=1)

        old_row = SellingUnitPriceChange.objects.create(
            variant_uom=self.vuom,
            old_price=Decimal("10.00"),
            new_price=Decimal("11.00"),
            actor=self.stocker,
            source=SellingUnitPriceChange.Source.CATALOGUE,
        )
        # changed_at has auto_now_add=True; update via raw SQL/queryset? Wait:
        # SellingUnitPriceChangeQuerySet blocks update(), so use super/bulk/Model.objects.filter?
        # Wait: let's check if SellingUnitPriceChangeQuerySet blocks .update(). Yes!
        # Let's use django.db.connection cursor to set changed_at in this test fixture.
        from django.db import connection

        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE inventory_selling_unit_price_change SET changed_at = %s WHERE id = %s",
                [old_dt, old_row.pk],
            )

        recent_row = SellingUnitPriceChange.objects.create(
            variant_uom=self.pack_vuom,
            old_price=Decimal("95.00"),
            new_price=Decimal("100.00"),
            actor=self.stocker,
            source=SellingUnitPriceChange.Source.CATALOGUE,
        )
        with connection.cursor() as cursor:
            cursor.execute(
                "UPDATE inventory_selling_unit_price_change SET changed_at = %s WHERE id = %s",
                [recent_dt, recent_row.pk],
            )

        other_row = SellingUnitPriceChange.objects.create(
            variant_uom=self.other_vuom,
            old_price=Decimal("15.00"),
            new_price=Decimal("18.00"),
            actor=self.manager,
            source=SellingUnitPriceChange.Source.CATALOGUE,
        )

        auth = self._auth(self.stocker)

        # ?product=
        by_product = cast(
            Response,
            self.client.get(f"{PRICE_CHANGES_URL}?product={self.other_product.pk}", **auth),
        )
        self.assertEqual(by_product.status_code, 200)
        self.assertEqual([r["id"] for r in by_product.data["results"]], [other_row.pk])

        # ?since=YYYY-MM-DD
        since_date = (timezone.localdate() - timedelta(days=3)).isoformat()
        by_since = cast(
            Response,
            self.client.get(f"{PRICE_CHANGES_URL}?since={since_date}", **auth),
        )
        self.assertEqual(by_since.status_code, 200)
        self.assertEqual(
            [r["id"] for r in by_since.data["results"]],
            [other_row.pk, recent_row.pk],
        )

        # ?q= by product name (case-insensitive)
        by_name = cast(
            Response,
            self.client.get(f"{PRICE_CHANGES_URL}?q=latex", **auth),
        )
        self.assertEqual(by_name.status_code, 200)
        self.assertEqual([r["id"] for r in by_name.data["results"]], [other_row.pk])

        # ?q= by barcode
        by_barcode = cast(
            Response,
            self.client.get(f"{PRICE_CHANGES_URL}?q=4800016123450", **auth),
        )
        self.assertEqual(by_barcode.status_code, 200)
        self.assertEqual([r["id"] for r in by_barcode.data["results"]], [recent_row.pk])

    def test_invalid_filter_values_return_400(self):
        auth = self._auth(self.stocker)
        bad_prod = cast(
            Response, self.client.get(f"{PRICE_CHANGES_URL}?product=abc", **auth)
        )
        self.assertEqual(bad_prod.status_code, 400)
        bad_date = cast(
            Response, self.client.get(f"{PRICE_CHANGES_URL}?since=not-a-date", **auth)
        )
        self.assertEqual(bad_date.status_code, 400)
