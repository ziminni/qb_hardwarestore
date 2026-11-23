# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Decision 25 — the Bodega module: claims, releases, delivery checks and the checker role."""

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from apps.inventory.models import InventoryBatch, StockAdjustment, StorageLocation
from apps.pos.models import Delivery, SalesOrder, SalesOrderItem
from apps.pos.services import (
    fulfil_sales_order,
    process_return,
    process_sale,
    transition_delivery,
)
from apps.pos.tests import POSTestBase

from .models import BodegaDelivery, BodegaRelease, BodegaReleaseLine

User = get_user_model()
RETURN_REASON = "customer changed their mind"
DELIVERY_SLIP = {
    "address": "12 Mabini St",
    "contact_name": "Pedro",
    "contact_phone": "09170000000",
    "scheduled_date": "2026-12-01",
    "fee": "0.00",
}


def _user(username, group):
    user = User.objects.create_user(
        username=username,
        email=f"{username}@x.com",
        password="pass12345",
        full_name=username.title(),
    )
    user.groups.add(Group.objects.get_or_create(name=group)[0])
    return user


class BodegaTestBase(POSTestBase):
    """POSTestBase's 10 bags, moved onto a Bodega shelf that is the product's home."""

    def setUp(self):
        super().setUp()
        self.bodega, _ = StorageLocation.objects.get_or_create(name="Bodega")
        self.bodega.is_bodega = True
        self.bodega.save(update_fields=["is_bodega"])
        self.variant.product.stored_at = self.bodega
        self.variant.product.save(update_fields=["stored_at"])
        InventoryBatch.objects.filter(variant=self.variant).update(location=self.bodega)
        self.checker = _user("checker", "Bodega Checker")
        self.manager = _user("boss", "Store Manager")
        self.api = APIClient()

    def _sell(self, qty):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": qty}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(qty) * 10}],
        )

    def _release(self, sale, qty, user=None, **extra):
        self.api.force_authenticate(user or self.checker)
        body = {
            "receipt": sale.transaction_no,
            "received_by": "Pedro",
            "plate_no": "ABC 123",
            "lines": [
                {
                    "variant": self.variant.pk,
                    "location": self.bodega.pk,
                    "qty": str(qty),
                }
            ],
        }
        body.update(extra)
        return self.api.post("/api/v1/bodega/releases/", body, format="json")

    def _lookup(self, sale):
        self.api.force_authenticate(self.checker)
        return self.api.get(
            "/api/v1/bodega/claims/lookup/", {"receipt": sale.transaction_no}
        )


