# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/inventory/tests_receiving_locations.py: the checker
# runs from a working directory outside the repo, so `Model.objects` is a false positive
# on valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client. The test
# run is the authority.

"""Phase 9 B4 (decision 21 §3, plan Design 2/6/11/12) — one-step numbered transfers.

The stock team records "move N from A to B". Stock moves AT ONCE, on a numbered slip,
with the batch's cost and age travelling with it:

* the quantity leaves the SOURCE shelf's batches FIFO-first (oldest delivery first) and
  lands in NEW batches on the destination shelf that copy the source batch's receipt,
  landed cost, selling price, markup and expiry - so FIFO age survives the move and every
  "what did this receipt bring in" sum skips the copy (`source_batch` non-null);
* the VARIANT's total is unchanged, so the low-stock threshold is untouched and no alert
  appears out of a transfer;
* one `TR-YYYYMMDD-NNNN` number, reserved through the locked `DocumentCounter` LAST (plan
  Design 12 d), and one `STOCK_TRANSFER` audit row in the SAME transaction;
* every refusal (same shelf, deactivated destination, archived variant, short stock at
  the source, a fraction on a whole unit, a quantity that is not a whole hundredth of the
  base unit, no lines) is answered **before or inside** that transaction, so a refused
  transfer leaves no header, no line, no move, no new batch and no audit row.
"""

import threading
from datetime import date, timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.pos.models import Customer, DocumentCounter, Shift
from apps.pos.services import process_sale
from apps.users.models import AuditLog

from . import transfers
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    InventoryBatch,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockTransfer,
    StockTransferLine,
    StockTransferMove,
    StorageLocation,
    Supplier,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
)
from .tests_storage_locations import StorageTestBase

User = get_user_model()

TRANSFERS_URL = "/api/v1/stock-transfers/"
TODAY = date.today().strftime("%Y%m%d")


class TransferTestBase(StorageTestBase):
    """A selling unit to transfer, one placed PO for batch receipts, and stock helpers."""

    def setUp(self):
        super().setUp()
        self.auth = self._auth(self.stocker)
        supplier = Supplier.objects.create(company_name="Acme Supply")
        self.po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )

    # -- fixture helpers ---------------------------------------------------
    def _batch(self, *, qty, location, cost="50.00", expiry=None, variant=None):
        """One delivered batch, minted straight through the ORM like a processed receipt."""
        return InventoryBatch.objects.create(
            variant=variant or self.variant,
            receipt=GoodsReceipt.objects.create(po=self.po, received_by=self.user),
            location=location,
            initial_qty=Decimal(qty),
            current_qty=Decimal(qty),
            unit_cost_landed=Decimal(cost),
            markup_percentage=Decimal("10.00"),
            batch_selling_price=Decimal("55.00"),
            expiration_date=expiry,
        )

    @staticmethod
    def _deactivate(location):
        StorageLocation.objects.filter(pk=location.pk).update(is_active=False)
        location.refresh_from_db()
        return location

    def _body(self, **overrides):
        body = {
            "from_location": self.store.pk,
            "to_location": self.bodega.pk,
            "lines": [{"variant_uom": self.vuom.pk, "qty": "4"}],
        }
        body.update(overrides)
        return body

    def _total(self, variant=None):
        return sum(
            (
                batch.current_qty
                for batch in InventoryBatch.objects.filter(
                    variant=variant or self.variant
                )
            ),
            Decimal(0),
        )

    def _assert_nothing_written(self, total_before):
        """A refused transfer writes no document, no move, no audit and moves no stock."""
        self.assertEqual(StockTransfer.objects.count(), 0)
        self.assertEqual(StockTransferLine.objects.count(), 0)
        self.assertEqual(StockTransferMove.objects.count(), 0)
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.STOCK_TRANSFER
            ).count(),
            0,
        )
        self.assertEqual(self._total(), total_before)


