# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reason as apps/pos/tests_cheque.py: the checker runs from a working
# directory outside the repo, so `Model.objects` is a false positive on valid Django and
# `**self.auth` splats the Authorization header into the WSGI environ.

"""Phase 5 task B3 (decision 18) — delivery: the charge, the record and its states.

Decision 18's delivery ruling, enforced on the server because it is money:

* a till sale or a sales order may be ``MARKED Deliver``: address, contact name/phone,
  scheduled date, fee;
* the fee is a VAT-INCLUSIVE "Delivery charge" with **no stock behind it**, so it joins
  the sale total but never the DISCOUNT: the percent is computed on the goods gross, and
  the grand total (and therefore VAT, change, the utang shortfall and the cheque check)
  is goods net + fee;
* a return refunds its share of the GOODS net only - a full return of a delivered sale
  gets the goods back, not the delivery charge (fee refunds are out of scope);
* ``SCHEDULED -> OUT_FOR_DELIVERY -> DELIVERED`` or ``FAILED`` with a reason, forward
  only, row-locked, audited; Store Manager, Admin and Stock Manager move it, and a
  cashier may take the delivery order without being able to move it.
"""

import threading
from decimal import Decimal
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import IntegrityError, connection, connections, transaction
from django.test import TestCase, TransactionTestCase
from django.test.utils import CaptureQueriesContext
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.models import (
    Customer,
    Delivery,
    HeldCart,
    SalesOrder,
    SalesTransaction,
    Shift,
)
from apps.pos.services import compute_z_reading, process_sale
from apps.pos.tests import POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
TRANSACTIONS_URL = "/api/v1/transactions/"
ORDERS_URL = "/api/v1/sales-orders/"
DELIVERIES_URL = "/api/v1/deliveries/"
HELD_CARTS_URL = "/api/v1/held-carts/"

CASHIER_USERNAME = "cashier1"
CASHIER_PASSWORD = "pass12345"  # nosemgrep: throwaway test fixture
CPMS_GROUP = "CPMS Service"


def _auth(token):
    return {"HTTP_AUTHORIZATION": f"Bearer {token}"}


def delivery_body(**overrides):
    """The `delivery` object the till and the order form send.

    `scheduled_date` is a plain ISO date: the wire is JSON, and the server parses and
    stores it as a date, never as a client-chosen timestamp.
    """
    body = {
        "address": "12 Mabini St, Barangay San Roque, Quezon City",
        "contact_name": "Ana Reyes",
        "contact_phone": "0917-555-0100",
        "scheduled_date": "2026-12-01",
        "fee": "20.00",
    }
    body.update(overrides)
    return body


class DeliveryTestBase(POSTestBase):
    """`POSTestBase` (one selling unit at 10.00, ten base units of stock) plus logins.

    Every role the ruling names gets its own account, so the matrix is one test per
    role rather than a mock of `has_role` - the permission is what is under test.
    """

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.regular = Customer.objects.create(
            name="Reyes Contracting", customer_type=Customer.Type.REGULAR
        )
        self.manager = self._user("d_manager", "Store Manager")
        self.stocker = self._user("d_stocker", "Stock Manager")
        self.admin = self._user("d_admin", "Admin")
        self.multi = self._user("d_multi", "Cashier", "Stock Manager")
        self.cpms = self._user("d_cpms", CPMS_GROUP)

        self.cashier_auth = _auth(self._token(CASHIER_USERNAME, CASHIER_PASSWORD))
        self.manager_auth = _auth(self._token("d_manager", self._user_password))
        self.stocker_auth = _auth(self._token("d_stocker", self._user_password))
        self.admin_auth = _auth(self._token("d_admin", self._user_password))
        self.multi_auth = _auth(self._token("d_multi", self._user_password))
        self.cpms_auth = _auth(self._token("d_cpms", self._user_password))

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
        self.assertEqual(login.status_code, 200, f"{username} must be able to log in")
        return login.json()["access"]

    def _cash(self, amount):
        return {"method": "CASH", "amount_tendered": f"{amount:.2f}"}

    def _ring(
        self,
        payments,
        *,
        qty=10,
        customer=None,
        delivery=None,
        discount=None,
        auth=None,
        key=None,
    ):
        body = {
            "customer": (self.regular.id if customer is None else customer),
            "source": "WALK_IN",
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payments": payments,
        }
        if delivery is not None:
            body["delivery"] = delivery
        if discount is not None:
            body["discount"] = discount
        extra = dict(auth or self.cashier_auth)
        if key is not None:
            extra["HTTP_IDEMPOTENCY_KEY"] = key
        return self.client.post(TRANSACTIONS_URL, body, format="json", **extra)

    def _transition(self, delivery_id, action, *, body=None, auth=None):
        return self.client.post(
            f"{DELIVERIES_URL}{delivery_id}/{action}/",
            body or {},
            format="json",
            **dict(auth or self.manager_auth),
        )

    def _delivery_for(self, txn):
        return Delivery.objects.get(sale=txn)


