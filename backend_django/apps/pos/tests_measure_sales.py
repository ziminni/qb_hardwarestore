"""Sell by measure: selling, returning and reserving kilos and metres."""

from datetime import timedelta
from decimal import ROUND_HALF_UP, Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db.models import F, Sum
from django.utils import timezone
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
from apps.inventory.services import add_measure_unit, record_opening_stock
from apps.inventory.transfers import record_stock_transfer
from apps.pos.models import (
    Customer,
    HeldCart,
    HeldCartItem,
    SalesItemDeduction,
    Shift,
)
from apps.pos.services import process_return, process_sale, void_transaction

User = get_user_model()


class MeasureSaleBase(APITestCase):
    def setUp(self):
        self.stocker = User.objects.create_user(
            username="measure_stk", email="measure_stk@example.com", password="x"
        )
        self.stocker.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.cashier = User.objects.create_user(
            username="measure_cash", email="measure_cash@example.com", password="x"
        )
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        Shift.objects.create(cashier=self.cashier, opening_float=Decimal("0"))
        self.walk_in = Customer.objects.create(
            name="Walk-in Customer", customer_type=Customer.Type.WALK_IN
        )
        self.store = StorageLocation.objects.get_or_create(name="Store")[0]
        self.bag = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )[0]
        self.roll = UnitOfMeasure.objects.get_or_create(
            code="ROLL", defaults={"name": "Roll", "is_whole": True}
        )[0]
        self.kg = UnitOfMeasure.objects.get_or_create(
            code="KG", defaults={"name": "Kilogram", "is_whole": False}
        )[0]
        self.metre = UnitOfMeasure.objects.get_or_create(
            code="M", defaults={"name": "Metre", "is_whole": False}
        )[0]
        product = Product.objects.create(
            category=Category.objects.create(name="Cement"),
            brand=Brand.objects.create(name="Rhino"),
            base_name="Portland Cement",
            stored_at=self.store,
        )
        self.cement = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=self.bag
        )
        self.bag_unit = VariantUOM.objects.create(
            variant=self.cement, uom=self.bag, conversion_factor=Decimal("1"),
            default_selling_price=Decimal("260"),
        )
        record_opening_stock(
            variant=self.cement, qty=Decimal("10"), unit_cost=Decimal("215"),
            user=self.stocker,
        )
        self.kilo = add_measure_unit(
            variant=self.cement, uom=self.kg, measure_per_base=Decimal("40"),
            default_selling_price=Decimal("7.50"), user=self.stocker,
        )

    def sell(self, unit, qty, cash="100000"):
        return process_sale(
            cashier=self.cashier,
            customer_id=self.walk_in.pk,
            items_data=[{"variant_id": unit.pk, "qty": str(qty)}],
            payments_data=[{"method": "CASH", "amount_tendered": cash}],
        )

    def on_hand(self, variant):
        return InventoryBatch.objects.filter(variant=variant).aggregate(
            total=Sum("current_qty")
        )["total"]

    def wire_roll(self, metres_per_roll="150", rolls="1", cost="1250"):
        product = Product.objects.create(
            category=Category.objects.create(name="Wire"),
            brand=Brand.objects.create(name="Phelps"),
            base_name="THHN Wire",
            stored_at=self.store,
        )
        wire = ProductVariant.objects.create(
            product=product, variant_name="2.0mm", base_uom=self.roll
        )
        VariantUOM.objects.create(
            variant=wire, uom=self.roll, conversion_factor=Decimal("1"),
            default_selling_price=Decimal("1480"),
        )
        record_opening_stock(
            variant=wire, qty=Decimal(rolls), unit_cost=Decimal(cost), user=self.stocker
        )
        metre = add_measure_unit(
            variant=wire, uom=self.metre, measure_per_base=Decimal(metres_per_roll),
            default_selling_price=Decimal("12"), user=self.stocker,
        )
        return wire, metre


