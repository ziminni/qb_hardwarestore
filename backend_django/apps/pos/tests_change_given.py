# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/pos/tests_cheque.py: the checker runs from a working
# directory outside the repo, so `Model.objects` is a false positive on valid Django and
# `**self.auth` splats the Authorization header into the WSGI environ.

"""QA High (Phase 4 close): change is money OUT of the drawer.

Live QA rang a 225.00 sale paid Cash 230.00 + GCash 10.00. The till previewed 15.00
change, the server stored both tenders as entered, and the receipt then said
Paid 240.00 / Change 0.00 - while `compute_z_reading` counted the whole 230.00 as cash
taken, so the expected drawer was 15.00 richer than the till. The same defect applied to
any single cash overpay (500.00 handed over for a 225.00 sale); split tenders only made
it visible.

The fix, enforced on the server because that is the trust boundary:

* `process_sale` derives `change_given = max(0, money in hand - net)` and stores it;
* change may only be paid from CASH, so a tender set whose change exceeds the cash
  taken is refused with 400 `PAYMENT_EXCEEDS_TOTAL` (lower the card/GCash amount);
* `compute_z_reading` subtracts that change from the cash tendered;
* sales written before the fix are backfilled by migration 0014 from the same rule.
"""

import importlib
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.pos.models import Customer, Payment, SalesTransaction
from apps.pos.services import compute_z_reading
from apps.pos.tests import POSTestBase

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
TRANSACTIONS_URL = "/api/v1/transactions/"

CASHIER_PASSWORD = "pass12345"  # nosemgrep: throwaway test fixture

migration = importlib.import_module(
    "apps.pos.migrations.0014_salestransaction_change_given"
)


def _cash(amount):
    return {"method": "CASH", "amount_tendered": f"{amount:.2f}"}


def _gcash(amount):
    return {
        "method": "GCASH",
        "amount_tendered": f"{amount:.2f}",
        "reference_no": "G-15",
    }


class ChangeGivenTestBase(POSTestBase):
    """`POSTestBase` re-priced so ONE cart is 225.00, the QA ticket's numbers.

    3 units at 75.00 = 225.00, and the fixture's ten base units cover it.
    """

    def setUp(self):
        super().setUp()
        self.vuom.default_selling_price = Decimal(75)
        self.vuom.save(update_fields=["default_selling_price"])

        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        login = self.client.post(
            LOGIN_URL,
            {"username": "cashier1", "password": CASHIER_PASSWORD},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200, "the cashier must be able to log in")
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {login.json()['access']}"}

        self.regular = Customer.objects.create(
            name="Utang Corp", customer_type=Customer.Type.REGULAR
        )

    def _ring(self, payments, *, qty=3, customer=None):
        body = {
            "customer": (self.regular.id if customer is None else customer),
            "source": "WALK_IN",
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payments": payments,
        }
        return self.client.post(
            TRANSACTIONS_URL, body, content_type="application/json", **self.auth
        )


class ChangeGivenSaleTests(ChangeGivenTestBase):
    """What the SALE records, and what the drawer therefore expects."""

    def test_a_single_cash_overpay_records_the_change(self):
        # The PRE-EXISTING half of the defect: the old till sent the full amount
        # received (500.00 for a 225.00 sale), and the drawer was never credited with
        # the 275.00 that went back over the counter.
        response = self._ring([_cash(500)])

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["grand_total"], "225.00")
        self.assertEqual(body["change_given"], "275.00")

        reading = compute_z_reading(self.shift)
        self.assertEqual(
            reading["cash_sales"], "225.00", "only what the shop kept is cash takings"
        )
        self.assertEqual(reading["change_given"], "275.00")
        self.assertEqual(reading["expected_drawer"], "5225.00")

    def test_split_cash_and_gcash_change_comes_out_of_the_cash(self):
        # QA's exact ticket: 225.00 Faucet, Cash 230.00 + GCash 10.00, change 15.00.
        response = self._ring([_cash(230), _gcash(10)])

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        txn = SalesTransaction.objects.get(pk=body["id"])
        self.assertEqual(body["change_given"], "15.00")
        self.assertEqual(txn.change_given, Decimal("15.00"))
        self.assertEqual(
            sorted(txn.payments.values_list("method", flat=True)),
            ["CASH", "GCASH"],
            "both tenders are still stored as entered - the change sits on the sale",
        )

        reading = compute_z_reading(self.shift)
        self.assertEqual(
            reading["cash_sales"], "215.00", "230.00 taken less 15.00 handed back"
        )
        self.assertEqual(reading["gcash_sales"], "10.00")
        self.assertEqual(reading["expected_drawer"], "5215.00")

    def test_gcash_covering_the_whole_sale_is_allowed_with_no_change(self):
        response = self._ring([_gcash(225)])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["change_given"], "0.00")
        self.assertEqual(compute_z_reading(self.shift)["cash_sales"], "0.00")

    def test_a_shortfall_still_owes_the_whole_difference(self):
        # The utang arithmetic is untouched: change is 0, the shortfall is still
        # grand_total - money in hand.
        response = self._ring([_cash(200)])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["change_given"], "0.00")
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.change_given, Decimal(0))
        self.assertEqual(
            CollectibleLedger.objects.get(transaction=txn).balance_due, Decimal("25.00")
        )