class DeliveryChargeMoneyTests(DeliveryTestBase):
    """The fee is goods-SEPARATE: it is charged, never discounted, never refunded."""

    def test_a_percent_discount_is_computed_on_the_goods_gross_only(self):
        # 10 units x 10.00 = 100.00 goods, 10 % (the cap) = 10.00 off the GOODS, and the
        # 20.00 delivery charge rides beside it. Discounting the fee as well would be
        # 12.00 off a 120.00 total - money the shop never agreed to give away.
        response = self._ring(
            [self._cash(110)],
            delivery=delivery_body(),
            discount={"kind": "PERCENT", "value": "10", "reason": "Loyal customer"},
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.discount_amount, Decimal("10.00"))
        self.assertEqual(txn.delivery_fee, Decimal("20.00"))
        self.assertEqual(txn.grand_total, Decimal("110.00"))

    def test_the_vat_comes_out_of_the_goods_plus_the_charge(self):
        response = self._ring([self._cash(120)], delivery=delivery_body(fee="20.00"))

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        # 120.00 / 1.12 = 107.14 vatable, 12.86 VAT, and the two add back to 120.00.
        self.assertEqual(txn.vatable_sales, Decimal("107.14"))
        self.assertEqual(txn.vat_amount, Decimal("12.86"))
        self.assertEqual(
            txn.vatable_sales + txn.vat_amount,
            txn.grand_total,
            "the receipt must add up exactly - the fee is inside the VAT split",
        )

    def test_change_is_computed_from_the_total_including_the_charge(self):
        response = self._ring([self._cash(150)], delivery=delivery_body(fee="20.00"))

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.grand_total, Decimal("120.00"))
        self.assertEqual(
            txn.change_given,
            Decimal("30.00"),
            "change is money OUT of the drawer: it must count the fee too",
        )

    def test_a_shortfall_including_the_charge_posts_to_utang(self):
        response = self._ring(
            [self._cash(100)],
            customer=self.regular.id,
            delivery=delivery_body(fee="20.00"),
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal("20.00"))

    def test_the_cheque_check_measures_against_the_total_including_the_charge(self):
        # 2 units = 20.00 goods + 10.00 delivery = 30.00. A 30.00 cheque covers exactly
        # what is still owed; if the fee were left out of the total, that same cheque
        # would look 10.00 too big and be refused for a sale the customer just paid for.
        response = self._ring(
            [
                {
                    "method": "CHEQUE",
                    "amount_tendered": "29.99",
                    "cheque_number": "CHQ-2001",
                    "bank": "BDO",
                    "cheque_date": "2026-12-05",
                }
            ],
            qty=2,
            delivery=delivery_body(fee="10.00"),
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.grand_total, Decimal("30.00"))
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(
            ledger.balance_due,
            Decimal("30.00"),
            "the pending cheque pays nothing yet, so the whole 30.00 - fee included - is owed",
        )
        self.assertEqual(self._delivery_for(txn).fee, Decimal("10.00"))

    def test_a_walk_in_may_not_owe_the_delivery_charge(self):
        # The existing walk-in rule already covers it: the fee is part of the total, so a
        # short payment leaves a walk-in owing the charge, which is money owed by nobody.
        response = self._ring(
            [self._cash(10)],
            customer=self.customer.id,
            delivery=delivery_body(fee="20.00"),
        )

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "WALK_IN_CANNOT_OWE")
        self.assertEqual(
            Delivery.objects.count(), 0, "a refused sale leaves no delivery"
        )
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_a_sale_without_a_delivery_still_reads_a_zero_charge(self):
        response = self._ring([self._cash(100)])

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.delivery_fee, Decimal("0.00"))
        self.assertEqual(txn.grand_total, Decimal("100.00"))
        self.assertEqual(Delivery.objects.count(), 0)

    def test_the_z_reading_gross_includes_the_delivery_charge(self):
        response = self._ring([self._cash(120)], delivery=delivery_body(fee="20.00"))
        self.assertEqual(response.status_code, 201, response.content)

        z = compute_z_reading(self.shift)
        self.assertEqual(z["gross_sales"], "120.00")
        self.assertEqual(z["vat"], "12.86")
        self.assertEqual(
            z["expected_drawer"],
            "5120.00",
            "5000.00 float plus the 120.00 taken, change already netted out",
        )

    def test_a_return_of_a_delivered_sale_refunds_the_goods_only(self):
        sale_response = self._ring(
            [self._cash(120)], delivery=delivery_body(fee="20.00")
        )
        self.assertEqual(sale_response.status_code, 201, sale_response.content)
        txn_id = sale_response.json()["id"]

        response = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": self.regular.id,
                "source": "RETURN",
                "items": [{"variant_id": self.vuom.id, "qty": 10}],
                "original_transaction": txn_id,
                "reason": "Customer refused the delivery at the gate",
                "payment_method": "CASH",
            },
            format="json",
            **self.cashier_auth,
        )

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(
            body["refund_summary"]["cash_refund"],
            "100.00",
            "the delivery charge is NOT refunded: the trip was made",
        )
        self.assertEqual(body["refund_summary"]["return_value"], "100.00")
        self.assertEqual(body["grand_total"], "-100.00")