class TransferMoveTests(TransferTestBase):
    """The happy path: FIFO out of the source, new copying batches at the destination."""

    def test_a_numbered_transfer_moves_fifo_stock_and_copies_the_batch(self):
        expiry = date.today() + timedelta(days=30)
        oldest = self._batch(qty="3", location=self.store, cost="50.00", expiry=expiry)
        newer = self._batch(qty="5", location=self.store, cost="60.00")

        response = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["number"], f"TR-{TODAY}-0001")
        self.assertEqual(response.data["from_location"], self.store.pk)
        self.assertEqual(response.data["to_location"], self.bodega.pk)
        self.assertEqual(len(response.data["lines"]), 1)

        oldest.refresh_from_db()
        newer.refresh_from_db()
        self.assertEqual(oldest.current_qty, Decimal(0), "FIFO takes the oldest first")
        self.assertEqual(newer.current_qty, Decimal(4))

        # Two destination batches: 3 off the oldest delivery, 1 off the newer one.
        landed = list(
            InventoryBatch.objects.filter(location=self.bodega).order_by("pk")
        )
        self.assertEqual(
            [batch.current_qty for batch in landed], [Decimal(3), Decimal(1)]
        )
        self.assertEqual(landed[0].source_batch_id, oldest.pk)
        self.assertEqual(landed[1].source_batch_id, newer.pk)
        self.assertEqual(landed[0].receipt_id, oldest.receipt_id)
        self.assertEqual(landed[0].unit_cost_landed, Decimal("50.00"))
        self.assertEqual(landed[1].unit_cost_landed, Decimal("60.00"))
        self.assertEqual(landed[0].expiration_date, expiry)
        self.assertEqual(landed[0].batch_selling_price, Decimal("55.00"))
        self.assertEqual(landed[0].markup_percentage, Decimal("10.00"))

        line = StockTransferLine.objects.get()
        self.assertEqual(line.qty, Decimal(4))
        self.assertEqual(line.base_qty, Decimal(4))
        self.assertEqual(
            list(
                StockTransferMove.objects.order_by("pk").values_list(
                    "source_batch_id", "dest_batch_id", "qty"
                )
            ),
            [
                (oldest.pk, landed[0].pk, Decimal(3)),
                (newer.pk, landed[1].pk, Decimal(1)),
            ],
        )

        # The VARIANT total did not move: the shop still owns 8 (plan Design 6).
        self.assertEqual(self._total(), Decimal(8))
        self.assertEqual(landed[0].current_qty + landed[1].current_qty, Decimal(4))

        audit = AuditLog.objects.get(action_type=AuditLog.ActionType.STOCK_TRANSFER)
        self.assertIn(f"TR-{TODAY}-0001", audit.description)
        self.assertEqual(audit.user_id, self.stocker.pk)

        # Total unchanged, so the low-stock threshold is untouched: no alert out of a move.
        self.assertEqual(SystemAlert.objects.count(), 0)

    def test_each_transfer_reserves_the_next_number(self):
        self._batch(qty="10", location=self.store)

        first = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )
        second = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(first.data["number"], f"TR-{TODAY}-0001")
        self.assertEqual(second.data["number"], f"TR-{TODAY}-0002")
        self.assertEqual(StockTransfer.objects.count(), 2)

    def test_the_number_is_reserved_after_the_batches_and_the_low_stock_check(self):
        """Plan Design 12(d), the order the docstring promises: batches, variants, number.

        The spy records what exists at the instant `_check_low_stock` runs: the destination
        batch is already there, the TR number is not. Reversing the two (the counter taken
        before the variant rows) fails here.
        """
        self._batch(qty="10", location=self.store)
        seen = []
        real_check = transfers._check_low_stock

        def spy(variant):
            seen.append(
                (
                    InventoryBatch.objects.filter(location=self.bodega).count(),
                    DocumentCounter.objects.filter(prefix="TR").count(),
                )
            )
            return real_check(variant)

        with mock.patch.object(transfers, "_check_low_stock", side_effect=spy):
            response = self.client.post(
                TRANSFERS_URL, self._body(), format="json", **self.auth
            )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            seen,
            [(1, 0)],
            "at the low-stock check the destination batch exists and no TR number is "
            "reserved yet (batches -> variants -> counter)",
        )

    def test_a_transfer_only_touches_the_source_shelf(self):
        self._batch(qty="10", location=self.store)
        elsewhere = self._batch(qty="6", location=self.bodega)

        response = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(response.status_code, 201, response.data)
        elsewhere.refresh_from_db()
        self.assertEqual(
            elsewhere.current_qty, Decimal(6), "the source shelf alone moves"
        )

    def test_stock_can_be_transferred_out_of_a_deactivated_shelf(self):
        self._batch(qty="6", location=self.bodega)
        self._deactivate(self.bodega)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(
                from_location=self.bodega.pk,
                to_location=self.store.pk,
                lines=[{"variant_uom": self.vuom.pk, "qty": "6"}],
            ),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            InventoryBatch.objects.get(location=self.store).current_qty, Decimal(6)
        )

    def test_two_variants_in_one_transfer_both_move(self):
        other_uom, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece"}
        )
        other = ProductVariant.objects.create(
            product=self.product, variant_name="50kg", base_uom=other_uom
        )
        other_vuom = VariantUOM.objects.create(
            variant=other,
            uom=other_uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        self._batch(qty="10", location=self.store)
        self._batch(qty="7", location=self.store, variant=other)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(
                lines=[
                    {"variant_uom": other_vuom.pk, "qty": "5"},
                    {"variant_uom": self.vuom.pk, "qty": "2"},
                ]
            ),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self._total(), Decimal(10))
        self.assertEqual(self._total(variant=other), Decimal(7))
        self.assertEqual(
            InventoryBatch.objects.get(variant=other, location=self.bodega).current_qty,
            Decimal(5),
        )
        self.assertEqual(StockTransferLine.objects.count(), 2)

    def test_a_selling_unit_converts_to_base_stock(self):
        box, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box"}
        )
        self.vuom.uom = box
        self.vuom.conversion_factor = Decimal(12)
        self.vuom.save()
        self._batch(qty="36", location=self.store)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(lines=[{"variant_uom": self.vuom.pk, "qty": "2"}]),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["lines"][0]["qty"], "2.00")
        self.assertEqual(response.data["lines"][0]["base_qty"], "24.00")
        self.assertEqual(
            InventoryBatch.objects.get(location=self.bodega).current_qty, Decimal(24)
        )


