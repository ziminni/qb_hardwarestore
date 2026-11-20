# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/pos/tests_shift_cash_movements.py: the checker runs
# from a working directory outside the repo, so `Model.objects` is a false positive on
# valid Django and `**self.auth` splats the Authorization header into the WSGI environ.

"""Opening cash carried forward — the drawer the last shift handed over (decision 06).

The owner's ruling: the till should OFFER the cash the previous close left behind, but
the previous close may have cleared the register out. So:

* closing accepts an optional `cash_left` (0 <= cash_left <= closing_count). What was
  left stays in the drawer; the rest is the deposit — both are on the Z-reading;
* a close that does not send it records NULL ("not recorded"), so an old client is not
  made to answer a question it was never asked;
* opening a shift stores `expected_opening` from the most recent CLOSED shift
  store-wide (there is one drawer), the payload shows `opening_difference`, and a
  mismatch writes an audit row — it never blocks the open, because a cashier holding a
  drawer in front of a customer must be able to start work;
* `GET /shifts/opening-suggestion/` is what the open-shift dialog asks: the number to
  prefill, where it came from, and whether the last shift left the drawer empty.

Shift cash movements are unchanged: they adjust the expected drawer, not the float.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.pos.models import Shift, ShiftCashMovement
from apps.pos.tests import POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
SHIFTS_URL = "/api/v1/shifts/"

CASHIER_USERNAME = "cashier1"
CASHIER_PASSWORD = "pass12345"  # nosemgrep: throwaway test fixture


def _auth(token):
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}


class ShiftCarryBase(POSTestBase):
    """Two cashiers and a manager, so "store-wide, any cashier" is a real question."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.other = self._user("s_cashier2", "Cashier")
        self.stocker = self._user("s_stocker", "Stock Manager")
        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.other_auth = _auth(self._token("s_cashier2", self._user_password))
        self.stocker_auth = _auth(self._token("s_stocker", self._user_password))

    def _user(self, username, *groups):
        if not hasattr(self, "_user_password"):
            self._user_password = get_random_string(20)
        user = User.objects.create_user(
            username=username,
            email=f"{username}@x.com",
            password=self._user_password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _token(self, username, password):
        login = self.client.post(
            LOGIN_URL, {"username": username, "password": password}, format="json"
        )
        self.assertEqual(login.status_code, 200, login.content)
        return login.json()["access"]

    def _close(self, shift=None, **body):
        return self.client.post(
            f"{SHIFTS_URL}{(shift or self.shift).id}/close/",
            body,
            format="json",
            **self.cashier_auth,
        )

    def _open(self, opening_float, auth=None):
        return self.client.post(
            f"{SHIFTS_URL}open/",
            {"opening_float": f"{opening_float:.2f}"},
            format="json",
            **dict(auth or self.other_auth),
        )

    def _suggestion(self, auth=None):
        return self.client.get(
            f"{SHIFTS_URL}opening-suggestion/", **dict(auth or self.other_auth)
        )


class CloseCashLeftTests(ShiftCarryBase):
    """What the close records, and what it refuses to guess."""

    def test_the_close_records_both_the_cash_left_and_what_was_taken_out(self):
        response = self._close(closing_count="5000.00", cash_left="1000.00")
        self.assertEqual(response.status_code, 200, response.content)
        shift = Shift.objects.get(pk=self.shift.pk)
        self.assertEqual(shift.cash_left_in_drawer, Decimal("1000.00"))
        z = response.json()["z_reading"]
        self.assertEqual(z["cash_left_in_drawer"], "1000.00")
        self.assertEqual(z["cash_taken_out"], "4000.00")

    def test_a_close_without_cash_left_records_nothing(self):
        # An older client that never asks the question must not be broken by the column:
        # NULL is "not recorded", which is a different fact from "left empty".
        response = self._close(closing_count="5000.00")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsNone(Shift.objects.get(pk=self.shift.pk).cash_left_in_drawer)
        z = response.json()["z_reading"]
        self.assertIsNone(z["cash_left_in_drawer"])
        self.assertIsNone(z["cash_taken_out"])

    def test_a_cash_left_above_the_counted_drawer_is_refused(self):
        response = self._close(closing_count="5000.00", cash_left="5000.01")
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_CASH_LEFT")
        shift = Shift.objects.get(pk=self.shift.pk)
        self.assertEqual(shift.status, Shift.Status.OPEN)
        self.assertIsNone(shift.closing_count)

    def test_a_negative_cash_left_is_refused(self):
        response = self._close(closing_count="5000.00", cash_left="-1.00")
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_CASH_LEFT")
        self.assertEqual(Shift.objects.get(pk=self.shift.pk).status, Shift.Status.OPEN)


class OpeningSuggestionTests(ShiftCarryBase):
    """The number the open-shift dialog prefills, and whether it is worth prefilling."""

    def test_with_nothing_ever_closed_there_is_nothing_to_suggest(self):
        response = self._suggestion()
        self.assertEqual(response.status_code, 200, response.content)
        self.assertIsNone(response.json()["suggested_float"])
        self.assertIsNone(response.json()["source"])
        self.assertFalse(response.json()["cleared"])

    def test_the_suggestion_is_the_cash_the_last_close_left_behind(self):
        self._close(closing_count="5000.00", cash_left="1000.00")

        response = self._suggestion()
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["suggested_float"], "1000.00")
        self.assertFalse(body["cleared"])
        self.assertEqual(body["source"]["shift_id"], self.shift.pk)
        self.assertEqual(body["source"]["cashier_name"], self.cashier.full_name)
        self.assertEqual(body["source"]["closing_count"], "5000.00")
        self.assertEqual(body["source"]["cash_left_in_drawer"], "1000.00")
        self.assertIsNotNone(body["source"]["closed_at"])

    def test_a_cleared_drawer_is_reported_as_cleared(self):
        self._close(closing_count="5000.00", cash_left="0.00")
        body = self._suggestion().json()
        self.assertEqual(body["suggested_float"], "0.00")
        self.assertTrue(body["cleared"])

    def test_a_close_that_did_not_record_cash_left_offers_no_number(self):
        self._close(closing_count="5000.00")
        body = self._suggestion().json()
        self.assertIsNone(body["suggested_float"])
        self.assertFalse(body["cleared"])
        # The shift is still named, so the dialog can say "the last close did not record it".
        self.assertEqual(body["source"]["shift_id"], self.shift.pk)
        self.assertIsNone(body["source"]["cash_left_in_drawer"])

    def test_the_suggestion_is_store_wide_not_per_cashier(self):
        # One drawer: a close by one cashier is what the next cashier inherits.
        self._close(closing_count="5000.00", cash_left="1000.00")
        body = self._suggestion(self.cashier_auth).json()
        self.assertEqual(body["suggested_float"], "1000.00")

    def test_a_role_with_no_till_access_cannot_ask(self):
        # A Stock Manager holds no POS role, so the drawer is not theirs to read.
        response = self._suggestion(self.stocker_auth)
        self.assertEqual(response.status_code, 403, response.content)


