# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/pos/tests_delivery.py: the checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django and `**self.auth` splats the Authorization header into the WSGI environ.

"""Utang (credit) markup per selling unit — the owner's ruling, enforced on the server.

An item may cost MORE when it is bought on utang. The shelf price is unchanged; the
markup is a per-selling-unit setting, either a peso AMOUNT or a PERCENT:

    credit price = round(base + value)            (AMOUNT)
    credit price = round(base x (1 + value/100))  (PERCENT)
    credit price = base                           (NONE)

Four rules, all server-side because all four are money:

* a `credit_sale` rings the till's lines at the credit price (an ORDER line keeps the
  price the manager agreed — that price was already signed off);
* a `credit_sale` that ends fully paid is refused (`CREDIT_SALE_FULLY_PAID`): the
  customer asked for utang terms and paid in full, so somebody ticked the wrong box;
* a sale that DOES end in utang, with the box unticked, is refused
  (`CREDIT_PRICE_REQUIRED`) when any till line carries a markup — otherwise a cashier
  could skip the markup by leaving the flag off, which is the one thing the flag is for;
* a return refunds the price the line was SOLD at, which is already the credit price.

Both refusals happen before (or roll back with) the first write, so a refused credit
sale leaves no transaction, no ledger, no moved stock.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import VariantUOM, credit_price
from apps.pos.exceptions import CreditPriceRequired, CreditSaleFullyPaid
from apps.pos.models import (
    Customer,
    SalesItem,
    SalesOrder,
    SalesOrderItem,
    SalesTransaction,
)
from apps.pos.services import process_return, process_sale
from apps.pos.tests import POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
TRANSACTIONS_URL = "/api/v1/transactions/"
VARIANT_UOMS_URL = "/api/v1/variant-uoms/"

CASHIER_USERNAME = "cashier1"
CASHIER_PASSWORD = "pass12345"  # nosemgrep: throwaway test fixture


def _auth(token):
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}


class CreditPriceHelperTests(TestCase):
    """ONE helper prices every credit line, so the till, the sale and the catalogue agree.

    Rounding is `money_round`'s rule — two decimals, HALF_UP, applied ONCE — and it is
    asserted here rather than assumed, because a markup that rounds differently from the
    total would put a centavo between the shelf and the receipt.
    """

    def test_an_amount_markup_adds_pesos_and_rounds_half_up(self):
        self.assertEqual(
            credit_price(Decimal("10.00"), kind="AMOUNT", value=Decimal("2.50")),
            Decimal("12.50"),
        )
        # 10.005 rounds UP, the way a hand calculator does.
        self.assertEqual(
            credit_price(Decimal("10.00"), kind="AMOUNT", value=Decimal("0.005")),
            Decimal("10.01"),
        )

    def test_a_percent_markup_multiplies_once_and_rounds_once(self):
        # 10.05 x 1.025 = 10.30125 -> 10.30
        self.assertEqual(
            credit_price(Decimal("10.05"), kind="PERCENT", value=Decimal("2.50")),
            Decimal("10.30"),
        )
        self.assertEqual(
            credit_price(Decimal("10.00"), kind="PERCENT", value=Decimal(1000)),
            Decimal("110.00"),
        )

    def test_no_markup_is_the_base_price_and_a_zero_value_changes_nothing(self):
        self.assertEqual(
            credit_price(Decimal("10.00"), kind="NONE", value=Decimal(0)),
            Decimal("10.00"),
        )
        self.assertEqual(
            credit_price(Decimal("10.00"), kind="PERCENT", value=Decimal(0)),
            Decimal("10.00"),
        )


class CreditMarkupBase(POSTestBase):
    """`POSTestBase` (one bag at 10.00, ten base units of stock) plus the till's people.

    The selling unit is the fixture's own row, REPRICED with a markup rather than a second
    unit created: one variant has one BAG unit, and a second would collide on
    `uq_variant_uom` without testing anything extra.
    """

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.regular = Customer.objects.create(
            name="Reyes Contracting", customer_type=Customer.Type.REGULAR
        )
        self.stocker = self._user("c_stocker", "Stock Manager")
        self.manager = self._user("c_manager", "Store Manager")
        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.stocker_auth = _auth(self._token("c_stocker", self._user_password))
        self.manager_auth = _auth(self._token("c_manager", self._user_password))

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

    def _with_markup(self, kind="PERCENT", value="5"):
        """Give the fixture's bag a markup: 10.00 becomes 10.50 at 5 PERCENT."""
        VariantUOM.objects.filter(pk=self.vuom.pk).update(
            credit_markup_kind=kind, credit_markup_value=Decimal(value)
        )
        self.vuom.refresh_from_db()
        return self.vuom