class DeliveryApiTests(DeliveryTestBase):
    """Wire shape: the till takes the order, and the slip data reads back."""

    def test_a_sale_can_be_rung_with_a_delivery(self):
        response = self._ring([self._cash(120)], delivery=delivery_body())

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        delivery = self._delivery_for(txn)
        self.assertTrue(delivery.delivery_no.startswith("DEL-"))
        self.assertEqual(
            delivery.address, "12 Mabini St, Barangay San Roque, Quezon City"
        )
        self.assertEqual(delivery.contact_name, "Ana Reyes")
        self.assertEqual(delivery.contact_phone, "0917-555-0100")
        self.assertEqual(delivery.scheduled_date.isoformat(), "2026-12-01")
        self.assertEqual(delivery.fee, Decimal("20.00"))
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)
        self.assertIsNone(delivery.sales_order_id)

    def test_the_detail_returns_the_slip_data(self):
        response = self._ring([self._cash(120)], delivery=delivery_body())
        delivery_id = self._delivery_for(
            SalesTransaction.objects.get(pk=response.json()["id"])
        ).id

        slip = self.client.get(f"{DELIVERIES_URL}{delivery_id}/", **self.manager_auth)

        self.assertEqual(slip.status_code, 200, slip.content)
        body = slip.json()
        self.assertEqual(body["status"], "SCHEDULED")
        self.assertEqual(body["fee"], "20.00")
        self.assertEqual(body["contact_name"], "Ana Reyes")
        self.assertEqual(body["scheduled_date"], "2026-12-01")
        self.assertTrue(body["delivery_no"].startswith("DEL-"))
        self.assertEqual(len(body["items"]), 1)
        line = body["items"][0]
        self.assertEqual(line["name"], "Portland Cement — 40kg")
        self.assertEqual(line["unit"], "BAG")
        self.assertEqual(Decimal(line["qty"]), Decimal("10.00"))
        self.assertEqual(body["customer_name"], "Reyes Contracting")

    def test_a_delivery_must_say_where_and_who_and_when(self):
        for missing in ("address", "contact_name", "contact_phone", "scheduled_date"):
            with self.subTest(missing=missing):
                response = self._ring(
                    [self._cash(120)], delivery=delivery_body(**{missing: ""})
                )
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(response.json()["code"], "INVALID_DELIVERY")
        self.assertEqual(SalesTransaction.objects.count(), 0)
        self.assertEqual(Delivery.objects.count(), 0)

    def test_the_charge_must_be_a_non_negative_two_decimal_amount(self):
        for fee in ("-1", "10.005", "lots"):
            with self.subTest(fee=fee):
                response = self._ring(
                    [self._cash(120)], delivery=delivery_body(fee=fee)
                )
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(response.json()["code"], "INVALID_DELIVERY")
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_the_idempotency_hash_includes_the_delivery(self):
        key = str(uuid4())
        first = self._ring([self._cash(120)], delivery=delivery_body(), key=key)
        self.assertEqual(first.status_code, 201, first.content)

        replay = self._ring([self._cash(120)], delivery=delivery_body(), key=key)

        self.assertEqual(replay.status_code, 200, replay.content)
        self.assertEqual(replay.json()["id"], first.json()["id"])
        self.assertEqual(Delivery.objects.count(), 1, "a replay takes no second fee")

        # Same key, a different CHARGE: that is a different request, not a retry.
        reused = self._ring(
            [self._cash(130)], delivery=delivery_body(fee="30.00"), key=key
        )
        self.assertEqual(reused.status_code, 409, reused.content)
        self.assertEqual(reused.json()["code"], "IDEMPOTENCY_KEY_REUSED")
        self.assertEqual(Delivery.objects.count(), 1)

    def test_a_refused_sale_leaves_no_delivery_behind(self):
        response = self._ring([self._cash(120)], qty=20, delivery=delivery_body())

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()["code"], "INSUFFICIENT_STOCK")
        self.assertEqual(Delivery.objects.count(), 0)

    def test_a_held_cart_can_be_completed_with_a_delivery(self):
        parked = self.client.post(
            HELD_CARTS_URL,
            {
                "customer": self.regular.id,
                "items": [
                    {"variant_uom": self.vuom.id, "qty": "10", "unit_price": "10.00"}
                ],
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(parked.status_code, 201, parked.content)

        response = self.client.post(
            f"{HELD_CARTS_URL}{parked.json()['id']}/complete/",
            {"payments": [self._cash(120)], "delivery": delivery_body()},
            format="json",
            **self.cashier_auth,
        )

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.grand_total, Decimal("120.00"))
        self.assertEqual(self._delivery_for(txn).fee, Decimal("20.00"))
        self.assertEqual(HeldCart.objects.count(), 0)

    def test_the_list_filters_by_status_date_and_sale(self):
        # Two units each: `POSTestBase` stocks ten base units, so two ten-unit sales
        # would leave the second one short of stock and test nothing about filters.
        first = self._ring(
            [self._cash(40)],
            qty=2,
            delivery=delivery_body(scheduled_date="2026-12-01"),
        )
        second = self._ring(
            [self._cash(40)],
            qty=2,
            delivery=delivery_body(scheduled_date="2026-12-20"),
        )
        first_txn = SalesTransaction.objects.get(pk=first.json()["id"])
        second_txn = SalesTransaction.objects.get(pk=second.json()["id"])
        self._transition(self._delivery_for(second_txn).id, "start")

        by_status = self.client.get(
            f"{DELIVERIES_URL}?status=OUT_FOR_DELIVERY", **self.manager_auth
        )
        self.assertEqual(by_status.status_code, 200, by_status.content)
        self.assertEqual(
            [row["sale"] for row in by_status.json()["results"]], [second_txn.id]
        )

        in_range = self.client.get(
            f"{DELIVERIES_URL}?date_from=2026-12-15&date_to=2026-12-31",
            **self.manager_auth,
        )
        self.assertEqual(in_range.status_code, 200, in_range.content)
        self.assertEqual(
            [row["sale"] for row in in_range.json()["results"]], [second_txn.id]
        )

        by_sale = self.client.get(
            f"{DELIVERIES_URL}?sale={first_txn.id}", **self.manager_auth
        )
        self.assertEqual(by_sale.status_code, 200, by_sale.content)
        self.assertEqual(
            [row["sale"] for row in by_sale.json()["results"]], [first_txn.id]
        )

    def test_a_bad_filter_is_a_400_not_an_empty_page(self):
        for query in ("status=DROPPED", "date_from=nope", "sale=abc"):
            with self.subTest(query=query):
                response = self.client.get(
                    f"{DELIVERIES_URL}?{query}", **self.manager_auth
                )
                self.assertEqual(response.status_code, 400, response.content)
                self.assertEqual(response.json()["code"], "INVALID_DELIVERY")


class DeliveryTransitionTests(DeliveryTestBase):
    """Scheduled -> out for delivery -> delivered, or failed with a reason. Forward only."""

    def _scheduled(self):
        response = self._ring([self._cash(120)], delivery=delivery_body())
        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        return self._delivery_for(txn)

    def test_start_and_deliver_move_the_row_forward_and_audit_each_step(self):
        delivery = self._scheduled()

        started = self._transition(delivery.id, "start")
        self.assertEqual(started.status_code, 200, started.content)
        self.assertEqual(started.json()["status"], "OUT_FOR_DELIVERY")

        delivered = self._transition(delivery.id, "deliver")
        self.assertEqual(delivered.status_code, 200, delivered.content)
        self.assertEqual(delivered.json()["status"], "DELIVERED")

        rows = AuditLog.objects.filter(action_type=AuditLog.ActionType.DELIVERY)
        self.assertEqual(rows.count(), 3, "one audit row per delivery event")

    def test_a_failure_needs_a_reason_and_records_it(self):
        delivery = self._scheduled()

        refused = self._transition(delivery.id, "fail", body={})
        self.assertEqual(refused.status_code, 400, refused.content)
        self.assertEqual(refused.json()["code"], "DELIVERY_REASON_REQUIRED")
        delivery.refresh_from_db()
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)

        failed = self._transition(
            delivery.id, "fail", body={"reason": "Gate locked, nobody home"}
        )
        self.assertEqual(failed.status_code, 200, failed.content)
        self.assertEqual(failed.json()["status"], "FAILED")
        self.assertEqual(failed.json()["failure_reason"], "Gate locked, nobody home")

    def test_a_failure_from_out_for_delivery_is_allowed(self):
        delivery = self._scheduled()
        self._transition(delivery.id, "start")

        failed = self._transition(
            delivery.id, "fail", body={"reason": "Buyer refused the load"}
        )

        self.assertEqual(failed.status_code, 200, failed.content)
        self.assertEqual(failed.json()["status"], "FAILED")

    def test_a_jump_over_a_state_is_refused(self):
        delivery = self._scheduled()

        jumped = self._transition(delivery.id, "deliver")

        self.assertEqual(jumped.status_code, 409, jumped.content)
        self.assertEqual(jumped.json()["code"], "DELIVERY_TRANSITION_INVALID")
        delivery.refresh_from_db()
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)

    def test_delivered_is_terminal(self):
        delivery = self._scheduled()
        self._transition(delivery.id, "start")
        self._transition(delivery.id, "deliver")

        for action, body in (("start", {}), ("deliver", {}), ("fail", {"reason": "x"})):
            with self.subTest(action=action):
                response = self._transition(delivery.id, action, body=body)
                self.assertEqual(response.status_code, 409, response.content)
                self.assertEqual(response.json()["code"], "DELIVERY_TRANSITION_INVALID")

    def test_failed_is_terminal(self):
        delivery = self._scheduled()
        self._transition(delivery.id, "fail", body={"reason": "Customer postponed"})

        for action, body in (("start", {}), ("deliver", {}), ("fail", {"reason": "x"})):
            with self.subTest(action=action):
                response = self._transition(delivery.id, action, body=body)
                self.assertEqual(response.status_code, 409, response.content)
                self.assertEqual(response.json()["code"], "DELIVERY_TRANSITION_INVALID")