class MeasureSaleTests(MeasureSaleBase):
    def test_sell_3kg_cost_is_three_fortieths(self):
        txn = self.sell(self.kilo, "3")
        self.assertEqual(txn.grand_total, Decimal("22.50"))
        deduction = SalesItemDeduction.objects.get(sales_item__transaction=txn)
        self.assertEqual(deduction.qty, Decimal("0.075"))
        self.assertEqual(deduction.unit_cost, Decimal("215.00"))
        self.assertEqual(
            (deduction.qty * deduction.unit_cost).quantize(
                Decimal("0.01"), rounding=ROUND_HALF_UP
            ),
            Decimal("16.13"),
        )
        self.assertEqual(self.on_hand(self.cement), Decimal("9.925"))

    def test_roll_sold_metre_by_metre_reaches_zero(self):
        wire, metre = self.wire_roll()
        for _ in range(150):
            self.sell(metre, "1")
        self.assertEqual(self.on_hand(wire), Decimal("0"))
        deductions = SalesItemDeduction.objects.filter(
            sales_item__variant_uom=metre
        )
        self.assertEqual(deductions.aggregate(t=Sum("qty"))["t"], Decimal("1"))
        cost = deductions.aggregate(t=Sum(F("qty") * F("unit_cost")))["t"]
        self.assertLessEqual(abs(cost - Decimal("1250")), Decimal("0.01"))

    def test_odd_lengths_leave_no_dust(self):
        wire, metre = self.wire_roll(metres_per_roll="75")
        for qty in ("0.35", "12.5", "7.15", "30", "25"):
            self.sell(metre, qty)
        # 75 - 75.00 sold: nothing left, not a few millionths of a roll.
        self.assertEqual(self.on_hand(wire), Decimal("0"))

    def test_30kg_bag(self):
        product = self.cement.product
        small = ProductVariant.objects.create(
            product=product, variant_name="30kg", base_uom=self.bag
        )
        VariantUOM.objects.create(
            variant=small, uom=self.bag, conversion_factor=Decimal("1"),
            default_selling_price=Decimal("200"),
        )
        record_opening_stock(
            variant=small, qty=Decimal("1"), unit_cost=Decimal("150"), user=self.stocker
        )
        kilo = add_measure_unit(
            variant=small, uom=self.kg, measure_per_base=Decimal("30"),
            default_selling_price=Decimal("6"), user=self.stocker,
        )
        for _ in range(30):
            self.sell(kilo, "1")
        self.assertEqual(self.on_hand(small), Decimal("0"))

    def test_more_than_on_hand_is_still_refused(self):
        from apps.inventory.exceptions import InsufficientStock

        wire, metre = self.wire_roll()
        with self.assertRaises(InsufficientStock):
            self.sell(metre, "150.5")

    def test_return_2_5kg_restores_exact(self):
        txn = self.sell(self.kilo, "7.5")
        self.assertEqual(self.on_hand(self.cement), Decimal("9.8125"))
        process_return(
            customer_id=self.walk_in.pk,
            cashier=self.cashier,
            items_data=[{"variant_id": self.kilo.pk, "qty": "2.5"}],
            original_transaction_id=txn.pk,
            reason="Customer bought too much",
        )
        self.assertEqual(self.on_hand(self.cement), Decimal("9.875"))

    def test_void_restores(self):
        txn = self.sell(self.kilo, "3")
        void_transaction(transaction_id=txn.pk, actor=self.cashier, reason="Wrong item")
        self.assertEqual(self.on_hand(self.cement), Decimal("10"))

    def test_held_cart_reserves_7_5kg(self):
        from apps.inventory.exceptions import InsufficientStock

        cart = HeldCart.objects.create(
            cashier=self.cashier, customer=self.walk_in,
            expires_at=timezone.now() + timedelta(hours=1),
        )
        HeldCartItem.objects.create(
            cart=cart, variant_uom=self.kilo, qty=Decimal("7.5"),
            unit_price=Decimal("7.50"),
        )
        # 10 bags = 400 kg; 7.5 kg is held, so 392.5 kg can still be sold, not 392.6.
        with self.assertRaises(InsufficientStock):
            self.sell(self.kilo, "392.6")
        self.sell(self.kilo, "392.5")
        self.assertEqual(self.on_hand(self.cement), Decimal("0.1875"))

    def test_three_decimal_qty_refused(self):
        self.client.force_authenticate(user=self.cashier)
        response = self.client.post(
            "/api/v1/transactions/",
            {
                "customer": self.walk_in.pk,
                "items": [{"variant_id": self.kilo.pk, "qty": "0.125"}],
                "payments": [{"method": "CASH", "amount_tendered": "10.00"}],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "QTY_TOO_PRECISE")
        self.assertEqual(self.on_hand(self.cement), Decimal("10"))

    def test_existing_bag_sale_unchanged(self):
        txn = self.sell(self.bag_unit, "2")
        deduction = SalesItemDeduction.objects.get(sales_item__transaction=txn)
        self.assertEqual(deduction.qty, Decimal("2"))
        self.assertEqual(str(deduction.qty), "2.00")
        self.assertEqual(self.on_hand(self.cement), Decimal("8"))

    def test_transfer_in_kg(self):
        bodega = StorageLocation.objects.get_or_create(name="Bodega")[0]
        record_stock_transfer(
            from_location=self.store, to_location=bodega,
            lines=[(self.kilo, Decimal("20"))], user=self.stocker,
        )
        moved = InventoryBatch.objects.filter(
            variant=self.cement, location=bodega
        ).aggregate(t=Sum("current_qty"))["t"]
        self.assertEqual(moved, Decimal("0.5"))
        self.assertEqual(self.on_hand(self.cement), Decimal("10"))

    def test_pick_up_caption_reads_in_kilos(self):
        self.client.force_authenticate(user=self.cashier)
        txn = self.sell(self.kilo, "7.5")
        response = self.client.get(f"/api/v1/transactions/{txn.pk}/")
        self.assertEqual(response.status_code, 200, response.content)
        pick_up = response.json()["items"][0]["pick_up"]
        self.assertEqual(pick_up[0]["qty"], "7.50")
        self.assertEqual(pick_up[0]["unit"], "KG")

    def test_sales_summary_profit_includes_kg_line(self):
        self.sell(self.kilo, "3")
        admin = User.objects.create_superuser(
            username="measure_admin", email="measure_admin@example.com", password="x"
        )
        self.client.force_authenticate(user=admin)
        response = self.client.get("/api/v1/reports/sales-summary/")
        self.assertEqual(response.status_code, 200, response.content)
        totals = response.json()["totals"]
        cogs = Decimal(str(totals["cogs"]))
        self.assertLessEqual(abs(cogs - Decimal("16.125")), Decimal("0.005"))
        self.assertEqual(
            Decimal(str(totals["gross_profit"])),
            Decimal(str(totals["merchandise_net_ex_vat"])) - cogs,
        )
