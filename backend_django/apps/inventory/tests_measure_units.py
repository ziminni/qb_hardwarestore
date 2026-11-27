"""Sell by measure: a kilo/metre selling unit on a whole-counted item."""

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
    SellingUnitPriceChange,
    StockAdjustment,
    StorageLocation,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import record_opening_stock

User = get_user_model()


class MeasureUnitTests(APITestCase):
    def setUp(self):
        self.stocker = User.objects.create_user(
            username="stocker_measure",
            email="stocker_measure@example.com",
            password="x",
            full_name="Stock Er",
        )
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.client.force_authenticate(user=self.stocker)
        self.loc = StorageLocation.objects.get_or_create(name="Store")[0]
        self.bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        self.kg, _ = UnitOfMeasure.objects.get_or_create(
            code="KG", defaults={"name": "Kilogram", "is_whole": False}
        )
        self.metre, _ = UnitOfMeasure.objects.get_or_create(
            code="M", defaults={"name": "Metre", "is_whole": False}
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
            conversion_factor=Decimal("1"),
            default_selling_price=Decimal("260.00"),
        )

    def url(self, variant=None):
        return f"/api/v1/variants/{(variant or self.variant).pk}/add-measure-unit/"

    def body(self, **extra):
        data = {"uom_id": self.kg.pk, "measure_per_base": "40", "default_selling_price": "7.50"}
        data.update(extra)
        return data

    def test_adds_kg_to_bag_with_sales_history(self):
        record_opening_stock(
            variant=self.variant, qty=Decimal("10"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        StockAdjustment.objects.create(
            variant=self.variant, location=self.loc, user=self.stocker,
            adjustment_type="CORRECTION", qty_adjusted=Decimal("1"),
        )
        response = self.client.post(self.url(), self.body(), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        kilo = VariantUOM.objects.get(variant=self.variant, uom=self.kg)
        self.assertEqual(kilo.measure_per_base, Decimal("40"))
        self.assertEqual(kilo.conversion_factor, Decimal("0.025"))
        self.assertEqual(kilo.default_selling_price, Decimal("7.50"))
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.base_uom, self.bag)
        self.assertEqual(
            InventoryBatch.objects.get(variant=self.variant).current_qty, Decimal("10")
        )
        units = {u["uom_code"]: u for u in response.data["selling_uoms"]}
        self.assertEqual(units["KG"]["measure_per_base"], "40.00")
        self.assertIsNone(units["BAG"]["measure_per_base"])

    def test_a_150_metre_roll_keeps_its_exact_length(self):
        roll, _ = UnitOfMeasure.objects.get_or_create(
            code="ROLL", defaults={"name": "Roll", "is_whole": True}
        )
        wire = ProductVariant.objects.create(
            product=self.variant.product, variant_name="THHN 2.0", base_uom=roll
        )
        response = self.client.post(
            self.url(wire),
            {"uom_id": self.metre.pk, "measure_per_base": "150", "default_selling_price": "12"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        metre = VariantUOM.objects.get(variant=wire, uom=self.metre)
        self.assertEqual(metre.measure_per_base, Decimal("150"))
        self.assertEqual(metre.conversion_factor, Decimal("0.006667"))

    def assertRefused(self, response, words):
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SELLING_UNIT")
        self.assertIn(words, response.data["detail"])
        self.assertFalse(
            VariantUOM.objects.filter(measure_per_base__isnull=False).exists()
        )

    def test_refuses_fractional_base(self):
        loose = ProductVariant.objects.create(
            product=self.variant.product, variant_name="Loose", base_uom=self.kg
        )
        self.assertRefused(
            self.client.post(self.url(loose), self.body(), format="json"),
            "already sold in any amount",
        )

    def test_refuses_whole_target_unit(self):
        piece, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece", "is_whole": True}
        )
        self.assertRefused(
            self.client.post(self.url(), self.body(uom_id=piece.pk), format="json"),
            "counted in whole numbers",
        )

    def test_refuses_per_base_not_above_one(self):
        self.assertRefused(
            self.client.post(self.url(), self.body(measure_per_base="1"), format="json"),
            "more than 1",
        )

    def test_refuses_per_base_with_three_decimals(self):
        self.assertRefused(
            self.client.post(
                self.url(), self.body(measure_per_base="40.125"), format="json"
            ),
            "two decimal places",
        )

    def test_refuses_second_measured_unit(self):
        first = self.client.post(self.url(), self.body(), format="json")
        self.assertEqual(first.status_code, 201, first.data)
        again = self.client.post(
            self.url(), self.body(uom_id=self.metre.pk), format="json"
        )
        self.assertEqual(again.status_code, 400, again.data)
        self.assertIn("already", again.data["detail"])
        self.assertEqual(
            VariantUOM.objects.filter(
                variant=self.variant, measure_per_base__isnull=False
            ).count(),
            1,
        )

    def test_refuses_negative_price(self):
        self.assertRefused(
            self.client.post(
                self.url(), self.body(default_selling_price="-1"), format="json"
            ),
            "negative",
        )

    def test_cashier_forbidden(self):
        cashier = User.objects.create_user(
            username="cash_measure", email="cash_measure@example.com", password="x"
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.client.force_authenticate(user=cashier)
        response = self.client.post(self.url(), self.body(), format="json")
        self.assertEqual(response.status_code, 403)

    def test_price_change_recorded(self):
        self.client.post(self.url(), self.body(), format="json")
        kilo = VariantUOM.objects.get(variant=self.variant, uom=self.kg)
        change = SellingUnitPriceChange.objects.get(variant_uom=kilo)
        self.assertEqual(change.new_price, Decimal("7.50"))

    def _kilo_with_stock(self):
        record_opening_stock(
            variant=self.variant, qty=Decimal("10"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        self.client.post(self.url(), self.body(), format="json")
        return VariantUOM.objects.get(variant=self.variant, uom=self.kg)

    def test_spill_half_kilo(self):
        kilo = self._kilo_with_stock()
        response = self.client.post(
            "/api/v1/adjustments/",
            {
                "variant": self.variant.pk,
                "variant_uom": kilo.pk,
                "adjustment_type": "DAMAGE",
                "qty_adjusted": "-0.5",
                "remarks": "Spilled while scooping",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        row = StockAdjustment.objects.get(pk=response.data["id"])
        self.assertEqual(row.qty_adjusted, Decimal("-0.0125"))
        self.assertEqual(
            InventoryBatch.objects.get(variant=self.variant).current_qty,
            Decimal("9.9875"),
        )

    def test_adjustment_in_another_variants_unit_is_refused(self):
        self._kilo_with_stock()
        other = ProductVariant.objects.create(
            product=self.variant.product, variant_name="25kg", base_uom=self.bag
        )
        other_unit = VariantUOM.objects.create(
            variant=other, uom=self.kg, conversion_factor=Decimal("0.04"),
            measure_per_base=Decimal("25"), default_selling_price=Decimal("8"),
        )
        response = self.client.post(
            "/api/v1/adjustments/",
            {
                "variant": self.variant.pk,
                "variant_uom": other_unit.pk,
                "adjustment_type": "DAMAGE",
                "qty_adjusted": "-1",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            InventoryBatch.objects.get(variant=self.variant).current_qty, Decimal("10")
        )

    def test_smaller_unit_refusal_mentions_measure(self):
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
            {"uom": self.kg.pk, "units_per_base": "30", "default_selling_price": "7"},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("by weight or length", response.data["detail"])
