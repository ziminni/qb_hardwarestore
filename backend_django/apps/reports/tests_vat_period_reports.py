# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Phase 6 tests: daily/weekly/monthly reports and OR-backed vs untagged VAT split."""

from decimal import Decimal

from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase

SALES_SUMMARY_URL = "/api/v1/reports/sales-summary/"
VAT_SUMMARY_URL = "/api/v1/reports/vat-summary/"


class VatAndPeriodReportTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=10, vat_registered=True, vat_rate=12)

    def _sell(self, qty, paid, invoice_no=""):
        body = self._sale_body()
        body["items"] = [{"variant_id": self.vuom.id, "qty": qty}]
        body["payments"] = [{"method": "CASH", "amount_tendered": paid}]
        if invoice_no:
            body["invoice_no"] = invoice_no
        res = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def test_vat_summary_splits_or_backed_and_untagged_os(self):
        # Sale 1: OR-backed (2 x 10.00 = 20.00 -> vatable 17.86, VAT 2.14)
        self._sell(2, "20.00", invoice_no="INV-2026-0001")
        # Sale 2: Untagged OS (3 x 10.00 = 30.00 -> vatable 26.79, VAT 3.21)
        self._sell(3, "30.00")

        for gran in ("day", "week", "month"):
            res = self.client.get(
                f"{VAT_SUMMARY_URL}?granularity={gran}", **self.admin_auth
            )
            self.assertEqual(res.status_code, 200, res.content)
            data = res.json()
            self.assertEqual(data["granularity"], gran)
            self.assertEqual(data["totals"]["or_backed"]["transactions"], 1)
            self.assertEqual(
                Decimal(str(data["totals"]["or_backed"]["vat"])), Decimal("2.14")
            )
            self.assertEqual(data["totals"]["untagged_os"]["transactions"], 1)
            self.assertEqual(
                Decimal(str(data["totals"]["untagged_os"]["vat"])), Decimal("3.21")
            )
            self.assertEqual(len(data["or_transactions"]), 1)
            self.assertEqual(data["or_transactions"][0]["invoice_no"], "INV-2026-0001")
            self.assertEqual(len(data["by_period"]), 1)

        # sales-summary also carries or_vat_breakdown and by_payment_method.
        sales = self.client.get(
            f"{SALES_SUMMARY_URL}?granularity=month", **self.admin_auth
        )
        self.assertEqual(sales.status_code, 200, sales.content)
        sdata = sales.json()
        self.assertEqual(sdata["granularity"], "month")
        self.assertEqual(sdata["or_vat_breakdown"]["or_backed"]["transactions"], 1)
        self.assertEqual(sdata["or_vat_breakdown"]["untagged_os"]["transactions"], 1)
        self.assertEqual(sdata["by_payment_method"][0]["method"], "CASH")
        self.assertEqual(
            Decimal(str(sdata["by_payment_method"][0]["total"])), Decimal("50.00")
        )
