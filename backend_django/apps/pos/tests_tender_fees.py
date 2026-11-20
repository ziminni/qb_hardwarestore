# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/pos/tests_delivery.py: the checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django and `**self.auth` splats the Authorization header into the WSGI environ.

"""Payment-method fees (GCash, card, bank transfer) — charged like VAT, never refunded.

The owner's ruling: paying by GCash or card costs the shop money, so the fee is
calculated by the SERVER and added to the bill. A `TenderFee` row is per method
(CARD / GCASH / BANK_TRANSFER — never cash or cheque), either a PERCENT of what that
tender covers or a flat AMOUNT per payment row. Nothing is seeded, so a fresh shop
charges no fee and every existing sale behaves exactly as before.

The arithmetic, and why each part is where it is:

* a payment's `amount` on the wire means "this much of the BILL", fee excluded. The
  server adds the fee, stores `Payment.fee`, and stores `Payment.amount_tendered` as
  covered + fee — the money that actually ARRIVED, which is what the drawer and the
  GCash report count;
* `SalesTransaction.payment_fee` is their sum and joins `grand_total` AFTER the
  discount (a fee is never discounted), like the delivery charge, but stays OUTSIDE the
  VAT split (owner ruling: fees and VAT are separate charges);
* so utang, change and the cheque check all keep measuring the same thing from both
  sides: covered + fees paid against the fee-inclusive total. A fully-GCash sale leaves
  nothing owed and no change; a split cash + GCash sale gives change out of the CASH;
* a refund is the GOODS' business only. The fee bought a transaction that happened, so
  it is excluded from the refund share exactly as the delivery charge is.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.pos.models import Customer, Payment, SalesTransaction, TenderFee
from apps.pos.services import process_return, process_sale
from apps.pos.tests import POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
TRANSACTIONS_URL = "/api/v1/transactions/"
SETTINGS_URL = "/api/v1/store-settings/"

CASHIER_USERNAME = "cashier1"
CASHIER_PASSWORD = "pass12345"  # nosemgrep: throwaway test fixture


def _auth(token):
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}


class TenderFeeBase(POSTestBase):
    """`POSTestBase` (one bag at 10.00, ten base units of stock) plus the till's people."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.regular = Customer.objects.create(
            name="Reyes Contracting", customer_type=Customer.Type.REGULAR
        )
        self.admin = self._user("t_admin", "Admin")
        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.admin_auth = _auth(self._token("t_admin", self._user_password))

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

    def _fee(self, method="GCASH", kind="PERCENT", value="2.00", is_active=True):
        """Configure one fee row directly: the settings endpoint's own tests set it over
        the wire, and the money tests only need it to exist."""
        return TenderFee.objects.create(
            method=method, kind=kind, value=Decimal(value), is_active=is_active
        )

    def _ring(
        self, payments, *, customer=None, delivery=None, discount=None, auth=None
    ):
        body = {
            "customer": (self.regular.id if customer is None else customer),
            "source": "WALK_IN",
            "items": [{"variant_id": self.vuom.id, "qty": 10}],
            "payments": payments,
        }
        if delivery is not None:
            body["delivery"] = delivery
        if discount is not None:
            body["discount"] = discount
        return self.client.post(
            TRANSACTIONS_URL, body, format="json", **dict(auth or self.cashier_auth)
        )


