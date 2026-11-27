"""Sell by measure: base-quantity conversion and 6-decimal stock quantities."""

from decimal import Decimal
from types import SimpleNamespace

from django.contrib.auth import get_user_model
from django.test import SimpleTestCase, TestCase

from apps.inventory.models import (
    Brand,
    Category,
    InventoryBatch,
    Product,
    ProductVariant,
    StorageLocation,
    UnitOfMeasure,
)
from apps.inventory.services import record_opening_stock
from common.quantities import (
    QTY,
    dust_tolerance,
    format_qty,
    to_base_qty,
    typed_qty_error,
)


def unit(factor="1", per_base=None):
    return SimpleNamespace(
        conversion_factor=Decimal(factor),
        measure_per_base=None if per_base is None else Decimal(per_base),
    )


class ToBaseQtyTests(SimpleTestCase):
    def test_quantum_is_six_decimals(self):
        self.assertEqual(QTY, Decimal("0.000001"))

    def test_to_base_qty_plain_unit_matches_old_math(self):
        self.assertEqual(to_base_qty(unit("12"), Decimal("2")), Decimal("24"))
        self.assertEqual(to_base_qty(unit("0.25"), Decimal("3")), Decimal("0.75"))

    def test_to_base_qty_measured_divides(self):
        self.assertEqual(
            to_base_qty(unit("0.006667", "150"), Decimal("1")), Decimal("0.006667")
        )
        self.assertEqual(to_base_qty(unit("0.025", "40"), Decimal("3")), Decimal("0.075"))
        # 1.5 m of a 150 m roll is exactly 0.01 roll: dividing, not the rounded factor.
        self.assertEqual(
            to_base_qty(unit("0.006667", "150"), Decimal("1.5")), Decimal("0.01")
        )

    def test_dust_tolerance(self):
        # One sellable step (0.01 kg of a 40 kg bag) plus half a millionth per earlier
        # measured sale still on the stock, the most their rounding can have drifted.
        self.assertEqual(dust_tolerance(unit("0.025", "40")), Decimal("0.00025"))
        self.assertEqual(
            dust_tolerance(unit("0.006667", "150"), prior_deductions=149),
            Decimal("0.000067") + Decimal("0.0000745"),
        )
        self.assertEqual(dust_tolerance(unit("12")), Decimal("0"))

    def test_format_qty_keeps_two_decimals_and_no_noise(self):
        self.assertEqual(format_qty(Decimal("2")), "2.00")
        self.assertEqual(format_qty(Decimal("9.750000")), "9.75")
        self.assertEqual(format_qty(Decimal("0.075000")), "0.075")
        self.assertEqual(format_qty(Decimal("0.006667")), "0.006667")
        self.assertEqual(format_qty(Decimal("-1.500000")), "-1.50")

    def test_typed_qty_error(self):
        self.assertIsNotNone(typed_qty_error(Decimal("0.125")))
        self.assertIsNone(typed_qty_error(Decimal("7.5")))
        self.assertIsNone(typed_qty_error(Decimal("7.500000")))


class QtyFieldTests(SimpleTestCase):
    def test_qty_field_prints_without_noise(self):
        from common.serializer_fields import QtyDecimalField

        field = QtyDecimalField(max_digits=18, decimal_places=6)
        self.assertEqual(field.to_representation(Decimal("10.000000")), "10.00")
        self.assertEqual(field.to_representation(Decimal("0.075000")), "0.075")

    def test_model_serializers_use_it_and_money_is_unchanged(self):
        from rest_framework import serializers

        from apps.inventory.models import VariantUOM

        class UnitOut(serializers.ModelSerializer):
            class Meta:
                model = VariantUOM
                fields = ("conversion_factor", "default_selling_price")

        out = UnitOut(
            VariantUOM(
                conversion_factor=Decimal("1.000000"),
                default_selling_price=Decimal("260"),
            )
        ).data
        self.assertEqual(out["conversion_factor"], "1.00")
        self.assertEqual(out["default_selling_price"], "260.00")

    def test_variant_uom_str_has_no_noise(self):
        from apps.inventory.models import VariantUOM

        unit = SimpleNamespace(
            variant="Cement — 40kg",
            uom=SimpleNamespace(code="BAG"),
            conversion_factor=Decimal("1.000000"),
        )
        self.assertIn("(×1.00)", VariantUOM.__str__(unit))


class StoredPrecisionTests(TestCase):
    def test_existing_values_survive_and_six_decimals_store(self):
        bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        loc = StorageLocation.objects.get_or_create(name="Store")[0]
        product = Product.objects.create(
            category=Category.objects.create(name="Cement"),
            brand=Brand.objects.create(name="Rhino"),
            base_name="Portland Cement",
            stored_at=loc,
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=bag
        )
        user = get_user_model().objects.create_user(
            username="qty_stocker", email="qty_stocker@example.com", password="x"
        )
        record_opening_stock(
            variant=variant, qty=Decimal("10"), unit_cost=Decimal("215"), user=user
        )
        batch = InventoryBatch.objects.get(variant=variant)
        batch.current_qty = Decimal("9.75")
        batch.save(update_fields=["current_qty"])
        batch.refresh_from_db()
        self.assertEqual(batch.current_qty, Decimal("9.75"))
        batch.current_qty = Decimal("9.006667")
        batch.save(update_fields=["current_qty"])
        batch.refresh_from_db()
        self.assertEqual(batch.current_qty, Decimal("9.006667"))

    def test_quantities_read_back_without_trailing_noise(self):
        """Messages built from stored quantities keep reading "10.00", not "10.000000"."""
        bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        product = Product.objects.create(
            category=Category.objects.create(name="Sand"),
            brand=Brand.objects.create(name="Local"),
            base_name="Sand",
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="Bag", base_uom=bag,
            min_stock_threshold=Decimal("10"),
        )
        variant.refresh_from_db()
        self.assertEqual(str(variant.min_stock_threshold), "10.00")
        variant.min_stock_threshold = Decimal("0.075")
        variant.save(update_fields=["min_stock_threshold"])
        variant.refresh_from_db()
        self.assertEqual(str(variant.min_stock_threshold), "0.075")
