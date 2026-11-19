# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Owner 2026-11-18: `GET /api/v1/reports/admin-dashboard/` — Admin → Dashboard."""

from decimal import Decimal

from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from apps.pos.services import process_sale
from apps.pos.tests import POSTestBase


class AdminDashboardTests(POSTestBase):
    URL = "/api/v1/reports/admin-dashboard/"

    def setUp(self):
        super().setUp()
        self.admin = self.cashier.__class__.objects.create_user(
            username="boss", email="b@x.com", password="pass12345"
        )
        self.admin.groups.add(Group.objects.get_or_create(name="Admin")[0])
        self.api = APIClient()

    def _read(self, user=None):
        self.api.force_authenticate(user or self.admin)
        return self.api.get(self.URL)

    def test_the_admin_gets_all_five_tabs(self):
        response = self._read()
        self.assertEqual(response.status_code, 200, response.data)
        for key in ("system", "sales", "inventory", "bodega", "finance"):
            self.assertIn(key, response.data)
        self.assertEqual(len(response.data["sales"]["last_7_days"]), 7)

    def test_a_sale_today_shows_in_the_sales_tab(self):
        before = Decimal(self._read().data["sales"]["today_total"])
        process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 3}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(30)}],
        )
        sales = self._read().data["sales"]
        self.assertEqual(Decimal(sales["today_total"]), before + Decimal(30))
        self.assertEqual(sales["today_transactions"], 1)
        self.assertEqual(sales["top_products_month"][0]["total"], "30.00")

    def test_stock_value_is_counted(self):
        inventory = self._read().data["inventory"]
        # POSTestBase receives 5 @ 40 and 5 @ 60.
        self.assertEqual(inventory["stock_cost"], "500.00")

    def test_a_store_manager_is_refused(self):
        manager = self.cashier.__class__.objects.create_user(
            username="mgr", email="m@x.com", password="pass12345"
        )
        manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.assertEqual(self._read(manager).status_code, 403)

    def test_one_section_answers_only_that_tab(self):
        self.api.force_authenticate(self.admin)
        response = self.api.get(self.URL, {"section": "finance"})
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(set(response.data), {"as_of", "finance"})

    def test_an_unknown_section_is_refused(self):
        self.api.force_authenticate(self.admin)
        response = self.api.get(self.URL, {"section": "payroll"})
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "UNKNOWN_SECTION")

    def test_an_overdue_bill_is_listed_and_flagged(self):
        from datetime import timedelta

        from django.utils import timezone

        from apps.inventory.models import SupplierBill

        bills = SupplierBill.objects.filter(balance_amount__gt=0)
        self.assertTrue(bills.exists(), "POSTestBase deliveries leave open bills")
        late = bills.first()
        # A bill row is immutable through save(); a queryset update stands in
        # for the calendar moving past its due date.
        SupplierBill.objects.filter(pk=late.pk).update(
            due_date=timezone.localdate() - timedelta(days=3)
        )

        finance = self._read().data["finance"]

        self.assertEqual(finance["payables_overdue_count"], 1)
        self.assertTrue(finance["open_bills"][0]["overdue"])
        self.assertEqual(finance["open_bills"][0]["balance"], f"{late.balance_amount:.2f}")
        self.assertEqual(
            sum(Decimal(row["balance"]) for row in finance["payables_by_supplier"]),
            Decimal(finance["payables_total"]),
        )

    def test_a_shift_left_open_from_yesterday_is_flagged(self):
        from datetime import timedelta

        from django.utils import timezone

        from apps.pos.models import Shift

        # A second cashier: one open shift per cashier, and the base class's
        # cashier may already hold one (today's, which must not be flagged).
        other = self.cashier.__class__.objects.create_user(
            username="late_cashier", email="l@x.com", password="pass12345"
        )
        shift = Shift.objects.create(cashier=other)
        Shift.objects.filter(pk=shift.pk).update(
            opened_at=timezone.now() - timedelta(days=1, hours=2)
        )

        stale = self._read().data["sales"]["stale_shifts"]

        self.assertEqual(len(stale), 1)
