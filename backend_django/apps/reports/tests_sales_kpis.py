# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/reports/tests.py: the checker runs with a working
# directory outside the repo, so no pyrightconfig is found and every `Model.objects`
# access reads as a type error on valid Django. The test run is the authority.

"""The three unit-economics KPIs on the sales summary: ABV, ASP and markdown %.

ABV (average bill value) is what a till ticket is worth, so a signed return row must
lower it — the report never pretends the return did not happen. ASP (average selling
price) divides merchandise net by BASE units, so a box of 2 bags is 2 in the divisor.
Markdown % is the share of the merchandise gross the shop chose not to charge.

Every denominator that can be zero yields None, never 0: an empty day and a freebie
are different facts and must not read the same.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase

from apps.pos.models import Customer, SalesItem, SalesTransaction

User = get_user_model()

SALES_SUMMARY_URL = "/api/v1/reports/sales-summary/"
LOGIN_URL = "/api/v1/auth/login/"
PASSWORD = "kpi-pass-12345"  # nosemgrep: python.lang.security.audit.hardcoded-password
# A throwaway login for a per-run test database: nothing outside the test run can use it.


class SalesSummaryKpiTests(TestCase):
    def setUp(self):
        from apps.inventory.models import (
            Brand,
            Category,
            Product,
            ProductVariant,
            UnitOfMeasure,
            VariantUOM,
        )

        self.manager = User.objects.create_user(
            username="kpimanager",
            email="km@x.com",
            password=PASSWORD,
            full_name="Maria Santos",
        )
        self.manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.cashier = User.objects.create_user(
            username="kpicashier",
            email="kc@x.com",
            password=PASSWORD,
            full_name="Cashy Ir",
        )
        self.customer = Customer.objects.create(name="Juan Dela Cruz")

        # One selling unit = 2 base units, so ASP must divide by base units and a
        # divisor written as selling units shows up as a doubled (wrong) ASP.
        cat = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Holcim")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag", "is_whole": True}
        )
        product = Product.objects.create(
            category=cat, brand=brand, base_name="Portland Cement"
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        self.vuom = VariantUOM.objects.create(
            variant=variant,
            uom=uom,
            conversion_factor=Decimal(2),
            default_selling_price=Decimal("280.00"),
        )

        login = self.client.post(
            LOGIN_URL,
            {"username": "kpimanager", "password": PASSWORD},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200, "the manager must be able to log in")
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {login.json()['access']}"}

    def _tx(self, no, *, grand_total, vatable, discount):
        return SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.cashier,
            transaction_no=no,
            grand_total=Decimal(grand_total),
            vatable_sales=Decimal(vatable),
            vat_amount=Decimal("0.00"),
            discount_amount=Decimal(discount),
            vat_registered=False,
        )

    def _item(
        self, tx, *, qty, price, subtotal, item_discount=None, cart_discount=None
    ):
        return SalesItem.objects.create(
            transaction=tx,
            variant_uom=self.vuom,
            qty=Decimal(qty),
            unit_price=Decimal(price),
            subtotal=Decimal(subtotal),
            item_discount_amount=None
            if item_discount is None
            else Decimal(item_discount),
            cart_discount_amount=None
            if cart_discount is None
            else Decimal(cart_discount),
        )

    def _summary(self, query=""):
        response = self.client.get(
            f"{SALES_SUMMARY_URL}?{query}" if query else SALES_SUMMARY_URL, **self.auth
        )  # pyright: ignore[reportArgumentType]
        self.assertEqual(response.status_code, 200, response.content)
        return response.json()

    def _d(self, value):
        return Decimal(str(value))

    def _build_three_sales(self):
        """760 merchandise gross, 104 discounts, 8 base units, 3 tickets, 656 collected."""
        a = self._tx(
            "TRX-KPI-A", grand_total="756.00", vatable="756.00", discount="84.00"
        )
        self._item(a, qty="3", price="280.00", subtotal="840.00", cart_discount="84.00")
        b = self._tx(
            "TRX-KPI-B", grand_total="-280.00", vatable="-280.00", discount="0.00"
        )
        self._item(b, qty="-1", price="280.00", subtotal="-280.00")
        c = self._tx(
            "TRX-KPI-C", grand_total="180.00", vatable="180.00", discount="20.00"
        )
        self._item(c, qty="2", price="100.00", subtotal="200.00", item_discount="20.00")

    def test_totals_carry_abv_asp_and_markdown(self):
        self._build_three_sales()

        totals = self._summary()["totals"]

        # 656 collected over 3 tickets (the return is one of them).
        self.assertEqual(self._d(totals["abv"]), Decimal("218.67"))
        # 656 net merchandise over (3 - 1 + 2) x 2 = 8 base units.
        self.assertEqual(self._d(totals["asp"]), Decimal("82.00"))
        # 104 discounts over 760 merchandise gross.
        self.assertEqual(self._d(totals["markdown_percent"]), Decimal("13.68"))

    def test_a_signed_return_drags_abv_and_asp_down(self):
        sale = self._tx(
            "TRX-KPI-S", grand_total="840.00", vatable="840.00", discount="0.00"
        )
        self._item(sale, qty="3", price="280.00", subtotal="840.00")
        ret = self._tx(
            "TRX-KPI-R", grand_total="-280.00", vatable="-280.00", discount="0.00"
        )
        self._item(ret, qty="-1", price="280.00", subtotal="-280.00")

        totals = self._summary()["totals"]

        # The sale alone would be ABV 840.00 / 1 and ASP 840.00 / 6 units. The return
        # is included, so the ticket average falls to (840 - 280) / 2.
        self.assertEqual(self._d(totals["abv"]), Decimal("280.00"))
        self.assertEqual(self._d(totals["asp"]), Decimal("140.00"))
        # A sale with no discount is a real 0.00, not a missing value.
        self.assertEqual(self._d(totals["markdown_percent"]), Decimal("0.00"))

    def test_by_day_and_by_period_rows_carry_the_same_kpis_as_totals(self):
        self._build_three_sales()

        body = self._summary("granularity=month")
        totals = body["totals"]

        self.assertEqual(len(body["by_day"]), 1, "all three rows land on one day")
        self.assertEqual(len(body["by_period"]), 1, "and in one month bucket")
        for scope in (body["by_day"][0], body["by_period"][0]):
            for key in ("abv", "asp", "markdown_percent"):
                self.assertIsNotNone(scope[key], f"{key} must be computed for {scope}")
                self.assertEqual(
                    self._d(scope[key]),
                    self._d(totals[key]),
                    f"{key} in {scope['transactions']} must not drift from totals",
                )

    def test_an_empty_range_reports_none_not_zero(self):
        body = self._summary("from=2020-01-01&to=2020-01-02")

        totals = body["totals"]
        self.assertEqual(totals["transactions"], 0)
        self.assertIsNone(totals["abv"], "no tickets means no average ticket")
        self.assertIsNone(totals["asp"], "no units means no average selling price")
        self.assertIsNone(
            totals["markdown_percent"], "nothing grossed means no markdown share"
        )
        self.assertEqual(body["by_day"], [])
        self.assertEqual(body["by_period"], [])

    def test_a_ticket_with_no_units_reports_abv_zero_and_asp_none(self):
        self._tx("TRX-KPI-Z", grand_total="0.00", vatable="0.00", discount="0.00")

        totals = self._summary()["totals"]

        self.assertEqual(
            self._d(totals["abv"]), Decimal("0.00"), "a ticket is a ticket"
        )
        self.assertIsNone(totals["asp"], "zero base units cannot average a price")
        self.assertIsNone(
            totals["markdown_percent"], "zero merchandise gross cannot carry a share"
        )
        body = self._summary("granularity=month")
        by_day = body["by_day"][0]
        self.assertEqual(self._d(by_day["abv"]), Decimal("0.00"))
        self.assertIsNone(by_day["asp"])
        self.assertIsNone(by_day["markdown_percent"])
        # A ticket with no items gives the day bucket no qty rows at all: the period
        # scope must still report the KPIs instead of quietly dropping them.
        by_period = body["by_period"][0]
        self.assertEqual(self._d(by_period["abv"]), Decimal("0.00"))
        self.assertIsNone(by_period["asp"])
