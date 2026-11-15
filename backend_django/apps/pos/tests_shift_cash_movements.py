# pyright: reportAttributeAccessIssue=false
"""Mid-shift cash drawer movements (cash out / cash in) and Z-reading reconciliation."""

from decimal import Decimal

from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog, User

from .models import Shift, ShiftCashMovement
from .tests import POSTestBase

LOGIN_URL = "/api/v1/auth/login/"
SHIFTS_URL = "/api/v1/shifts/"


class ShiftCashMovementTests(POSTestBase):
    def setUp(self):
        super().setUp()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.password = get_random_string(12)
        self.cashier.set_password(self.password)
        self.cashier.save(update_fields=["password"])
        self.client = APIClient()
        login = self.client.post(
            LOGIN_URL,
            {"username": self.cashier.username, "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200)
        self.bearer = f'Bearer {login.data["access"]}'

    def test_cash_out_and_cash_in_adjust_expected_drawer_and_write_audit_logs(self):
        # Opening float is 5000.00. Owner withdraws 1200.00, cashier adds 500.00 coins.
        out_resp = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {
                "kind": "CASH_OUT",
                "amount": "1200.00",
                "reason": "Owner safe drop for bank deposit",
            },
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(out_resp.status_code, 201, out_resp.data)
        self.assertEqual(out_resp.data["z_reading"]["cash_out"], "1200.00")
        self.assertEqual(out_resp.data["z_reading"]["cash_in"], "0.00")
        self.assertEqual(out_resp.data["z_reading"]["expected_drawer"], "3800.00")

        in_resp = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {
                "kind": "CASH_IN",
                "amount": "500.00",
                "reason": "Added small bills for change",
            },
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(in_resp.status_code, 201, in_resp.data)
        self.assertEqual(in_resp.data["z_reading"]["cash_out"], "1200.00")
        self.assertEqual(in_resp.data["z_reading"]["cash_in"], "500.00")
        self.assertEqual(in_resp.data["z_reading"]["expected_drawer"], "4300.00")
        self.assertEqual(len(in_resp.data["cash_movements"]), 2)
        self.assertEqual(
            [m["kind"] for m in in_resp.data["cash_movements"]],
            ["CASH_OUT", "CASH_IN"],
        )

        # Closing with 4300.00 produces 0.00 variance because the withdrawal is logged.
        close_resp = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/close/",
            {"closing_count": "4300.00"},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(close_resp.status_code, 200, close_resp.data)
        self.assertEqual(close_resp.data["z_reading"]["expected_drawer"], "4300.00")
        self.assertEqual(close_resp.data["z_reading"]["variance"], "0.00")

        logs = AuditLog.objects.filter(action_type=AuditLog.ActionType.SHIFT_CASH)
        self.assertEqual(logs.count(), 2)

    def test_validation_refuses_blank_reason_bad_amount_bad_kind_and_closed_shift(self):
        no_reason = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {"kind": "CASH_OUT", "amount": "100.00", "reason": "   "},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(no_reason.status_code, 400)
        self.assertEqual(no_reason.data["code"], "REASON_REQUIRED")

        bad_amount = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {"kind": "CASH_OUT", "amount": "0", "reason": "Zero test"},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(bad_amount.status_code, 400)
        self.assertEqual(bad_amount.data["code"], "INVALID_CASH_MOVEMENT_AMOUNT")

        bad_kind = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {"kind": "BORROW", "amount": "100.00", "reason": "Test"},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(bad_kind.status_code, 400)
        self.assertEqual(bad_kind.data["code"], "INVALID_CASH_MOVEMENT_KIND")

        self.shift.status = Shift.Status.CLOSED
        self.shift.save(update_fields=["status"])
        closed = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {"kind": "CASH_OUT", "amount": "100.00", "reason": "Late drop"},
            format="json",
            HTTP_AUTHORIZATION=self.bearer,
        )
        self.assertEqual(closed.status_code, 400)
        self.assertEqual(closed.data["code"], "SHIFT_ALREADY_CLOSED")
        self.assertEqual(ShiftCashMovement.objects.count(), 0)

    def test_other_cashier_cannot_record_movement_on_shift(self):
        other_pw = get_random_string(12)
        other = User.objects.create_user(
            username="cashier_other", email="other@x.com", password=other_pw
        )
        other.groups.add(Group.objects.get(name="Cashier"))
        login = self.client.post(
            LOGIN_URL,
            {"username": other.username, "password": other_pw},
            format="json",
        )
        other_bearer = f'Bearer {login.data["access"]}'

        resp = self.client.post(
            f"{SHIFTS_URL}{self.shift.id}/cash-movements/",
            {"kind": "CASH_OUT", "amount": "100.00", "reason": "Not my drawer"},
            format="json",
            HTTP_AUTHORIZATION=other_bearer,
        )
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(
            ShiftCashMovement.objects.filter(shift=self.shift).count(),
            0,
        )
        self.assertEqual(Decimal(self.shift.opening_float), Decimal("5000"))