class TransferRefusalTests(TransferTestBase):
    """Every refusal writes nothing at all - no header, no move, no audit, no stock."""

    def test_the_same_shelf_is_refused(self):
        self._batch(qty="10", location=self.store)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(to_location=self.store.pk),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self._assert_nothing_written(Decimal(10))

    def test_a_deactivated_destination_is_refused(self):
        self._batch(qty="10", location=self.store)
        self._deactivate(self.bodega)

        response = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_STORAGE_LOCATION")
        self._assert_nothing_written(Decimal(10))

    def test_an_archived_variant_is_refused(self):
        self._batch(qty="10", location=self.store)
        ProductVariant.objects.filter(pk=self.variant.pk).update(is_active=False)

        response = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self._assert_nothing_written(Decimal(10))

    def test_short_stock_at_the_source_is_refused_and_names_the_shelf(self):
        self._batch(qty="2", location=self.store)
        self._batch(qty="10", location=self.bodega)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(lines=[{"variant_uom": self.vuom.pk, "qty": "5"}]),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INSUFFICIENT_STOCK")
        self.assertIn("Store", response.data["detail"])
        self.assertEqual(response.data["shortfall"], "3.00")
        # The Bodega's own 10 must not pay for a Store shortage.
        self._assert_nothing_written(Decimal(12))

    def test_a_fraction_of_a_whole_unit_is_refused(self):
        self.vuom.uom.is_whole = True
        self.vuom.uom.save()
        self._batch(qty="10", location=self.store)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(lines=[{"variant_uom": self.vuom.pk, "qty": "1.5"}]),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "WHOLE_UNIT_QUANTITY")
        self._assert_nothing_written(Decimal(10))

    def test_a_quantity_that_is_not_a_whole_hundredth_is_refused(self):
        self.vuom.uom.is_whole = False
        self.vuom.uom.save()
        self.vuom.conversion_factor = Decimal("0.03")
        self.vuom.save()
        self._batch(qty="10", location=self.store)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(lines=[{"variant_uom": self.vuom.pk, "qty": "0.50"}]),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "TRANSFER_QUANTITY_UNREPRESENTABLE")
        self._assert_nothing_written(Decimal(10))

    def test_a_transfer_with_no_lines_is_refused(self):
        self._batch(qty="10", location=self.store)

        response = self.client.post(
            TRANSFERS_URL, self._body(lines=[]), format="json", **self.auth
        )

        self.assertEqual(response.status_code, 400, response.data)
        self._assert_nothing_written(Decimal(10))

    def test_a_zero_or_negative_quantity_is_refused(self):
        self._batch(qty="10", location=self.store)

        response = self.client.post(
            TRANSFERS_URL,
            self._body(lines=[{"variant_uom": self.vuom.pk, "qty": "0"}]),
            format="json",
            **self.auth,
        )

        self.assertEqual(response.status_code, 400, response.data)
        self._assert_nothing_written(Decimal(10))

    def test_a_refused_transfer_burns_no_number(self):
        """A 400 leaves no gap: the next accepted transfer is still -0002.

        The number is reserved LAST (plan Design 12 d), so a refusal never reaches it.
        """
        self._batch(qty="10", location=self.store)

        first = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )
        refused = self.client.post(
            TRANSFERS_URL,
            self._body(to_location=self.store.pk),
            format="json",
            **self.auth,
        )
        second = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(first.data["number"], f"TR-{TODAY}-0001")
        self.assertEqual(
            second.data["number"],
            f"TR-{TODAY}-0002",
            "the refused transfer did not consume -0002",
        )


