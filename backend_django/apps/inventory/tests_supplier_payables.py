# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Phase 5 B2 (decision 18) — supplier terms, PO money and receipt-linked bills.

What this file pins:

* **PO money is computed, never trusted.** `gross_amount` = ordered qty × unit cost,
  `discount_amount` is the header's own input (never above gross), and the net/VAT/total
  triple follows the header's `vat_inclusive` flag and its SNAPSHOT `vat_rate` (taken
  from StoreSettings when the API creates the order, 0 when the shop is not VAT
  registered). All of it is read-only on the wire.
* **A processed receipt creates exactly ONE bill**, inside the same transaction as the
  batches and the audit row. The bill's gross is the DELIVERED PACKAGE qty × the
  package cost (never base qty × package cost), its discount is the receipt's
  proportional share of the PO's header discount (cumulative cent allocation that sums
  to the header discount exactly), and its due date is the receipt date + the supplier's
  terms snapshot.
* **History does not drift.** A later settings change rewrites no bill; a receipt that
  was already processed before this phase gets no retroactive bill.
* **Payments are append-only, locked and audited.** Partial allowed, never above the
  balance, cheque needs its number/bank/date, `OVERPAYMENT` and `BILL_PAID` are stable
  codes, Store Manager/Admin pay while Stock Manager only reads.
