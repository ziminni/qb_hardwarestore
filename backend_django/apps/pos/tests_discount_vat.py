# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/pos/tests_sale_integrity.py: the checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django and `**self.auth` splats the Authorization header into the WSGI environ.

"""Phase 4 Task B1 — store settings, VAT breakdown, capped discount, net refunds.

Decision 18 says the SERVER is the trust boundary for all of it:

* store settings (`vat_registered`, `vat_rate`, `discount_cap_percent`) are one row the
  Admin edits, and the checkout reads - never a constant in the client;
* money is `Decimal`, rounded `ROUND_HALF_UP` ONCE: shelf prices include VAT, so
  `net = gross - discount`, `vatable_sales = round(net / (1 + rate/100))` and
  `vat_amount = net - vatable_sales`; a non-VAT store answers 0/0 and flags the sale;
* a whole-sale discount (AMOUNT or PERCENT) needs a reason, may not exceed the gross,
  and above the Admin's cap needs a one-time approval token minted from a Store
  Manager's or Admin's own credentials - checked here, never stored, never logged;
* a return of a discounted sale refunds the NET share of what was paid, so a refund can
  never hand back the discount the customer already received;
* a CPMS material release is a sale with no discount and the same VAT breakdown.

Every refusal is HTTP 400 `{code, detail}` with the stable codes
`INVALID_DISCOUNT`, `DISCOUNT_REASON_REQUIRED`, `DISCOUNT_OVER_CAP` and
`DISCOUNT_APPROVAL_INVALID`, and nothing is written.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.cache import cache
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.pos.exceptions import DiscountApprovalInvalid
from apps.pos.models import (
    Customer,
    DiscountApproval,
    Payment,
    SalesTransaction,
    Shift,
    StoreSettings,
)
from apps.pos.services import process_sale
from apps.pos.tests import POSTestBase
from apps.requisitions.models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)
from apps.requisitions.services import release_materials
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
TRANSACTIONS_URL = "/api/v1/transactions/"
SETTINGS_URL = "/api/v1/store-settings/"
APPROVALS_URL = "/api/v1/discount-approvals/"
HELD_CARTS_URL = "/api/v1/held-carts/"

# The 429 a locked (username, address) pair is answered with. Distinct from
# `LOGIN_LOCKED` because the till has to say WHAT is locked out.
APPROVAL_LOCKED_CODE = "DISCOUNT_APPROVAL_LOCKED"
APPROVAL_LOCKED_DETAIL = "Too many failed discount approval attempts"
MAX_FAILURES = 5
WINDOW_SECONDS = 15 * 60

# `POSTestBase`'s cashier, and the password it was created with.
CASHIER_USERNAME = "cashier1"
CASHIER_PASSWORD = "pass12345"  # nosemgrep: test fixture, throwaway test DB


def _auth(token):
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}


class DiscountVATBase(POSTestBase):
    """`POSTestBase` (one selling unit at 10.00, 10 base units in stock) + logins.

    The fixture sells at 10.00 a unit, so a 2-unit sale is 20.00 - a number whose VAT
    split (17.86 + 2.14 at 12%) cannot be confused with the gross, which is what makes
    the assertions below say something.
    """

    def setUp(self):
        # The failed-credential lockout lives in the process-wide cache, so a test that
        # spends five wrong passwords would make an unrelated test's login answer 429.
        # Cleared here, for every test in this module, not only the lockout ones.
        cache.clear()
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])

        # A Store Manager and an Admin: the two roles that may approve a discount above
        # the cap. Random per-run passwords, because they only have to work inside the
        # throwaway test database.
        manager_password = get_random_string(20)
        self.manager = User.objects.create_user(
            username="disc_manager",
            email="dm@x.com",
            password=manager_password,
            full_name="Maria Santos",
        )
        self.manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        self.manager_password = manager_password

        admin_password = get_random_string(20)
        self.admin = User.objects.create_user(
            username="disc_admin",
            email="da@x.com",
            password=admin_password,
            full_name="Ana Lopez",
        )
        self.admin.groups.add(Group.objects.get_or_create(name="Admin")[0])
        self.admin_password = admin_password

        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.manager_auth = _auth(self._token("disc_manager", self.manager_password))
        self.admin_auth = _auth(self._token("disc_admin", self.admin_password))

    def _token(self, username, password):
        login = self.client.post(
            LOGIN_URL,
            {"username": username, "password": password},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200, f"{username} must be able to log in")
        return login.json()["access"]

    # -- fixture helpers ---------------------------------------------------
    def _sale_body(
        self, *, qty=2, discount=None, approval=None, payments=None, customer=None
    ):
        body = {
            "customer": customer if customer is not None else self.customer.id,
            "source": "WALK_IN",
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payments": payments
            if payments is not None
            else [
                {
                    "method": "CASH",
                    "amount_tendered": f"{Decimal(qty) * Decimal(10):.2f}",
                }
            ],
        }
        if discount is not None:
            body["discount"] = discount
        if approval is not None:
            body["discount_approval"] = approval
        return body

    def _ring(self, *, as_auth=None, **kwargs):
        return self.client.post(
            TRANSACTIONS_URL,
            self._sale_body(**kwargs),
            format="json",
            **(as_auth or self.cashier_auth),
        )

    def _approve(
        self, *, percent, username="disc_manager", password=None, as_auth=None, **extra
    ):
        return self.client.post(
            APPROVALS_URL,
            {
                "username": username,
                "password": password if password is not None else self.manager_password,
                "percent": str(percent),
            },
            format="json",
            **(as_auth or self.cashier_auth),
            **extra,
        )

    def _settings(self, **values):
        row = StoreSettings.load()
        for key, value in values.items():
            setattr(row, key, value)
        row.save()
        return row


class StoreSettingsTests(DiscountVATBase):
    """The Admin's settings row: any authenticated user reads, Admin alone writes."""

    def test_any_authenticated_user_reads_the_settings(self):
        response = self.client.get(SETTINGS_URL, **self.cashier_auth)  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertTrue(body["vat_registered"])
        self.assertEqual(body["vat_rate"], "12.00")
        self.assertEqual(body["discount_cap_percent"], "10.00")

    def test_an_anonymous_caller_is_refused(self):
        self.assertEqual(self.client.get(SETTINGS_URL).status_code, 401)

    def test_the_admin_changes_the_settings_and_the_change_is_audited(self):
        response = self.client.patch(
            SETTINGS_URL,
            {"vat_registered": False, "discount_cap_percent": "5.00"},
            format="json",
            **self.admin_auth,
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertFalse(body["vat_registered"])
        self.assertEqual(body["discount_cap_percent"], "5.00")
        row = StoreSettings.load()
        self.assertFalse(row.vat_registered)
        self.assertEqual(row.discount_cap_percent, Decimal("5.00"))
        self.assertTrue(
            AuditLog.objects.filter(action_type="SETTINGS_UPDATE").exists(),
            "a settings change is an admin decision and belongs in the trail",
        )

    def test_a_cashier_cannot_change_the_settings(self):
        response = self.client.patch(
            SETTINGS_URL, {"vat_registered": False}, format="json", **self.cashier_auth
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 403)
        self.assertTrue(StoreSettings.load().vat_registered)

    def test_a_patch_that_changes_nothing_saves_and_audits_nothing(self):
        # Phase 6 B5 item 3: a PATCH that repeats the current values is not an admin
        # decision. It used to save the row (bumping `updated_at`) and write a
        # `SETTINGS_UPDATE` audit row saying nothing changed.
        before = self.client.get(SETTINGS_URL, **self.cashier_auth).json()  # pyright: ignore[reportArgumentType]

        response = self.client.patch(
            SETTINGS_URL,
            {
                "vat_registered": True,
                "vat_rate": "12.00",
                "discount_cap_percent": "10.00",
            },
            format="json",
            **self.admin_auth,
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertTrue(body["vat_registered"])
        self.assertEqual(body["vat_rate"], "12.00")
        self.assertEqual(body["discount_cap_percent"], "10.00")
        self.assertEqual(
            body["updated_at"],
            before["updated_at"],
            "an unchanged PATCH must not save the row",
        )
        self.assertFalse(
            AuditLog.objects.filter(action_type="SETTINGS_UPDATE").exists(),
            "a PATCH that changes nothing is not an admin decision",
        )

    def test_an_impossible_rate_is_refused(self):
        response = self.client.patch(
            SETTINGS_URL, {"vat_rate": "off"}, format="json", **self.admin_auth
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(StoreSettings.load().vat_rate, Decimal("12.00"))


class VATBreakdownTests(DiscountVATBase):
    """VAT is inclusive, computed on the server, and rounded once."""

    def test_the_sale_carries_the_vat_breakdown_of_its_net(self):
        response = self._ring()

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["grand_total"], "20.00")
        self.assertEqual(body["vatable_sales"], "17.86")
        self.assertEqual(body["vat_amount"], "2.14")
        self.assertTrue(body["vat_registered"])

    def test_a_non_vat_store_answers_zero_and_flags_the_sale(self):
        self._settings(vat_registered=False)

        response = self._ring()

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["grand_total"], "20.00")
        self.assertEqual(body["vatable_sales"], "0.00")
        self.assertEqual(body["vat_amount"], "0.00")
        self.assertFalse(body["vat_registered"])

    def test_a_different_rate_moves_the_split(self):
        self._settings(vat_rate=Decimal("0.00"))

        body = self._ring().json()

        self.assertEqual(body["vatable_sales"], "20.00")
        self.assertEqual(body["vat_amount"], "0.00")

    def test_a_cpms_release_gets_the_breakdown_with_no_discount(self):
        # Decision 18: the CPMS contract is unaffected - a release is still a sale with
        # no discount, it simply reports VAT now.
        customer = Customer.objects.create(
            name="Builder Corp", customer_type=Customer.Type.CONSTRUCTION_FIRM
        )
        project = Project.objects.create(name="House Build", customer=customer)
        requisition = Requisition.objects.create(
            project=project,
            req_number="REQ-VAT-0001",
            status=Requisition.Status.ACCEPTED,
            requester_name="Rey Quester",
        )
        RequisitionItem.objects.create(
            requisition=requisition, variant_uom=self.vuom, quantity=Decimal(10)
        )
        token = MaterialToken.objects.create(requisition=requisition)

        result = release_materials(token_value=str(token.token), cashier=self.cashier)

        txn = SalesTransaction.objects.get(id=result["transaction_id"])
        self.assertEqual(txn.grand_total, Decimal(100))
        self.assertEqual(txn.discount_amount, Decimal(0))
        self.assertEqual(txn.vatable_sales, Decimal("89.29"))
        self.assertEqual(txn.vat_amount, Decimal("10.71"))
        self.assertTrue(txn.vat_registered)


class DiscountTests(DiscountVATBase):
    """Whole-sale discount: reason, cap, gross bound, and the net it produces."""

    def test_a_percent_discount_within_the_cap_is_applied_to_the_net(self):
        response = self._ring(
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Loyal customer"}
        )

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["discount_amount"], "2.00")
        self.assertEqual(body["grand_total"], "18.00")
        self.assertEqual(body["vatable_sales"], "16.07")
        self.assertEqual(body["vat_amount"], "1.93")
        self.assertEqual(body["discount_reason"], "Loyal customer")
        # VAT is computed AFTER the discount: 18 / 1.12, not 20 / 1.12.
        self.assertNotEqual(body["vatable_sales"], "17.86")

    def test_an_amount_discount_works_the_same_way(self):
        body = self._ring(
            discount={"kind": "AMOUNT", "value": "1.50", "reason": "Damaged bag"}
        ).json()

        self.assertEqual(body["discount_amount"], "1.50")
        self.assertEqual(body["grand_total"], "18.50")

    def test_a_zero_discount_needs_no_reason(self):
        response = self._ring(discount={"kind": "AMOUNT", "value": "0"})

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["grand_total"], "20.00")

    def test_a_discount_without_a_reason_is_refused_and_writes_nothing(self):
        response = self._ring(discount={"kind": "PERCENT", "value": "10.00"})

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "DISCOUNT_REASON_REQUIRED")
        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(Payment.objects.exists())

    def test_a_discount_bigger_than_the_sale_is_refused(self):
        response = self._ring(
            discount={"kind": "AMOUNT", "value": "25.00", "reason": "Too much"}
        )

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_DISCOUNT")
        self.assertFalse(SalesTransaction.objects.exists())

    def test_an_unknown_kind_or_a_negative_value_is_refused(self):
        for discount in (
            {"kind": "FREE", "value": "1", "reason": "x"},
            {"kind": "AMOUNT", "value": "-5", "reason": "x"},
            {"kind": "PERCENT", "value": "120", "reason": "x"},
            "not-an-object",
        ):
            with self.subTest(discount=discount):
                response = self._ring(discount=discount)
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(response.json()["code"], "INVALID_DISCOUNT")
        self.assertFalse(SalesTransaction.objects.exists())

    def test_above_the_cap_needs_an_approval(self):
        response = self._ring(
            discount={
                "kind": "PERCENT",
                "value": "15.00",
                "reason": "Panel price match",
            }
        )

        self.assertEqual(response.status_code, 400, response.content)
        body = response.json()
        self.assertEqual(body["code"], "DISCOUNT_OVER_CAP")
        self.assertEqual(body["cap_percent"], "10.00")
        self.assertEqual(body["requested_percent"], "15.00")
        self.assertFalse(SalesTransaction.objects.exists())

    def test_the_cap_is_the_admins_number_not_a_constant(self):
        self._settings(discount_cap_percent=Decimal("20.00"))

        response = self._ring(
            discount={
                "kind": "PERCENT",
                "value": "15.00",
                "reason": "Panel price match",
            }
        )

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["discount_amount"], "3.00")

    def test_the_utang_carries_the_net_not_the_gross(self):
        named = Customer.objects.create(
            name="Maria Santos", customer_type=Customer.Type.REGULAR
        )

        response = self._ring(
            customer=named.id,
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Loyal"},
            payments=[{"method": "CASH", "amount_tendered": "10.00"}],
        )

        self.assertEqual(response.status_code, 201, response.content)
        ledger = named.collectible_ledgers.get()
        self.assertEqual(ledger.balance_due, Decimal("8.00"))

    def test_a_held_cart_completion_takes_the_same_discount(self):
        hold = self.client.post(
            HELD_CARTS_URL,
            {
                "customer": self.customer.id,
                "items": [
                    {"variant_uom": self.vuom.id, "qty": 2, "unit_price": "10.00"}
                ],
            },
            format="json",
            **self.cashier_auth,
        )  # pyright: ignore[reportArgumentType]
        self.assertEqual(hold.status_code, 201, hold.content)

        response = self.client.post(
            f"{HELD_CARTS_URL}{hold.json()['id']}/complete/",
            {
                "payments": [{"method": "CASH", "amount_tendered": "18.00"}],
                "discount": {
                    "kind": "PERCENT",
                    "value": "10.00",
                    "reason": "Loyal customer",
                },
            },
            format="json",
            **self.cashier_auth,
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["discount_amount"], "2.00")
        self.assertEqual(response.json()["grand_total"], "18.00")


