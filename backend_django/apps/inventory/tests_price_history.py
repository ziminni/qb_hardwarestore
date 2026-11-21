# pyright: reportAttributeAccessIssue=false
# Same reason as apps/inventory/tests.py: no django-stubs, so `Model.objects` and
# `request.user` are false positives on valid Django.
from decimal import Decimal
from types import SimpleNamespace
from typing import cast

from rest_framework.response import Response

from .models import SellingUnitPriceChange
from .tests_catalog_writes import VARIANT_UOMS_URL, CatalogWriteTestBase


class PriceHistoryTests(CatalogWriteTestBase):
    def test_edit_records_price_and_actor_once_and_history_is_role_fenced(self):
        unit_url = f"{VARIANT_UOMS_URL}{self.vuom.pk}/"
        auth = self._auth(self.stocker)["HTTP_AUTHORIZATION"]
        for _ in range(2):
            response = cast(
                Response,
                self.client.patch(
                    unit_url,
                    {"default_selling_price": "12.50"},
                    format="json",
                    HTTP_AUTHORIZATION=auth,
                ),
            )
            self.assertEqual(response.status_code, 200, response.data)
        event = SellingUnitPriceChange.objects.get(variant_uom=self.vuom)
        self.assertEqual(event.old_price, Decimal("10.00"))
        self.assertEqual(event.new_price, Decimal("12.50"))
        self.assertEqual(event.actor_id, self.stocker.pk)
        response = cast(
            Response,
            self.client.get(f"{unit_url}price-history/", HTTP_AUTHORIZATION=auth),
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertIsNotNone(response.data)
        assert response.data is not None
        self.assertEqual(response.data["results"][0]["new_price"], "12.50")
        denied = cast(
            Response,
            self.client.get(
                f"{unit_url}price-history/",
                HTTP_AUTHORIZATION=self._auth(self.cashier)["HTTP_AUTHORIZATION"],
            ),
        )
        self.assertEqual(denied.status_code, 403)

    def test_admin_save_records_real_changes_only(self):
        from django.contrib.admin.sites import site
        from django.test import RequestFactory

        model_admin = site._registry[type(self.vuom)]
        request = RequestFactory().post("/")
        request.user = self.stocker

        form = SimpleNamespace(changed_data=["default_selling_price"])

        self.vuom.default_selling_price = Decimal("11.00")
        model_admin.save_model(request, self.vuom, form, True)
        form.changed_data = []
        self.vuom.default_selling_price = Decimal("99.00")  # stale form value
        model_admin.save_model(request, self.vuom, form, True)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal("11.00"))
        rows = list(SellingUnitPriceChange.objects.filter(variant_uom=self.vuom))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].source, SellingUnitPriceChange.Source.ADMIN)
        self.assertEqual(
            (rows[0].old_price, rows[0].new_price),
            (Decimal("10.00"), Decimal("11.00")),
        )

    def test_creating_a_selling_unit_records_its_first_price(self):
        from .models import UnitOfMeasure, VariantUOM

        unit = UnitOfMeasure.objects.create(code="SK", name="Sack", is_whole=True)
        response = cast(
            Response,
            self.client.post(
                VARIANT_UOMS_URL,
                {
                    "variant": self.vuom.variant_id,
                    "uom": unit.pk,
                    "conversion_factor": "10",
                    "default_selling_price": "95.00",
                },
                format="json",
                HTTP_AUTHORIZATION=self._auth(self.stocker)["HTTP_AUTHORIZATION"],
            ),
        )
        self.assertEqual(response.status_code, 201, response.data)
        created = VariantUOM.objects.exclude(pk=self.vuom.pk).get(uom=unit)
        event = SellingUnitPriceChange.objects.get(variant_uom=created)
        self.assertIsNone(event.old_price)
        self.assertEqual(event.new_price, Decimal("95.00"))
