# pyright: reportAttributeAccessIssue=false
"""Phase 9 task B2 (decision 21 §2, plan Design 4) — "where was it taken from".

A sale that draws from two shelves must TELL the customer and the picker where each part
came from: `pick_up` on the sale line is the list of shelves the line actually left, in
the order the allocator took them (home first, then the other active locations, inactive
ones last).

The unit rule is the owner's delegated ruling: when one selling unit splits across
shelves - one BOX of 12 giving 7 from the Store and 5 from the Bodega - the parts are
reported in BASE units with the base code, because "0.58 BOX" is not something anybody
can count. When every part divides exactly, the selling unit is kept ("1 BOX at Store,
1 BOX at Bodega").

A line with no deduction rows is a sale rung before this phase (or an order not yet
fulfilled): it keeps today's caption, one entry naming the product's `stored_at`.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase

from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StorageLocation,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)

from .models import (
    Customer,
    Delivery,
    SalesItemDeduction,
    SalesOrder,
    SalesOrderItem,
    Shift,
)
from .serializers import DeliverySerializer, SalesItemSerializer
from .services import process_return, process_sale

User = get_user_model()

RETURN_REASON = "customer brought it back"


class PickUpTestBase(TestCase):
    """A product whose base unit is PC and whose selling units are PC and BOX of 12.

    Deliberately NOT the shared `POSTestBase`: that fixture stocks its batches through a
    goods receipt (which stamps the product's home shelf), and these tests need stock
    placed on chosen shelves with chosen delivery dates.
    """

    def setUp(self):
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.cashier = User.objects.create_user(
            username="pickup_cashier",
            email="p@x.com",
            password="pass12345",
            full_name="Pickup Cashier",
        )
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal(5000)
        )
        self.customer = Customer.objects.create(name="Juan Dela Cruz")
        category = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Rhino")
        self.pc, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece", "is_whole": True}
        )
        self.box, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box", "is_whole": True}
        )
        self.product = Product.objects.create(
            category=category,
            brand=brand,
            base_name="Portland Cement",
            stored_at=self.store,
        )
        self.variant = ProductVariant.objects.create(
            product=self.product, variant_name="40kg", base_uom=self.pc
        )
        self.pc_unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.pc,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        self.box_unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=self.box,
            conversion_factor=Decimal(12),
            default_selling_price=Decimal(120),
        )

    def _batch(self, location, qty, days_ago=0):
        supplier = Supplier.objects.create(
            company_name=f"Acme {location.name} {days_ago}"
        )
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.cashier,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=self.variant,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal(5),
            received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.cashier)
        GoodsReceipt.objects.filter(pk=receipt.pk).update(
            receive_date=date(2026, 1, 1) - timedelta(days=days_ago)
        )
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            location=location,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(5),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(5),
        )

    def _sell(self, vuom, qty):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": vuom.id, "qty": qty}],
            payments_data=[
                {
                    "method": "CASH",
                    "amount_tendered": Decimal(qty) * vuom.default_selling_price,
                }
            ],
        )

    def _pick_up(self, txn):
        pick_up = SalesItemSerializer(txn.items.get()).data.get("pick_up")
        if pick_up is None:
            # A caption that is MISSING and a caption that is wrong are different bugs.
            self.fail("the sale line carries no pick_up caption")
        return pick_up


class SalePickUpTests(PickUpTestBase):
    def test_a_sale_spanning_two_shelves_names_both_in_the_selling_unit(self):
        self._batch(self.store, "3", days_ago=1)
        self._batch(self.bodega, "2", days_ago=1)

        txn = self._sell(self.pc_unit, 5)

        self.assertEqual(
            self._pick_up(txn),
            [
                {
                    "location": self.store.pk,
                    "location_name": "Store",
                    "qty": "3.00",
                    "unit": "PC",
                },
                {
                    "location": self.bodega.pk,
                    "location_name": "Bodega",
                    "qty": "2.00",
                    "unit": "PC",
                },
            ],
        )
        # The rows behind the caption: one deduction per shelf touched, which is what
        # makes the location a FACT rather than a caption computed from the product.
        self.assertEqual(
            sorted(
                SalesItemDeduction.objects.filter(
                    sales_item__transaction=txn
                ).values_list("batch__location_id", "qty")
            ),
            [(self.store.pk, Decimal(3)), (self.bodega.pk, Decimal(2))],
        )

    def test_an_exact_split_keeps_the_selling_unit(self):
        self._batch(self.store, "12", days_ago=1)
        self._batch(self.bodega, "12", days_ago=1)

        txn = self._sell(self.box_unit, 2)

        self.assertEqual(
            [(row["qty"], row["unit"]) for row in self._pick_up(txn)],
            [("1.00", "BOX"), ("1.00", "BOX")],
        )

    def test_a_split_selling_unit_is_reported_in_base_units(self):
        # The owner's example: 1 BOX of 12 giving 7 from the Store and 5 from the Bodega
        # is NOT "0.58 BOX" - it is 7 pieces and 5 pieces, which a picker can count.
        self._batch(self.store, "7", days_ago=1)
        self._batch(self.bodega, "5", days_ago=1)

        txn = self._sell(self.box_unit, 1)

        pick_up = self._pick_up(txn)
        self.assertEqual(
            [(row["qty"], row["unit"]) for row in pick_up],
            [("7.00", "PC"), ("5.00", "PC")],
        )
        self.assertEqual([row["location_name"] for row in pick_up], ["Store", "Bodega"])

    def test_a_line_with_no_deductions_keeps_todays_caption(self):
        # A pre-Phase-9 sale never wrote deduction rows. The caption must still name a
        # shelf, so it falls back to the product's `stored_at` - the one entry the
        # receipt prints today.
        self._batch(self.store, "5", days_ago=1)
        txn = self._sell(self.pc_unit, 2)
        SalesItemDeduction.objects.filter(sales_item__transaction=txn).delete()

        self.assertEqual(
            self._pick_up(txn),
            [
                {
                    "location": self.store.pk,
                    "location_name": "Store",
                    "qty": "2.00",
                    "unit": "PC",
                }
            ],
        )

    def test_the_delivery_slip_carries_the_same_split(self):
        self._batch(self.store, "3", days_ago=1)
        self._batch(self.bodega, "2", days_ago=1)
        txn = self._sell(self.pc_unit, 5)
        delivery = Delivery.objects.create(
            sale=txn,
            created_by=self.cashier,
            address="12 Mabini St",
            contact_name="Juan",
            contact_phone="09170000000",
            scheduled_date=date(2026, 1, 2),
            fee=Decimal(0),
        )

        items = DeliverySerializer(delivery).data.get("items")
        # The slip's own `items` is a list of plain dicts; `self.fail` (not `assert`) so a
        # missing caption names itself in the failure instead of looking like a typo.
        if items is None:
            self.fail("the slip carries no items")
        pick_up = items[0]["pick_up"]
        if pick_up is None:
            self.fail("the slip line carries no pick_up caption")

        self.assertEqual(
            [(row["qty"], row["unit"]) for row in pick_up],
            [("3.00", "PC"), ("2.00", "PC")],
        )
        self.assertEqual(
            [row["location_name"] for row in pick_up],
            ["Store", "Bodega"],
        )

    def test_a_shelf_never_moves_when_its_stock_is_sold_and_returned(self):
        store_batch = self._batch(self.store, "3", days_ago=1)
        bodega_batch = self._batch(self.bodega, "2", days_ago=1)
        txn = self._sell(self.pc_unit, 5)

        process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.pc_unit.id, "qty": 2}],
            original_transaction_id=txn.id,
            payment_method="CASH",
            reason=RETURN_REASON,
        )

        store_batch.refresh_from_db()
        bodega_batch.refresh_from_db()
        self.assertEqual(store_batch.location_id, self.store.pk)
        self.assertEqual(bodega_batch.location_id, self.bodega.pk)
        self.assertEqual(
            sorted(
                InventoryBatch.objects.filter(variant=self.variant).values_list(
                    "location_id", flat=True
                )
            ),
            sorted([self.store.pk, self.bodega.pk]),
            "a sale or a return must never mint or move a batch",
        )

    def test_the_return_writes_a_negative_deduction_on_the_shelf_it_reopened(self):
        # A LINKED return restocks through NEGATIVE deduction rows on the batches the
        # original sale drew from (`pos/services.py` `qty=-add`). Two later readers
        # depend on that sign and must not be tested only in the abstract:
        #   * `pick_up_caption` takes `abs()`, so the RETURN line's own caption must read
        #     "2.00 at Store", never "-2.00";
        #   * the `qty__lt=0` cap that stops a second return from over-restocking sums
        #     these rows, so a POSITIVE row here would quietly break the cap.
        store_batch = self._batch(self.store, "3", days_ago=2)
        self._batch(self.bodega, "2", days_ago=1)
        txn = self._sell(self.pc_unit, 5)

        ret = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.pc_unit.id, "qty": 2}],
            original_transaction_id=txn.id,
            payment_method="CASH",
            reason=RETURN_REASON,
        )

        store_batch.refresh_from_db()
        self.assertEqual(store_batch.current_qty, Decimal(2), "the stock went back")
        self.assertEqual(
            list(
                SalesItemDeduction.objects.filter(
                    sales_item__transaction=ret
                ).values_list("batch__location_id", "qty")
            ),
            [(self.store.pk, Decimal(-2))],
            "the return restocks the reopened shelf through a NEGATIVE deduction row",
        )
        # The caption on the RETURN line itself: absolute, in the selling unit.
        self.assertEqual(
            self._pick_up(ret),
            [
                {
                    "location": self.store.pk,
                    "location_name": "Store",
                    "qty": "2.00",
                    "unit": "PC",
                }
            ],
        )

    def test_an_order_slip_names_the_home_shelf_until_it_is_fulfilled(self):
        # An ORDER line has no deduction rows - nothing has left a shelf yet - so the slip
        # keeps the caption it printed before this phase: ONE entry, the product's home
        # shelf, for the whole line. This is the `getattr(row, 'deductions', None)` branch
        # of the slip builder, and it must not blow up or report a shelf it never used.
        self._batch(self.store, "5", days_ago=1)
        order = SalesOrder.objects.create(
            order_no="SO-20260101-0001", customer=self.customer, created_by=self.cashier
        )
        SalesOrderItem.objects.create(
            order=order,
            variant_uom=self.pc_unit,
            qty=Decimal(2),
            unit_price=Decimal(10),
        )
        delivery = Delivery.objects.create(
            sales_order=order,
            created_by=self.cashier,
            address="12 Mabini St",
            contact_name="Juan",
            contact_phone="09170000000",
            scheduled_date=date(2026, 1, 2),
            fee=Decimal(0),
        )

        items = DeliverySerializer(delivery).data.get("items")
        if items is None:
            self.fail("the slip carries no items")

        self.assertEqual(
            items[0]["pick_up"],
            [
                {
                    "location": self.store.pk,
                    "location_name": "Store",
                    "qty": "2.00",
                    "unit": "PC",
                }
            ],
        )
