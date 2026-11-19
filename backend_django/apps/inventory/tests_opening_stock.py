# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Owner 2026-11-18 (teammate Add product form): SKU and opening stock.

Opening stock is the first stock a NEW product starts with. It is a bill-free
delivery from the internal "Opening stock" supplier onto the product's home shelf;
a Bodega home waits for the checker. Once a variant has stock history it is refused,
so it is never a way round purchasing.
"""

from decimal import Decimal

from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from .models import (
    InventoryBatch,
    StorageLocation,
    SupplierBill,
    UnitOfMeasure,
    VariantUOM,
)
from .tests import InventoryTestBase


class OpeningStockTests(InventoryTestBase):
    def setUp(self):
        super().setUp()
        self.user.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.api = APIClient()
        self.api.force_authenticate(self.user)
        VariantUOM.objects.create(
            variant=self.variant, uom=self.uom,
            conversion_factor=Decimal(1), default_selling_price=Decimal(260),
        )

    def _open(self, qty="40", cost="215.00", variant=None):
        variant = variant or self.variant
        return self.api.post(
            f"/api/v1/variants/{variant.pk}/opening-stock/",
            {"qty": qty, "unit_cost": cost},
            format="json",
        )

    def _on_hand(self):
        return sum(
            b.current_qty for b in InventoryBatch.objects.filter(variant=self.variant)
        )

    def test_opening_stock_is_stocked_at_home_at_its_cost_with_no_bill(self):
        response = self._open()
        self.assertEqual(response.status_code, 201, response.data)
        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(
            (batch.current_qty, batch.unit_cost_landed, batch.location_id),
            (Decimal(40), Decimal("215.00"), self.product.stored_at_id),
        )
        self.assertFalse(SupplierBill.objects.exists())
        self.assertEqual(batch.receipt.po.supplier.company_name, "Opening stock")

    def test_a_second_opening_stock_is_refused(self):
        self._open()
        response = self._open()
        self.assertEqual(response.data["code"], "OPENING_STOCK_REFUSED")
        self.assertEqual(self._on_hand(), Decimal(40))

    def test_a_product_with_deliveries_has_no_opening_stock(self):
        from .services import process_goods_receipt

        _po, _item, receipt = self._receive("5")
        process_goods_receipt(receipt=receipt, user=self.user)
        self.assertEqual(self._open().data["code"], "OPENING_STOCK_REFUSED")

    def test_zero_or_negative_is_refused(self):
        self.assertEqual(self._open(qty="0").data["code"], "OPENING_STOCK_REFUSED")
        self.assertEqual(self._open(cost="-1").data["code"], "OPENING_STOCK_REFUSED")
        self.assertFalse(InventoryBatch.objects.exists())

    def test_a_fraction_of_a_whole_unit_is_refused(self):
        UnitOfMeasure.objects.filter(pk=self.uom.pk).update(is_whole=True)
        response = self._open(qty="2.5")
        self.assertEqual(response.status_code, 400)
        self.assertFalse(InventoryBatch.objects.exists())

    def test_a_bodega_product_waits_for_the_checker(self):
        from apps.bodega.models import BodegaDelivery

        bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        bodega.is_bodega = True
        bodega.save(update_fields=["is_bodega"])
        self.product.stored_at = bodega
        self.product.save(update_fields=["stored_at"])
        self.assertEqual(self._open().status_code, 201)
        self.assertFalse(InventoryBatch.objects.exists())
        self.assertEqual(
            BodegaDelivery.objects.get().lines.get().delivered_qty, Decimal(40)
        )

    def test_a_cashier_cannot_add_opening_stock(self):
        cashier = self.user.__class__.objects.create_user(
            username="till", email="t@x.com", password="pass12345"
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.api.force_authenticate(cashier)
        self.assertEqual(self._open().status_code, 403)

    def test_the_variant_carries_an_sku(self):
        response = self.api.patch(
            f"/api/v1/variants/{self.variant.pk}/", {"sku": "CEM-40"}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["sku"], "CEM-40")