class NonCashOverpayRefusalTests(ChangeGivenTestBase):
    """A non-cash tender may not buy change the drawer never took."""

    def test_gcash_above_the_total_is_refused_with_a_stable_code(self):
        response = self._ring([_gcash(240)])

        self.assertEqual(response.status_code, 400, response.content)
        body = response.json()
        self.assertEqual(body["code"], "PAYMENT_EXCEEDS_TOTAL")
        self.assertEqual(body["change_given"], "15.00")
        self.assertEqual(body["cash_tendered"], "0.00")
        self.assertIn("lower the card or GCash amount", body["detail"])
        self.assertEqual(
            SalesTransaction.objects.count(),
            0,
            "a refused sale leaves no transaction behind",
        )
        self.assertEqual(Payment.objects.count(), 0)

    def test_cash_plus_a_non_cash_tender_still_may_not_exceed_the_cash_taken(self):
        # 5.00 cash + 240.00 GCash on a 225.00 sale asks for 20.00 change with only
        # 5.00 in the drawer.
        response = self._ring([_cash(5), _gcash(240)])

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "PAYMENT_EXCEEDS_TOTAL")
        self.assertEqual(response.json()["cash_tendered"], "5.00")

    def test_an_overpay_covered_by_cash_is_still_accepted(self):
        response = self._ring([_cash(240), _gcash(10)])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["change_given"], "25.00")


class ChangeGivenBackfillTests(TestCase):
    """Migration 0014: the same rule, applied to the sales already on disk."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="bf_owner", email="bf@example.com", password=get_random_string(16)
        )
        self.customer = Customer.objects.create(name="Legacy Buyer")

    def _sale(
        self,
        total="225.00",
        *,
        source=SalesTransaction.Source.WALK_IN,
        no="TRX-BF-0001",
    ):
        return SalesTransaction.objects.create(
            customer=self.customer,
            cashier=self.user,
            transaction_no=no,
            source=source,
            grand_total=Decimal(total),
        )

    def _pay(self, txn, method, amount):
        return Payment.objects.create(
            transaction=txn, method=method, amount_tendered=Decimal(amount)
        )

    def test_an_overpaid_sale_is_backfilled_with_its_change(self):
        txn = self._sale()
        self._pay(txn, Payment.Method.CASH, "230.00")
        self._pay(txn, Payment.Method.GCASH, "10.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(txn.change_given, Decimal("15.00"))

    def test_a_fully_paid_sale_gets_no_change(self):
        txn = self._sale()
        self._pay(txn, Payment.Method.CASH, "225.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(txn.change_given, Decimal(0))

    def test_a_short_paid_sale_gets_no_change(self):
        txn = self._sale()
        self._pay(txn, Payment.Method.CASH, "200.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(
            txn.change_given,
            Decimal(0),
            "an utang is not change: nothing left the drawer",
        )

    def test_a_return_row_is_left_alone(self):
        txn = self._sale("-225.00", source=SalesTransaction.Source.RETURN)
        self._pay(txn, Payment.Method.CASH, "-225.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(txn.change_given, Decimal(0))

    def test_backfilled_change_never_exceeds_the_cash_tendered(self):
        # A legacy GCash overpay handed no cash back: the drawer can only pay change
        # out of the cash it took, so the Z-reading's cash can never go negative.
        txn = self._sale()
        self._pay(txn, Payment.Method.CASH, "5.00")
        self._pay(txn, Payment.Method.GCASH, "240.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(txn.change_given, Decimal("5.00"))

    def test_a_pending_cheque_is_not_money_in_hand(self):
        txn = self._sale()
        self._pay(txn, Payment.Method.CASH, "5.00")
        self._pay(txn, Payment.Method.CHEQUE, "220.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        txn.refresh_from_db()
        self.assertEqual(
            txn.change_given,
            Decimal(0),
            "an uncleared cheque never pays change out of the drawer",
        )

    def test_the_sale_path_drops_its_change_into_the_z_reading(self):
        # The whole point of the backfill: an old overpaid sale stops inflating the
        # expected drawer the moment the migration has run.
        from apps.pos.models import Shift

        shift = Shift.objects.create(cashier=self.user, opening_float=Decimal(5000))
        txn = self._sale(total="225.00")
        txn.shift = shift
        txn.save(update_fields=["shift"])
        self._pay(txn, Payment.Method.CASH, "500.00")

        migration.backfill_change_given(
            __import__("django.apps", fromlist=["apps"]).apps, None
        )

        reading = compute_z_reading(shift)
        self.assertEqual(reading["cash_sales"], "225.00")
        self.assertEqual(reading["expected_drawer"], "5225.00")
