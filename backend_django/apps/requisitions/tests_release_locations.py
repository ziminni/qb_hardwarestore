# pyright: reportAttributeAccessIssue=false
"""Phase 9 task B2 (decision 21 §2/§4) — a material release knows its shelves too.

A release is a sale (it deducts stock and books a receivable), so from this phase it
writes the same `SalesItemDeduction` rows a till sale writes, and its result carries the
same `pick_up` caption. Without the rows the release left no record of where the goods
came from; without the caption the cashier cannot be told to fetch half of it from the
Bodega.

`_on_hand_base` and `_release_plan` already sum every batch with `current_qty > 0`
whatever shelf it sits on, which is exactly the set the allocator takes. The tests below
pin that agreement: a shelf the plan counts must be a shelf the release can draw from.
"""

from decimal import Decimal

from django.db import connection
from django.test.utils import CaptureQueriesContext

from apps.inventory.models import (
    GoodsReceipt,
    InventoryBatch,
    POItem,
    PurchaseOrder,
    StorageLocation,
    Supplier,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.models import SalesItemDeduction

from .services import release_materials, verify_token
from .tests import RequisitionTestBase


class ReleasePickUpTests(RequisitionTestBase):
    def setUp(self):
        super().setUp()
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.variant.product.stored_at = self.store
        self.variant.product.save(update_fields=["stored_at"])

    def _receive_at(self, location, qty, variant=None):
        """Put `qty` base units on `location` through the REAL receiving path.

        `_create_batch` stamps the product's home shelf, so a batch bound for the Bodega
        is moved by hand afterwards - the receiving DESTINATION per line is B3's job, and
        this test is about what the allocator and the release do with stock already
        sitting somewhere.
        """
        variant = variant or self.variant
        supplier = Supplier.objects.create(company_name=f"Restock {location.name}")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=variant,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal(1),
            received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        batches = process_goods_receipt(receipt=receipt, user=self.manager)
        # `location` is immutable once a batch exists (Design 1), so the destination is
        # stamped at creation - the same update the B1 migration used for legacy rows.
        InventoryBatch.objects.filter(pk__in=[b.pk for b in batches]).update(
            location=location
        )
        return batches

    def _leave_on_shelf(self, qty, location_id=None):
        """Burn the fixture's stock down to `qty` through the allocator (no test writes)."""
        from apps.inventory.services import allocate_fifo

        on_shelf = sum(
            self.variant.batches.filter(
                **({} if location_id is None else {"location_id": location_id})
            ).values_list("current_qty", flat=True)
        )
        allocate_fifo(
            variant_id=self.variant.pk,
            qty_needed=on_shelf - Decimal(qty),
            location_id=location_id,
        )

    def _move_to_bodega(self, qty):
        """Put `qty` of the fixture's own stock on the Bodega shelf."""
        source = (
            self.variant.batches.filter(current_qty__gt=0)
            .order_by("receipt__receive_date", "id")
            .first()
        )
        source.current_qty -= Decimal(qty)
        source.save(update_fields=["current_qty"])
        InventoryBatch.objects.create(
            variant=self.variant,
            receipt=source.receipt,
            location=self.bodega,
            source_batch=source,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=source.unit_cost_landed,
            markup_percentage=source.markup_percentage,
            batch_selling_price=source.batch_selling_price,
        )

    def test_a_release_writes_its_deductions_like_a_sale(self):
        token = self._mint_token()

        result = release_materials(token_value=str(token.token), cashier=self.cashier)

        rows = SalesItemDeduction.objects.filter(
            sales_item__transaction_id=result["transaction_id"]
        )
        self.assertEqual(
            sum(row.qty for row in rows),
            Decimal(10),
            "a release must record the batches it drew from, like process_sale",
        )

    def test_a_release_spanning_two_shelves_reports_both(self):
        # 6 at home and 3 at the Bodega: a release of 5 is covered by the home shelf, so
        # the Bodega is never reached and the caption names ONE shelf. Placed Bodega-first,
        # then home burnt down to 6, because moving stock needs a source that holds it.
        self._move_to_bodega(3)
        self._leave_on_shelf(6, location_id=self.store.pk)
        token = self._mint_token()
        self.requisition.items.filter(pk=self.req_item.pk).update(quantity=Decimal(5))

        result = release_materials(token_value=str(token.token), cashier=self.cashier)

        released = result["items"][0]
        self.assertEqual(released["released_now"], "5.00")
        self.assertEqual(
            [
                (row["location_name"], row["qty"], row["unit"])
                for row in released["pick_up"]
            ],
            [("Store", "5.00", "BAG")],
            "the home shelf covers it, so the Bodega is untouched",
        )

    def test_a_release_that_needs_both_shelves_names_both(self):
        # Stock is placed where the test needs it: 4 units moved to the Bodega FIRST, then
        # the home shelf burnt down to 3 with the allocator's own `location_id` filter. A
        # release of 7 then has to take 3 at home and 4 at the Bodega.
        self._move_to_bodega(4)
        self._leave_on_shelf(3, location_id=self.store.pk)
        self.requisition.items.filter(pk=self.req_item.pk).update(quantity=Decimal(7))
        token = self._mint_token()

        result = release_materials(token_value=str(token.token), cashier=self.cashier)

        self.assertEqual(
            [
                (row["location_name"], row["qty"], row["unit"])
                for row in result["items"][0]["pick_up"]
            ],
            [("Store", "3.00", "BAG"), ("Bodega", "4.00", "BAG")],
        )
        self.assertEqual(
            sorted(
                SalesItemDeduction.objects.filter(
                    sales_item__transaction_id=result["transaction_id"]
                ).values_list("batch__location_id", "qty")
            ),
            [(self.store.pk, Decimal(3)), (self.bodega.pk, Decimal(4))],
        )


class ReleasePlanCountsEveryShelfTests(RequisitionTestBase):
    """`_on_hand_base`/`_release_plan` must count the same set the allocator takes."""

    def setUp(self):
        super().setUp()
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.variant.product.stored_at = self.store
        self.variant.product.save(update_fields=["stored_at"])
        # 100 base units sit at home from the shared fixture; put 4 on the Bodega.
        source = (
            self.variant.batches.filter(current_qty__gt=0)
            .order_by("receipt__receive_date", "id")
            .first()
        )
        source.current_qty -= Decimal(4)
        source.save(update_fields=["current_qty"])
        InventoryBatch.objects.create(
            variant=self.variant,
            receipt=source.receipt,
            location=self.bodega,
            source_batch=source,
            initial_qty=Decimal(4),
            current_qty=Decimal(4),
            unit_cost_landed=source.unit_cost_landed,
            markup_percentage=source.markup_percentage,
            batch_selling_price=source.batch_selling_price,
        )

    def test_the_plan_counts_stock_on_every_shelf(self):
        token = self._mint_token()
        self.requisition.items.filter(pk=self.req_item.pk).update(quantity=Decimal(104))

        info = verify_token(token_value=str(token.token))

        self.assertEqual(
            info["items"][0]["releasable"],
            "100.00",
            "the plan must count the 4 units on the Bodega as well as the 96 at home",
        )

    def test_two_lines_on_one_variant_share_every_shelf(self):
        # Two lines on one variant share the shelves, and the plan must not promise the
        # same stock twice - the rule decision 05 has always had, now that the stock is
        # split. 100 units are on hand (96 home + 4 Bodega); the shelf is burnt down to 15
        # here so the second line has to be told the short truth: 10 go to the first line,
        # 5 are left for the second.
        from apps.inventory.services import allocate_fifo

        allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(85))
        self.requisition.items.create(
            requisition=self.requisition,
            variant_uom=self.vuom,
            quantity=Decimal(10),
        )
        token = self._mint_token()

        info = verify_token(token_value=str(token.token))

        self.assertEqual(
            [row["releasable"] for row in info["items"]],
            ["10.00", "5.00"],
            "11 at home + 4 at the Bodega is 15: the first line takes 10, the second 5",
        )


class ReleaseLockingTests(RequisitionTestBase):
    """The release keeps reading its batches under a row lock (Design 12)."""

    def test_the_release_locks_the_batches_it_deducts(self):
        token = self._mint_token()

        with CaptureQueriesContext(connection) as captured:
            release_materials(token_value=str(token.token), cashier=self.cashier)

        self.assertTrue(
            any(
                "inventory_batch" in query["sql"] and "FOR UPDATE" in query["sql"]
                for query in captured.captured_queries
            ),
            "a release must keep the allocator's batch lock",
        )


__all__ = [
    "ReleaseLockingTests",
    "ReleasePickUpTests",
    "ReleasePlanCountsEveryShelfTests",
]