class TransferAccessTests(TransferTestBase):
    """Append-only and role-fenced, like every other stock-evidence document."""

    def test_put_patch_and_delete_are_forbidden_for_every_role(self):
        self._batch(qty="5", location=self.store)
        created = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **self.auth
        )
        self.assertEqual(created.status_code, 201, created.data)
        transfer_id = created.data["id"]
        admin = self._auth(self.admin)

        detail = f"{TRANSFERS_URL}{transfer_id}/"
        self.assertEqual(
            self.client.put(detail, self._body(), format="json", **admin).status_code,
            405,
        )
        self.assertEqual(
            self.client.patch(
                detail, {"remarks": "x"}, format="json", **admin
            ).status_code,
            405,
        )
        self.assertEqual(self.client.delete(detail, **admin).status_code, 405)
        self.assertEqual(StockTransfer.objects.count(), 1)

    def test_a_cashier_can_neither_record_nor_read_transfers(self):
        self._batch(qty="5", location=self.store)
        cashier = self._auth(self.cashier)

        refused = self.client.post(
            TRANSFERS_URL, self._body(), format="json", **cashier
        )
        listed = self.client.get(TRANSFERS_URL, **cashier)

        self.assertEqual(refused.status_code, 403, refused.data)
        self.assertEqual(listed.status_code, 403, listed.data)
        self.assertEqual(StockTransfer.objects.count(), 0)
        self.assertEqual(
            InventoryBatch.objects.get(location=self.store).current_qty, Decimal(5)
        )

    def test_the_list_shows_the_number_shelves_and_lines(self):
        self._batch(qty="5", location=self.store)
        self.client.post(TRANSFERS_URL, self._body(), format="json", **self.auth)

        listed = self.client.get(TRANSFERS_URL, **self.auth)

        self.assertEqual(listed.status_code, 200, listed.data)
        results = listed.data.get("results", listed.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["number"], f"TR-{TODAY}-0001")
        self.assertEqual(results[0]["from_location_name"], "Store")
        self.assertEqual(results[0]["to_location_name"], "Bodega")
        self.assertEqual(len(results[0]["lines"][0]["moves"]), 1)


