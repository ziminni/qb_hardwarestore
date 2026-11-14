# pyright: reportAttributeAccessIssue=false
"""Phase 9 task B2 (decision 21 §9) — an UNLINKED return goes HOME first.

A linked return has always put stock back where it came from (the deduction rows say
which batches). An unlinked one has no history to read, and the pre-Phase-9 rule was "the
newest batch anywhere", which after per-location stock could restock a Bodega shelf while
the home shelf - the one the next sale looks at first - stayed empty.

The ruling is the allocator's order read backwards: the newest batch at the product's
HOME shelf, then the newest one elsewhere, and only when the variant has no batch at all
does the overall-newest fallback apply. That keeps the shelf a picker walks to first
stocked, and it matches where a sale of that stock would have been taken from.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string

from apps.inventory.models import (
    GoodsReceipt,
    InventoryBatch,
    StorageLocation,
)
from apps.pos.models import Shift
from apps.pos.tests import POSTestBase

from .services import process_return

User = get_user_model()

RETURN_REASON = "customer brought it back"


class UnlinkedReturnShelfTests(POSTestBase):
    """`_restock_returned`'s unlinked branch, read through the real return endpoint."""

    def setUp(self):
        super().setUp()
        self.store = StorageLocation.objects.get(name="Store")
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.variant.product.stored_at = self.store
        self.variant.product.save(update_fields=["stored_at"])

    def _move_to_bodega(self, qty, days_ago=0):
        """Move `qty` of the fixture's own stock onto the Bodega shelf."""
        source = (
            self.variant.batches.filter(current_qty__gt=0)
            .order_by("receipt__receive_date", "id")
            .first()
        )
        source.current_qty -= Decimal(qty)
        source.save(update_fields=["current_qty"])
        batch = InventoryBatch.objects.create(
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
        if days_ago:
            GoodsReceipt.objects.filter(pk=source.receipt_id).update(
                receive_date=date(2026, 1, 1) - timedelta(days=days_ago)
            )
        return batch

    def _manager(self):
        username = "unlinked_mgr"
        manager = User.objects.create_user(
            username=username,
            email=f"{username}@x.com",
            password=get_random_string(20),
            full_name="Store Manager",
        )
        manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        Shift.objects.create(cashier=manager, opening_float=Decimal(5000))
        return manager

    def _unlinked_return(self, qty):
        return process_return(
            customer_id=self.customer.id,
            cashier=self._manager(),
            items_data=[{"variant_id": self.vuom.id, "qty": qty}],
            payment_method="CASH",
            reason=RETURN_REASON,
        )

    def test_an_unlinked_return_lands_on_the_home_shelf(self):
        # The Bodega batch is NEWER, so the old "newest batch anywhere" rule would pick
        # it. The home shelf must win: it is the one the next sale looks at first. The
        # assertion is the home shelf's TOTAL, because WHICH home batch reopens is the
        # next test's question - this one is about which SHELF.
        self._move_to_bodega(4, days_ago=0)
        bodega_before = sum(
            self.variant.batches.filter(location=self.bodega).values_list(
                "current_qty", flat=True
            )
        )
        home_before = sum(
            self.variant.batches.filter(location=self.store).values_list(
                "current_qty", flat=True
            )
        )

        self._unlinked_return(2)

        self.assertEqual(
            sum(
                self.variant.batches.filter(location=self.store).values_list(
                    "current_qty", flat=True
                )
            ),
            home_before + Decimal(2),
            "an unlinked return must restock the product's HOME shelf first",
        )
        self.assertEqual(
            sum(
                self.variant.batches.filter(location=self.bodega).values_list(
                    "current_qty", flat=True
                )
            ),
            bodega_before,
            "the newer Bodega batch must NOT be the one reopened",
        )

    def test_the_home_shelf_gets_the_newest_of_its_own_batches(self):
        # Two home batches: the returned stock reopens the NEWEST at home, exactly as the
        # unlinked rule always did inside one shelf. "Newest" is by delivery DATE, then by
        # id, so two deliveries that arrive on the same day still have an order.
        oldest = (
            self.variant.batches.filter(location=self.store)
            .order_by("receipt__receive_date", "id")
            .first()
        )
        oldest_before = oldest.current_qty
        newest_home = (
            self.variant.batches.filter(location=self.store)
            .order_by("-receipt__receive_date", "-id")
            .first()
        )
        newest_before = newest_home.current_qty
        self.assertNotEqual(
            oldest.pk, newest_home.pk, "the fixture needs two distinct home batches"
        )

        self._unlinked_return(1)

        oldest.refresh_from_db()
        newest_home.refresh_from_db()
        self.assertEqual(oldest.current_qty, oldest_before)
        self.assertEqual(newest_home.current_qty, newest_before + Decimal(1))

    def test_when_home_holds_nothing_the_newest_other_shelf_is_reopened(self):
        # Home is empty; only a Bodega batch carries stock. The return must not fail -
        # "elsewhere" is the next shelf in the same order. (Moved first, zeroed second:
        # the move needs a source with stock to take from.)
        bodega_batch = self._move_to_bodega(2)
        self.variant.batches.filter(location=self.store).update(current_qty=0)

        self._unlinked_return(1)

        bodega_batch.refresh_from_db()
        self.assertEqual(bodega_batch.current_qty, Decimal(3))

    def test_a_variant_with_no_batch_at_all_is_still_refused(self):
        from .exceptions import ReturnError

        self.variant.batches.all().delete()

        with self.assertRaises(ReturnError):
            self._unlinked_return(1)


__all__ = ["UnlinkedReturnShelfTests"]