class DeliveryRoleTests(DeliveryTestBase):
    """The ruling's matrix: cashier takes the order, three roles move it, CPMS is out."""

    def _scheduled(self, *, auth=None):
        response = self._ring([self._cash(120)], delivery=delivery_body(), auth=auth)
        self.assertEqual(response.status_code, 201, response.content)
        return self._delivery_for(
            SalesTransaction.objects.get(pk=response.json()["id"])
        )

    def test_a_cashier_may_take_a_delivery_order(self):
        self._scheduled()

    def test_a_cashier_may_not_move_a_delivery(self):
        delivery = self._scheduled()

        response = self._transition(delivery.id, "start", auth=self.cashier_auth)

        self.assertEqual(response.status_code, 403, response.content)
        delivery.refresh_from_db()
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)

    def test_a_stock_manager_may_move_a_delivery(self):
        delivery = self._scheduled()

        response = self._transition(delivery.id, "start", auth=self.stocker_auth)

        self.assertEqual(response.status_code, 200, response.content)

    def test_a_store_manager_may_deliver(self):
        delivery = self._scheduled()
        self._transition(delivery.id, "start", auth=self.manager_auth)

        response = self._transition(delivery.id, "deliver", auth=self.manager_auth)

        self.assertEqual(response.status_code, 200, response.content)

    def test_an_admin_may_fail_a_delivery(self):
        delivery = self._scheduled()

        response = self._transition(
            delivery.id,
            "fail",
            body={"reason": "Address does not exist"},
            auth=self.admin_auth,
        )

        self.assertEqual(response.status_code, 200, response.content)

    def test_a_cashier_who_is_also_a_stock_manager_may_move_it(self):
        # Multi-role union: the wider role wins, exactly as `has_role` documents. The sale
        # is rung by the CASHIER (the multi-role account has no open shift), and the same
        # account then moves the delivery it could not move as a plain cashier.
        delivery = self._scheduled()

        response = self._transition(delivery.id, "start", auth=self.multi_auth)

        self.assertEqual(response.status_code, 200, response.content)

    def test_the_cpms_service_account_is_refused(self):
        delivery = self._scheduled()

        listing = self.client.get(DELIVERIES_URL, **self.cpms_auth)
        self.assertEqual(listing.status_code, 403, listing.content)

        moved = self._transition(delivery.id, "start", auth=self.cpms_auth)
        self.assertEqual(moved.status_code, 403, moved.content)
        delivery.refresh_from_db()
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)