"""

import threading
from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import IntegrityError, connections, transaction
from django.test import TransactionTestCase
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.pos.models import StoreSettings
from apps.users.models import AuditLog

from .exceptions import ImmutablePayableRecord, ReceiptAlreadyProcessed
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    SupplierBill,
    SupplierPayment,
    UnitOfMeasure,
    VariantUOM,
)
from .services import process_goods_receipt
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
PO_URL = "/api/v1/purchase-orders/"
RECEIPTS_URL = "/api/v1/goods-receipts/"
BILLS_URL = "/api/v1/supplier-bills/"
PAYMENTS_URL = "/api/v1/supplier-payments/"
SUPPLIERS_URL = "/api/v1/suppliers/payables/"


class PayablesTestBase(InventoryTestBase):
    """Named actors for every role B2 cares about, plus PO/receipt fixture helpers."""

    def setUp(self):
        super().setUp()
        self.password = get_random_string(16)
        self.stocker = self._user("pay_stocker", "Stock Manager")
        self.manager = self._user("pay_manager", "Store Manager")
        self.cashier = self._user("pay_cashier", "Cashier")
        self.admin = self._user("pay_admin", "Admin")
        self.cpms = self._user("pay_cpms", "CPMS Service")
        self.supplier = Supplier.objects.create(company_name="Cebu Building Supply")
        # Phase 5 B1: an API line that omits `variant_uom` defaults to the variant's base
        # selling unit, so the fixture has one - exactly what every real product has.
        VariantUOM.objects.create(
            variant=self.variant,
            uom=self.uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(100),
        )

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

    def _login(self, user):
        client = APIClient()
        response = client.post(
            LOGIN_URL,
            {"username": user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        return client

    def _po(
        self,
        *,
        ordered="10",
        cost="100",
        unit=None,
        discount="0",
        vat_inclusive=True,
        vat_rate="0",
        status=PurchaseOrder.Status.ORDERED,
        supplier=None,
    ):
        po = PurchaseOrder.objects.create(
            supplier=supplier or self.supplier,
            created_by=self.user,
            status=status,
            discount_amount=Decimal(discount),
            vat_inclusive=vat_inclusive,
            vat_rate=Decimal(vat_rate),
        )
        item = POItem.objects.create(
            po=po,
            variant=self.variant,
            variant_uom=unit,
            ordered_qty=Decimal(ordered),
            unit_cost=Decimal(cost),
        )
        return po, item

    def _receipt(self, po, lines):
        """One receipt carrying `[(po_item, qty), ...]` DELIVERED lines."""
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        for item, qty in lines:
            qty = Decimal(qty)
            item.received_qty += qty
            item.save(update_fields=["received_qty"])
            GoodsReceiptItem.objects.create(receipt=receipt, po_item=item, qty=qty)
        return GoodsReceipt.objects.get(pk=receipt.pk)

    def _process(self, receipt):
        return process_goods_receipt(receipt=receipt, user=self.user)

    def _bill(self, receipt):
        """Process one receipt and return the bill it must have created."""
        self._process(receipt)
        return SupplierBill.objects.get(receipt=receipt)


# =========================================================================
# PO money (header discount + VAT) — computed, read-only, DRAFT-only input
# =========================================================================


class PurchaseOrderMoneyTests(PayablesTestBase):
    def _post_po(self, *, items=None, discount="0", vat_inclusive=True):
        payload = {
            "supplier": self.supplier.pk,
            "discount_amount": discount,
            "vat_inclusive": vat_inclusive,
            "items": items
            or [{"variant": self.variant.pk, "ordered_qty": "10", "unit_cost": "100"}],
        }
        return self._login(self.stocker).post(PO_URL, payload, format="json")

    def test_vat_inclusive_totals_extract_vat_from_the_discounted_net(self):
        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("12.00")}
        )

        response = self._post_po(discount="100")

        self.assertEqual(response.status_code, 201, response.data)
        body = response.data
        self.assertEqual(body["gross_amount"], "1000.00")
        self.assertEqual(body["discount_amount"], "100.00")
        self.assertEqual(body["net_amount"], "900.00")
        self.assertEqual(body["vatable_amount"], "803.57")
        self.assertEqual(body["vat_amount"], "96.43")
        self.assertEqual(body["total_amount"], "900.00")
        self.assertEqual(body["vat_rate"], "12.00")

    def test_vat_exclusive_totals_add_vat_on_the_discounted_net(self):
        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("12.00")}
        )

        response = self._post_po(discount="100", vat_inclusive=False)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["net_amount"], "900.00")
        self.assertEqual(response.data["vat_amount"], "108.00")
        self.assertEqual(response.data["total_amount"], "1008.00")

    def test_not_registered_store_snapshots_a_zero_rate_and_charges_no_vat(self):
        StoreSettings.objects.update_or_create(
            pk=1,
            defaults={"vat_registered": False, "vat_rate": Decimal("12.00")},
        )

        response = self._post_po(discount="0")

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["vat_rate"], "0.00")
        self.assertEqual(response.data["vat_amount"], "0.00")
        self.assertEqual(response.data["total_amount"], "1000.00")

    def test_discount_above_gross_is_refused_before_anything_is_written(self):
        response = self._post_po(discount="1000.01")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_PO")
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_negative_discount_is_refused(self):
        response = self._post_po(discount="-1")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_PO")
        self.assertEqual(PurchaseOrder.objects.count(), 0)

    def test_computed_money_is_not_client_writable(self):
        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("12.00")}
        )

        response = self._login(self.stocker).post(
            PO_URL,
            {
                "supplier": self.supplier.pk,
                "discount_amount": "0",
                "gross_amount": "1.00",
                "net_amount": "1.00",
                "vatable_amount": "1.00",
                "vat_amount": "1.00",
                "total_amount": "1.00",
                "vat_rate": "0.00",
                "items": [
                    {
                        "variant": self.variant.pk,
                        "ordered_qty": "10",
                        "unit_cost": "100",
                    }
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["gross_amount"], "1000.00")
        self.assertEqual(response.data["total_amount"], "1000.00")
        # The snapshot came from StoreSettings, not from the body.
        self.assertEqual(response.data["vat_rate"], "12.00")

    def test_money_can_only_change_while_the_order_is_a_draft(self):
        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("12.00")}
        )
        po, _item = self._po(status=PurchaseOrder.Status.DRAFT)

        placed = self._login(self.stocker).post(
            f"{PO_URL}{po.pk}/place/", {}, format="json"
        )
        self.assertEqual(placed.status_code, 200, placed.data)

        refused = self._login(self.stocker).patch(
            f"{PO_URL}{po.pk}/", {"discount_amount": "50"}, format="json"
        )

        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "PO_LOCKED")
        po.refresh_from_db()
        self.assertEqual(po.discount_amount, Decimal(0))

    def test_draft_money_edit_keeps_the_rate_snapshot(self):
        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("12.00")}
        )
        create = self._post_po(discount="0")
        self.assertEqual(create.status_code, 201, create.data)
        po_id = create.data["id"]

        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": True, "vat_rate": Decimal("5.00")}
        )
        edited = self._login(self.stocker).patch(
            f"{PO_URL}{po_id}/", {"discount_amount": "50"}, format="json"
        )

        self.assertEqual(edited.status_code, 200, edited.data)
        self.assertEqual(edited.data["vat_rate"], "12.00")
        self.assertEqual(edited.data["discount_amount"], "50.00")


class SupplierTermsTests(PayablesTestBase):
    def test_terms_default_to_zero(self):
        self.assertEqual(self.supplier.terms_days, 0)

    def test_terms_are_editable(self):
        client = self._login(self.stocker)

        response = client.patch(
            f"/api/v1/suppliers/{self.supplier.pk}/", {"terms_days": 30}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.supplier.refresh_from_db()
        self.assertEqual(self.supplier.terms_days, 30)

    def test_negative_terms_are_refused(self):
        client = self._login(self.stocker)

        response = client.patch(
            f"/api/v1/suppliers/{self.supplier.pk}/",
            {"terms_days": -1},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SUPPLIER_TERMS")
        self.supplier.refresh_from_db()
        self.assertEqual(self.supplier.terms_days, 0)


# =========================================================================
# The bill a processed receipt creates
# =========================================================================


class BillCreationTests(PayablesTestBase):
    def test_packaged_receipt_bills_package_qty_times_package_cost(self):
        box, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box"}
        )
        unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=box,
            conversion_factor=Decimal("2.5"),
            default_selling_price=Decimal(300),
        )
        po, item = self._po(ordered="10", cost="250", unit=unit)
        receipt = self._receipt(po, [(item, "4")])

        bill = self._bill(receipt)

        # Stock is 4 packages × 2.5 = 10 base units at 100/base; the BILL is what the
        # shop agreed to pay: 4 × 250 = 1000, not 10 × 250 = 2500.
        batch = InventoryBatch.objects.get(receipt=receipt)
        self.assertEqual(batch.initial_qty, Decimal(10))
        self.assertEqual(batch.unit_cost_landed, Decimal(100))
        self.assertEqual(bill.gross_amount, Decimal("1000.00"))

    def test_partial_receipt_gets_its_proportional_share_of_the_po_discount(self):
        po, item = self._po(ordered="10", cost="100", discount="100", vat_rate="12")
        receipt = self._receipt(po, [(item, "4")])

        bill = self._bill(receipt)

        self.assertEqual(bill.gross_amount, Decimal("400.00"))
        self.assertEqual(bill.discount_amount, Decimal("40.00"))
        self.assertEqual(bill.net_amount, Decimal("360.00"))
        # VAT-inclusive: 360 / 1.12 = 321.428… -> 321.43, remainder is the VAT.
        self.assertEqual(bill.vat_amount, Decimal("38.57"))
        self.assertEqual(bill.total_amount, Decimal("360.00"))
        self.assertEqual(bill.vat_rate, Decimal("12.00"))

    def test_cumulative_fractional_receipts_recover_the_header_discount_exactly(self):
        po, item = self._po(ordered="3", cost="100", discount="100")

        bills = []
        for _ in range(3):
            receipt = self._receipt(po, [(item, "1")])
            bills.append(self._bill(receipt))

        allocated = sum((bill.discount_amount for bill in bills), Decimal(0))
        self.assertEqual(allocated, Decimal("100.00"), bills)
        self.assertEqual(
            [bill.discount_amount for bill in bills],
            [Decimal("33.33"), Decimal("33.34"), Decimal("33.33")],
        )
        self.assertEqual(
            sum((bill.net_amount for bill in bills), Decimal(0)), Decimal("200.00")
        )

    def test_a_receipt_against_a_zero_value_order_cannot_divide_by_zero(self):
        po, item = self._po(ordered="10", cost="0", discount="0")
        receipt = self._receipt(po, [(item, "4")])

        self._process(receipt)

        # Nothing was owed, so no bill is fabricated; the stock still moved.
        self.assertEqual(SupplierBill.objects.count(), 0)
        self.assertEqual(InventoryBatch.objects.filter(receipt=receipt).count(), 1)

    def test_vat_exclusive_bill_adds_vat_to_the_discounted_net(self):
        po, item = self._po(
            ordered="10", cost="100", discount="100", vat_inclusive=False, vat_rate="12"
        )
        receipt = self._receipt(po, [(item, "4")])

        bill = self._bill(receipt)

        self.assertEqual(bill.net_amount, Decimal("360.00"))
        self.assertEqual(bill.vat_amount, Decimal("43.20"))
        self.assertEqual(bill.total_amount, Decimal("403.20"))

    def test_due_date_is_the_receipt_date_plus_the_supplier_terms(self):
        self.supplier.terms_days = 30
        self.supplier.save(update_fields=["terms_days"])
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])

        bill = self._bill(receipt)

        self.assertEqual(bill.received_date, receipt.receive_date)
        self.assertEqual(bill.terms_days, 30)
        self.assertEqual(bill.due_date, receipt.receive_date + timedelta(days=30))

    def test_zero_terms_is_due_on_the_receipt_date(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])

        bill = self._bill(receipt)

        self.assertEqual(bill.due_date, receipt.receive_date)

    def test_a_later_settings_change_rewrites_no_bill(self):
        # The order carries the 12% snapshot it was created with (what the API takes
        # from StoreSettings), and the shop then stops being VAT registered.
        po, item = self._po(ordered="10", cost="100", vat_rate="12")
        bill = self._bill(self._receipt(po, [(item, "4")]))

        StoreSettings.objects.update_or_create(
            pk=1, defaults={"vat_registered": False, "vat_rate": Decimal("0.00")}
        )

        bill.refresh_from_db()
        self.assertEqual(bill.vat_rate, Decimal("12.00"))
        # 400.00 inclusive at 12%: vatable 357.14, VAT 42.86 - unchanged by the setting.
        self.assertEqual(bill.net_amount, Decimal("400.00"))
        self.assertEqual(bill.vat_amount, Decimal("42.86"))

        # The ORDER's snapshot is what the next delivery is billed with, so the
        # remaining receipts of the same order keep the same VAT.
        second_bill = self._bill(self._receipt(po, [(item, "2")]))
        self.assertEqual(second_bill.vat_rate, Decimal("12.00"))
        self.assertEqual(second_bill.vat_amount, Decimal("21.43"))

    def test_reprocessing_creates_no_second_bill(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])
        self._bill(receipt)

        with self.assertRaises(ReceiptAlreadyProcessed):
            self._process(receipt)

        self.assertEqual(SupplierBill.objects.filter(receipt=receipt).count(), 1)

    def test_a_second_bill_row_for_the_same_receipt_is_refused_by_the_database(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])
        self._bill(receipt)

        with self.assertRaises(IntegrityError), transaction.atomic():
            SupplierBill.objects.create(
                receipt=receipt,
                supplier=po.supplier,
                purchase_order=po,
                gross_amount=Decimal(1),
                discount_amount=Decimal(0),
                net_amount=Decimal(1),
                vat_amount=Decimal(0),
                vat_rate=Decimal(0),
                total_amount=Decimal(1),
                balance_amount=Decimal(1),
                received_date=receipt.receive_date,
                terms_days=0,
                due_date=receipt.receive_date,
            )

    def test_a_bill_is_immutable_after_it_exists(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])
        bill = self._bill(receipt)

        bill.total_amount = Decimal("1.00")
        with self.assertRaises(ImmutablePayableRecord):
            bill.save()

        with self.assertRaises(ImmutablePayableRecord):
            bill.delete()

    def test_a_failed_bill_rolls_back_the_batches_and_the_audit_row(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])
        client = self._login(self.stocker)

        with (
            mock.patch(
                "apps.inventory.payables.create_bill_for_receipt",
                side_effect=RuntimeError("bill write failed"),
            ),
            self.assertRaises(RuntimeError),
        ):
            client.post(f"{RECEIPTS_URL}{receipt.pk}/process/", {}, format="json")

        receipt.refresh_from_db()
        self.assertIsNone(receipt.processed_at)
        self.assertEqual(InventoryBatch.objects.filter(receipt=receipt).count(), 0)
        self.assertEqual(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.RECEIPT).count(), 0
        )
        self.assertEqual(SupplierBill.objects.count(), 0)

    def test_an_already_processed_historical_receipt_gets_no_retroactive_bill(self):
        po, item = self._po()
        receipt = self._receipt(po, [(item, "2")])
        GoodsReceipt.objects.filter(pk=receipt.pk).update(processed_at=timezone.now())

        with self.assertRaises(ReceiptAlreadyProcessed):
            self._process(GoodsReceipt.objects.get(pk=receipt.pk))

        self.assertEqual(SupplierBill.objects.count(), 0)

    def test_a_legacy_receipt_without_lines_bills_the_stocked_delta(self):
        po, item = self._po(ordered="10", cost="50")
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        POItem.objects.filter(pk=item.pk).update(received_qty=Decimal(3))

        bill = self._bill(receipt)

        self.assertEqual(bill.gross_amount, Decimal("150.00"))
        self.assertEqual(
            InventoryBatch.objects.get(receipt=receipt).initial_qty, Decimal(3)
        )


# =========================================================================
# Reading bills
# =========================================================================


class BillReadTests(PayablesTestBase):
    def _two_bills(self):
        po, item = self._po(ordered="10", cost="100", discount="0", vat_rate="12")
        first = self._bill(self._receipt(po, [(item, "2")]))
        second = self._bill(self._receipt(po, [(item, "2")]))
        other_supplier = Supplier.objects.create(company_name="Other Supply")
        other_po, other_item = self._po(supplier=other_supplier, cost="10")
        third = self._bill(self._receipt(other_po, [(other_item, "1")]))
        return first, second, third

    def test_list_is_paginated_and_filterable(self):
        first, _second, third = self._two_bills()
        SupplierBill.objects.filter(pk=third.pk).update(
            due_date=first.due_date - timedelta(days=30)
        )
        client = self._login(self.stocker)

        page = client.get(BILLS_URL)
        self.assertEqual(page.status_code, 200, page.data)
        self.assertIn("count", page.data)
        self.assertIn("results", page.data)
        self.assertEqual(page.data["count"], 3)

        by_supplier = client.get(BILLS_URL, {"supplier": self.supplier.pk})
        self.assertEqual(by_supplier.data["count"], 2)

        overdue = client.get(BILLS_URL, {"overdue": "true"})
        self.assertEqual(overdue.data["count"], 1)
        self.assertEqual(overdue.data["results"][0]["id"], third.pk)

        paid = client.get(BILLS_URL, {"status": "PAID"})
        self.assertEqual(paid.data["count"], 0)
        unpaid = client.get(BILLS_URL, {"status": "UNPAID"})
        self.assertEqual(unpaid.data["count"], 3)

        bad = client.get(BILLS_URL, {"status": "NOPE"})
        self.assertEqual(bad.status_code, 400, bad.data)

    def test_detail_carries_the_payment_history(self):
        first, _second, _third = self._two_bills()
        client = self._login(self.manager)
        paid = client.post(
            PAYMENTS_URL,
            {"bill": first.pk, "amount": "50", "method": "CASH", "reference": "CV-1"},
            format="json",
        )
        self.assertEqual(paid.status_code, 201, paid.data)

        detail = self._login(self.stocker).get(f"{BILLS_URL}{first.pk}/")

        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(detail.data["balance_amount"], "150.00")
        self.assertEqual(detail.data["paid_amount"], "50.00")
        self.assertEqual(detail.data["status"], "PARTIAL")
        self.assertEqual(len(detail.data["payments"]), 1)
        self.assertEqual(detail.data["payments"][0]["amount"], "50.00")
        self.assertEqual(detail.data["payments"][0]["method"], "CASH")
        self.assertEqual(detail.data["payments"][0]["reference"], "CV-1")

    def test_per_supplier_aggregate_reads_original_paid_balance_and_overdue(self):
        first, _second, third = self._two_bills()
        SupplierBill.objects.filter(pk=third.pk).update(
            due_date=first.due_date - timedelta(days=30)
        )
        self._login(self.manager).post(
            PAYMENTS_URL,
            {"bill": first.pk, "amount": "50", "method": "CASH"},
            format="json",
        )

        response = self._login(self.stocker).get(SUPPLIERS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        rows = {row["supplier"]: row for row in response.data["results"]}
        ours = rows[self.supplier.pk]
        self.assertEqual(ours["original"], "400.00")
        self.assertEqual(ours["paid"], "50.00")
        self.assertEqual(ours["balance"], "350.00")
        self.assertEqual(ours["overdue"], "0.00")
        other = rows[Supplier.objects.get(company_name="Other Supply").pk]
        self.assertEqual(other["overdue"], "10.00")

    def test_bills_have_no_write_verbs_for_any_role(self):
        po, item = self._po()
        bill = self._bill(self._receipt(po, [(item, "2")]))
        client = self._login(self.admin)

        self.assertEqual(client.post(BILLS_URL, {}, format="json").status_code, 405)
        self.assertEqual(
            client.patch(f"{BILLS_URL}{bill.pk}/", {}, format="json").status_code, 405
        )
        self.assertEqual(client.delete(f"{BILLS_URL}{bill.pk}/").status_code, 405)


# =========================================================================
# Payments
# =========================================================================


class SupplierPaymentTests(PayablesTestBase):
    def setUp(self):
        super().setUp()
        po, item = self._po(ordered="10", cost="100")
        self.bill = self._bill(self._receipt(po, [(item, "2")]))  # 200.00

    def _pay(self, user=None, **body):
        payload = {"bill": self.bill.pk, "amount": "50", "method": "CASH"}
        payload.update(body)
        return self._login(user or self.manager).post(
            PAYMENTS_URL, payload, format="json"
        )

    def test_partial_payment_reduces_the_balance_and_marks_the_bill_partial(self):
        response = self._pay()

        self.assertEqual(response.status_code, 201, response.data)
        self.bill.refresh_from_db()
        self.assertEqual(self.bill.balance_amount, Decimal("150.00"))
        self.assertEqual(self.bill.status, "PARTIAL")
        self.assertEqual(response.data["paid_by"], self.manager.pk)

    def test_a_second_payment_settles_the_bill(self):
        self._pay(amount="200")

        self.bill.refresh_from_db()
        self.assertEqual(self.bill.balance_amount, Decimal("0.00"))
        self.assertEqual(self.bill.status, "PAID")

    def test_overpayment_is_refused_and_writes_nothing(self):
        response = self._pay(amount="200.01")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "OVERPAYMENT")
        self.bill.refresh_from_db()
        self.assertEqual(self.bill.balance_amount, Decimal("200.00"))
        self.assertEqual(SupplierPayment.objects.count(), 0)
        self.assertEqual(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.PAYMENT).count(), 0
        )

    def test_paying_a_settled_bill_is_refused_with_bill_paid(self):
        self._pay(amount="200")

        response = self._pay(amount="1")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "BILL_PAID")
        self.assertEqual(SupplierPayment.objects.count(), 1)

    def test_zero_negative_and_non_finite_amounts_are_refused(self):
        for amount in ("0", "-5", "NaN", "Infinity"):
            with self.subTest(amount=amount):
                response = self._pay(amount=amount)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data["code"], "INVALID_SUPPLIER_PAYMENT", response.data
                )
        self.assertEqual(SupplierPayment.objects.count(), 0)

    def test_a_cheque_needs_its_number_bank_and_date(self):
        for body in (
            {"method": "CHEQUE"},
            {"method": "CHEQUE", "cheque_number": "000123"},
            {"method": "CHEQUE", "cheque_number": "000123", "cheque_bank": "BDO"},
            {
                "method": "CHEQUE",
                "cheque_number": "000123",
                "cheque_date": "2026-11-11",
            },
        ):
            with self.subTest(body=body):
                response = self._pay(**body)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data["code"], "INVALID_SUPPLIER_PAYMENT", response.data
                )

        response = self._pay(
            method="CHEQUE",
            cheque_number="000123",
            cheque_bank="BDO",
            cheque_date="2026-11-11",
            reference="CHK-123",
        )

        self.assertEqual(response.status_code, 201, response.data)
        payment = SupplierPayment.objects.get()
        self.assertEqual(payment.cheque_number, "000123")
        self.assertEqual(payment.cheque_bank, "BDO")
        self.assertIsNotNone(payment.cheque_date)
        # Decision 18: a supplier cheque is recorded as paid when issued.
        self.assertIsNotNone(payment.paid_on)

    def test_bank_transfer_and_unknown_methods(self):
        ok = self._pay(method="BANK_TRANSFER", reference="BT-1")
        self.assertEqual(ok.status_code, 201, ok.data)

        refused = self._pay(bill=self.bill.pk, method="GCASH")
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "INVALID_SUPPLIER_PAYMENT")

    def test_payment_roles(self):
        stocker = self._login(self.stocker)
        cashier = self._login(self.cashier)
        cpms = self._login(self.cpms)

        self.assertEqual(stocker.get(BILLS_URL).status_code, 200)
        self.assertEqual(stocker.get(PAYMENTS_URL).status_code, 200)
        self.assertEqual(
            stocker.post(
                PAYMENTS_URL,
                {"bill": self.bill.pk, "amount": "1", "method": "CASH"},
                format="json",
            ).status_code,
            403,
        )
        self.assertEqual(cashier.get(BILLS_URL).status_code, 403)
        self.assertEqual(cashier.get(PAYMENTS_URL).status_code, 403)
        self.assertEqual(
            cashier.post(
                PAYMENTS_URL,
                {"bill": self.bill.pk, "amount": "1", "method": "CASH"},
                format="json",
            ).status_code,
            403,
        )
        self.assertEqual(cpms.get(BILLS_URL).status_code, 403)
        self.assertEqual(self._pay(user=self.admin).status_code, 201)

    def test_a_payment_is_audited_with_its_actor_and_bill(self):
        self._pay(amount="50")

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.PAYMENT)
        self.assertEqual(row.user_id, self.manager.pk)
        self.assertIn(str(self.bill.pk), row.description)
        self.assertIn("50.00", row.description)

    def test_an_audit_failure_rolls_back_the_payment_and_the_balance(self):
        with (
            mock.patch(
                "apps.inventory.views.audit_request",
                side_effect=RuntimeError("audit down"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self._pay(amount="50")

        self.bill.refresh_from_db()
        self.assertEqual(self.bill.balance_amount, Decimal("200.00"))
        self.assertEqual(SupplierPayment.objects.count(), 0)

    def test_payments_cannot_be_edited_or_deleted(self):
        response = self._pay()
        payment = SupplierPayment.objects.get()
        client = self._login(self.admin)

        self.assertEqual(
            client.patch(f"{PAYMENTS_URL}{payment.pk}/", {}, format="json").status_code,
            405,
        )
        self.assertEqual(
            client.put(f"{PAYMENTS_URL}{payment.pk}/", {}).status_code, 405
        )
        self.assertEqual(client.delete(f"{PAYMENTS_URL}{payment.pk}/").status_code, 405)
        payment.amount = Decimal(1)
        with self.assertRaises(ImmutablePayableRecord):
            payment.save()
        with self.assertRaises(ImmutablePayableRecord):
            payment.delete()
        self.assertEqual(response.status_code, 201)


class ConcurrentPayablesTests(TransactionTestCase):
    """Two writers at once: one receipt, one bill; one balance, one winner.

    `TransactionTestCase` because the worker threads must see each other's COMMITTED
    rows - the wrapped transaction a `TestCase` uses hides them, and the test would then
    pass on timing rather than on the lock.
    """

    def setUp(self):
        self.password = get_random_string(16)
        category = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Rhino")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        product = Product.objects.create(
            category=category, brand=brand, base_name="Cement"
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        self.user = User.objects.create_user(
            username="pay_racer", email="racer@example.com", password=self.password
        )
        self.user.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.supplier = Supplier.objects.create(company_name="Cebu Supply")
        self.po = PurchaseOrder.objects.create(
            supplier=self.supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
            discount_amount=Decimal(10),
            vat_rate=Decimal(12),
        )
        self.item = POItem.objects.create(
            po=self.po,
            variant=variant,
            ordered_qty=Decimal(10),
            unit_cost=Decimal(100),
        )

    def _workers(self, worker, count=2):
        barrier = threading.Barrier(count, timeout=20)
        results = []
        lock = threading.Lock()

        def run():
            try:
                barrier.wait()
                outcome = worker()
                with lock:
                    results.append(outcome)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=run) for _ in range(count)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=40)
        return results

    def test_two_concurrent_process_calls_make_one_bill(self):
        receipt = GoodsReceipt.objects.create(po=self.po, received_by=self.user)
        GoodsReceiptItem.objects.create(
            receipt=receipt, po_item=self.item, qty=Decimal(4)
        )

        def worker():
            try:
                process_goods_receipt(receipt=receipt, user=self.user)
                return "processed"
            except Exception as exc:  # noqa: BLE001 - the refusal is the assertion
                return type(exc).__name__

        results = self._workers(worker)

        self.assertEqual(sorted(results), ["ReceiptAlreadyProcessed", "processed"])
        self.assertEqual(SupplierBill.objects.filter(receipt=receipt).count(), 1)

    def test_two_concurrent_payments_never_overpay(self):
        receipt = GoodsReceipt.objects.create(po=self.po, received_by=self.user)
        GoodsReceiptItem.objects.create(
            receipt=receipt, po_item=self.item, qty=Decimal(2)
        )
        process_goods_receipt(receipt=receipt, user=self.user)
        bill = SupplierBill.objects.get(receipt=receipt)

        from rest_framework.test import APIClient as Client

        login = Client().post(
            LOGIN_URL,
            {"username": self.user.username, "password": self.password},
            format="json",
        )
        auth = {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}

        def worker():
            client = Client()
            return client.post(
                PAYMENTS_URL,
                {"bill": bill.pk, "amount": "100", "method": "CASH"},
                format="json",
                **auth,
            ).status_code

        results = self._workers(worker)

        self.assertEqual(sorted(results), [201, 400], results)
        bill.refresh_from_db()
        self.assertEqual(bill.balance_amount, bill.total_amount - Decimal(100))
        self.assertEqual(SupplierPayment.objects.count(), 1)