class ConcurrentTransferTests(TransactionTestCase):
    """A transfer and a sale reaching for the same last units: exactly one wins.

    `TransactionTestCase` because the two worker threads must see each other's COMMITTED
    rows — the wrapped transaction a `TestCase` uses hides them, and the test would then
    pass or fail on timing rather than on the row locks (plan Design 12).
    """

    def setUp(self):
        self.password = get_random_string(16)
        self.store = StorageLocation.objects.get_or_create(name="Store")[0]
        self.bodega = StorageLocation.objects.get_or_create(name="Bodega")[0]
        supplier = Supplier.objects.create(company_name="Race Supply")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        self.stocker = self._user("race_stocker", "Stock Manager")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.stocker,
            status=PurchaseOrder.Status.ORDERED,
        )
        product = Product.objects.create(
            category=Category.objects.create(name="Cement"),
            brand=Brand.objects.create(name="Rhino"),
            base_name="Portland Cement",
            stored_at=self.store,
        )
        self.variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        self.vuom = VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        InventoryBatch.objects.create(
            variant=self.variant,
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.stocker),
            location=self.store,
            initial_qty=Decimal(10),
            current_qty=Decimal(10),
            unit_cost_landed=Decimal("50.00"),
            markup_percentage=Decimal(0),
            batch_selling_price=Decimal("55.00"),
        )
        self.cashier = self._user("race_cashier", "Cashier")
        Shift.objects.create(cashier=self.cashier, opening_float=Decimal(0))
        self.customer = Customer.objects.create(name="Race Customer")

    def _user(self, username, *groups):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@example.com",
            password=self.password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def test_a_transfer_and_a_sale_cannot_both_take_the_last_units(self):
        barrier = threading.Barrier(2, timeout=20)
        results = {}
        lock = threading.Lock()

        def transfer_worker():
            client = APIClient()
            login = client.post(
                "/api/v1/auth/login/",
                {"username": "race_stocker", "password": self.password},
                format="json",
            )
            auth = {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}
            try:
                barrier.wait()
                response = client.post(
                    TRANSFERS_URL,
                    {
                        "from_location": self.store.pk,
                        "to_location": self.bodega.pk,
                        "lines": [{"variant_uom": self.vuom.pk, "qty": "10"}],
                    },
                    format="json",
                    **auth,
                )
                with lock:
                    results["transfer"] = response.status_code
                    results["transfer_body"] = response.data
            finally:
                connections.close_all()

        def sale_worker():
            try:
                barrier.wait()
                process_sale(
                    customer_id=self.customer.pk,
                    cashier=self.cashier,
                    items_data=[{"variant_id": self.vuom.pk, "qty": Decimal(10)}],
                    payments_data=[{"method": "CASH", "amount_tendered": Decimal(200)}],
                )
                with lock:
                    results["sale"] = "SOLD"
            except ValueError:  # InsufficientStock: the transfer got there first
                with lock:
                    results["sale"] = "SHORT"
            except Exception as exc:  # noqa: BLE001 - a crash here IS the failure
                with lock:
                    results["sale"] = f"ERROR {exc!r}"
            finally:
                connections.close_all()

        threads = [
            threading.Thread(target=transfer_worker),
            threading.Thread(target=sale_worker),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        # The sale is variant-wide (it draws from whatever shelf still holds stock), so the
        # two orders of events are both legitimate: the SALE rings first and empties the
        # Store (the transfer then has nothing to move and is refused), or the TRANSFER
        # commits first and the sale takes the moved units off the Bodega. What may never
        # happen is both taking the same ten: that is an oversell, and it shows up as a
        # negative batch or as a total below zero.
        self.assertEqual(results["sale"], "SOLD", results)
        self.assertIn(results["transfer"], (201, 400), results)

        total = sum(
            (
                batch.current_qty
                for batch in InventoryBatch.objects.filter(variant=self.variant)
            ),
            Decimal(0),
        )
        self.assertEqual(total, Decimal(0), "ten units were sold OR moved, never both")
        self.assertFalse(
            InventoryBatch.objects.filter(current_qty__lt=0).exists(),
            "no shelf may be oversold",
        )

        bodega = InventoryBatch.objects.filter(
            variant=self.variant, location=self.bodega
        ).first()
        if results["transfer"] == 201:
            # The move committed and the sale still succeeded, so the sale must have taken
            # the SAME units off the Bodega - written once, never duplicated.
            self.assertIsNotNone(bodega, "the move must mint a destination batch")
            self.assertEqual(bodega.initial_qty, Decimal(10), "written exactly once")
            self.assertEqual(bodega.current_qty, Decimal(0), "and sold from there")
            self.assertEqual(
                InventoryBatch.objects.filter(
                    variant=self.variant, location=self.bodega
                ).count(),
                1,
                "one source batch moved once = one destination batch",
            )
        else:
            self.assertEqual(results["transfer_body"]["code"], "INSUFFICIENT_STOCK")
            self.assertIsNone(
                bodega, "a refused transfer must mint no destination batch"
            )