class DiscountApprovalTests(DiscountVATBase):
    """Above the cap: a manager's own credentials mint a one-time, percent-bound token."""

    def test_an_admin_can_approve(self):
        response = self._approve(
            percent="15.00", username="disc_admin", password=self.admin_password
        )

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertTrue(body["token"])
        self.assertEqual(body["percent"], "15.00")
        self.assertEqual(body["approver"], "Ana Lopez")

    def test_a_cashiers_credentials_cannot_approve(self):
        response = self._approve(
            percent="15.00", username=CASHIER_USERNAME, password=CASHIER_PASSWORD
        )

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "DISCOUNT_APPROVAL_INVALID")
        self.assertFalse(DiscountApproval.objects.exists())

    def test_a_wrong_password_is_refused_and_the_password_is_never_stored(self):
        # Not a literal: a password-looking string beside a `password=` argument is
        # exactly what the hardcoded-secret rule is for, and this value is a test
        # constant, not a credential.
        wrong_password = "not-the-password"  # a test constant, not a credential
        response = self._approve(percent="15.00", password=wrong_password)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "DISCOUNT_APPROVAL_INVALID")
        self.assertFalse(DiscountApproval.objects.exists())
        trail = " ".join(AuditLog.objects.values_list("description", flat=True))
        self.assertNotIn("not-the-password", trail)

    def test_the_approval_is_audited_without_the_password(self):
        self._approve(percent="15.00")

        row = AuditLog.objects.get(action_type="DISCOUNT_APPROVAL")
        self.assertIn("15.00", row.description)
        self.assertIn("disc_manager", row.description)
        self.assertNotIn(self.manager_password, row.description)

    def test_an_approved_discount_above_the_cap_goes_through(self):
        token = self._approve(percent="15.00").json()["token"]

        response = self._ring(
            discount={
                "kind": "PERCENT",
                "value": "15.00",
                "reason": "Panel price match",
            },
            approval=token,
        )

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["discount_amount"], "3.00")
        approval = DiscountApproval.objects.get()
        self.assertIsNotNone(approval.used_at)
        self.assertEqual(approval.transaction.discount_amount, Decimal("3.00"))

    def test_an_approval_cannot_be_used_twice(self):
        token = self._approve(percent="15.00").json()["token"]
        self.assertEqual(
            self._ring(
                discount={"kind": "PERCENT", "value": "15.00", "reason": "One"},
                approval=token,
            ).status_code,
            201,
        )

        second = self._ring(
            discount={"kind": "PERCENT", "value": "15.00", "reason": "Two"},
            approval=token,
        )

        self.assertEqual(second.status_code, 400, second.content)
        self.assertEqual(second.json()["code"], "DISCOUNT_APPROVAL_INVALID")
        self.assertEqual(SalesTransaction.objects.count(), 1)

    def test_an_approval_is_bound_to_the_percent_it_approved(self):
        token = self._approve(percent="12.00").json()["token"]

        response = self._ring(
            discount={"kind": "PERCENT", "value": "20.00", "reason": "Bigger"},
            approval=token,
        )

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "DISCOUNT_APPROVAL_INVALID")
        self.assertFalse(SalesTransaction.objects.exists())

    def test_a_forged_token_is_refused(self):
        response = self._ring(
            discount={"kind": "PERCENT", "value": "15.00", "reason": "Forged"},
            approval="not-a-signed-token",
        )

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "DISCOUNT_APPROVAL_INVALID")

    def test_a_tampered_approval_row_is_refused(self):
        # The signature binds the payload, so a caller cannot edit the approved percent
        # by hand - but the ROW is the server's own record, and the two must agree.
        token = self._approve(percent="12.00").json()["token"]
        row = DiscountApproval.objects.get()
        row.percent = Decimal("40.00")
        row.save(update_fields=["percent"])

        with self.assertRaises(DiscountApprovalInvalid):
            process_sale(
                customer_id=self.customer.id,
                cashier=self.cashier,
                items_data=[{"variant_id": self.vuom.id, "qty": 2}],
                payments_data=[{"method": "CASH", "amount_tendered": Decimal(15)}],
                discount_data={
                    "kind": "PERCENT",
                    "value": "25.00",
                    "reason": "Tampered",
                },
                discount_approval=token,
            )