class ClaimAndReleaseTests(BodegaTestBase):
    def test_a_bodega_sale_is_an_open_claim_for_everything_sold(self):
        sale = self._sell(6)
        response = self._lookup(sale)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data["is_open"])
        (line,) = response.data["lines"]
        self.assertEqual(
            (line["sold"], line["released"], line["remaining"]),
            (Decimal(6), Decimal(0), Decimal(6)),
        )

    def test_the_receipt_or_number_finds_the_claim_too(self):
        sale = self._sell(2)
        self.api.force_authenticate(self.checker)
        response = self.api.get(
            "/api/v1/bodega/claims/lookup/", {"receipt": sale.receipt.or_number}
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["transaction_no"], sale.transaction_no)

    def test_partial_releases_count_down_and_close_the_claim(self):
        sale = self._sell(6)
        self.assertEqual(self._release(sale, 4).status_code, 201)
        self.assertEqual(self._release(sale, 2).status_code, 201)
        response = self._lookup(sale)
        self.assertFalse(response.data["is_open"])
        self.assertEqual(response.data["lines"][0]["remaining"], Decimal(0))
        self.assertEqual(len(response.data["releases"]), 2)
        self.assertTrue(BodegaRelease.objects.first().number.startswith("BR-"))

    def test_more_than_was_paid_for_is_refused_and_nothing_is_written(self):
        sale = self._sell(3)
        self._release(sale, 2)
        response = self._release(sale, 2)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "RELEASE_EXCEEDS_CLAIM")
        self.assertEqual(BodegaRelease.objects.count(), 1)

    def test_a_release_moves_no_stock(self):
        sale = self._sell(3)
        before = sum(
            b.current_qty for b in InventoryBatch.objects.filter(variant=self.variant)
        )
        self._release(sale, 3)
        after = sum(
            b.current_qty for b in InventoryBatch.objects.filter(variant=self.variant)
        )
        self.assertEqual(
            before, after, "stock left the books at the sale, not at the gate"
        )

    def test_a_linked_return_shrinks_what_is_left_to_collect(self):
        sale = self._sell(5)
        process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 2}],
            original_transaction_id=sale.id,
            reason=RETURN_REASON,
        )
        line = self._lookup(sale).data["lines"][0]
        self.assertEqual((line["sold"], line["remaining"]), (Decimal(3), Decimal(3)))

    def test_a_sale_from_the_store_shelf_is_not_a_bodega_claim(self):
        store = StorageLocation.objects.get(name="Store")
        InventoryBatch.objects.filter(variant=self.variant).update(location=store)
        sale = self._sell(1)
        response = self._lookup(sale)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "NO_BODEGA_CLAIM")
        self.assertEqual(self._release(sale, 1).data["code"], "NO_BODEGA_CLAIM")

    def test_receiver_name_is_required(self):
        sale = self._sell(1)
        response = self._release(sale, 1, received_by="  ")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "INVALID_BODEGA_RELEASE")

    def test_open_claims_list_drops_a_fully_released_receipt(self):
        done, waiting = self._sell(1), self._sell(2)
        self._release(done, 1)
        self.api.force_authenticate(self.checker)
        numbers = [
            c["transaction_no"] for c in self.api.get("/api/v1/bodega/claims/").data
        ]
        self.assertEqual(numbers, [waiting.transaction_no])

    def test_stock_shows_books_unreleased_and_physical(self):
        sale = self._sell(4)
        self._release(sale, 1)
        self.api.force_authenticate(self.checker)
        (row,) = self.api.get("/api/v1/bodega/stock/").data
        self.assertEqual(
            (row["on_hand"], row["unreleased"], row["physical"]),
            (Decimal(6), Decimal(3), Decimal(9)),
        )

    def test_idempotency_key_replays_the_original_release_without_double_releasing(
        self,
    ):
        sale = self._sell(4)
        self.api.force_authenticate(self.checker)
        body = {
            "receipt": sale.transaction_no,
            "received_by": "Pedro",
            "plate_no": "ABC 123",
            "lines": [
                {"variant": self.variant.pk, "location": self.bodega.pk, "qty": "2.00"}
            ],
        }
        first = self.api.post(
            "/api/v1/bodega/releases/",
            body,
            format="json",
            HTTP_IDEMPOTENCY_KEY="offline-bodega-key-1",
        )
        self.assertEqual(first.status_code, 201, first.data)
        replay = self.api.post(
            "/api/v1/bodega/releases/",
            body,
            format="json",
            HTTP_IDEMPOTENCY_KEY="offline-bodega-key-1",
        )
        self.assertEqual(replay.status_code, 200, replay.data)
        self.assertEqual(replay.data["id"], first.data["id"])
        self.assertEqual(BodegaRelease.objects.filter(sale=sale).count(), 1)


