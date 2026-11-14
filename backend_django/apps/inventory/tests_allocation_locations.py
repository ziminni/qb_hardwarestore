# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/inventory/tests.py: this checker runs from a working
# directory outside the repo, so no pyrightconfig.json is found and `Model.objects` is a
# false positive on valid Django. The test run is the authority.
"""Phase 9 task B2 (decision 21 §2 and its follow-up rulings) — the allocator's ORDER.

Stock now sits on several shelves. A sale or a release takes the product's **home**
shelf first, then the other ACTIVE locations in location order, and only then stock on a
deactivated shelf (the owner's ruling: inactive stock stays sellable and is taken LAST,
so nothing is stranded). Inside one shelf the oldest delivery still goes first, so FIFO
age survives the move.

These tests read `allocate_fifo` directly rather than through a sale: the ordering is the
allocator's own rule, and a failure here should name the shelf, not a receipt total.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.db import connection
from django.test.utils import CaptureQueriesContext

from .models import (
    GoodsReceipt,
    InventoryBatch,
    PurchaseOrder,
    StorageLocation,
    Supplier,
)
from .services import allocate_fifo
from .tests import InventoryTestBase


class AllocationOrderTests(InventoryTestBase):
    """The shelf order: home first, then active others, then inactive ones."""

    def setUp(self):
        super().setUp()
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        # The product's HOME is the Store: `Product.stored_at` is the column B1 backfilled
        # every batch to, and the one the ordering rule reads.
        self.product.stored_at = self.store
        self.product.save(update_fields=["stored_at"])

    def _batch(self, location, qty, days_ago=0):
        """One delivery of `qty` base units onto `location`, received `days_ago`."""
        supplier = Supplier.objects.create(
            company_name=f"Acme {location.name} {days_ago}"
        )
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        # `receive_date` is auto_now_add, so the date is set after the fact - the FIFO
        # ORDER is what is under test and it reads this column.
        GoodsReceipt.objects.filter(pk=receipt.pk).update(
            receive_date=date(2026, 1, 1) - timedelta(days=days_ago)
        )
        return InventoryBatch.objects.create(
            variant=self.variant,
            receipt=receipt,
            location=location,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(50),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal(50),
        )

    def test_the_home_shelf_is_taken_first_even_when_it_is_the_newest_stock(self):
        # The Bodega delivery is OLDER, and pure FIFO would take it first. The owner's
        # rule is the shelf order first, age inside the shelf - so the Store goes first.
        home = self._batch(self.store, "3", days_ago=1)
        self._batch(self.bodega, "5", days_ago=10)

        allocations = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(2))

        self.assertEqual(
            [(b.pk, take) for b, take in allocations], [(home.pk, Decimal(2))]
        )

    def test_fifo_age_still_orders_batches_inside_one_shelf(self):
        older_home = self._batch(self.store, "2", days_ago=9)
        newer_home = self._batch(self.store, "2", days_ago=1)
        self._batch(self.bodega, "5", days_ago=30)

        allocations = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(5))

        self.assertEqual(
            [(b.location_id, take) for b, take in allocations],
            [
                (self.store.pk, Decimal(2)),
                (self.store.pk, Decimal(2)),
                (self.bodega.pk, Decimal(1)),
            ],
        )
        self.assertEqual(
            [b.pk for b, _ in allocations][:2], [older_home.pk, newer_home.pk]
        )

    def test_other_active_shelves_are_taken_in_location_order(self):
        self._batch(self.store, "0", days_ago=1)
        third = StorageLocation.objects.create(name="Warehouse")
        # The LOWER-pk shelf carries the NEWER delivery, so the two candidate rules
        # disagree: pure FIFO would take Warehouse first, location order takes Bodega.
        # With the dates the other way round this test passed before the ordering key
        # existed, which is the same as not testing it.
        self.assertLess(self.bodega.pk, third.pk, "the fixture needs the pk order")
        first_other = self._batch(self.bodega, "2", days_ago=1)
        second_other = self._batch(third, "2", days_ago=5)

        allocations = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(4))

        self.assertEqual(
            [b.location_id for b, _ in allocations],
            sorted([self.bodega.pk, third.pk]),
            "active shelves are taken in location order, not by delivery date",
        )
        # Named rows too, so a re-numbered pk cannot pass by accident.
        self.assertEqual(
            {b.pk for b, _ in allocations}, {first_other.pk, second_other.pk}
        )

    def test_stock_on_a_deactivated_shelf_is_taken_last_but_is_still_taken(self):
        home = self._batch(self.store, "1", days_ago=1)
        closed = StorageLocation.objects.create(name="Closed Annex", is_active=False)
        stranded = self._batch(closed, "4", days_ago=60)

        allocations = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(3))

        self.assertEqual(
            [(b.location_id, take) for b, take in allocations],
            [(self.store.pk, Decimal(1)), (closed.pk, Decimal(2))],
        )
        self.assertEqual([b.pk for b, _ in allocations], [home.pk, stranded.pk])

    def test_a_missing_shelf_never_hides_stock_from_the_total(self):
        # A quieter regression: a filter that only looked at ACTIVE locations would leave
        # the inactive shelf's stock unsellable, which the owner ruled against.
        closed = StorageLocation.objects.create(name="Closed Too", is_active=False)
        self._batch(closed, "2")

        allocations = allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(2))

        self.assertEqual(sum(take for _, take in allocations), Decimal(2))


class AllocatedLocationRestrictionTests(AllocationOrderTests):
    """`location_id=` keeps an allocation on ONE shelf (decision 21 §3)."""

    def test_location_id_restricts_the_allocation_to_that_shelf(self):
        self._batch(self.store, "5")
        bodega = self._batch(self.bodega, "2")

        allocations = allocate_fifo(
            variant_id=self.variant.pk,
            qty_needed=Decimal(2),
            location_id=self.bodega.pk,
        )

        self.assertEqual([b.pk for b, _ in allocations], [bodega.pk])

    def test_location_id_is_refused_when_that_shelf_cannot_cover_it(self):
        from .exceptions import InsufficientStock

        self._batch(self.store, "10")
        self._batch(self.bodega, "2")

        with self.assertRaises(InsufficientStock):
            allocate_fifo(
                variant_id=self.variant.pk,
                qty_needed=Decimal(5),
                location_id=self.bodega.pk,
            )


class AllocationQueryTests(AllocationOrderTests):
    """One locked query orders the whole shelf list (plan Design 12 lock order)."""

    def test_the_whole_order_costs_one_locked_query(self):
        self._batch(self.store, "2")
        self._batch(self.bodega, "2")

        with CaptureQueriesContext(connection) as captured:
            allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(3))

        inserts = [
            query["sql"]
            for query in captured.captured_queries
            if query["sql"].lstrip().upper().startswith("SELECT")
        ]
        self.assertEqual(len(inserts), 1, [q["sql"] for q in captured.captured_queries])
        self.assertIn("FOR UPDATE", inserts[0])

    def test_the_lock_covers_only_the_batch_rows(self):
        # `of=("self",)` is load-bearing: the joins through to the storage location and
        # the product are for ORDERING, and locking those catalog rows would serialise
        # unrelated sales of the same product. PostgreSQL spells the locked set after
        # `OF`, so the assertion reads that clause - the joined tables legitimately appear
        # in the SELECT and the ORDER BY of the same statement.
        self._batch(self.store, "2")

        with CaptureQueriesContext(connection) as captured:
            allocate_fifo(variant_id=self.variant.pk, qty_needed=Decimal(1))

        locked = [
            query["sql"]
            for query in captured.captured_queries
            if "FOR UPDATE" in query["sql"]
        ]
        self.assertEqual(len(locked), 1, locked)
        self.assertTrue(
            locked[0].endswith('FOR UPDATE OF "inventory_batch"'),
            locked[0],
        )