class OpeningExpectationTests(ShiftCarryBase):
    """`expected_opening` is recorded at open, and a mismatch is AUDITED, not blocked."""

    def test_opening_from_a_previous_close_records_the_expectation_and_the_difference(
        self,
    ):
        self._close(closing_count="5000.00", cash_left="1000.00")

        response = self._open(Decimal("1200.00"))
        self.assertEqual(response.status_code, 201, response.content)

        shift = Shift.objects.get(pk=response.json()["id"])
        self.assertEqual(shift.expected_opening, Decimal("1000.00"))
        self.assertEqual(response.json()["expected_opening"], "1000.00")
        self.assertEqual(response.json()["z_reading"]["expected_opening"], "1000.00")
        self.assertEqual(response.json()["z_reading"]["opening_difference"], "200.00")
        self.assertTrue(
            AuditLog.objects.filter(
                action_type="SHIFT_OPEN", description__icontains="expected"
            ).exists()
        )

    def test_a_matching_float_records_a_zero_difference(self):
        self._close(closing_count="5000.00", cash_left="1000.00")

        response = self._open(Decimal("1000.00"))
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["z_reading"]["opening_difference"], "0.00")

    def test_opening_with_no_previous_close_has_no_expectation(self):
        response = self._open(Decimal("500.00"))
        self.assertEqual(response.status_code, 201, response.content)
        self.assertIsNone(response.json()["expected_opening"])
        self.assertIsNone(response.json()["z_reading"]["expected_opening"])
        self.assertIsNone(response.json()["z_reading"]["opening_difference"])

    def test_a_close_that_did_not_record_cash_left_sets_no_expectation(self):
        self._close(closing_count="5000.00")
        response = self._open(Decimal("500.00"))
        self.assertEqual(response.status_code, 201, response.content)
        self.assertIsNone(response.json()["expected_opening"])

    def test_a_cash_movement_still_adjusts_the_expected_drawer(self):
        # The carry-forward must not disturb the movement arithmetic it sits beside.
        ShiftCashMovement.objects.create(
            shift=self.shift,
            kind=ShiftCashMovement.Kind.CASH_OUT,
            amount=Decimal("1200.00"),
            reason="Owner safe drop",
            recorded_by=self.cashier,
        )
        response = self._close(closing_count="3800.00", cash_left="800.00")
        z = response.json()["z_reading"]
        self.assertEqual(z["cash_out"], "1200.00")
        self.assertEqual(z["expected_drawer"], "3800.00")
        self.assertEqual(z["variance"], "0.00")
        self.assertEqual(z["cash_taken_out"], "3000.00")
