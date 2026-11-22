# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Phase 5 tests: cash drawer denomination count, categorised cash-outs, store-day summary."""

from decimal import Decimal

from apps.pos.tests_discount_vat import DiscountVATBase

SHIFTS_URL = "/api/v1/shifts/"


class CashDrawerPhase5Tests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=10, vat_registered=False)

    def test_categorised_cash_outs_and_denomination_close(self):
        # Record two categorised cash-outs on the open shift.
        r1 = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {
                "kind": "CASH_OUT",
                "category": "LUNCH",
                "amount": "150.00",
                "reason": "Staff lunch",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(r1.status_code, 201, r1.content)
        r2 = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {
                "kind": "CASH_OUT",
                "category": "FUEL",
                "amount": "200.00",
                "reason": "Delivery truck diesel",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(r2.status_code, 201, r2.content)

        # Close shift using PHP denominations (1x1000 + 1x500 + 3x50 = 1650.00).
        closed = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/close/",
            {
                "closing_count": "1650.00",
                "denominations": {"1000": 1, "500": 1, "50": 3},
                "cash_left": "500.00",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(closed.status_code, 200, closed.content)
        data = closed.json()
        self.assertEqual(Decimal(data["closing_count"]), Decimal("1650.00"))
        self.assertEqual(data["denomination_counts"], {"1000": 1, "500": 1, "50": 3})
        z = data["z_reading"]
        self.assertEqual(z["cash_out_by_category"]["LUNCH"], "150.00")
        self.assertEqual(z["cash_out_by_category"]["FUEL"], "200.00")
        self.assertEqual(z["denomination_counts"], {"1000": 1, "500": 1, "50": 3})

        # Store-day summary aggregates the day's shifts and categories.
        day = self.client.get(f"{SHIFTS_URL}store-day/", **self.cashier_auth)
        self.assertEqual(day.status_code, 200, day.content)
        day_data = day.json()
        self.assertEqual(day_data["shift_count"], 1)
        self.assertEqual(day_data["closed_shift_count"], 1)
        self.assertEqual(day_data["cash_out_by_category"]["LUNCH"], "150.00")
        self.assertEqual(day_data["cash_out_by_category"]["FUEL"], "200.00")

    def test_invalid_denomination_is_refused(self):
        bad = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/close/",
            {
                "closing_count": "100.00",
                "denominations": {"999": 1},
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(bad.status_code, 400)
        self.assertEqual(bad.json()["code"], "INVALID_DENOMINATIONS")