class TenderFeeSettingsTests(TenderFeeBase):
    """Who may set a fee, and what the settings row says about them."""

    def test_no_fee_is_seeded_so_a_fresh_shop_charges_nothing(self):
        response = self.client.get(SETTINGS_URL, **self.cashier_auth)
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["tender_fees"], [])

    def test_an_admin_sets_the_fees_and_the_till_reads_them(self):
        response = self.client.patch(
            SETTINGS_URL,
            {
                "tender_fees": [
                    {"method": "GCASH", "kind": "PERCENT", "value": "2.00"},
                    {"method": "CARD", "kind": "AMOUNT", "value": "5.00"},
                ]
            },
            format="json",
            **self.admin_auth,
        )
        self.assertEqual(response.status_code, 200, response.content)
        # The body lists fees in METHOD order (the model's own ordering), so a client can
        # diff two responses without re-sorting: CARD, then GCASH, then BANK_TRANSFER.
        self.assertEqual(
            {
                f["method"]: (f["kind"], f["value"])
                for f in response.json()["tender_fees"]
            },
            {"GCASH": ("PERCENT", "2.00"), "CARD": ("AMOUNT", "5.00")},
        )
        # The till needs the numbers to preview the fee before the customer pays.
        read = self.client.get(SETTINGS_URL, **self.cashier_auth)
        self.assertEqual(len(read.json()["tender_fees"]), 2)
        self.assertTrue(
            AuditLog.objects.filter(
                action_type="SETTINGS_UPDATE", description__icontains="tender fee"
            ).exists()
        )

    def test_a_cashier_can_read_the_fees_but_not_change_them(self):
        self._fee("GCASH", "PERCENT", "2.00")
        read = self.client.get(SETTINGS_URL, **self.cashier_auth)
        self.assertEqual(len(read.json()["tender_fees"]), 1)

        write = self.client.patch(
            SETTINGS_URL,
            {"tender_fees": [{"method": "GCASH", "kind": "PERCENT", "value": "9.00"}]},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(write.status_code, 403, write.content)
        self.assertEqual(TenderFee.objects.get(method="GCASH").value, Decimal("2.00"))

    def test_cash_and_cheque_cannot_carry_a_fee(self):
        for method in ("CASH", "CHEQUE"):
            response = self.client.patch(
                SETTINGS_URL,
                {
                    "tender_fees": [
                        {"method": method, "kind": "AMOUNT", "value": "5.00"}
                    ]
                },
                format="json",
                **self.admin_auth,
            )
            self.assertEqual(response.status_code, 400, response.content)
            self.assertEqual(response.json()["code"], "INVALID_SETTINGS")
        self.assertFalse(TenderFee.objects.exists())

    def test_a_negative_fee_is_refused_and_nothing_is_written(self):
        response = self.client.patch(
            SETTINGS_URL,
            {"tender_fees": [{"method": "GCASH", "kind": "AMOUNT", "value": "-1.00"}]},
            format="json",
            **self.admin_auth,
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_SETTINGS")
        self.assertFalse(TenderFee.objects.exists())

    def test_the_same_method_twice_in_one_body_is_refused(self):
        response = self.client.patch(
            SETTINGS_URL,
            {
                "tender_fees": [
                    {"method": "GCASH", "kind": "AMOUNT", "value": "1.00"},
                    {"method": "GCASH", "kind": "PERCENT", "value": "2.00"},
                ]
            },
            format="json",
            **self.admin_auth,
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertFalse(TenderFee.objects.exists())


class TenderFeeMoneyTests(TenderFeeBase):
    """The fee is computed, stored and added — and it changes no existing rule."""

    def test_a_percent_fee_is_added_to_the_total_and_stored_on_the_payment(self):
        self._fee("GCASH", "PERCENT", "2.00")
        response = self._ring([{"method": "GCASH", "amount_tendered": "100.00"}])

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        # 100.00 of goods, 2 % of 100.00 = 2.00 of fee, and the customer paid 102.00.
        self.assertEqual(txn.payment_fee, Decimal("2.00"))
        self.assertEqual(txn.grand_total, Decimal("102.00"))
        self.assertEqual(txn.change_given, Decimal("0.00"))
        self.assertFalse(CollectibleLedger.objects.filter(transaction=txn).exists())
        payment = Payment.objects.get(transaction=txn)
        self.assertEqual(payment.fee, Decimal("2.00"))
        self.assertEqual(payment.amount_tendered, Decimal("102.00"))
        self.assertEqual(response.json()["payment_fee"], "2.00")
        self.assertEqual(response.json()["payments"][0]["fee"], "2.00")

    def test_an_amount_fee_is_charged_once_per_payment_row(self):
        self._fee("GCASH", "AMOUNT", "5.00")
        response = self._ring(
            [
                {"method": "GCASH", "amount_tendered": "60.00"},
                {"method": "GCASH", "amount_tendered": "40.00"},
            ]
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.payment_fee, Decimal("10.00"))
        self.assertEqual(txn.grand_total, Decimal("110.00"))
        self.assertEqual(
            sorted(p.amount_tendered for p in txn.payments.all()),
            [Decimal("45.00"), Decimal("65.00")],
        )

    def test_a_cash_payment_carries_no_fee(self):
        # Cash has no fee row by design (the till cannot charge for its own drawer), so a
        # cash sale is the pre-existing sale to the centavo.
        self._fee("GCASH", "PERCENT", "2.00")
        response = self._ring([{"method": "CASH", "amount_tendered": "100.00"}])
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.payment_fee, Decimal("0.00"))
        self.assertEqual(txn.grand_total, Decimal("100.00"))
        self.assertEqual(
            Payment.objects.get(transaction=txn).amount_tendered, Decimal("100.00")
        )

    def test_an_inactive_fee_charges_nothing(self):
        self._fee("GCASH", "PERCENT", "2.00", is_active=False)
        response = self._ring([{"method": "GCASH", "amount_tendered": "100.00"}])
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.payment_fee, Decimal("0.00"))
        self.assertEqual(txn.grand_total, Decimal("100.00"))

    def test_a_split_cash_and_gcash_sale_gives_change_from_the_cash_only(self):
        self._fee("GCASH", "PERCENT", "2.00")
        response = self._ring(
            [
                {"method": "GCASH", "amount_tendered": "60.00"},
                {"method": "CASH", "amount_tendered": "50.00"},
            ]
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        # Bill = 100 goods + 1.20 fee on the GCash part = 101.20; tendered = 61.20 + 50.
        self.assertEqual(txn.payment_fee, Decimal("1.20"))
        self.assertEqual(txn.grand_total, Decimal("101.20"))
        self.assertEqual(txn.change_given, Decimal("10.00"))
        gcash = Payment.objects.get(transaction=txn, method="GCASH")
        self.assertEqual(gcash.amount_tendered, Decimal("61.20"))

    def test_noncash_overpayment_with_fee_is_refused_even_with_cash_tender(self):
        self._fee("GCASH", "PERCENT", "2.00")
        before = SalesTransaction.objects.count()
        response = self._ring(
            [
                {"method": "GCASH", "amount_tendered": "120.00"},
                {"method": "CASH", "amount_tendered": "100.00"},
            ]
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "PAYMENT_EXCEEDS_TOTAL")
        self.assertEqual(SalesTransaction.objects.count(), before)

    def test_a_utang_sale_with_a_gcash_part_posts_the_rest_to_the_ledger(self):
        self._fee("GCASH", "PERCENT", "2.00")
        response = self._ring([{"method": "GCASH", "amount_tendered": "50.00"}])

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        # 100 goods + 1.00 fee on the GCash part; 51.00 arrived, so 50.00 is still owed.
        self.assertEqual(txn.grand_total, Decimal("101.00"))
        self.assertEqual(txn.payment_fee, Decimal("1.00"))
        self.assertEqual(
            CollectibleLedger.objects.get(transaction=txn).balance_due, Decimal("50.00")
        )

    def test_a_fully_gcash_sale_needs_no_extra_centavo_from_the_customer(self):
        # The exact-figure case the owner will hit every day: a fee-bearing tender that
        # covers the whole bill must leave zero owed and zero change.
        self._fee("CARD", "PERCENT", "3.00")
        response = self._ring([{"method": "CARD", "amount_tendered": "100.00"}])
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.grand_total, Decimal("103.00"))
        self.assertEqual(txn.change_given, Decimal("0.00"))
        self.assertEqual(
            Payment.objects.get(transaction=txn).amount_tendered, Decimal("103.00")
        )
        self.assertFalse(CollectibleLedger.objects.filter(transaction=txn).exists())

    def test_the_fee_is_never_refunded(self):
        self._fee("GCASH", "PERCENT", "2.00")
        sale = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            payments_data=[{"method": "GCASH", "amount_tendered": Decimal(100)}],
        )
        self.assertEqual(sale.grand_total, Decimal("102.00"))

        refund = process_return(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            original_transaction_id=sale.id,
            reason="Wrong bags delivered to the site",
        )
        # The goods come back, the fee does not: it bought a transaction, not an item.
        self.assertEqual(refund.refund_summary["return_value"], "100.00")
        self.assertEqual(refund.refund_summary["cash_refund"], "100.00")

    def test_the_fee_rides_beside_the_discount_and_the_delivery_charge(self):
        self._fee("CARD", "PERCENT", "2.00")
        response = self._ring(
            [{"method": "CARD", "amount_tendered": "110.00"}],
            discount={"kind": "PERCENT", "value": "10", "reason": "Loyal customer"},
            delivery={
                "address": "12 Mabini St, Quezon City",
                "contact_name": "Ana Reyes",
                "contact_phone": "0917-555-0100",
                "scheduled_date": "2026-12-01",
                "fee": "20.00",
            },
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        # 100 goods - 10 discount = 90 net, + 20 delivery = 110 billed, + 2.20 fee.
        self.assertEqual(txn.discount_amount, Decimal("10.00"))
        self.assertEqual(txn.delivery_fee, Decimal("20.00"))
        self.assertEqual(txn.payment_fee, Decimal("2.20"))
        self.assertEqual(txn.grand_total, Decimal("112.20"))
        self.assertEqual(txn.change_given, Decimal("0.00"))
        # Owner ruling: the fee is NOT taxed - VAT comes out of goods + delivery only.
        self.assertEqual(txn.vatable_sales + txn.vat_amount, Decimal("110.00"))
        self.assertEqual(
            txn.vatable_sales + txn.vat_amount + txn.payment_fee, txn.grand_total
        )
