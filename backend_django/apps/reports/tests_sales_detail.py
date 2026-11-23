# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""P1 sales detail reports — item-wise, hourly and cashier-wise.

The locked conventions these tests pin (planning/reports-suite/MAP.md):

* a return/exchange is a NEGATIVE COMPLETED row, so every total includes it signed
  and nothing filters it out;
* discounts are the line's own `item_discount_amount` + its share of the sale discount
  (`cart_discount_amount`);
* COGS is deduction qty x the snapshotted `unit_cost`; a NULL cost is MISSING history,
  reported as such, never priced at zero;
* rows are DRF-paginated 50 per page with a total count (decision 04).
"""

from decimal import Decimal

from apps.inventory.models import UnitOfMeasure, VariantUOM
from apps.pos.models import SalesItem, SalesItemDeduction
from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase

ITEM_WISE_URL = "/api/v1/reports/sales-by-item/"
HOURLY_URL = "/api/v1/reports/sales-by-hour/"
CASHIER_WISE_URL = "/api/v1/reports/sales-by-cashier/"


class SalesDetailReportTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=20, vat_registered=False)
        pc, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece"}
        )
        # One "PC" is 2 base units, so a sale of 1 must report 2 base units.
        self.pair = VariantUOM.objects.create(
            variant=self.variant,
            uom=pc,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal(10),
        )

    def _sell(self, items, paid):
        body = self._sale_body()
        body["items"] = items
        body["payments"] = [{"method": "CASH", "amount_tendered": paid}]
        res = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def _return(self, original_id, unit, qty=1):
        res = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.customer.id,
                "source": "RETURN",
                "original_transaction": original_id,
                "items": [{"variant_id": unit.id, "qty": qty}],
                "payment_method": "CASH",
                "reason": "changed mind",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    # -- item-wise ---------------------------------------------------------
    def test_item_wise_reports_base_units_net_discounts_cogs_and_profit(self):
        # 2 BAG @ 10.00 less a 2.00 line discount -> net 18.00, FIFO 2 x 40.00 = 80.00 COGS.
        self._sell(
            [
                {
                    "variant_id": self.vuom.id,
                    "qty": 2,
                    "discount": {
                        "kind": "AMOUNT",
                        "value": "2.00",
                        "reason": "Promo",
                    },
                }
            ],
            "18.00",
        )
        # 1 PC (conversion 2) @ 10.00 -> 2 base units, FIFO 2 x 40.00 = 80.00 COGS.
        self._sell([{"variant_id": self.pair.id, "qty": 1}], "10.00")

        res = self.client.get(ITEM_WISE_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual(data["count"], 2)
        self.assertEqual(len(data["results"]), 2)
        rows = {row["variant_uom_id"]: row for row in data["results"]}

        bag = rows[self.vuom.id]
        self.assertEqual(Decimal(str(bag["qty_sold"])), Decimal(2))
        self.assertEqual(Decimal(str(bag["qty_base"])), Decimal(2))
        self.assertEqual(Decimal(str(bag["merchandise_gross"])), Decimal("20.00"))
        self.assertEqual(Decimal(str(bag["discounts"])), Decimal("2.00"))
        self.assertEqual(Decimal(str(bag["net_merchandise"])), Decimal("18.00"))
        self.assertEqual(Decimal(str(bag["cogs"])), Decimal("80.00"))
        self.assertEqual(Decimal(str(bag["gross_profit"])), Decimal("-62.00"))
        self.assertEqual(bag["missing_cost_deductions"], 0)

        pair = rows[self.pair.id]
        self.assertEqual(Decimal(str(pair["qty_sold"])), Decimal(1))
        self.assertEqual(Decimal(str(pair["qty_base"])), Decimal(2))
        self.assertEqual(Decimal(str(pair["net_merchandise"])), Decimal("10.00"))
        self.assertEqual(Decimal(str(pair["cogs"])), Decimal("80.00"))

        totals = data["totals"]
        self.assertEqual(Decimal(str(totals["qty_base"])), Decimal(4))
        self.assertEqual(Decimal(str(totals["net_merchandise"])), Decimal("28.00"))
        self.assertEqual(Decimal(str(totals["cogs"])), Decimal("160.00"))
        self.assertEqual(Decimal(str(totals["gross_profit"])), Decimal("-132.00"))
        self.assertEqual(totals["missing_cost_deductions"], 0)

    def test_item_wise_null_unit_cost_is_missing_not_zero(self):
        self._sell([{"variant_id": self.vuom.id, "qty": 1}], "10.00")
        SalesItemDeduction.objects.filter(sales_item=SalesItem.objects.get()).update(
            unit_cost=None
        )

        res = self.client.get(ITEM_WISE_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        row = data["results"][0]
        self.assertIsNone(row["cogs"])
        self.assertIsNone(row["gross_profit"])
        self.assertEqual(row["missing_cost_deductions"], 1)
        self.assertIsNone(data["totals"]["cogs"])

    # -- hourly ------------------------------------------------------------
    def test_hourly_buckets_include_the_signed_return(self):
        self._sell([{"variant_id": self.vuom.id, "qty": 2}], "20.00")
        original = self._sell([{"variant_id": self.vuom.id, "qty": 1}], "10.00")
        self._return(original["id"], self.vuom)

        res = self.client.get(HOURLY_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual([row["hour"] for row in data["results"]], list(range(24)))
        self.assertEqual(data["count"], 24)
        self.assertEqual(Decimal(str(data["totals"]["invoice_total"])), Decimal("20.00"))
        self.assertEqual(data["totals"]["transactions"], 3)

        active = [row for row in data["results"] if row["transactions"]]
        self.assertEqual(len(active), 1)
        self.assertEqual(active[0]["transactions"], 3)
        self.assertEqual(Decimal(str(active[0]["invoice_total"])), Decimal("20.00"))

    # -- cashier-wise ------------------------------------------------------
    def test_cashier_wise_totals_are_signed_and_discounts_come_from_lines(self):
        original = self._sell(
            [
                {
                    "variant_id": self.vuom.id,
                    "qty": 2,
                    "discount": {
                        "kind": "AMOUNT",
                        "value": "2.00",
                        "reason": "Promo",
                    },
                }
            ],
            "18.00",
        )
        self._sell([{"variant_id": self.vuom.id, "qty": 1}], "10.00")
        # The discounted line refunds its own net per unit: 18.00 / 2 = 9.00.
        self._return(original["id"], self.vuom)

        res = self.client.get(CASHIER_WISE_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual(data["count"], 1)
        row = data["results"][0]
        self.assertEqual(row["cashier_id"], self.cashier.id)
        self.assertEqual(row["cashier_name"], "Cashy Ir")
        self.assertEqual(row["transactions"], 3)
        self.assertEqual(Decimal(str(row["invoice_total"])), Decimal("19.00"))
        self.assertEqual(Decimal(str(row["discounts"])), Decimal("2.00"))
        self.assertEqual(Decimal(str(data["totals"]["invoice_total"])), Decimal("19.00"))
        self.assertEqual(Decimal(str(data["totals"]["discounts"])), Decimal("2.00"))

    # -- shared behaviour --------------------------------------------------
    def test_all_three_reports_refuse_a_malformed_date(self):
        for url in (ITEM_WISE_URL, HOURLY_URL, CASHIER_WISE_URL):
            res = self.client.get(f"{url}?from=nope", **self.admin_auth)
            self.assertEqual(res.status_code, 400, url)

    def test_all_three_reports_are_manager_only(self):
        for url in (ITEM_WISE_URL, HOURLY_URL, CASHIER_WISE_URL):
            res = self.client.get(url, **self.cashier_auth)
            self.assertEqual(res.status_code, 403, url)
