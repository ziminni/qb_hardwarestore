# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Tests for voiding completed POS sales (POST /api/v1/transactions/{id}/void/)."""

from decimal import Decimal

from django.db.models import Sum

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.inventory.models import InventoryBatch
from apps.pos.models import Customer, SalesTransaction
from apps.pos.services import compute_z_reading
from apps.pos.tests_discount_vat import DiscountVATBase

TXN_URL = "/api/v1/transactions/"
SHIFTS_URL = "/api/v1/shifts/"


class VoidSaleTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=10, vat_registered=True)
        self.named_customer = Customer.objects.create(
            name="Mang Jose Builders",
            customer_type=Customer.Type.CONTRACTOR,
            total_credit_limit=Decimal("5000.00"),
        )

    def _stock_total(self):
        return InventoryBatch.objects.filter(variant=self.variant).aggregate(
            total=Sum("current_qty")
        )["total"] or Decimal("0.00")

    def _sell(self, *, customer_id=None, qty="2", paid="20.00", credit_sale=False):
        payload = {
            "customer": customer_id or self.customer.id,
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payments": [{"method": "CASH", "amount_tendered": paid}]
            if Decimal(paid) > 0
            else [],
            "credit_sale": credit_sale,
        }
        res = self.client.post(TXN_URL, payload, format="json", **self.cashier_auth)
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def test_void_restores_stock_updates_z_reading_and_appears_in_voids_report(self):
        before_qty = self._stock_total()
        sale = self._sell(qty="7", paid="70.00")
        self.assertEqual(self._stock_total(), before_qty - Decimal("7.00"))

        z_before = compute_z_reading(self.shift)
        self.assertEqual(Decimal(z_before["gross_sales"]), Decimal("70.00"))

        res = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "Customer changed mind at counter"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 200, res.content)
        body = res.json()
        self.assertEqual(body["status"], SalesTransaction.Status.VOID)
        self.assertIn("Customer changed mind at counter", body["notes"])

        # Both FIFO batches restored to exact original total.
        self.assertEqual(self._stock_total(), before_qty)

        # Shift Z-reading excludes voided sale completely.
        z_after = compute_z_reading(self.shift)
        self.assertEqual(Decimal(z_after["gross_sales"]), Decimal("0.00"))
        self.assertEqual(Decimal(z_after["cash_sales"]), Decimal("0.00"))
        self.assertEqual(
            Decimal(z_after["expected_drawer"]),
            self.shift.opening_float,
        )

        # Voids report includes this voided sale.
        rep = self.client.get("/api/v1/reports/voids/", **self.manager_auth)
        self.assertEqual(rep.status_code, 200, rep.content)
        rows = rep.json().get("results", [])
        self.assertTrue(
            any(r["transaction_no"] == sale["transaction_no"] for r in rows),
            rows,
        )

        # Voiding a second time is rejected as conflict.
        again = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "Duplicate void attempt"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(again.status_code, 409, again.content)
        self.assertEqual(again.json()["code"], "VOID_NOT_COMPLETED")

    def test_void_requires_reason(self):
        sale = self._sell(qty="1", paid="10.00")
        res = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "   "},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()["code"], "VOID_REASON_REQUIRED")

    def test_void_reverses_uncollected_utang_ledger_and_blocks_if_paid(self):
        sale = self._sell(
            customer_id=self.named_customer.id,
            qty="2",
            paid="5.00",
            credit_sale=True,
        )
        self.assertEqual(
            CollectibleLedger.objects.filter(transaction_id=sale["id"]).count(), 1
        )

        # Void removes the uncollected utang ledger.
        res = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "Wrong customer account"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(
            CollectibleLedger.objects.filter(transaction_id=sale["id"]).count(), 0
        )

        # If a collectible payment was already recorded, void must be blocked.
        sale2 = self._sell(
            customer_id=self.named_customer.id,
            qty="2",
            paid="5.00",
            credit_sale=True,
        )
        ledger = CollectibleLedger.objects.get(transaction_id=sale2["id"])
        CollectiblePayment.objects.create(
            collectible=ledger,
            amount_paid=Decimal("5.00"),
            payment_method="CASH",
            processed_by=self.cashier,
        )
        blocked = self.client.post(
            f"{TXN_URL}{sale2['id']}/void/",
            {"reason": "Should fail"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(blocked.status_code, 409, blocked.content)
        self.assertEqual(blocked.json()["code"], "VOID_LEDGER_HAS_PAYMENTS")

    def test_closed_shift_void_requires_manager(self):
        sale = self._sell(qty="1", paid="10.00")
        close = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/close/",
            {"closing_count": "5010.00"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(close.status_code, 200, close.content)

        # Cashier cannot void a sale from a closed shift.
        refused = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "Late void"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(refused.status_code, 403, refused.content)
        self.assertEqual(refused.json()["code"], "VOID_SHIFT_CLOSED")

        # Manager can void it.
        allowed = self.client.post(
            f"{TXN_URL}{sale['id']}/void/",
            {"reason": "Manager approved void"},
            format="json",
            **self.manager_auth,
        )
        self.assertEqual(allowed.status_code, 200, allowed.content)
        self.assertEqual(allowed.json()["status"], SalesTransaction.Status.VOID)
