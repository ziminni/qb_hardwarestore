# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Phase 4 tests: held cart stock reservation with expiry + FIFO batch visibility."""

from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from apps.pos.models import HeldCart
from apps.pos.tests_discount_vat import (
    HELD_CARTS_URL,
    SETTINGS_URL,
    TRANSACTIONS_URL,
    DiscountVATBase,
)


class HeldCartReservationAndFifoTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=10, vat_registered=False)

    def _hold(self, qty):
        return self.client.post(
            HELD_CARTS_URL,
            {
                "customer": self.customer.id,
                "notes": "Customer fetching wallet",
                "items": [
                    {
                        "variant_uom": self.vuom.id,
                        "qty": str(qty),
                        "unit_price": "10.00",
                    }
                ],
            },
            format="json",
            **self.cashier_auth,
        )

    def test_held_cart_reserves_stock_and_blocks_oversell_until_completed_or_expired(self):
        # POSTestBase starts with 10 units of self.vuom in stock.
        # Hold 8 units -> 2 units remain available.
        held = self._hold(8)
        self.assertEqual(held.status_code, 201, held.content)
        held_data = held.json()
        self.assertIsNotNone(held_data["expires_at"])
        self.assertIs(held_data["is_expired"], False)

        # Another sale asking for 3 units must be refused (only 2 unreserved).
        body = self._sale_body()
        body["items"] = [{"variant_id": self.vuom.id, "qty": 3}]
        body["payments"] = [{"method": "CASH", "amount_tendered": "30.00"}]
        blocked = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(blocked.status_code, 400, blocked.content)
        self.assertEqual(blocked.json()["code"], "INSUFFICIENT_STOCK")

        # Holding 3 more units must also be refused.
        blocked_hold = self._hold(3)
        self.assertEqual(blocked_hold.status_code, 400, blocked_hold.content)

        # Completing the held cart itself succeeds (its own reservation is excluded).
        completed = self.client.post(
            f"{HELD_CARTS_URL}{held_data['id']}/complete/",
            {"payments": [{"method": "CASH", "amount_tendered": "80.00"}]},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(completed.status_code, 201, completed.content)
        # Sale response exposes FIFO batch deductions on each line item!
        line = completed.json()["items"][0]
        self.assertIn("fifo_batches", line)
        self.assertGreaterEqual(len(line["fifo_batches"]), 1)
        total_deducted = sum(Decimal(b["qty"]) for b in line["fifo_batches"])
        self.assertEqual(total_deducted, Decimal("8.00"))

    def test_expired_held_cart_releases_stock_automatically(self):
        held = self._hold(9)
        self.assertEqual(held.status_code, 201, held.content)
        cart = HeldCart.objects.get(pk=held.json()["id"])
        cart.expires_at = timezone.now() - timedelta(minutes=1)
        cart.save(update_fields=["expires_at"])

        # Now a walk-in sale for 5 units succeeds because the hold expired!
        body = self._sale_body()
        body["items"] = [{"variant_id": self.vuom.id, "qty": 5}]
        body["payments"] = [{"method": "CASH", "amount_tendered": "50.00"}]
        res = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(res.status_code, 201, res.content)

    def test_admin_can_configure_held_cart_expiry_minutes(self):
        patch = self.client.patch(
            SETTINGS_URL,
            {"held_cart_expiry_minutes": 45},
            format="json",
            **self.admin_auth,
        )
        self.assertEqual(patch.status_code, 200, patch.content)
        self.assertEqual(patch.json()["held_cart_expiry_minutes"], 45)

        bad = self.client.patch(
            SETTINGS_URL,
            {"held_cart_expiry_minutes": 2},
            format="json",
            **self.admin_auth,
        )
        self.assertEqual(bad.status_code, 400)
