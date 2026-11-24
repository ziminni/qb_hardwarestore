# pyright: reportAttributeAccessIssue=false
"""Persisted mid-shift X-readings (capture, numbering, immutability, scoping)."""

from decimal import Decimal

from django.contrib.auth.models import Group
from django.utils import timezone
from rest_framework.test import APIClient

from apps.users.models import User

from .models import Payment, SalesTransaction, Shift, ShiftXReading
from .tests import POSTestBase

SHIFTS_URL = "/api/v1/shifts/"


class ShiftXReadingTests(POSTestBase):
    def setUp(self):
        super().setUp()
        self.cashier_group = Group.objects.get_or_create(name="Cashier")[0]
        self.manager_group = Group.objects.get_or_create(name="Store Manager")[0]
        self.cashier.groups.add(self.cashier_group)
        self.client = APIClient()
        self.client.force_authenticate(user=self.cashier)

    def test_create_x_reading_on_open_shift_generates_sequential_numbers(self):
        today_stamp = timezone.localdate().strftime("%Y%m%d")

        first = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/",
            {"notes": "Midday drawer check"},
            format="json",
        )
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(first.data["shift_id"], self.shift.id)
        self.assertEqual(first.data["cashier_name"], self.cashier.full_name)
        self.assertEqual(first.data["taken_by"], self.cashier.id)
        self.assertEqual(first.data["taken_by_name"], self.cashier.full_name)
        self.assertEqual(first.data["reading_number"], f"X-{today_stamp}-001")
        self.assertEqual(first.data["notes"], "Midday drawer check")
        self.assertEqual(first.data["snapshot"]["expected_drawer"], "5000.00")

        second = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/",
            {},
            format="json",
        )
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(second.data["reading_number"], f"X-{today_stamp}-002")
        self.assertEqual(ShiftXReading.objects.filter(shift=self.shift).count(), 2)

    def test_refuses_x_reading_on_closed_shift(self):
        self.shift.status = Shift.Status.CLOSED
        self.shift.closing_count = Decimal("5000.00")
        self.shift.closed_at = timezone.now()
        self.shift.save(update_fields=["status", "closing_count", "closed_at"])

        resp = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/",
            {},
            format="json",
        )
        self.assertEqual(resp.status_code, 400, resp.data)
        self.assertEqual(resp.data["code"], "SHIFT_CLOSED")
        self.assertEqual(ShiftXReading.objects.count(), 0)

    def test_snapshot_is_immutable_after_subsequent_sales(self):
        first = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/",
            {},
            format="json",
        )
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(first.data["snapshot"]["transaction_count"], 0)
        self.assertEqual(first.data["snapshot"]["gross_sales"], "0.00")
        self.assertEqual(first.data["snapshot"]["expected_drawer"], "5000.00")

        # Record a completed cash sale AFTER taking the first X-reading.
        txn = SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.cashier,
            shift=self.shift,
            transaction_no="TRX-XREAD-0001",
            grand_total=Decimal("1250.00"),
            status=SalesTransaction.Status.COMPLETED,
        )
        Payment.objects.create(
            transaction=txn,
            method=Payment.Method.CASH,
            amount_tendered=Decimal("1250.00"),
        )

        # The persisted first X-reading snapshot must remain unchanged.
        saved_first = ShiftXReading.objects.get(pk=first.data["id"])
        self.assertEqual(saved_first.snapshot["transaction_count"], 0)
        self.assertEqual(saved_first.snapshot["gross_sales"], "0.00")
        self.assertEqual(saved_first.snapshot["expected_drawer"], "5000.00")

        # A second X-reading captures the new totals.
        second = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/",
            {},
            format="json",
        )
        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(second.data["snapshot"]["transaction_count"], 1)
        self.assertEqual(second.data["snapshot"]["gross_sales"], "1250.00")
        self.assertEqual(second.data["snapshot"]["expected_drawer"], "6250.00")

    def test_list_x_readings_returns_persisted_records_and_respects_cashier_scoping(
        self,
    ):
        other_cashier = User.objects.create_user(
            username="cashier_two",
            email="cashier_two@test.local",
            password="pw",
            full_name="Cashier Two",
        )
        other_cashier.groups.add(self.cashier_group)
        other_shift = Shift.objects.create(
            cashier=other_cashier,
            opening_float=Decimal("3000.00"),
        )

        manager = User.objects.create_user(
            username="mgr_xread",
            email="mgr_xread@test.local",
            password="pw",
            full_name="Store Manager",
        )
        manager.groups.add(self.manager_group)

        # Cashier 1 takes an X-reading on their shift.
        r1 = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/", {}, format="json"
        )
        self.assertEqual(r1.status_code, 201)

        # Cashier 2 takes an X-reading on their own shift, cannot take on Cashier 1's.
        other_client = APIClient()
        other_client.force_authenticate(user=other_cashier)
        forbidden = other_client.post(
            f"{SHIFTS_URL}{self.shift.id}/x-reading/", {}, format="json"
        )
        self.assertEqual(forbidden.status_code, 404)

        r2 = other_client.post(
            f"{SHIFTS_URL}{other_shift.id}/x-reading/", {}, format="json"
        )
        self.assertEqual(r2.status_code, 201)

        # Cashier 1 only sees their own X-reading.
        c1_list = self.client.get(f"{SHIFTS_URL}x-readings/")
        self.assertEqual(c1_list.status_code, 200)
        c1_items = c1_list.data.get("results", c1_list.data)
        self.assertEqual([item["id"] for item in c1_items], [r1.data["id"]])

        # Manager sees both X-readings and can filter by shift_id and date.
        mgr_client = APIClient()
        mgr_client.force_authenticate(user=manager)
        mgr_list = mgr_client.get(f"{SHIFTS_URL}x-readings/")
        self.assertEqual(mgr_list.status_code, 200)
        mgr_items = mgr_list.data.get("results", mgr_list.data)
        self.assertEqual(
            {item["id"] for item in mgr_items}, {r1.data["id"], r2.data["id"]}
        )

        filtered = mgr_client.get(
            f"{SHIFTS_URL}x-readings/?shift_id={other_shift.id}&date={timezone.localdate().isoformat()}"
        )
        self.assertEqual(filtered.status_code, 200)
        filtered_items = filtered.data.get("results", filtered.data)
        self.assertEqual([item["id"] for item in filtered_items], [r2.data["id"]])