class DiscountedReturnTests(DiscountVATBase):
    """A return of a discounted sale refunds the net share, never the gross."""

    def _sale_with_discount(self, *, qty=3):
        body = self._ring(
            qty=qty,
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Loyal"},
            payments=[
                {
                    "method": "CASH",
                    "amount_tendered": f"{Decimal(qty) * Decimal(9):.2f}",
                }
            ],
        ).json()
        return SalesTransaction.objects.get(id=body["id"])

    def _return(self, original, *, qty=1):
        return self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.customer.id,
                "source": "RETURN",
                "original_transaction": original.id,
                "items": [{"variant_id": self.vuom.id, "qty": qty}],
                "payment_method": "CASH",
                "reason": "wrong size",
            },
            format="json",
            **self.cashier_auth,
        )  # pyright: ignore[reportArgumentType]

    def test_a_line_of_a_discounted_sale_refunds_its_net_share(self):
        original = self._sale_with_discount()
        self.assertEqual(original.grand_total, Decimal("27.00"))

        response = self._return(original)

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["refund_summary"]["return_value"], "9.00")
        self.assertEqual(body["grand_total"], "-9.00")

    def test_returning_every_line_adds_up_to_exactly_what_was_paid(self):
        original = self._sale_with_discount()
        refunded = Decimal(0)
        for _ in range(3):
            body = self._return(original).json()
            refunded += Decimal(body["refund_summary"]["return_value"])

        self.assertEqual(refunded, original.grand_total)

    def test_an_undiscounted_sale_still_refunds_its_full_price(self):
        original = SalesTransaction.objects.get(id=self._ring(qty=2).json()["id"])

        body = self._return(original).json()

        self.assertEqual(body["refund_summary"]["return_value"], "10.00")


