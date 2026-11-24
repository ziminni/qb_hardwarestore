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
    StorageLocation,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import record_opening_stock
from apps.pos.models import Customer, SalesItem, SalesTransaction

User = get_user_model()


class AddSmallerUnitTests(APITestCase):
    def setUp(self):
        self.stocker = User.objects.create_user(
            username="stocker_uom",
            email="stocker_uom@example.com",
            password="pass1234",
        )
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.client.force_authenticate(user=self.stocker)
        self.cat = Category.objects.create(name="Paints")
        self.brand = Brand.objects.create(name="Boysen")
        self.loc = StorageLocation.objects.create(name="Main Shelf")
        self.box, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box", "is_whole": True}
        )
        self.can, _ = UnitOfMeasure.objects.get_or_create(
            code="CAN", defaults={"name": "Can", "is_whole": True}
        )
        self.product = Product.objects.create(
            category=self.cat,
            brand=self.brand,
            base_name="Spray Paint",
            stored_at=self.loc,
        )
        self.variant = ProductVariant.objects.create(
            product=self.product,
            variant_name="Gloss Black",
            base_uom=self.box,
            min_stock_threshold=Decimal("2.00"),
        )
        self.box_vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.box,
            conversion_factor=Decimal("1.00"),
            default_selling_price=Decimal("1500.00"),
        )

    def test_rebases_fresh_variant_with_opening_stock_cleanly(self):
        record_opening_stock(
            variant=self.variant,
            qty=Decimal("10.00"),
            unit_cost=Decimal("1200.00"),
            user=self.stocker,
        )

        resp = self.client.post(
            f"/api/v1/variants/{self.variant.pk}/add-smaller-unit/",
            {
                "uom": self.can.pk,
                "units_per_base": "24",
                "default_selling_price": "70.00",
            },
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.data)

        self.variant.refresh_from_db()
        self.box_vuom.refresh_from_db()
        can_vuom = VariantUOM.objects.get(variant=self.variant, uom=self.can)
        batch = InventoryBatch.objects.get(variant=self.variant)

        self.assertEqual(self.variant.base_uom_id, self.can.pk)
        self.assertEqual(self.variant.min_stock_threshold, Decimal("48.00"))
        self.assertEqual(can_vuom.conversion_factor, Decimal("1.00"))
        self.assertEqual(can_vuom.default_selling_price, Decimal("70.00"))
        self.assertEqual(self.box_vuom.conversion_factor, Decimal("24.00"))
        self.assertEqual(self.box_vuom.default_selling_price, Decimal("1500.00"))
        self.assertEqual(batch.initial_qty, Decimal("240.00"))
        self.assertEqual(batch.current_qty, Decimal("240.00"))
        self.assertEqual(batch.unit_cost_landed, Decimal("50.00"))

    def test_with_sales_history_allows_exact_divisor_and_refuses_non_exact(self):
        customer = Customer.objects.create(name="Walk-in")
        tx = SalesTransaction.objects.create(
            customer=customer,
            cashier=self.stocker,
            grand_total=Decimal("1500.00"),
        )
        SalesItem.objects.create(
            transaction=tx,
            variant_uom=self.box_vuom,
            qty=Decimal("1.00"),
            unit_price=Decimal("1500.00"),
            subtotal=Decimal("1500.00"),
        )

        # Non-exact (1/24) is refused clearly once sold
        bad = self.client.post(
            f"/api/v1/variants/{self.variant.pk}/add-smaller-unit/",
            {
                "uom": self.can.pk,
                "units_per_base": "24",
                "default_selling_price": "70.00",
            },
            format="json",
        )
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(bad.data.get("code"), "INVALID_SELLING_UNIT")

        # Exact 2-decimal divisor (1/20 = 0.05) succeeds without touching base
        good = self.client.post(
            f"/api/v1/variants/{self.variant.pk}/add-smaller-unit/",
            {
                "uom": self.can.pk,
                "units_per_base": "20",
                "default_selling_price": "80.00",
            },
            format="json",
        )
        self.assertEqual(good.status_code, 201, good.data)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.base_uom_id, self.box.pk)
        can_vuom = VariantUOM.objects.get(variant=self.variant, uom=self.can)
        self.assertEqual(can_vuom.conversion_factor, Decimal("0.05"))
