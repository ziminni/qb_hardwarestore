"""Report accuracy found by the 2026-11-27 walkthrough.

* profit is measured on revenue WITHOUT VAT in every report, and a non-VAT store's
  revenue is its whole net (it used to read as zero, so profit = minus COGS);
* bill-wise and the summary's payment split add up to the sales total: change comes
  off the cash, and what nobody paid at the counter shows as ON_ACCOUNT;
* inventory value at retail uses today's shelf price, not the cost stamped on the batch.
"""

from decimal import Decimal

from apps.inventory.models import InventoryBatch
from apps.pos.models import Customer
from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase

SUMMARY_URL = "/api/v1/reports/sales-summary/"
ITEM_WISE_URL = "/api/v1/reports/sales-by-item/"
BILL_WISE_URL = "/api/v1/reports/bill-wise/"
VALUATION_URL = "/api/v1/reports/inventory-valuation/"
ADMIN_DASHBOARD_URL = "/api/v1/reports/admin-dashboard/"


class ReportAccuracyTests(DiscountVATBase):
    def _sell(self, qty, paid, customer=None, credit=False):
        body = self._sale_body()
        body["items"] = [{"variant_id": self.vuom.id, "qty": qty}]
        body["payments"] = [{"method": "CASH", "amount_tendered": paid}]
        if customer is not None:
            body["customer"] = customer
        if credit:
            body["credit_sale"] = True
        res = self.client.post(TRANSACTIONS_URL, body, format="json", **self.cashier_auth)
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def _price(self):
        return Decimal(str(self.vuom.default_selling_price))

    def _cogs(self, data):
        return Decimal(str(data["totals"]["cogs"]))

    def test_vat_store_profit_is_the_same_in_summary_and_item_wise(self):
        self._settings(discount_cap_percent=20, vat_registered=True, vat_rate=Decimal("12"))
        self._sell(2, str(self._price() * 2))
        summary = self.client.get(SUMMARY_URL, **self.admin_auth).json()
        items = self.client.get(ITEM_WISE_URL, **self.admin_auth).json()
        net_ex_vat = (self._price() * 2 * 100 / 112).quantize(Decimal("0.01"))
        expected = net_ex_vat - self._cogs(items)
        self.assertEqual(Decimal(str(summary["totals"]["gross_profit"])), expected)
        self.assertEqual(Decimal(str(items["totals"]["gross_profit"])), expected)
        self.assertEqual(Decimal(str(items["results"][0]["net_ex_vat"])), net_ex_vat)

    def test_non_vat_store_profit_uses_the_whole_net(self):
        self._settings(discount_cap_percent=20, vat_registered=False)
        self._sell(2, str(self._price() * 2))
        summary = self.client.get(SUMMARY_URL, **self.admin_auth).json()
        net = self._price() * 2
        self.assertEqual(Decimal(str(summary["totals"]["merchandise_net_ex_vat"])), net)
        self.assertEqual(
            Decimal(str(summary["totals"]["gross_profit"])), net - self._cogs(summary)
        )

    def test_tenders_add_up_to_the_total_with_change_and_utang(self):
        self._settings(discount_cap_percent=20, vat_registered=True, vat_rate=Decimal("12"))
        price = self._price()
        # Cash sale with change.
        self._sell(1, str(price + 50))
        # A named customer takes one on credit, paying nothing now.
        named = Customer.objects.create(
            name="Ana Reyes", customer_type=Customer.Type.REGULAR,
            total_credit_limit=Decimal("100000"),
        )
        self._sell(1, "0.00", customer=named.id, credit=True)

        bills = self.client.get(BILL_WISE_URL, **self.admin_auth).json()
        methods = {k: Decimal(str(v)) for k, v in bills["totals"]["methods"].items()}
        self.assertEqual(sum(methods.values()), Decimal(str(bills["totals"]["grand_total"])))
        self.assertGreater(methods["ON_ACCOUNT"], 0)

        summary = self.client.get(SUMMARY_URL, **self.admin_auth).json()
        split = {row["method"]: Decimal(str(row["total"])) for row in summary["by_payment_method"]}
        self.assertEqual(sum(split.values()), Decimal(str(summary["totals"]["gross_sales"])))
        self.assertEqual(split["CASH"], price)

    def test_value_at_retail_uses_the_shelf_price(self):
        batch = InventoryBatch.objects.filter(variant=self.vuom.variant, current_qty__gt=0).first()
        InventoryBatch.objects.filter(pk=batch.pk).update(
            batch_selling_price=batch.unit_cost_landed
        )
        data = self.client.get(VALUATION_URL, **self.admin_auth).json()
        on_hand = sum(
            (b.current_qty for b in InventoryBatch.objects.filter(current_qty__gt=0)),
            Decimal(0),
        )
        self.assertEqual(
            Decimal(str(data["totals"]["total_retail_value"])),
            on_hand * self._price(),
        )

    def test_admin_dashboard_cash_is_net_of_change(self):
        price = self._price()
        self._sell(1, str(price + 50))
        data = self.client.get(ADMIN_DASHBOARD_URL, **self.admin_auth).json()
        cash = [
            row for row in data["sales"]["by_payment_method_month"]
            if row["method"] == "CASH"
        ]
        self.assertEqual(Decimal(cash[0]["total"]), price)