class DiscountApprovalLockoutTests(DiscountVATBase):
    """The approval endpoint spends a manager's PASSWORD, so it serves the login lockout.

    `apps.users.lockout` is the shop's one counter: five failures, a fixed 15-minute
    window, one bucket per (username, client address). Without it the till is an
    unlimited, unmonitored password oracle for the highest-value credential in the shop
    - and it costs the attacker nothing, because a wrong guess writes nothing either.
    """

    def setUp(self):
        super().setUp()
        # `DiscountVATBase` already cleared the counter for this test.

    def test_five_wrong_passwords_lock_the_manager_even_for_the_right_one(self):
        for _ in range(MAX_FAILURES):
            self.assertEqual(
                self._approve(percent="15.00", password="wrong-guess").status_code, 400
            )

        response = self._approve(percent="15.00")

        self.assertEqual(response.status_code, 429, response.content)
        body = response.json()
        self.assertEqual(body["code"], APPROVAL_LOCKED_CODE)
        self.assertIn(APPROVAL_LOCKED_DETAIL, body["detail"])
        self.assertGreater(body["retry_after"], 0)
        self.assertLessEqual(body["retry_after"], WINDOW_SECONDS)
        # The password was never checked, so no token was minted.
        self.assertNotIn("token", body)
        self.assertFalse(DiscountApproval.objects.exists())

    def test_the_lockout_covers_one_manager_and_one_address(self):
        for _ in range(MAX_FAILURES):
            self._approve(
                percent="15.00", password="wrong-guess", REMOTE_ADDR="10.0.0.1"
            )

        locked = self._approve(percent="15.00", REMOTE_ADDR="10.0.0.1")
        self.assertEqual(locked.status_code, 429, locked.content)

        # Another manager's password is a different bucket: a cashier hammering maria
        # must not lock the admin out of approving at the next till.
        other_manager = self._approve(
            percent="15.00",
            username="disc_admin",
            password=self.admin_password,
            REMOTE_ADDR="10.0.0.1",
        )
        self.assertEqual(other_manager.status_code, 201, other_manager.content)

        # Same manager, another terminal: the address is part of the key.
        elsewhere = self._approve(percent="15.00", REMOTE_ADDR="10.0.0.2")
        self.assertEqual(elsewhere.status_code, 201, elsewhere.content)

    def test_a_successful_approval_resets_that_managers_counter(self):
        for _ in range(MAX_FAILURES - 1):
            self.assertEqual(
                self._approve(percent="15.00", password="wrong-guess").status_code, 400
            )
        self.assertEqual(self._approve(percent="15.00").status_code, 201)

        # Four more failures reach the limit only if the success had not reset it.
        for _ in range(MAX_FAILURES - 1):
            self.assertEqual(
                self._approve(percent="15.00", password="wrong-guess").status_code, 400
            )
        self.assertEqual(self._approve(percent="15.00").status_code, 201)

    def test_each_refused_approval_is_audited_without_the_password(self):
        attempts = "pw-MARKER-12345"  # a test constant, not a credential
        for _ in range(MAX_FAILURES):
            self._approve(percent="15.00", password=attempts)

        rows = AuditLog.objects.filter(action_type="DISCOUNT_APPROVAL")
        self.assertEqual(rows.count(), MAX_FAILURES)
        for row in rows:
            # The row is about the credential that was refused, like `LOGIN_FAILED`, and
            # names the cashier who asked in the description.
            self.assertEqual(row.user_id, self.manager.pk)
            self.assertEqual(row.username_snapshot, "disc_manager")
            self.assertIn("refused", row.description)
            self.assertIn(CASHIER_USERNAME, row.description)
            self.assertNotIn(attempts, row.description)

    def test_the_locked_refusal_writes_no_extra_audit_row(self):
        for _ in range(MAX_FAILURES):
            self._approve(percent="15.00", password="wrong-guess")
        counted = AuditLog.objects.filter(action_type="DISCOUNT_APPROVAL").count()

        self.assertEqual(self._approve(percent="15.00").status_code, 429)

        self.assertEqual(
            AuditLog.objects.filter(action_type="DISCOUNT_APPROVAL").count(), counted
        )


