"""Sell in parts (planning/sell-in-parts): ½ and ¼ of a whole-counted unit."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from rest_framework.test import APITestCase

from apps.inventory.models import (
    Brand,
    Category,
    InventoryBatch,
    Product,
    ProductVariant,
    StockAdjustment,
    StorageLocation,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import record_opening_stock
from apps.pos.models import Customer, SalesItemDeduction, Shift
from apps.pos.services import process_sale

User = get_user_model()


class PartUnitTests(APITestCase):
    def setUp(self):
        self.stocker = User.objects.create_user(
            username="stocker_parts", email="stocker_parts@example.com", password="pass1234", full_name="Stock Er"
        )
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.cashier = User.objects.create_user(
            username="cash_parts", email="cash_parts@example.com", password="x")
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.client.force_authenticate(user=self.stocker)
        self.loc = StorageLocation.objects.get_or_create(name="Store")[0]
        self.bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        self.kg, _ = UnitOfMeasure.objects.get_or_create(
            code="KG", defaults={"name": "Kilogram", "is_whole": False}
        )
        product = Product.objects.create(
            category=Category.objects.create(name="Cement"),
            brand=Brand.objects.create(name="Rhino"),
            base_name="Portland Cement",
            stored_at=self.loc,
        )
        self.variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=self.bag
        )
        self.bag_unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.bag,
            conversion_factor=Decimal("1.00"),
            default_selling_price=Decimal("260.00"),
        )

    def url(self, variant=None):
        return f"/api/v1/variants/{(variant or self.variant).pk}/add-part-unit/"

    def test_adds_a_quarter_without_rebasing(self):
        record_opening_stock(
            variant=self.variant, qty=Decimal("10"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        response = self.client.post(
            self.url(), {"parts": 4, "default_selling_price": "70.00"}, format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        quarter = VariantUOM.objects.get(variant=self.variant, uom__code="QTR")
        self.assertEqual(quarter.conversion_factor, Decimal("0.25"))
        self.assertEqual(quarter.default_selling_price, Decimal("70.00"))
        self.assertTrue(quarter.uom.is_whole)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.base_uom, self.bag)
        self.bag_unit.refresh_from_db()
        self.assertEqual(self.bag_unit.conversion_factor, Decimal("1.00"))
        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.current_qty, Decimal("10.00"))

    def test_half_uses_the_shared_half_unit(self):
        self.client.post(
            self.url(), {"parts": 2, "default_selling_price": "135"}, format="json"
        )
        half = VariantUOM.objects.get(variant=self.variant, uom__code="HALF")
        self.assertEqual(half.conversion_factor, Decimal("0.50"))
        self.assertEqual(UnitOfMeasure.objects.filter(code="HALF").count(), 1)

    def test_selling_three_quarters_takes_the_fraction_at_batch_cost(self):
        record_opening_stock(
            variant=self.variant, qty=Decimal("10"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        self.client.post(
            self.url(), {"parts": 4, "default_selling_price": "70"}, format="json"
        )
        quarter = VariantUOM.objects.get(variant=self.variant, uom__code="QTR")
        Shift.objects.create(cashier=self.cashier, opening_float=Decimal("0"))
        walk_in = Customer.objects.create(
            name="Walk-in Customer", customer_type=Customer.Type.WALK_IN
        )
        txn = process_sale(
            cashier=self.cashier,
            customer_id=walk_in.pk,
            items_data=[{"variant_id": quarter.pk, "qty": "3"}],
            payments_data=[{"method": "CASH", "amount_tendered": "210.00"}],
        )
        self.assertEqual(txn.grand_total, Decimal("210.00"))
        deduction = SalesItemDeduction.objects.get(sales_item__transaction=txn)
        self.assertEqual(deduction.qty, Decimal("0.75"))
        self.assertEqual(deduction.unit_cost, Decimal("215.00"))
        batch = InventoryBatch.objects.get(variant=self.variant)
        self.assertEqual(batch.current_qty, Decimal("9.25"))

    def test_refuses_parts_of_a_measured_base_unit(self):
        product = self.variant.product
        loose = ProductVariant.objects.create(
            product=product, variant_name="Loose", base_uom=self.kg
        )
        response = self.client.post(
            self.url(loose), {"parts": 4, "default_selling_price": "2"}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SELLING_UNIT")
        self.assertIn("any amount", response.data["detail"])

    def test_refuses_an_unknown_part_count_and_a_duplicate(self):
        bad = self.client.post(
            self.url(), {"parts": 3, "default_selling_price": "90"}, format="json"
        )
        self.assertEqual(bad.status_code, 400, bad.data)
        self.client.post(
            self.url(), {"parts": 4, "default_selling_price": "70"}, format="json"
        )
        again = self.client.post(
            self.url(), {"parts": 4, "default_selling_price": "75"}, format="json"
        )
        self.assertEqual(again.status_code, 400, again.data)
        self.assertIn("already", again.data["detail"])
        self.assertEqual(
            VariantUOM.objects.filter(variant=self.variant, uom__code="QTR").count(), 1
        )

    def test_refuses_a_negative_price(self):
        response = self.client.post(
            self.url(), {"parts": 2, "default_selling_price": "-1"}, format="json"
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(VariantUOM.objects.filter(uom__code="HALF").exists())

    def test_cashier_cannot_add_parts(self):
        self.client.force_authenticate(user=self.cashier)
        response = self.client.post(
            self.url(), {"parts": 4, "default_selling_price": "70"}, format="json"
        )
        self.assertEqual(response.status_code, 403)

    def test_smaller_unit_refusal_points_to_parts(self):
        record_opening_stock(
            variant=self.variant, qty=Decimal("2"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        StockAdjustment.objects.create(
            variant=self.variant, location=self.loc, user=self.stocker,
            adjustment_type="CORRECTION", qty_adjusted=Decimal("1"),
        )
        response = self.client.post(
            f"/api/v1/variants/{self.variant.pk}/add-smaller-unit/",
            {"uom": self.kg.pk, "units_per_base": "40", "default_selling_price": "7"},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("in parts", response.data["detail"])


class AdjustmentUserNameTests(APITestCase):
    def test_adjustment_rows_carry_the_user_name(self):
        user = User.objects.create_user(
            username="stk", email="stk@example.com", password="x", full_name="Maria Stocker"
        )
        user.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.client.force_authenticate(user=user)
        loc = StorageLocation.objects.get_or_create(name="Store")[0]
        bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        product = Product.objects.create(
            category=Category.objects.create(name="C"),
            brand=Brand.objects.create(name="B"),
            base_name="Cement",
            stored_at=loc,
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=bag
        )
        StockAdjustment.objects.create(
            variant=variant, location=loc, user=user,
            adjustment_type="DAMAGE", qty_adjusted=Decimal("-1"),
        )
        response = self.client.get("/api/v1/adjustments/")
        rows = response.data.get("results", response.data)
        self.assertEqual(rows[0]["user_name"], "Maria Stocker")