class CreditSalePricingTests(CreditMarkupBase):
    """A `credit_sale` prices the till's lines at the credit price, and nothing else."""

    def test_a_credit_sale_prices_its_till_lines_at_the_credit_price(self):
        self._with_markup("PERCENT", "5")
        txn = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(50)}],
            credit_sale=True,
        )

        self.assertTrue(txn.credit_sale)
        # 10 x 10.50 = 105.00, and the utang is what is left after the 50.00 handed over.
        self.assertEqual(txn.grand_total, Decimal("105.00"))
        self.assertEqual(
            SalesItem.objects.get(transaction=txn).unit_price, Decimal("10.50")
        )
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal("55.00"))

    def test_a_cash_sale_keeps_the_base_price(self):
        self._with_markup("PERCENT", "5")
        txn = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(100)}],
        )

        self.assertFalse(txn.credit_sale)
        self.assertEqual(txn.grand_total, Decimal("100.00"))
        self.assertEqual(
            SalesItem.objects.get(transaction=txn).unit_price, Decimal("10.00")
        )

    def test_a_credit_sale_that_ends_fully_paid_is_refused(self):
        # The customer asked for utang terms and then paid in full. Recording it would
        # charge the markup to somebody who is not on utang at all.
        self._with_markup("PERCENT", "5")
        with self.assertRaises(CreditSaleFullyPaid) as caught:
            process_sale(
                customer_id=self.regular.id,
                cashier=self.cashier,
                items_data=[{"variant_id": self.vuom.id, "qty": 10}],
                payments_data=[{"method": "CASH", "amount_tendered": Decimal(200)}],
                credit_sale=True,
            )
        self.assertEqual(caught.exception.code, "CREDIT_SALE_FULLY_PAID")
        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertEqual(
            sorted(self.variant.batches.values_list("current_qty", flat=True)),
            [Decimal(5), Decimal(5)],
        )

    def test_utang_on_a_marked_up_unit_without_the_credit_flag_is_refused(self):
        # The box the flag exists to close: a cashier who leaves it off would skip the
        # markup on a sale the customer pays for in utang.
        self._with_markup("PERCENT", "5")
        with self.assertRaises(CreditPriceRequired) as caught:
            process_sale(
                customer_id=self.regular.id,
                cashier=self.cashier,
                items_data=[{"variant_id": self.vuom.id, "qty": 10}],
                payments_data=[{"method": "CASH", "amount_tendered": Decimal(50)}],
            )
        self.assertEqual(caught.exception.code, "CREDIT_PRICE_REQUIRED")
        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertEqual(
            sorted(self.variant.batches.values_list("current_qty", flat=True)),
            [Decimal(5), Decimal(5)],
        )

    def test_utang_on_a_unit_with_no_markup_needs_no_credit_flag(self):
        # With nothing marked up there is nothing to charge for, so the old behaviour
        # stands: an underpaid sale posts the shortfall to the customer's ledger.
        txn = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(50)}],
        )
        self.assertFalse(txn.credit_sale)
        self.assertEqual(
            CollectibleLedger.objects.get(transaction=txn).balance_due, Decimal("50.00")
        )

    def test_an_order_line_keeps_its_agreed_price_on_a_credit_sale(self):
        # The manager agreed 9.00 for this order line. A credit sale must not reprice it:
        # the agreed price is the price, markup or no markup.
        self._with_markup("PERCENT", "5")
        order = SalesOrder.objects.create(
            customer=self.regular, created_by=self.cashier
        )
        line = SalesOrderItem.objects.create(
            order=order,
            variant_uom=self.vuom,
            qty=Decimal(5),
            unit_price=Decimal("9.00"),
        )
        txn = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 5, "order_line": line.pk}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(10)}],
            order_lines={line.pk: line},
            credit_sale=True,
        )
        self.assertEqual(txn.grand_total, Decimal("45.00"))
        self.assertEqual(
            SalesItem.objects.get(transaction=txn).unit_price, Decimal("9.00")
        )

    def test_a_return_of_a_credit_sold_item_refunds_the_credit_price(self):
        self._with_markup("PERCENT", "5")
        sale = process_sale(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 10}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(50)}],
            credit_sale=True,
        )
        refund = process_return(
            customer_id=self.regular.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 2}],
            original_transaction_id=sale.id,
            reason="Two bags came back damp",
        )
        # 2 x 10.50 = 21.00, and it settles utang first (55.00 owed) rather than paying cash.
        self.assertEqual(refund.grand_total, Decimal("-21.00"))
        self.assertEqual(refund.refund_summary["return_value"], "21.00")
        self.assertEqual(refund.refund_summary["debt_reduced"], "21.00")
        self.assertEqual(refund.refund_summary["cash_refund"], "0.00")
        self.assertEqual(
            SalesItem.objects.get(transaction=refund).unit_price, Decimal("10.50")
        )

    def test_the_checkout_wire_carries_the_credit_flag(self):
        self._with_markup("AMOUNT", "2")
        response = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "source": "WALK_IN",
                "items": [{"variant_id": self.vuom.id, "qty": 10}],
                "payments": [{"method": "CASH", "amount_tendered": "50.00"}],
                "credit_sale": True,
            },
            format="json",
            **self.cashier_auth,
        )

        self.assertEqual(response.status_code, 201, response.content)
        self.assertIs(response.json()["credit_sale"], True)
        self.assertEqual(response.json()["grand_total"], "120.00")

    def test_string_false_is_not_treated_as_credit_pricing(self):
        response = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "items": [{"variant_id": self.vuom.id, "qty": 1}],
                "payments": [{"method": "CASH", "amount_tendered": "10.00"}],
                "credit_sale": "false",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(response.status_code, 201, response.content)
        self.assertIs(response.json()["credit_sale"], False)

    def test_invalid_credit_flag_is_refused_before_writes(self):
        from apps.pos.models import SalesTransaction

        before = SalesTransaction.objects.count()
        response = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "credit_sale": "not-a-boolean",
                "items": [{"variant_id": self.vuom.id, "qty": 1}],
                "payments": [{"method": "CASH", "amount_tendered": "1.00"}],
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(SalesTransaction.objects.count(), before)

    def test_held_cart_completion_passes_credit_flag_and_reprices(self):
        from apps.pos.models import HeldCart, HeldCartItem

        self._with_markup("AMOUNT", "2")
        cart = HeldCart.objects.create(cashier=self.cashier, customer=self.regular)
        HeldCartItem.objects.create(
            cart=cart, variant_uom=self.vuom, qty=10, unit_price=Decimal("0.01")
        )
        response = self.client.post(
            f"/api/v1/held-carts/{cart.pk}/complete/",
            {
                "credit_sale": True,
                "payments": [{"method": "CASH", "amount_tendered": "50.00"}],
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["grand_total"], "120.00")
        self.assertIs(response.json()["credit_sale"], True)
        self.assertFalse(HeldCart.objects.filter(pk=cart.pk).exists())

    def test_both_refusals_reach_the_client_as_their_own_codes(self):
        self._with_markup("PERCENT", "5")
        paid_in_full = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "items": [{"variant_id": self.vuom.id, "qty": 10}],
                "payments": [{"method": "CASH", "amount_tendered": "200.00"}],
                "credit_sale": True,
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(paid_in_full.status_code, 400, paid_in_full.content)
        self.assertEqual(paid_in_full.json()["code"], "CREDIT_SALE_FULLY_PAID")

        skipped = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "items": [{"variant_id": self.vuom.id, "qty": 10}],
                "payments": [{"method": "CASH", "amount_tendered": "50.00"}],
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(skipped.status_code, 400, skipped.content)
        self.assertEqual(skipped.json()["code"], "CREDIT_PRICE_REQUIRED")
        self.assertFalse(SalesTransaction.objects.exists())


class CreditMarkupCatalogueTests(CreditMarkupBase):
    """The catalogue row is where a markup is SET, so the till can show what utang costs.

    Writable by the same roles that may write `default_selling_price` (the inventory
    roles), with a read-only `credit_selling_price` so the client never recomputes it.
    """

    def test_the_catalogue_reports_the_credit_price_alongside_the_base_price(self):
        self._with_markup("PERCENT", "5")
        response = self.client.get(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/", **self.cashier_auth
        )
        self.assertEqual(response.status_code, 200, response.content)
        body = response.json()
        self.assertEqual(body["default_selling_price"], "10.00")
        self.assertEqual(body["credit_markup_kind"], "PERCENT")
        self.assertEqual(body["credit_markup_value"], "5.00")
        self.assertEqual(body["credit_selling_price"], "10.50")

    def test_a_manager_can_set_a_markup_and_the_audit_trail_names_it(self):
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "AMOUNT", "credit_markup_value": "2.50"},
            format="json",
            **self.stocker_auth,
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["credit_selling_price"], "12.50")
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.credit_markup_kind, "AMOUNT")
        self.assertEqual(self.vuom.credit_markup_value, Decimal("2.50"))
        row = AuditLog.objects.filter(action_type="UPDATE").first()
        self.assertIsNotNone(row)
        self.assertIn("credit markup", row.description)

    def test_a_cashier_may_read_a_markup_but_not_set_one(self):
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "PERCENT", "credit_markup_value": "5"},
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(response.status_code, 403, response.content)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.credit_markup_kind, "NONE")

    def test_a_none_kind_with_a_value_normalises_the_value_to_zero(self):
        # NONE means "no markup". Storing a leftover 5 would make the row read as if a
        # 5-peso markup were configured and silently switched off — a trap for the next
        # person who flips the kind back.
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "NONE", "credit_markup_value": "5"},
            format="json",
            **self.manager_auth,
        )
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["credit_markup_value"], "0.00")
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.credit_markup_value, Decimal(0))
        self.assertEqual(self.vuom.credit_selling_price, Decimal("10.00"))

    def test_a_negative_markup_is_refused_and_nothing_is_written(self):
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "AMOUNT", "credit_markup_value": "-1"},
            format="json",
            **self.manager_auth,
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_SELLING_UNIT")
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.credit_markup_value, Decimal(0))

    def test_a_percent_markup_above_a_thousand_is_refused(self):
        # 1000 percent is already an eleven-fold price; beyond it a typo (a trailing
        # digit) would make the utang price meaningless and the ledger absurd.
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "PERCENT", "credit_markup_value": "1000.01"},
            format="json",
            **self.manager_auth,
        )
        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INVALID_SELLING_UNIT")

    def test_an_unknown_markup_kind_is_refused(self):
        response = self.client.patch(
            f"{VARIANT_UOMS_URL}{self.vuom.id}/",
            {"credit_markup_kind": "DISCOUNT", "credit_markup_value": "5"},
            format="json",
            **self.manager_auth,
        )
        self.assertEqual(response.status_code, 400, response.content)
