# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""P1 sales detail reports, second half — bill-wise, returns/exchanges, discounts, voids.

The locked conventions these tests pin (planning/reports-suite/MAP.md):

* a return/exchange is a NEGATIVE `SalesTransaction` row (source RETURN/EXCHANGE), so a
  bill listing keeps it signed and nothing re-filters the completed rows;
* the return/exchange reason is the reversal row's `notes`;
* discounts are the lines' own `item_discount_amount` (LINE) and `cart_discount_amount`
  (CART); an APPROVAL row is the cart discount on the sales a manager signed off, so it
  is a SUBSET of CART and is never added to it again;
* rows are DRF-paginated 50 per page with report totals outside them (decision 04).
"""

from decimal import Decimal

from apps.pos.models import DiscountApproval, SalesTransaction
from apps.pos.services import process_exchange
from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase

BILLS_URL = "/api/v1/reports/bill-wise/"
RETURNS_URL = "/api/v1/reports/returns-exchanges/"
DISCOUNTS_URL = "/api/v1/reports/discounts/"
VOIDS_URL = "/api/v1/reports/voids/"


class SalesDetail2ReportTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(
            discount_cap_percent=50, shift_discount_cap_percent=50, vat_registered=False
        )

    def _sell(self, *, qty=1, discount=None, approval=None, payments=None, items=None):
        body = self._sale_body(
            qty=qty, discount=discount, approval=approval, payments=payments
        )
        if items is not None:
            body["items"] = items
        res = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def _return(self, original_id, *, qty=1, reason="changed mind"):
        res = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.customer.id,
                "source": "RETURN",
                "original_transaction": original_id,
                "items": [{"variant_id": self.vuom.id, "qty": qty}],
                "payment_method": "CASH",
                "reason": reason,
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def _exchange(self, original_id, *, reason="size swap"):
        # Even swap: the returned unit and the replacement both ring at 10.00.
        return process_exchange(
            customer_id=self.customer.id,
            cashier=self.cashier,
            original_transaction_id=original_id,
            return_items_data=[{"variant_id": self.vuom.id, "qty": 1}],
            replacement_items_data=[{"variant_id": self.vuom.id, "qty": 1}],
            payment_method="CASH",
            reason=reason,
        )

    # -- bill-wise ---------------------------------------------------------
    def test_bill_wise_one_signed_row_per_completed_bill(self):
        first = self._sell(qty=1)
        second = self._sell(
            qty=2,
            discount={"kind": "AMOUNT", "value": "2.00", "reason": "Promo"},
        )
        ret = self._return(first["id"])

        res = self.client.get(BILLS_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual(data["count"], 3)
        self.assertEqual(len(data["results"]), 3)
        rows = {row["id"]: row for row in data["results"]}

        # The return keeps its negative total: it is a bill, signed as stored.
        self.assertEqual(rows[ret["id"]]["source"], "RETURN")
        self.assertEqual(
            Decimal(str(rows[ret["id"]]["grand_total"])), Decimal("-10.00")
        )
        self.assertEqual(rows[ret["id"]]["original_transaction_id"], first["id"])

        sale = rows[second["id"]]
        self.assertEqual(sale["source"], "WALK_IN")
        self.assertEqual(sale["cashier_id"], self.cashier.id)
        self.assertEqual(sale["cashier_name"], "Cashy Ir")
        self.assertEqual(Decimal(str(sale["discount"])), Decimal("2.00"))
        self.assertEqual(Decimal(str(sale["grand_total"])), Decimal("18.00"))
        self.assertEqual(Decimal(str(sale["methods"]["CASH"])), Decimal("18.00"))
        self.assertTrue(sale["or_number"])
        self.assertTrue(sale["date"])

        totals = data["totals"]
        self.assertEqual(totals["transactions"], 3)
        self.assertEqual(Decimal(str(totals["discount"])), Decimal("2.00"))
        self.assertEqual(Decimal(str(totals["grand_total"])), Decimal("18.00"))
        self.assertEqual(Decimal(str(totals["methods"]["CASH"])), Decimal("18.00"))

        # The OR number is the paper receipt's, not the transaction number.
        receipt_or = SalesTransaction.objects.get(pk=second["id"]).receipt.or_number
        self.assertEqual(sale["or_number"], receipt_or)

    def test_bill_wise_splits_method_totals_per_bill(self):
        self._sell(
            qty=2,
            payments=[
                {"method": "CASH", "amount_tendered": "10.00"},
                {"method": "GCASH", "amount_tendered": "10.00"},
            ],
        )

        data = self.client.get(BILLS_URL, **self.admin_auth).json()
        row = data["results"][0]
        self.assertEqual(Decimal(str(row["methods"]["CASH"])), Decimal("10.00"))
        self.assertEqual(Decimal(str(row["methods"]["GCASH"])), Decimal("10.00"))
        self.assertEqual(
            Decimal(str(data["totals"]["methods"]["GCASH"])), Decimal("10.00")
        )

    # -- returns & exchanges ----------------------------------------------
    def test_returns_report_lists_only_reversals_with_link_amount_and_reason(self):
        original = self._sell(qty=2)
        self._sell(qty=1)  # an ordinary sale that must not appear
        self._return(original["id"], reason="changed mind")
        self._exchange(original["id"], reason="size swap")

        res = self.client.get(RETURNS_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual(data["count"], 2)
        by_source = {row["source"]: row for row in data["results"]}
        self.assertEqual(set(by_source), {"RETURN", "EXCHANGE"})

        ret = by_source["RETURN"]
        self.assertEqual(ret["original_transaction_id"], original["id"])
        self.assertEqual(
            ret["original_transaction_no"],
            SalesTransaction.objects.get(pk=original["id"]).transaction_no,
        )
        self.assertEqual(Decimal(str(ret["refunded"])), Decimal("10.00"))
        self.assertEqual(ret["reason"], "changed mind")

        exchange = by_source["EXCHANGE"]
        self.assertEqual(Decimal(str(exchange["refunded"])), Decimal("0.00"))
        self.assertEqual(exchange["reason"], "size swap")
        self.assertEqual(exchange["original_transaction_id"], original["id"])

        totals = data["totals"]
        self.assertEqual(totals["returns"], 1)
        self.assertEqual(totals["exchanges"], 1)
        self.assertEqual(Decimal(str(totals["refunded"])), Decimal("10.00"))

    # -- discounts ---------------------------------------------------------
    def test_discounts_report_splits_line_cart_and_approved_discounts(self):
        # LINE: 2.00 off one line. CART: 10% of 20.00 = 2.00. APPROVAL: above the cap.
        self._sell(
            items=[
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
            payments=[{"method": "CASH", "amount_tendered": "18.00"}],
        )
        self._sell(
            qty=2,
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Loyalty"},
        )
        self._settings(discount_cap_percent=10)
        token = self._approve(percent="15.00").json()["token"]
        self._sell(
            qty=2,
            discount={"kind": "PERCENT", "value": "15.00", "reason": "Bulk"},
            approval=token,
        )
        self.assertEqual(
            DiscountApproval.objects.filter(used_at__isnull=False).count(), 1
        )

        res = self.client.get(DISCOUNTS_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        rows = {row["type"]: row for row in data["results"]}

        line = rows["LINE"]
        self.assertEqual(line["transactions"], 1)
        self.assertEqual(Decimal(str(line["total_discount"])), Decimal("2.00"))

        cart = rows["CART"]
        self.assertEqual(cart["transactions"], 2)
        self.assertEqual(Decimal(str(cart["total_discount"])), Decimal("5.00"))

        approval = rows["APPROVAL"]
        self.assertEqual(approval["transactions"], 1)
        self.assertEqual(Decimal(str(approval["total_discount"])), Decimal("3.00"))
        self.assertEqual(approval["approvals"], 1)

        totals = data["totals"]
        self.assertEqual(Decimal(str(totals["line_discount"])), Decimal("2.00"))
        self.assertEqual(Decimal(str(totals["cart_discount"])), Decimal("5.00"))
        self.assertEqual(Decimal(str(totals["approval_discount"])), Decimal("3.00"))
        # The approval is WHY part of the cart discount happened, not extra money.
        self.assertEqual(Decimal(str(totals["total_discount"])), Decimal("7.00"))

    def test_discounts_report_is_empty_when_nothing_was_discounted(self):
        self._sell(qty=1)

        data = self.client.get(DISCOUNTS_URL, **self.admin_auth).json()
        self.assertEqual(data["count"], 0)
        self.assertEqual(data["results"], [])
        self.assertEqual(Decimal(str(data["totals"]["total_discount"])), Decimal(0))

    # -- voids -------------------------------------------------------------
    def test_voids_report_lists_void_rows_with_reason_and_total(self):
        voided = self._sell(qty=1)
        self._sell(qty=1)
        SalesTransaction.objects.filter(pk=voided["id"]).update(
            status=SalesTransaction.Status.VOID, notes="wrong item rung"
        )

        res = self.client.get(VOIDS_URL, **self.admin_auth)
        self.assertEqual(res.status_code, 200, res.content)
        data = res.json()
        self.assertEqual(data["count"], 1)
        row = data["results"][0]
        self.assertEqual(row["id"], voided["id"])
        self.assertEqual(row["cashier_id"], self.cashier.id)
        self.assertEqual(row["cashier_name"], "Cashy Ir")
        self.assertEqual(Decimal(str(row["voided_total"])), Decimal("10.00"))
        self.assertEqual(row["reason"], "wrong item rung")
        self.assertTrue(row["date"])
        self.assertEqual(Decimal(str(data["totals"]["voided_total"])), Decimal("10.00"))

    # -- shared behaviour --------------------------------------------------
    def test_all_four_reports_respect_the_date_range(self):
        self._sell(qty=1)

        for url in (BILLS_URL, RETURNS_URL, DISCOUNTS_URL, VOIDS_URL):
            data = self.client.get(
                f"{url}?from=2019-01-01&to=2019-01-31", **self.admin_auth
            ).json()
            self.assertEqual(data["count"], 0, url)
            self.assertEqual(data["results"], [], url)

    def test_all_four_reports_use_drf_pagination(self):
        # Written straight to the table: the fixture only stocks 10 units, and this test
        # is about the 50-row page split, not about ringing 51 sales.
        for index in range(51):
            SalesTransaction.objects.create(
                customer=self.customer,
                cashier=self.cashier,
                transaction_no=f"PAGE{index:03d}",
                grand_total=Decimal("1.00"),
            )

        data = self.client.get(BILLS_URL, **self.admin_auth).json()
        self.assertEqual(data["count"], 51)
        self.assertEqual(len(data["results"]), 50)
        self.assertTrue(data["next"])
        self.assertIsNone(data["previous"])

    def test_all_four_reports_refuse_a_malformed_date(self):
        for url in (BILLS_URL, RETURNS_URL, DISCOUNTS_URL, VOIDS_URL):
            res = self.client.get(f"{url}?from=nope", **self.admin_auth)
            self.assertEqual(res.status_code, 400, url)

    def test_all_four_reports_are_manager_only(self):
        for url in (BILLS_URL, RETURNS_URL, DISCOUNTS_URL, VOIDS_URL):
            res = self.client.get(url, **self.cashier_auth)
            self.assertEqual(res.status_code, 403, url)