class DispatchSaleTests(BodegaTestBase):
    """Owner ruling: a customer delivery is worked in Sales Deliveries, never at the gate.

    The sale still takes the goods off the books at the till, so the Bodega has to keep
    saying where they physically are (`awaiting_dispatch`) without pretending someone is
    coming to collect them.
    """

    def _sell_for_delivery(self, qty):
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": qty}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(qty) * 10}],
            delivery_data=dict(DELIVERY_SLIP),
        )

    def _stock(self):
        self.api.force_authenticate(self.checker)
        (row,) = self.api.get("/api/v1/bodega/stock/").data
        return row

    def test_a_dispatch_sale_surfaces_in_bodega_claims_as_for_delivery(self):
        sale = self._sell_for_delivery(6)
        response = self._lookup(sale)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data["is_delivery"])
        self.assertTrue(response.data["delivery_no"].startswith("DEL-"))
        self.assertEqual(response.data["delivery_address"], "12 Mabini St")
        self.api.force_authenticate(self.checker)
        claims = self.api.get("/api/v1/bodega/claims/").data
        self.assertEqual(len(claims), 1)
        self.assertTrue(claims[0]["is_delivery"])
        self.assertEqual(self._release(sale, 2).status_code, 201)

    def test_a_scheduled_dispatch_is_physical_stock_until_it_goes_out(self):
        sale = self._sell_for_delivery(6)
        row = self._stock()
        self.assertEqual(
            (
                row["on_hand"],
                row["unreleased"],
                row["awaiting_dispatch"],
                row["physical"],
            ),
            (Decimal(4), Decimal(0), Decimal(6), Decimal(10)),
        )
        transition_delivery(
            delivery_id=Delivery.objects.get(sale=sale).pk, action="start"
        )
        row = self._stock()
        self.assertEqual(
            (row["awaiting_dispatch"], row["physical"]),
            (Decimal(0), Decimal(4)),
        )

    def test_an_old_release_row_still_shows_and_never_double_counts_the_shelf(self):
        # Written before this ruling, a gate release against a delivery sale must stay in
        # the append-only log; the goods it handed over are not on the shelf any more.
        sale = self._sell_for_delivery(6)
        release = BodegaRelease.objects.create(
            number="BR-LEGACY-1",
            sale=sale,
            checker=self.checker,
            received_by="Old data",
        )
        BodegaReleaseLine.objects.create(
            release=release, variant=self.variant, location=self.bodega, qty=Decimal(2)
        )
        row = self._stock()
        self.assertEqual(
            (row["awaiting_dispatch"], row["physical"]),
            (Decimal(4), Decimal(8)),
        )
        self.api.force_authenticate(self.checker)
        response = self.api.get("/api/v1/bodega/releases/")
        self.assertEqual(response.status_code, 200, response.data)
        numbers = [r["number"] for r in response.data["results"]]
        self.assertEqual(numbers, ["BR-LEGACY-1"])

    def test_a_later_fulfilment_of_a_delivery_order_is_not_a_claim(self):
        # Only the FIRST fulfilment sale carries `Delivery.sale`; a later partial one is
        # recognised through SalesItem.order_line -> order -> Delivery.
        self.customer.customer_type = self.customer.Type.REGULAR
        self.customer.save(update_fields=["customer_type"])
        order = SalesOrder.objects.create(
            order_no="SO-DISPATCH-1",
            customer=self.customer,
            status=SalesOrder.Status.CONFIRMED,
            created_by=self.cashier,
        )
        line = SalesOrderItem.objects.create(
            order=order,
            variant_uom=self.vuom,
            qty=Decimal(6),
            unit_price=Decimal(10),
        )
        Delivery.objects.create(
            sales_order=order,
            created_by=self.cashier,
            address="12 Mabini St",
            contact_name="Pedro",
            contact_phone="09170000000",
            scheduled_date=date(2026, 12, 1),
            fee=Decimal(0),
        )
        sold = []
        for qty in (2, 3):
            sold.append(
                fulfil_sales_order(
                    order_id=order.pk,
                    cashier=self.cashier,
                    lines_data=[{"order_line": line.pk, "qty": qty}],
                    payments_data=[
                        {"method": "CASH", "amount_tendered": Decimal(qty) * 10}
                    ],
                )
            )
        for sale in sold:
            with self.subTest(sale=sale.transaction_no):
                res = self._lookup(sale)
                self.assertEqual(res.status_code, 200)
                self.assertTrue(res.data["is_delivery"])
        row = self._stock()
        self.assertEqual(
            (row["unreleased"], row["awaiting_dispatch"], row["physical"]),
            (Decimal(0), Decimal(5), Decimal(10)),
        )