class StoredAtOnSaleAndSlipTests(DeliveryTestBase):
    """B4 (decision 18): the till line and the delivery slip say where goods are kept.

    "Stored at" is a LABEL, not a second stock ledger: the sale line and the slip name
    the product's location so whoever prints the slip knows where to pick the goods up.
    """

    def _at_bodega(self):
        from apps.inventory.models import StorageLocation

        return StorageLocation.objects.get(name="Bodega")

    def test_a_sale_line_carries_the_label(self):
        Product.objects.filter(pk=self.variant.product_id).update(
            stored_at=self._at_bodega()
        )

        response = self._ring([self._cash(120)])

        self.assertEqual(response.status_code, 201, response.content)
        line = response.json()["items"][0]
        self.assertEqual(line["stored_at"], self._at_bodega().pk)
        self.assertEqual(line["stored_at_name"], "Bodega")
        detail = self.client.get(
            f"{TRANSACTIONS_URL}{response.json()['id']}/", **self.cashier_auth
        )
        self.assertEqual(detail.status_code, 200, detail.content)
        self.assertEqual(detail.json()["items"][0]["stored_at_name"], "Bodega")

    def test_the_slip_items_name_where_each_line_is_picked_up(self):
        Product.objects.filter(pk=self.variant.product_id).update(
            stored_at=self._at_bodega()
        )
        txn = SalesTransaction.objects.get(
            pk=self._ring([self._cash(120)], delivery=delivery_body()).json()["id"]
        )
        delivery = self._delivery_for(txn)

        slip = self.client.get(f"{DELIVERIES_URL}{delivery.id}/", **self.manager_auth)

        self.assertEqual(slip.status_code, 200, slip.content)
        line = slip.json()["items"][0]
        self.assertEqual(line["stored_at"], self._at_bodega().pk)
        self.assertEqual(line["stored_at_name"], "Bodega")

    def test_an_order_slip_item_carries_the_label_too(self):
        Product.objects.filter(pk=self.variant.product_id).update(
            stored_at=self._at_bodega()
        )
        order = self.client.post(
            ORDERS_URL,
            {
                "customer": self.regular.id,
                "items": [
                    {"variant_uom": self.vuom.id, "qty": "10.00", "unit_price": "10.00"}
                ],
                "delivery": delivery_body(fee="35.00"),
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(order.status_code, 201, order.content)
        delivery = Delivery.objects.get(sales_order_id=order.json()["id"])

        slip = self.client.get(f"{DELIVERIES_URL}{delivery.id}/", **self.manager_auth)

        self.assertEqual(slip.status_code, 200, slip.content)
        self.assertEqual(slip.json()["items"][0]["stored_at_name"], "Bodega")


class StoredAtQueryCountTests(DeliveryTestBase):
    """B4 fix: the sale list and detail join each line's location, never per line.

    `stored_at_name` walks `variant_uom -> variant -> product -> stored_at`; without the
    viewset's `Prefetch(...select_related(...))` that walk costs a few queries PER LINE,
    so a page with more lines would answer slower than the same page with fewer. Measured
    as "adding lines does not add queries", and the payload is asserted to carry the real
    label so joining the wrong path cannot pass by being fast.
    """

    def setUp(self):
        super().setUp()
        from apps.inventory.models import StorageLocation

        Product.objects.filter(pk=self.variant.product_id).update(
            stored_at=StorageLocation.objects.get(name="Bodega")
        )

    def _ring_lines(self, line_count):
        body = {
            "customer": self.regular.id,
            "source": "WALK_IN",
            "items": [
                {"variant_id": self.vuom.id, "qty": 1} for _ in range(line_count)
            ],
            "payments": [self._cash(line_count * 10)],
        }
        response = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(response.status_code, 201, response.content)
        return response.json()["id"]

    def _measure(self, url):
        with CaptureQueriesContext(connection) as captured:
            response = self.client.get(url, **self.cashier_auth)
        self.assertEqual(response.status_code, 200, response.content)
        return len(captured), response.json()

    def test_the_sale_list_does_not_query_once_per_line(self):
        self._ring_lines(1)
        first, first_payload = self._measure(TRANSACTIONS_URL)
        self.assertEqual(
            [line["stored_at_name"] for line in first_payload["results"][0]["items"]],
            ["Bodega"],
        )

        self._ring_lines(3)
        self._ring_lines(3)
        second, second_payload = self._measure(TRANSACTIONS_URL)

        self.assertEqual(
            [line["stored_at_name"] for line in second_payload["results"][0]["items"]],
            ["Bodega"] * 3,
        )
        self.assertEqual(first, second, "the sale list must not query once per line")

    def test_the_sale_detail_does_not_query_once_per_line(self):
        one_line = self._ring_lines(1)
        first, first_payload = self._measure(f"{TRANSACTIONS_URL}{one_line}/")
        self.assertEqual(
            [line["stored_at_name"] for line in first_payload["items"]], ["Bodega"]
        )

        three_lines = self._ring_lines(3)
        second, second_payload = self._measure(f"{TRANSACTIONS_URL}{three_lines}/")

        self.assertEqual(
            [line["stored_at_name"] for line in second_payload["items"]],
            ["Bodega"] * 3,
        )
        self.assertEqual(first, second, "the sale detail must not query once per line")


class SalesOrderDeliveryTests(DeliveryTestBase):
    """An order may be marked Deliver too.

    An order has no money total on the wire (its `items` are the promise, not a receipt),
    so the fee lives on the `Delivery` row and joins no sale: there is no fulfil-to-sale
    path in this codebase to carry it into, and inventing one is not this task's job.
    """

    def _order(self, **overrides):
        body = {
            "customer": self.regular.id,
            "items": [
                {"variant_uom": self.vuom.id, "qty": "10.00", "unit_price": "10.00"}
            ],
            "delivery": delivery_body(fee="35.00"),
        }
        body.update(overrides)
        return self.client.post(ORDERS_URL, body, format="json", **self.cashier_auth)

    def test_an_order_can_be_created_with_a_delivery(self):
        response = self._order()

        self.assertEqual(response.status_code, 201, response.content)
        order = SalesOrder.objects.get(pk=response.json()["id"])
        delivery = Delivery.objects.get(sales_order=order)
        self.assertIsNone(delivery.sale_id)
        self.assertEqual(delivery.fee, Decimal("35.00"))
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)

    def test_an_order_delivery_carries_the_orders_items_on_the_slip(self):
        order_id = self._order().json()["id"]
        delivery = Delivery.objects.get(sales_order_id=order_id)

        slip = self.client.get(f"{DELIVERIES_URL}{delivery.id}/", **self.manager_auth)

        self.assertEqual(slip.status_code, 200, slip.content)
        self.assertEqual(
            slip.json()["order_no"], SalesOrder.objects.get(pk=order_id).order_no
        )
        self.assertEqual(len(slip.json()["items"]), 1)
        self.assertEqual(slip.json()["items"][0]["unit"], "BAG")

    def test_an_order_delivery_moves_through_the_same_states(self):
        order_id = self._order().json()["id"]
        delivery = Delivery.objects.get(sales_order_id=order_id)

        self.assertEqual(self._transition(delivery.id, "start").status_code, 200)
        self.assertEqual(self._transition(delivery.id, "deliver").status_code, 200)
        # An order is a document, not money: nothing was sold and no stock moved.
        self.assertEqual(SalesTransaction.objects.count(), 0)


class ConcurrentDeliveryTransitionTests(TransactionTestCase):
    """Two role-holders pressing `start` at the same moment, on a committed row.

    `TransactionTestCase` because both workers must see each other's COMMITTED state: the
    wrapped transaction of a `TestCase` hides it and the race would be decided by timing
    instead of by the row lock.
    """

    def setUp(self):
        self.password = get_random_string(20)
        self.cashier = self._user("race_cashier", "Cashier")
        self.manager = self._user("race_manager", "Store Manager")
        self.stocker = self._user("race_stocker", "Stock Manager")
        category = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Rhino")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        product = Product.objects.create(
            category=category, brand=brand, base_name="Cement"
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        self.vuom = VariantUOM.objects.create(
            variant=variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        supplier = Supplier.objects.create(company_name="Acme Race")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=variant,
            ordered_qty=Decimal(20),
            unit_cost=Decimal(5),
            received_qty=Decimal(20),
        )
        process_goods_receipt(
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.manager),
            user=self.manager,
        )
        self.customer = Customer.objects.create(name="Race Customer")
        Shift.objects.create(cashier=self.cashier, opening_float=Decimal(0))
        # Rung through the SERVICE, so the only DELIVERY audit rows are the transitions.
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": Decimal(2)}],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(30)}],
            delivery_data=delivery_body(fee="10.00"),
        )
        self.delivery_id = Delivery.objects.get(sale=txn).id

    def _user(self, username, *groups):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@x.com",
            password=self.password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _login(self, client, user):
        login = client.post(
            LOGIN_URL,
            {"username": user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200, login.data)
        return {"HTTP_AUTHORIZATION": f"Bearer {login.json()['access']}"}

    def test_two_simultaneous_starts_let_one_win_and_audit_once(self):
        barrier = threading.Barrier(2, timeout=20)
        codes = []
        lock = threading.Lock()

        def worker(user):
            client = APIClient()
            auth = self._login(client, user)
            try:
                barrier.wait()
                response = client.post(
                    f"{DELIVERIES_URL}{self.delivery_id}/start/",
                    {},
                    format="json",
                    **auth,
                )
                code = response.status_code
            finally:
                connections.close_all()
            with lock:
                codes.append(code)

        threads = [
            threading.Thread(target=worker, args=(self.manager,)),
            threading.Thread(target=worker, args=(self.stocker,)),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(sorted(codes), [200, 409], codes)
        self.assertEqual(
            Delivery.objects.get(pk=self.delivery_id).status,
            Delivery.Status.OUT_FOR_DELIVERY,
        )
        self.assertEqual(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.DELIVERY).count(),
            1,
            "the losing request must write no audit row",
        )


class DeliverySchemaTests(TestCase):
    """The invariants that live in the DATABASE, not in a view-level lookup."""

    def test_a_delivery_needs_at_least_one_document(self):
        cashier = User.objects.create_user(
            username="schema_cashier", email="s@x.com", password="pass12345"
        )
        customer = Customer.objects.create(name="Schema Co")
        category = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Rhino")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        product = Product.objects.create(
            category=category, brand=brand, base_name="Cement"
        )
        variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        vuom = VariantUOM.objects.create(
            variant=variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        txn = SalesTransaction.objects.create(
            customer=customer, cashier=cashier, transaction_no="TRX-SCHEMA-1"
        )
        order = SalesOrder.objects.create(customer=customer, created_by=cashier)
        self.assertIsNotNone(vuom.pk)

        common = {
            "address": "A",
            "contact_name": "C",
            "contact_phone": "P",
            "scheduled_date": "2026-12-01",
            "fee": Decimal(0),
            "created_by": cashier,
        }
        # Phase 7 B1 (decision 19): BOTH links are allowed now - B4 re-links an order's
        # delivery to the first fulfilment sale and the row must keep the order it was
        # arranged for. The database refuses only a delivery that belongs to NOTHING.
        re_linked = Delivery.objects.create(sale=txn, sales_order=order, **common)
        self.assertEqual(re_linked.sale_id, txn.pk)
        self.assertEqual(re_linked.sales_order_id, order.pk)
        with self.assertRaises(IntegrityError), transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            Delivery.objects.create(**common)
        self.assertEqual(Delivery.objects.count(), 1)


class DeliveryScopeTests(DeliveryTestBase):
    """B3 review fix (decision 02): a cashier-only caller sees only THEIR deliveries.

    The review reproduced a cashier reading another till's delivery - address, contact
    name and phone, which is the customer's personal data. `/transactions/` already
    scoped a cashier-only user to the rows they own (`OwnSalesScopeMixin`); the
    deliveries endpoint had no scope at all. The rule is the SAME rule: the owner is
    `Delivery.created_by`, the cashier who took the order, and a foreign row is a
    **404** - hidden, not forbidden - so the API never confirms that a stranger's trip
    exists. Manager / Admin / Stock Manager keep the whole store, and the wider role
    wins for a cashier who holds one.
    """

    def setUp(self):
        super().setUp()
        self.cashier_b = self._user("d_cashier_b", "Cashier")
        Shift.objects.create(cashier=self.cashier_b, opening_float=Decimal(5000))
        self.cashier_b_auth = _auth(self._token("d_cashier_b", self._user_password))
        self.delivery_a = self._taken(self.cashier_auth)
        self.delivery_b = self._taken(self.cashier_b_auth)

    def _taken(self, auth):
        # Two units: `POSTestBase` stocks ten base units, and each cashier needs a full
        # sale with its own delivery row.
        response = self._ring(
            [self._cash(40)], qty=2, delivery=delivery_body(), auth=auth
        )
        self.assertEqual(response.status_code, 201, response.content)
        return self._delivery_for(
            SalesTransaction.objects.get(pk=response.json()["id"])
        )

    def _ids(self, auth, query=""):
        response = self.client.get(f"{DELIVERIES_URL}{query}", **auth)
        self.assertEqual(response.status_code, 200, response.content)
        return [row["id"] for row in response.json()["results"]]

    def test_a_cashier_lists_only_the_deliveries_they_took(self):
        self.assertEqual(self._ids(self.cashier_auth), [self.delivery_a.id])

    def test_a_cashier_still_reads_their_own_delivery(self):
        response = self.client.get(
            f"{DELIVERIES_URL}{self.delivery_a.id}/", **self.cashier_auth
        )

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["id"], self.delivery_a.id)

    def test_another_cashiers_delivery_is_404_not_403(self):
        response = self.client.get(
            f"{DELIVERIES_URL}{self.delivery_b.id}/", **self.cashier_auth
        )

        self.assertEqual(
            response.status_code,
            404,
            "a row outside the caller's scope must not be confirmed to exist",
        )

    def test_the_status_filter_runs_inside_the_scope(self):
        self._transition(self.delivery_b.id, "start")

        self.assertEqual(
            self._ids(self.cashier_auth, "?status=OUT_FOR_DELIVERY"),
            [],
            "the filter must not widen the scope to another till's trip",
        )
        self.assertEqual(
            self._ids(self.cashier_b_auth, "?status=OUT_FOR_DELIVERY"),
            [self.delivery_b.id],
        )

    def test_a_store_manager_sees_every_delivery(self):
        self.assertEqual(
            sorted(self._ids(self.manager_auth)),
            sorted([self.delivery_a.id, self.delivery_b.id]),
        )

    def test_a_stock_manager_sees_every_delivery(self):
        self.assertEqual(
            sorted(self._ids(self.stocker_auth)),
            sorted([self.delivery_a.id, self.delivery_b.id]),
        )

    def test_a_cashier_who_is_also_a_manager_sees_every_delivery(self):
        # The wider role wins, exactly as it does on /transactions/.
        self.assertEqual(
            sorted(self._ids(self.multi_auth)),
            sorted([self.delivery_a.id, self.delivery_b.id]),
        )

    def test_an_order_delivery_is_scoped_to_the_cashier_who_took_the_order(self):
        order = self.client.post(
            ORDERS_URL,
            {
                "customer": self.regular.id,
                "items": [
                    {"variant_uom": self.vuom.id, "qty": "2.00", "unit_price": "10.00"}
                ],
                "delivery": delivery_body(fee="35.00"),
            },
            format="json",
            **self.cashier_b_auth,
        )
        self.assertEqual(order.status_code, 201, order.content)
        delivery = Delivery.objects.get(sales_order_id=order.json()["id"])

        self.assertIn(delivery.id, self._ids(self.cashier_b_auth))
        self.assertNotIn(delivery.id, self._ids(self.cashier_auth))
        foreign = self.client.get(
            f"{DELIVERIES_URL}{delivery.id}/", **self.cashier_auth
        )
        self.assertEqual(foreign.status_code, 404, foreign.content)

    def test_a_foreign_delivery_cannot_be_moved(self):
        # A cashier may not move ANY delivery (403 from the permission class, which runs
        # before the row is looked up), and the scope is what keeps the row itself out of
        # reach for a scoped caller. Either way the trip does not move.
        response = self._transition(self.delivery_b.id, "start", auth=self.cashier_auth)

        self.assertIn(response.status_code, (403, 404), response.content)
        self.delivery_b.refresh_from_db()
        self.assertEqual(self.delivery_b.status, Delivery.Status.SCHEDULED)