class HistoricalVATRateTests(DiscountVATBase):
    """A sale keeps the RATE it was rung at, and its returns keep it too.

    `vat_registered` was stored on the row so a reprint keeps claiming what it claimed;
    the RATE has to be stored for the same reason. Reading today's settings for a
    return booked the refund at a rate the customer never paid, so reports stopped
    agreeing with the receipt in the customer's hand.
    """

    def _set_rate(self, rate):
        self._settings(vat_rate=Decimal(rate))

    def _return(self, original=None, *, qty=1, as_auth=None):
        body = {
            "customer": self.customer.id,
            "source": "RETURN",
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payment_method": "CASH",
            "reason": "wrong size",
        }
        if original is not None:
            body["original_transaction"] = original.id
        return self.client.post(
            TRANSACTIONS_URL, body, format="json", **(as_auth or self.cashier_auth)
        )  # pyright: ignore[reportArgumentType]

    def test_the_sale_stores_the_rate_it_was_rung_at(self):
        body = self._ring().json()

        txn = SalesTransaction.objects.get(id=body["id"])
        self.assertEqual(txn.vat_rate, Decimal("12.00"))
        self.assertEqual(body["vat_rate"], "12.00")

    def test_a_linked_return_uses_the_rate_the_sale_was_rung_at(self):
        original = SalesTransaction.objects.get(id=self._ring().json()["id"])
        self._set_rate("8.00")  # the Admin changes the rate after the sale

        response = self._return(original)

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["vat_rate"], "12.00")
        self.assertEqual(body["vatable_sales"], "-8.93")
        self.assertEqual(body["vat_amount"], "-1.07")
        # The refund's VAT is the sale's VAT, so sale + return net to zero in reports.
        self.assertEqual(
            Decimal(body["vatable_sales"]) + original.vatable_sales, Decimal("8.93")
        )
        self.assertEqual(
            Decimal(body["vat_amount"]) + original.vat_amount, Decimal("1.07")
        )

    def test_a_legacy_sale_without_a_stored_rate_refunds_no_vat(self):
        # Pre-Phase-4 rows recorded vat 0 and no rate: their receipt claimed no VAT, so
        # the refund may not invent one. The rule is "a NULL rate means 0.00 percent".
        original = SalesTransaction.objects.get(id=self._ring().json()["id"])
        SalesTransaction.objects.filter(pk=original.pk).update(
            vat_rate=None, vatable_sales=Decimal("0.00"), vat_amount=Decimal("0.00")
        )
        original.refresh_from_db()

        response = self._return(original, qty=2)

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["vat_rate"], "0.00")
        self.assertEqual(body["vat_amount"], "0.00")
        self.assertEqual(
            Decimal(body["vat_amount"]) + original.vat_amount, Decimal("0.00")
        )

    def test_an_unlinked_return_uses_the_current_rate(self):
        # Documented, not hidden: with no original to read, today's setting is the only
        # rate there is. ENDPOINTS.md says so beside the returns rules.
        self._set_rate("8.00")
        # A refund is money out of a drawer, and a drawer is a shift.
        Shift.objects.create(cashier=self.manager, opening_float=Decimal(5000))

        response = self._return(as_auth=self.manager_auth)

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body["vat_rate"], "8.00")
        self.assertEqual(body["vat_amount"], "-0.74")

    def test_a_cpms_release_stores_the_rate_it_was_issued_at(self):
        customer = Customer.objects.create(
            name="Builder Corp", customer_type=Customer.Type.CONSTRUCTION_FIRM
        )
        project = Project.objects.create(name="House Build", customer=customer)
        requisition = Requisition.objects.create(
            project=project,
            req_number="REQ-VAT-0002",
            status=Requisition.Status.ACCEPTED,
            requester_name="Rey Quester",
        )
        RequisitionItem.objects.create(
            requisition=requisition, variant_uom=self.vuom, quantity=Decimal(10)
        )
        token = MaterialToken.objects.create(requisition=requisition)

        result = release_materials(token_value=str(token.token), cashier=self.cashier)

        txn = SalesTransaction.objects.get(id=result["transaction_id"])
        self.assertEqual(txn.vat_rate, Decimal("12.00"))