class DeliveryCheckTests(BodegaTestBase):
    """Decision 25 rev.: a Bodega delivery is stock only after the checker confirms it."""

    def _deliver(self, qty, location=None):
        from apps.inventory.models import (
            GoodsReceipt,
            GoodsReceiptItem,
            POItem,
            PurchaseOrder,
            Supplier,
        )
        from apps.inventory.services import process_goods_receipt

        supplier = Supplier.objects.create(company_name="Quarry Co")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        item = POItem.objects.create(
            po=po,
            variant=self.variant,
            variant_uom=self.vuom,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal("40.00"),
            received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        GoodsReceiptItem.objects.create(
            receipt=receipt,
            po_item=item,
            qty=Decimal(qty),
            location=location or self.bodega,
        )
        process_goods_receipt(receipt=receipt, user=self.manager)
        return receipt

    def _on_hand(self):
        return sum(
            b.current_qty for b in InventoryBatch.objects.filter(variant=self.variant)
        )

    def _confirm(self, delivery_id, good, damaged, user=None):
        self.api.force_authenticate(user or self.checker)
        line = BodegaDelivery.objects.get(pk=delivery_id).lines.get()
        return self.api.post(
            f"/api/v1/bodega/deliveries/{delivery_id}/confirm/",
            {
                "lines": [
                    {
                        "line": line.pk,
                        "good_qty": str(good),
                        "damaged_qty": str(damaged),
                        "remarks": "cracked",
                    }
                ]
            },
            format="json",
        )

    def test_a_bodega_delivery_waits_for_the_checker_and_adds_no_stock(self):
        before = self._on_hand()
        receipt = self._deliver(10)
        self.assertEqual(self._on_hand(), before)
        delivery = BodegaDelivery.objects.get()
        self.assertEqual(delivery.status, "PENDING")
        self.assertTrue(delivery.number.startswith("BD-"))
        self.assertIsNotNone(receipt.__class__.objects.get(pk=receipt.pk).processed_at)
        self.api.force_authenticate(self.checker)
        (row,) = self.api.get("/api/v1/bodega/stock/").data
        self.assertEqual(row["for_checking"], Decimal(10))

    def test_the_bill_follows_the_stockers_receipt_not_the_check(self):
        from apps.inventory.models import SupplierBill

        receipt = self._deliver(10)
        self.assertEqual(SupplierBill.objects.filter(receipt=receipt).count(), 1)

    def test_confirming_stocks_the_good_and_writes_off_damaged_and_missing(self):
        before = self._on_hand()
        self._deliver(10)
        delivery = BodegaDelivery.objects.get()
        response = self._confirm(delivery.pk, good=7, damaged=2)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CHECKED")
        self.assertEqual(self._on_hand(), before + 7)
        self.assertEqual(
            sorted(
                StockAdjustment.objects.values_list("adjustment_type", "qty_adjusted")
            ),
            [("DAMAGE", Decimal(-2)), ("SHRINKAGE", Decimal(-1))],
        )
        self.assertEqual(response.data["lines"][0]["missing_qty"], "1.00")

    def test_more_than_was_delivered_is_refused_and_nothing_moves(self):
        before = self._on_hand()
        self._deliver(10)
        response = self._confirm(BodegaDelivery.objects.get().pk, good=9, damaged=2)
        self.assertEqual(response.data["code"], "INVALID_BODEGA_DELIVERY")
        self.assertEqual(self._on_hand(), before)
        self.assertEqual(BodegaDelivery.objects.get().status, "PENDING")

    def test_a_fraction_of_a_whole_unit_is_refused(self):
        self.variant.base_uom.is_whole = True
        self.variant.base_uom.save(update_fields=["is_whole"])
        self._deliver(10)
        response = self._confirm(BodegaDelivery.objects.get().pk, good="9.5", damaged=0)
        self.assertEqual(response.data["code"], "INVALID_BODEGA_DELIVERY")

    def test_a_delivery_is_checked_once(self):
        self._deliver(10)
        delivery_id = BodegaDelivery.objects.get().pk
        self.assertEqual(self._confirm(delivery_id, 10, 0).status_code, 200)
        self.assertEqual(
            self._confirm(delivery_id, 10, 0).data["code"], "INVALID_BODEGA_DELIVERY"
        )

    def test_a_store_delivery_is_stocked_at_once_as_before(self):
        store = StorageLocation.objects.get(name="Store")
        before = self._on_hand()
        self._deliver(5, location=store)
        self.assertEqual(self._on_hand(), before + 5)
        self.assertFalse(BodegaDelivery.objects.exists())

    def test_a_cashier_cannot_confirm(self):
        self._deliver(10)
        response = self._confirm(
            BodegaDelivery.objects.get().pk, 10, 0, user=_user("till2", "Cashier")
        )
        self.assertEqual(response.status_code, 403)


class CheckerRoleTests(BodegaTestBase):
    def test_the_checker_is_the_bodega_area_only(self):
        self.api.force_authenticate(self.checker)
        me = self.api.get("/api/v1/auth/me/")
        self.assertEqual(me.status_code, 200)
        self.assertEqual([r["name"] for r in me.data["roles"]], ["bodega"])

    def test_the_checker_cannot_ring_or_read_sales(self):
        self.api.force_authenticate(self.checker)
        self.assertEqual(self.api.get("/api/v1/transactions/").status_code, 403)
        self.assertEqual(
            self.api.post("/api/v1/transactions/", {}, format="json").status_code, 403
        )

    def test_a_cashier_has_no_bodega_screens(self):
        self.api.force_authenticate(_user("till", "Cashier"))
        self.assertEqual(self.api.get("/api/v1/bodega/stock/").status_code, 403)
        self.assertEqual(self.api.get("/api/v1/bodega/claims/").status_code, 403)

    def test_bodega_is_an_assignable_role_code(self):
        admin = _user("root", "Admin")
        self.api.force_authenticate(admin)
        target = _user("newbie", "Cashier")
        response = self.api.patch(
            f"/api/v1/users/{target.pk}/", {"roles": ["bodega"]}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            list(target.groups.values_list("name", flat=True)), ["Bodega Checker"]
        )
