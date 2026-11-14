# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# `reportArgumentType` for the same reason `apps/pos/tests.py` carries it: the Django test
# client takes unknown call kwargs straight into the WSGI environ (that is HOW an
# Authorization header or an Idempotency-Key is set), so the splatted HTTP_* dict reads as
# `follow=`/`secure=` to this checker. The test run remains the authority.
"""Phase 7 tasks B1/B3/B4 (decision 19) — the sales-order lifecycle.

B1 pinned the schema and the status machine, B3 the manager's edit/cancel, and B4 the
fulfilment that rings an order into a real sale through `process_sale`. These tests pin
the facts every later task reads — the legacy-status rule, the one transition table, the
per-line arithmetic the order sheet and the till both use, and the money rules a
fulfilment shares with checkout (price source, fee once, VAT, change, utang).
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

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
    SalesOrder,
    SalesOrderItem,
    SalesTransaction,
    Shift,
    StoreSettings,
)
from apps.pos.services import SALES_ORDER_TRANSITIONS, issue_discount_approval
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
ORDERS_URL = "/api/v1/sales-orders/"
TRANSACTIONS_URL = "/api/v1/transactions/"


class SalesOrderLifecycleBase(TestCase):
    def setUp(self):
        self.manager = User.objects.create_superuser(
            username="lcmgr", email="lc@x.com", password="pass12345"
        )
        # REGULAR, not the model's WALK_IN default: B5 refuses an order on the walk-in
        # placeholder (decision 19's "walk-in orders are already impossible"), so every
        # order a test POSTs names a real customer.
        self.customer = Customer.objects.create(
            name="Reyes Trading", customer_type=Customer.Type.REGULAR
        )
        category = Category.objects.create(name="Lifecycle Cement")
        brand = Brand.objects.create(name="Lifecycle Rhino")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="LCBAG", defaults={"name": "Lifecycle Bag"}
        )
        product = Product.objects.create(
            category=category, brand=brand, base_name="Lifecycle Cement"
        )
        self.variant = ProductVariant.objects.create(
            product=product, variant_name="40kg", base_uom=uom
        )
        self.variant_uom = VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(315),
        )
        self.client = APIClient()
        response = self.client.post(
            LOGIN_URL, {"username": "lcmgr", "password": "pass12345"}, format="json"
        )
        token = response.data.get("access") or response.data.get("token")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def _order(self, *, status=None, qty="10.00", unit_price="315.00"):
        order = SalesOrder.objects.create(
            customer=self.customer, created_by=self.manager
        )
        if status is not None:
            # A legacy row is what Phase 5 wrote; the model default is CONFIRMED.
            SalesOrder.objects.filter(pk=order.pk).update(status=status)
            order.refresh_from_db()
        SalesOrderItem.objects.create(
            order=order,
            variant_uom=self.variant_uom,
            qty=Decimal(qty),
            unit_price=Decimal(unit_price),
        )
        return order


class LegacyStatusReadingTests(SalesOrderLifecycleBase):
    """Decision 19: legacy PROCESSING/READY rows read as CONFIRMED, on the wire too."""

    def test_a_legacy_ready_order_reads_as_confirmed(self):
        order = self._order(status=SalesOrder.Status.READY)

        self.assertEqual(order.status, SalesOrder.Status.READY, "the row is unchanged")
        self.assertEqual(order.effective_status, SalesOrder.Status.CONFIRMED)

        response = self.client.get(f"{ORDERS_URL}{order.pk}/")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CONFIRMED")

    def test_a_legacy_processing_order_reads_as_confirmed(self):
        order = self._order(status=SalesOrder.Status.PROCESSING)

        self.assertEqual(order.effective_status, SalesOrder.Status.CONFIRMED)
        response = self.client.get(f"{ORDERS_URL}{order.pk}/")
        self.assertEqual(response.data["status"], "CONFIRMED")

    def test_a_lifecycle_order_reads_as_its_own_status(self):
        order = self._order(status=SalesOrder.Status.PARTIAL)

        self.assertEqual(order.effective_status, SalesOrder.Status.PARTIAL)
        response = self.client.get(f"{ORDERS_URL}{order.pk}/")
        self.assertEqual(response.data["status"], "PARTIAL")

    def test_a_new_order_is_confirmed(self):
        order = self._order()

        self.assertEqual(order.effective_status, SalesOrder.Status.CONFIRMED)


class StatusIsNotClientWritableTests(SalesOrderLifecycleBase):
    """Decision 19: status is a server action, never a field a client writes."""

    def test_the_create_body_cannot_choose_a_status(self):
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "status": "CANCELLED",
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "10.00",
                        "unit_price": "315.00",
                    }
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "CONFIRMED")
        self.assertEqual(
            SalesOrder.objects.get(pk=response.data["id"]).status,
            SalesOrder.Status.CONFIRMED,
        )

    def test_a_status_write_never_changes_the_row(self):
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"status": "CANCELLED", "reason": "Trying to write a status", "notes": "x"},
            format="json",
        )

        # B1 kept PATCH unrouted; B3 routes it for managers. Either way `status` is
        # READ-ONLY: the field is ignored, so the row and the wire stay CONFIRMED and the
        # only way to cancel is the reasoned `cancel/` action.
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CONFIRMED")
        self.assertEqual(
            SalesOrder.objects.get(pk=order.pk).status, SalesOrder.Status.CONFIRMED
        )


class RemainingQuantityTests(SalesOrderLifecycleBase):
    """Decision 19 #3: the order tracks fulfilled vs remaining per line."""

    def test_remaining_qty_subtracts_fulfilled_and_cancelled(self):
        order = self._order(qty="10.00")
        line = order.items.get()
        line.fulfilled_qty = Decimal("4.00")
        line.cancelled_qty = Decimal("1.50")
        line.save(update_fields=["fulfilled_qty", "cancelled_qty"])

        self.assertEqual(order.items.get().remaining_qty, Decimal("4.50"))

    def test_remaining_qty_starts_at_the_ordered_quantity(self):
        order = self._order(qty="10.00")

        line = order.items.get()
        self.assertEqual(line.fulfilled_qty, Decimal("0.00"))
        self.assertEqual(line.cancelled_qty, Decimal("0.00"))
        self.assertEqual(line.remaining_qty, Decimal("10.00"))

    def test_the_wire_exposes_the_line_quantities_read_only(self):
        order = self._order(qty="10.00")
        line = order.items.get()
        line.fulfilled_qty = Decimal("6.00")
        line.cancelled_qty = Decimal("1.00")
        line.save(update_fields=["fulfilled_qty", "cancelled_qty"])

        response = self.client.get(f"{ORDERS_URL}{order.pk}/")
        row = response.data["items"][0]
        self.assertEqual(Decimal(row["fulfilled_qty"]), Decimal("6.00"))
        self.assertEqual(Decimal(row["cancelled_qty"]), Decimal("1.00"))
        self.assertEqual(Decimal(row["remaining_qty"]), Decimal("3.00"))

    def test_a_client_cannot_set_the_line_quantities(self):
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "10.00",
                        "unit_price": "315.00",
                        "fulfilled_qty": "10.00",
                        "cancelled_qty": "10.00",
                    }
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        line = SalesOrderItem.objects.get(order_id=response.data["id"])
        self.assertEqual(line.fulfilled_qty, Decimal("0.00"))
        self.assertEqual(line.cancelled_qty, Decimal("0.00"))


class OrderLinePriceGuardTests(SalesOrderLifecycleBase):
    """Decision 19 #1: a line below catalogue is a discount, capped at save time.

    The catalogue price is the selling unit's `default_selling_price` (315.00 here); a
    line BELOW it discounts `(catalogue - agreed) / catalogue`, and the LARGEST line
    percent is what the Admin's cap and a manager's token are compared against.
    """

    def _post(self, *, lines, **extra):
        return self.client.post(
            ORDERS_URL,
            {"customer": self.customer.id, "items": lines, **extra},
            format="json",
        )

    def _line(self, unit_price, qty="10.00"):
        return {
            "variant_uom": self.variant_uom.id,
            "qty": qty,
            "unit_price": unit_price,
        }

    def _assert_nothing_written(self):
        self.assertFalse(SalesOrder.objects.exists(), "no order")
        self.assertFalse(SalesOrderItem.objects.exists(), "no lines")
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.CREATE).exists(),
            "no CREATE audit row",
        )

    def test_a_line_fifty_percent_below_catalogue_is_refused(self):
        response = self._post(lines=[self._line("157.50")])

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DISCOUNT_OVER_CAP")
        self.assertEqual(response.data["cap_percent"], "10.00")
        self.assertEqual(response.data["requested_percent"], "50.00")
        self._assert_nothing_written()

    def test_the_largest_line_percent_decides(self):
        response = self._post(
            lines=[self._line("157.50"), self._line("315.00", qty="1.00")]
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DISCOUNT_OVER_CAP")
        self.assertEqual(response.data["requested_percent"], "50.00")
        self._assert_nothing_written()

    def test_a_line_within_the_cap_saves_as_is(self):
        response = self._post(lines=[self._line("300.00")])

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["items"][0]["unit_price"], "300.00")

    def test_an_above_catalogue_price_is_not_a_discount(self):
        response = self._post(lines=[self._line("400.00")])

        self.assertEqual(response.status_code, 201, response.data)

    def test_an_above_cap_order_with_a_token_saves_and_stamps_the_approval(self):
        approval, token = issue_discount_approval(
            approver=self.manager, percent=Decimal("50.00"), reason="Panel price match"
        )

        response = self._post(lines=[self._line("157.50")], discount_approval=token)

        self.assertEqual(response.status_code, 201, response.data)
        approval.refresh_from_db()
        self.assertIsNotNone(approval.used_at, "the token is spent by the order")
        self.assertEqual(approval.sales_order_id, response.data["id"])

    def test_a_bad_token_is_refused_and_writes_nothing(self):
        response = self._post(
            lines=[self._line("157.50")], discount_approval="not-a-real-token"
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DISCOUNT_APPROVAL_INVALID")
        self._assert_nothing_written()

    def test_a_token_too_small_for_the_line_is_refused(self):
        approval, token = issue_discount_approval(
            approver=self.manager, percent=Decimal("20.00")
        )

        response = self._post(lines=[self._line("157.50")], discount_approval=token)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DISCOUNT_APPROVAL_INVALID")
        approval.refresh_from_db()
        self.assertIsNone(approval.used_at, "a refusal spends nothing")
        self.assertIsNone(approval.sales_order_id)
        self._assert_nothing_written()

    def test_the_cap_is_the_admins_number_not_a_constant(self):
        settings_row = StoreSettings.load()
        settings_row.discount_cap_percent = Decimal("60.00")
        settings_row.save(update_fields=["discount_cap_percent"])

        response = self._post(lines=[self._line("157.50")])

        self.assertEqual(response.status_code, 201, response.data)

    def test_a_line_exactly_at_the_cap_saves(self):
        # 283.50 is exactly 10.00 percent below the 315.00 catalogue; 283.51 rounds to the
        # same 10.00 through `money_round`. The comparison is `> cap`, so the cap itself is
        # allowed - a manager is only called for a discount MORE than the Admin permits.
        for agreed in ("283.50", "283.51"):
            with self.subTest(agreed=agreed):
                response = self._post(lines=[self._line(agreed)])

                self.assertEqual(response.status_code, 201, response.data)
                self.assertEqual(response.data["items"][0]["unit_price"], agreed)

    def test_a_cashier_saving_with_a_manager_token_is_allowed(self):
        # Decision 19 ruling 2: the approval rule is ROLE-BLIND. The manager's credentials
        # mint the token; the cashier who types the order spends it.
        from django.contrib.auth.models import Group

        User = get_user_model()
        cashier = User.objects.create_user(
            username="b2cashier", email="b2c@x.com", password="pass12345"
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        cashier_client = APIClient()
        login = cashier_client.post(
            LOGIN_URL, {"username": "b2cashier", "password": "pass12345"}, format="json"
        )
        cashier_client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        approval, token = issue_discount_approval(
            approver=self.manager, percent=Decimal("50.00")
        )

        response = cashier_client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [self._line("157.50")],
                "discount_approval": token,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        approval.refresh_from_db()
        self.assertEqual(approval.sales_order_id, response.data["id"])
        self.assertIsNotNone(approval.used_at, "the token is spent")


class TransitionTableTests(TestCase):
    """Decision 19: the lifecycle is DATA, so a jump that is not listed is impossible."""

    def test_the_lifecycle_allows_only_the_ruled_moves(self):
        self.assertEqual(
            {
                status: set(targets)
                for status, targets in SALES_ORDER_TRANSITIONS.items()
            },
            {
                SalesOrder.Status.CONFIRMED: {
                    SalesOrder.Status.PARTIAL,
                    SalesOrder.Status.COMPLETED,
                    SalesOrder.Status.CANCELLED,
                },
                SalesOrder.Status.PARTIAL: {SalesOrder.Status.COMPLETED},
            },
        )

    def test_no_transition_leads_back_to_a_legacy_status(self):
        legacy = {SalesOrder.Status.PROCESSING, SalesOrder.Status.READY}

        for targets in SALES_ORDER_TRANSITIONS.values():
            self.assertFalse(legacy & set(targets), targets)

    def test_terminal_statuses_are_absent(self):
        for status in (SalesOrder.Status.COMPLETED, SalesOrder.Status.CANCELLED):
            self.assertNotIn(status, SALES_ORDER_TRANSITIONS)


# ---------------------------------------------------------------------------
# Phase 7 B3 (decision 19 #4) — managers edit and cancel; cashiers neither.
# ---------------------------------------------------------------------------

DELIVERY_BODY = {
    "address": "12 Mabini St, Barangay San Roque, Quezon City",
    "contact_name": "Ana Reyes",
    "contact_phone": "0917-555-0100",
    "scheduled_date": "2026-12-01",
    "fee": "20.00",
}


class SalesOrderActionBase(SalesOrderLifecycleBase):
    """Shared helpers for the B3 edit/cancel tests."""

    def _cashier_client(self, username="b3cashier"):
        from django.contrib.auth.models import Group

        cashier = User.objects.create_user(
            username=username, email=f"{username}@x.com", password="pass12345"
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        client = APIClient()
        login = client.post(
            LOGIN_URL, {"username": username, "password": "pass12345"}, format="json"
        )
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        return client

    def _line_body(self, unit_price="315.00", qty="10.00"):
        return {
            "variant_uom": self.variant_uom.id,
            "qty": qty,
            "unit_price": unit_price,
        }

    def _order_with_delivery(self, **delivery_overrides):
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [self._line_body()],
                "delivery": {**DELIVERY_BODY, **delivery_overrides},
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        order = SalesOrder.objects.get(pk=response.data["id"])
        return order

    def _order_audit_rows(self):
        return AuditLog.objects.filter(action_type=AuditLog.ActionType.SALES_ORDER)


class SalesOrderEditTests(SalesOrderActionBase):
    """PATCH /sales-orders/{id}/ — Store Manager/Admin, CONFIRMED and nothing fulfilled."""

    def test_a_cashier_cannot_edit_an_order(self):
        order = self._order()
        cashier = self._cashier_client()

        response = cashier.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"notes": "Call before delivery", "reason": "Customer asked"},
            format="json",
        )

        self.assertEqual(response.status_code, 403, response.data)

    def test_a_manager_can_replace_the_lines(self):
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {
                "items": [self._line_body("300.00", "4.00"), self._line_body("315.00")],
                "reason": "Customer changed the order",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(len(response.data["items"]), 2)
        prices = sorted(row["unit_price"] for row in response.data["items"])
        self.assertEqual(prices, ["300.00", "315.00"])
        self.assertEqual(
            order.items.count(), 2, "the old line is replaced, not added to"
        )

    def test_an_edit_needs_a_reason(self):
        order = self._order()

        missing = self.client.patch(
            f"{ORDERS_URL}{order.pk}/", {"notes": "no reason"}, format="json"
        )
        blank = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"notes": "blank", "reason": "   "},
            format="json",
        )

        for response in (missing, blank):
            self.assertEqual(response.status_code, 400, response.data)
            self.assertEqual(response.data["code"], "SALES_ORDER_REASON_REQUIRED")
        order.refresh_from_db()
        self.assertEqual(order.notes, "")
        self.assertFalse(self._order_audit_rows().exists(), "a refusal writes no trail")

    def test_an_edit_re_runs_the_price_guard(self):
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {
                "items": [self._line_body("157.50")],
                "reason": "Panel price match",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "DISCOUNT_OVER_CAP")
        self.assertEqual(
            order.items.get().unit_price, Decimal("315.00"), "nothing changed"
        )
        self.assertFalse(self._order_audit_rows().exists())

    def test_an_edit_with_a_token_saves_and_stamps_the_approval(self):
        order = self._order()
        approval, token = issue_discount_approval(
            approver=self.manager, percent=Decimal("50.00"), reason="Panel price match"
        )

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {
                "items": [self._line_body("157.50")],
                "reason": "Panel price match",
                "discount_approval": token,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        approval.refresh_from_db()
        self.assertIsNotNone(approval.used_at, "the edit spends the token")
        self.assertEqual(approval.sales_order_id, order.pk)

    def test_an_edit_cannot_patch_a_single_nested_line(self):
        order = self._order()
        line = order.items.get()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"items": [{"id": line.pk, "qty": "2.00"}], "reason": "Just this line"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(order.items.get().qty, Decimal("10.00"), "nothing changed")

    def test_an_edit_is_refused_after_a_partial_fulfilment(self):
        order = self._order()
        line = order.items.get()
        line.fulfilled_qty = Decimal("2.00")
        line.save(update_fields=["fulfilled_qty"])
        SalesOrder.objects.filter(pk=order.pk).update(status=SalesOrder.Status.PARTIAL)

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"notes": "late edit", "reason": "Oops"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_NOT_EDITABLE")

    def test_an_edit_is_refused_when_a_line_is_already_fulfilled(self):
        # The status is still CONFIRMED but a line has moved: the second half of the gate.
        order = self._order()
        line = order.items.get()
        line.fulfilled_qty = Decimal("2.00")
        line.save(update_fields=["fulfilled_qty"])

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"notes": "late edit", "reason": "Oops"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_NOT_EDITABLE")

    def test_an_edit_of_a_cancelled_order_is_refused(self):
        order = self._order(status=SalesOrder.Status.CANCELLED)

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"notes": "edit", "reason": "Oops"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_NOT_EDITABLE")

    def test_an_edit_does_not_change_the_customer(self):
        order = self._order()
        other = Customer.objects.create(name="Someone Else")

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"customer": other.id, "reason": "Wrong customer"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        order.refresh_from_db()
        self.assertEqual(order.customer_id, self.customer.id)

    def test_an_edit_updates_the_delivery_while_it_is_scheduled(self):
        order = self._order_with_delivery()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {
                "delivery": {
                    **DELIVERY_BODY,
                    "fee": "35.00",
                    "address": "9 Mabini Ext.",
                },
                "reason": "Customer moved",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        delivery = order.deliveries.get()
        self.assertEqual(delivery.fee, Decimal("35.00"))
        self.assertEqual(delivery.address, "9 Mabini Ext.")
        self.assertEqual(delivery.status, Delivery.Status.SCHEDULED)

    def test_an_edit_of_a_delivery_already_out_is_refused(self):
        order = self._order_with_delivery()
        Delivery.objects.filter(sales_order=order).update(
            status=Delivery.Status.OUT_FOR_DELIVERY
        )

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"delivery": {**DELIVERY_BODY, "fee": "35.00"}, "reason": "Moved"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(order.deliveries.get().fee, Decimal("20.00"))

    def test_an_edit_is_audited_as_a_sales_order_event(self):
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {
                "items": [self._line_body("300.00", "4.00")],
                "reason": "Customer cut it down",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        row = self._order_audit_rows().get()
        self.assertIn(order.order_no, row.description)
        self.assertIn("Customer cut it down", row.description)
        self.assertIn("lines 1 -> 1", row.description)

    # --- B3 review round: the `reason` field, the notes-only edit, and the empty edit.

    def test_a_create_body_may_carry_a_reason(self):
        # The `reason` field exists for the EDIT, but a client that echoes it on create
        # must not reach `SalesOrder.objects.create(reason=...)`: there is no such column,
        # and the TypeError used to surface as a 500 on an ordinary POST.
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [self._line_body()],
                "reason": "Phone order, no changes yet",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "CONFIRMED")
        self.assertTrue(SalesOrder.objects.filter(pk=response.data["id"]).exists())

    def test_an_edit_without_a_line_block_keeps_the_lines(self):
        # Ported from the retired duplicate suite: an edit that names no lines is a notes
        # edit, and it must not touch the promised lines.
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"reason": "Note only", "notes": "Ring before delivery"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.notes, "Ring before delivery")
        self.assertEqual(order.items.count(), 1)
        self.assertEqual(order.items.get().unit_price, Decimal("315.00"))

    def test_an_edit_that_only_carries_a_reason_succeeds(self):
        # Nothing to change is still a legal edit: the manager looked, and the audit row
        # records that the order was reviewed under a reason.
        order = self._order()

        response = self.client.patch(
            f"{ORDERS_URL}{order.pk}/",
            {"reason": "Reviewed, nothing to change"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CONFIRMED")
        self.assertEqual(len(response.data["items"]), 1)
        self.assertEqual(self._order_audit_rows().count(), 1)


class SalesOrderCancelTests(SalesOrderActionBase):
    """POST /sales-orders/{id}/cancel/ {reason} — the reasoned way out of a promise."""

    def test_a_cashier_cannot_cancel_an_order(self):
        order = self._order()
        cashier = self._cashier_client("b3cancashier")

        response = cashier.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer called"},
            format="json",
        )

        self.assertEqual(response.status_code, 403, response.data)

    def test_a_cancel_needs_a_reason(self):
        order = self._order()

        missing = self.client.post(f"{ORDERS_URL}{order.pk}/cancel/", {}, format="json")
        blank = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/", {"reason": "  "}, format="json"
        )

        for response in (missing, blank):
            self.assertEqual(response.status_code, 400, response.data)
            self.assertEqual(response.data["code"], "SALES_ORDER_REASON_REQUIRED")
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)
        self.assertFalse(self._order_audit_rows().exists())

    def test_cancelling_a_confirmed_order_cancels_its_lines(self):
        order = self._order(qty="10.00")

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "CANCELLED")
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CANCELLED)
        self.assertEqual(order.cancel_reason, "Customer backed out")
        self.assertEqual(order.cancelled_by_id, self.manager.pk)
        self.assertIsNotNone(order.cancelled_at)
        line = order.items.get()
        self.assertEqual(line.cancelled_qty, Decimal("10.00"))
        self.assertEqual(line.remaining_qty, Decimal("0.00"))

    def test_cancelling_a_partially_fulfilled_order_completes_it(self):
        order = self._order(qty="10.00")
        line = order.items.get()
        line.fulfilled_qty = Decimal("4.00")
        line.save(update_fields=["fulfilled_qty"])
        SalesOrder.objects.filter(pk=order.pk).update(status=SalesOrder.Status.PARTIAL)

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Only half delivered"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], "COMPLETED")
        line.refresh_from_db()
        self.assertEqual(
            line.fulfilled_qty, Decimal("4.00"), "what was rung stays rung"
        )
        self.assertEqual(
            line.cancelled_qty, Decimal("6.00"), "the remainder is written off"
        )
        self.assertEqual(line.remaining_qty, Decimal("0.00"))

    def test_cancelling_marks_a_scheduled_delivery_failed(self):
        order = self._order_with_delivery()

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        delivery = order.deliveries.get()
        self.assertEqual(delivery.status, Delivery.Status.FAILED)
        self.assertEqual(
            delivery.failure_reason, "Order cancelled: Customer backed out"
        )

    def test_cancelling_is_refused_while_the_delivery_is_out(self):
        order = self._order_with_delivery()
        Delivery.objects.filter(sales_order=order).update(
            status=Delivery.Status.OUT_FOR_DELIVERY
        )

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_CANCEL_BLOCKED")
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED, "nothing changed")
        self.assertEqual(
            order.deliveries.get().status, Delivery.Status.OUT_FOR_DELIVERY
        )
        self.assertFalse(self._order_audit_rows().exists())

    def test_cancelling_a_finished_order_is_refused(self):
        for status in (SalesOrder.Status.CANCELLED, SalesOrder.Status.COMPLETED):
            with self.subTest(status=status):
                order = self._order(status=status)

                response = self.client.post(
                    f"{ORDERS_URL}{order.pk}/cancel/",
                    {"reason": "again"},
                    format="json",
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data["code"], "SALES_ORDER_TRANSITION_INVALID"
                )
                order.refresh_from_db()
                self.assertEqual(order.status, status)

    def test_a_cancel_is_audited_as_a_sales_order_event(self):
        order = self._order()

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        row = self._order_audit_rows().get()
        self.assertIn(order.order_no, row.description)
        self.assertIn("Customer backed out", row.description)
        self.assertIn("CONFIRMED -> CANCELLED", row.description)

    # --- B3 review round: FAILED slips, DELIVERED slips, and a partial cancel in flight.

    def test_cancelling_leaves_a_failed_delivery_untouched(self):
        # Decision 19 refuses only OUT_FOR_DELIVERY/DELIVERED. A slip whose trip already
        # FAILED is a closed fact: the order can be cancelled, and the slip keeps the
        # reason it already carries.
        order = self._order_with_delivery()
        Delivery.objects.filter(sales_order=order).update(
            status=Delivery.Status.FAILED, failure_reason="Customer not home"
        )

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CANCELLED)
        delivery = order.deliveries.get()
        self.assertEqual(delivery.status, Delivery.Status.FAILED)
        self.assertEqual(delivery.failure_reason, "Customer not home")

    def test_cancelling_is_refused_once_the_delivery_is_delivered(self):
        # Ported from the retired duplicate suite: DELIVERED is the second status the
        # ruling names, and it blocks a cancel exactly like OUT_FOR_DELIVERY.
        order = self._order_with_delivery()
        Delivery.objects.filter(sales_order=order).update(
            status=Delivery.Status.DELIVERED
        )

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Customer backed out"},
            format="json",
        )

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_CANCEL_BLOCKED")
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)

    def test_a_partial_cancel_leaves_a_delivery_in_flight_alone(self):
        # Ported from the retired duplicate suite: once a fulfilment has gone out, the
        # slip belongs to that SALE, so closing the remainder must not be blocked by it.
        order = self._order_with_delivery()
        line = order.items.get()
        line.fulfilled_qty = Decimal("4.00")
        line.save(update_fields=["fulfilled_qty"])
        SalesOrder.objects.filter(pk=order.pk).update(status=SalesOrder.Status.PARTIAL)
        Delivery.objects.filter(sales_order=order).update(
            status=Delivery.Status.OUT_FOR_DELIVERY
        )

        response = self.client.post(
            f"{ORDERS_URL}{order.pk}/cancel/",
            {"reason": "Rest of it is not coming"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.COMPLETED)
        self.assertEqual(
            order.deliveries.get().status, Delivery.Status.OUT_FOR_DELIVERY
        )


class SalesOrderFulfilmentBase(SalesOrderActionBase):
    """Shared helpers for the B4 fulfil tests: stock, an open shift, a priced order.

    Every fulfilment goes through `process_sale`, so the fixtures are the checkout
    fixtures: stock on the shelf (FIFO has to have something to take), an open shift for
    the cashier ringing it, and an order whose agreed price differs from the catalogue
    price - that difference is what proves WHERE a fulfilment's money comes from.
    """

    def setUp(self):
        super().setUp()
        # Decision 19's delegated default: a fulfilment uses the order's NAMED customer
        # (a walk-in order is impossible), and only a named customer may owe - the
        # walk-in record is a placeholder nobody owes. The lifecycle base's customer is
        # whatever the model default is, so it is named here for the B4 tests only.
        Customer.objects.filter(pk=self.customer.pk).update(
            customer_type=Customer.Type.REGULAR
        )
        self.customer.refresh_from_db()
        self._stock("100")

    def _stock(self, qty):
        supplier = Supplier.objects.create(company_name="Fulfilment Supply")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=self.variant,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal(200),
            received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

    def _open_shift(self):
        return Shift.objects.create(cashier=self.manager, opening_float=Decimal(5000))

    def _fulfiller(self, username="b4cashier"):
        cashier = User.objects.create_user(
            username=username, email=f"{username}@x.com", password="pass12345"
        )
        cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        client = APIClient()
        login = client.post(
            LOGIN_URL, {"username": username, "password": "pass12345"}, format="json"
        )
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        return client, cashier

    def _cash(self, amount):
        return [{"method": "CASH", "amount_tendered": amount}]

    def _fulfil(
        self, order, *, lines, payments=None, delivery=None, key=None, client=None
    ):
        body = {"lines": lines, "payments": payments if payments is not None else []}
        if delivery is not None:
            body["delivery"] = delivery
        headers = {"format": "json"}
        if key is not None:
            headers["HTTP_IDEMPOTENCY_KEY"] = key
        return (client or self.client).post(
            f"{ORDERS_URL}{order.pk}/fulfil/", body, **headers
        )

    def _line(self, order, qty, *, index=0):
        return {"order_line": order.items.all()[index].id, "qty": qty}


class SalesOrderFulfilTests(SalesOrderFulfilmentBase):
    """POST /sales-orders/{id}/fulfil/ — decision 19 #3/#4, through `process_sale`."""

    def test_a_fulfilment_rings_a_sale_at_the_agreed_price(self):
        # Money rule #1 (decision 19 #1): the SALE charges the order's agreed line price,
        # never today's catalogue price, and carries no sale-level discount (the approval
        # was spent when the order was saved).
        order = self._order(qty="10.00", unit_price="300.00")
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1200.00")
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = SalesTransaction.objects.get(pk=response.data["id"])
        item = sale.items.get()
        self.assertEqual(item.unit_price, Decimal("300.00"), "order price, not 315")
        self.assertEqual(item.order_line_id, order.items.get().id)
        self.assertEqual(sale.grand_total, Decimal("1200.00"))
        self.assertEqual(sale.discount_amount, Decimal("0.00"))
        self.assertEqual(sale.customer_id, order.customer_id)
        # The same VAT split a walk-in sale gets: tax comes OUT of the inclusive total.
        self.assertEqual(
            sale.vatable_sales + sale.vat_amount, sale.grand_total, "VAT adds back up"
        )
        line = order.items.get()
        self.assertEqual(line.fulfilled_qty, Decimal("4.00"))
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.PARTIAL)

    def test_the_fulfilment_and_its_audit_rows_are_one_transaction(self):
        order = self._order()
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.SALE).count(), 1
        )
        row = AuditLog.objects.get(action_type=AuditLog.ActionType.SALES_ORDER)
        self.assertIn(order.order_no, row.description)

    def test_the_last_fulfilment_completes_the_order(self):
        order = self._order(qty="6.00")
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "6.00")], payments=self._cash("1890.00")
        )

        self.assertEqual(response.status_code, 201, response.data)
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.COMPLETED)
        self.assertEqual(order.items.get().fulfilled_qty, Decimal("6.00"))

    def test_two_fulfilments_cannot_both_take_the_same_quantity(self):
        # The double-fulfilment race from the outside: the first request takes the whole
        # order, the second (tenant of the same lock) must be REFUSED, not 500 and not a
        # second sale.
        order = self._order(qty="4.00")
        self._open_shift()

        first = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )
        second = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(second.status_code, 400, second.data)
        self.assertEqual(second.data["code"], "SALES_ORDER_TRANSITION_INVALID")
        self.assertEqual(SalesTransaction.objects.count(), 1, "one sale only")
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.COMPLETED)
        self.assertEqual(order.items.get().fulfilled_qty, Decimal("4.00"))

    def test_a_fulfilment_above_the_remaining_quantity_is_refused(self):
        order = self._order(qty="10.00")
        line = order.items.get()
        line.fulfilled_qty = Decimal("8.00")
        line.save(update_fields=["fulfilled_qty"])
        SalesOrder.objects.filter(pk=order.pk).update(status=SalesOrder.Status.PARTIAL)
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "3.00")], payments=self._cash("945.00")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_FULFIL_REFUSED")
        self.assertEqual(SalesTransaction.objects.count(), 0, "nothing rung")
        line.refresh_from_db()
        self.assertEqual(line.fulfilled_qty, Decimal("8.00"), "nothing moved")

    def test_a_fulfilment_needs_an_open_shift(self):
        # Decision 06 ruling 2 reaches fulfilment unchanged: no shift, no sale.
        order = self._order()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "NO_OPEN_SHIFT")
        self.assertEqual(SalesTransaction.objects.count(), 0)
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)
        self.assertEqual(order.items.get().fulfilled_qty, Decimal("0.00"))

    def test_short_stock_refuses_the_whole_fulfilment(self):
        # `InsufficientStock` from FIFO refuses the WHOLE fulfilment: no sale, no moved
        # stock, no fulfilled quantity. The order is untouched and can be rung later.
        self._stock(
            "0"
        )  # nothing more to receive; the shelf holds what `setUp` put there
        order = self._order(qty="10.00")
        self._open_shift()
        VariantStock = type(self.variant).batches.rel.related_model
        stocked = sum(
            VariantStock.objects.filter(variant=self.variant).values_list(
                "current_qty", flat=True
            ),
            Decimal(0),
        )
        self.assertEqual(stocked, Decimal("100.00"), "the fixture's shelf")

        for batch in VariantStock.objects.filter(variant=self.variant):
            batch.current_qty = Decimal("1.00")
            batch.save(update_fields=["current_qty"])

        response = self._fulfil(
            order, lines=[self._line(order, "10.00")], payments=self._cash("3150.00")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INSUFFICIENT_STOCK")
        self.assertEqual(SalesTransaction.objects.count(), 0, "nothing written")
        order.refresh_from_db()
        self.assertEqual(order.items.get().fulfilled_qty, Decimal("0.00"))

    def test_a_replayed_idempotency_key_returns_the_first_sale(self):
        # Decision 09 item 2 through the fulfil path: the retry of a response the client
        # never saw answers 200 with the SAME sale, and charges nothing twice.
        order = self._order(qty="10.00")
        self._open_shift()
        lines = [self._line(order, "4.00")]

        first = self._fulfil(
            order, lines=lines, payments=self._cash("1260.00"), key="fulfil-1"
        )
        replay = self._fulfil(
            order, lines=lines, payments=self._cash("1260.00"), key="fulfil-1"
        )

        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(replay.status_code, 200, replay.data)
        self.assertEqual(replay.data["id"], first.data["id"], "the same sale")
        self.assertEqual(SalesTransaction.objects.count(), 1)
        order.refresh_from_db()
        self.assertEqual(order.items.get().fulfilled_qty, Decimal("4.00"))

    def test_the_delivery_fee_is_charged_on_the_first_fulfilment_only(self):
        order = self._order_with_delivery(fee="20.00")
        self._open_shift()

        first = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1280.00")
        )
        second = self._fulfil(
            order, lines=[self._line(order, "6.00")], payments=self._cash("1890.00")
        )

        self.assertEqual(first.status_code, 201, first.data)
        first_sale = SalesTransaction.objects.get(pk=first.data["id"])
        self.assertEqual(first_sale.delivery_fee, Decimal("20.00"))
        self.assertEqual(first_sale.grand_total, Decimal("1280.00"), "goods + fee once")
        slip = Delivery.objects.get(sales_order=order)
        self.assertEqual(slip.sale_id, first_sale.id, "the slip moved to the sale")
        self.assertEqual(slip.sales_order_id, order.id, "and kept its order")

        self.assertEqual(second.status_code, 201, second.data)
        second_sale = SalesTransaction.objects.get(pk=second.data["id"])
        self.assertEqual(second_sale.delivery_fee, Decimal("0.00"), "no fee twice")
        self.assertEqual(second_sale.grand_total, Decimal("1890.00"))

    def test_a_later_fulfilment_refuses_a_delivery_payload(self):
        order = self._order_with_delivery(fee="20.00")
        self._open_shift()
        self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1280.00")
        )

        response = self._fulfil(
            order,
            lines=[self._line(order, "6.00")],
            payments=self._cash("1890.00"),
            delivery={"fee": "20.00"},
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_DELIVERY_NOT_ACCEPTED")
        self.assertEqual(SalesTransaction.objects.count(), 1, "the second never rang")
        self.assertEqual(Delivery.objects.filter(sales_order=order).count(), 1)

    def test_even_the_first_fulfilment_refuses_a_delivery_payload(self):
        # B4 carry-forward (decision 19's delivery default): the refusal is
        # UNCONDITIONAL - a fulfilment never carries a delivery of its own, the ORDER's
        # slip does - so the FIRST fulfilment refuses it exactly as a later one does,
        # whether or not the order already has a slip. Nothing is written either way.
        self._open_shift()

        for has_slip in (True, False):
            with self.subTest(order_has_delivery_slip=has_slip):
                order = (
                    self._order_with_delivery(fee="20.00")
                    if has_slip
                    else self._order(qty="10.00")
                )

                response = self._fulfil(
                    order,
                    lines=[self._line(order, "4.00")],
                    payments=self._cash("1280.00"),
                    delivery={"fee": "20.00"},
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(
                    response.data["code"], "SALES_ORDER_DELIVERY_NOT_ACCEPTED"
                )
                self.assertEqual(SalesTransaction.objects.count(), 0, "nothing rung")
                self.assertEqual(
                    Delivery.objects.filter(sales_order=order).count(),
                    1 if has_slip else 0,
                    "no slip was created or changed",
                )
                order.refresh_from_db()
                self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)
                self.assertEqual(
                    order.items.get().fulfilled_qty, Decimal("0.00"), "nothing moved"
                )

    def test_a_cancelled_order_cannot_be_fulfilled(self):
        order = self._order(status=SalesOrder.Status.CANCELLED)
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "SALES_ORDER_TRANSITION_INVALID")
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_a_cashier_can_fulfil_at_the_till(self):
        # Decision 19 #4: fulfilment is till work, so a plain Cashier rings it - and the
        # order's customer, not the cashier, is who the sale is for.
        order = self._order()
        client, cashier = self._fulfiller()
        Shift.objects.create(cashier=cashier, opening_float=Decimal(5000))

        response = self._fulfil(
            order,
            lines=[self._line(order, "2.00")],
            payments=self._cash("630.00"),
            client=client,
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = SalesTransaction.objects.get(pk=response.data["id"])
        self.assertEqual(sale.cashier_id, cashier.id)
        self.assertEqual(sale.customer_id, order.customer_id)

    def test_a_fulfilment_keeps_the_checkout_change_rule(self):
        # The change/utang arithmetic is `process_sale`'s, unchanged: an overpaid cash
        # fulfilment records the change, and the drawer figure comes from the sale.
        order = self._order()
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1500.00")
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = SalesTransaction.objects.get(pk=response.data["id"])
        self.assertEqual(sale.grand_total, Decimal("1260.00"))
        self.assertEqual(sale.change_given, Decimal("240.00"))

    def test_a_fulfilment_underpaid_by_a_named_customer_goes_on_utang(self):
        order = self._order()
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1000.00")
        )

        self.assertEqual(response.status_code, 201, response.data)
        sale = SalesTransaction.objects.get(pk=response.data["id"])
        from apps.collectibles.models import CollectibleLedger

        ledger = CollectibleLedger.objects.get(transaction=sale)
        self.assertEqual(ledger.balance_due, Decimal("260.00"), "the shortfall")

    def test_an_archived_unit_is_refused(self):
        # Plan B4: the archived-unit refusal is the Phase 6 B3 helper REUSED, so the code
        # is the shared `INACTIVE_SELLING_UNIT` - not the till's own `INVALID_SALE` text.
        self.variant.product.is_active = False
        self.variant.product.save(update_fields=["is_active"])
        order = self._order()
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "4.00")], payments=self._cash("1260.00")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self.assertEqual(SalesTransaction.objects.count(), 0, "nothing rung")

    def test_a_fractional_quantity_on_a_whole_unit_is_refused(self):
        # The same whole-unit rule every quantity path uses (decision 16), on the order's
        # own selling unit: a bag is counted in ones.
        self.variant_uom.uom.is_whole = True
        self.variant_uom.uom.save(update_fields=["is_whole"])
        order = self._order()
        self._open_shift()

        response = self._fulfil(
            order, lines=[self._line(order, "1.50")], payments=self._cash("472.50")
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "WHOLE_UNIT_QUANTITY")
        self.assertEqual(SalesTransaction.objects.count(), 0, "nothing rung")


class OrderCustomerRuleTests(SalesOrderLifecycleBase):
    """B5: an order must name a REAL customer - decision 19's premise, made code.

    Fulfilment rings the ORDER's customer into an ordinary sale, and only a named
    customer may owe (decision 14). An order on the seeded Walk-in placeholder would
    therefore promise goods to nobody and could carry a debt owed by nobody, so it is
    refused at CREATE - before the order, its lines and its audit row exist.
    """

    def _post(self, customer):
        return self.client.post(
            ORDERS_URL,
            {
                "customer": customer.id,
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "2.00",
                        "unit_price": "315.00",
                    }
                ],
            },
            format="json",
        )

    def test_a_walk_in_customer_cannot_hold_an_order(self):
        walk_in = Customer.objects.create(
            name="Walk-in Customer", customer_type=Customer.Type.WALK_IN
        )

        response = self._post(walk_in)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "WALK_IN_CANNOT_ORDER")
        self.assertFalse(SalesOrder.objects.exists(), "no order")
        self.assertFalse(SalesOrderItem.objects.exists(), "no lines")
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.CREATE).exists(),
            "no CREATE audit row",
        )

    def test_a_named_customer_can_hold_an_order(self):
        response = self._post(self.customer)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["customer"], self.customer.id)


class OrderStockHintTests(SalesOrderFulfilmentBase):
    """Decision 19 #2: no reservation anywhere - but the ORDER READ carries a live hint.

    `available_qty` is the sellable stock in that line's OWN selling unit, capped by the
    line's remaining quantity, so the client reads "enough / short by N" straight off the
    wire (`shortfall = remaining_qty - available_qty`). The shelf here holds 100 BASE
    units: 100 bags, or 8 whole boxes of twelve.
    """

    def setUp(self):
        super().setUp()
        box, _ = UnitOfMeasure.objects.get_or_create(
            code="LCBOX", defaults={"name": "Lifecycle Box", "is_whole": True}
        )
        self.box = VariantUOM.objects.create(
            variant=self.variant,
            uom=box,
            conversion_factor=Decimal(12),
            default_selling_price=Decimal("3780.00"),
        )

    def _two_unit_order(self):
        """One order, one line in bags and one in boxes, both priced at catalogue."""
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "30.00",
                        "unit_price": "315.00",
                    },
                    {
                        "variant_uom": self.box.id,
                        "qty": "30.00",
                        "unit_price": "3780.00",
                    },
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        return SalesOrder.objects.get(pk=response.data["id"])

    def _hints(self, order):
        response = self.client.get(f"{ORDERS_URL}{order.pk}/")
        self.assertEqual(response.status_code, 200, response.data)
        return {
            row["variant_uom"]: row["available_qty"] for row in response.data["items"]
        }

    def _on_shelf(self):
        from apps.inventory.models import InventoryBatch

        return sum(
            InventoryBatch.objects.filter(variant=self.variant).values_list(
                "current_qty", flat=True
            ),
            Decimal(0),
        )

    def test_the_read_carries_a_hint_in_each_lines_own_unit(self):
        order = self._two_unit_order()

        hints = self._hints(order)

        # A bag is one base unit, so the bag line is capped by its own remaining 30; a box
        # is twelve, so the same 100-unit shelf is only 8 whole boxes (8.33 rounded DOWN).
        self.assertEqual(hints[self.variant_uom.id], "30.00")
        self.assertEqual(hints[self.box.id], "8.00")

    def test_the_hint_follows_the_shelf_without_reserving_anything(self):
        order = self._two_unit_order()
        self.assertEqual(self._on_shelf(), Decimal(100))

        self._stock("12")  # 112 base units: exactly one more whole box

        self.assertEqual(self._hints(order)[self.box.id], "9.00")

    def test_the_hint_is_read_only_and_a_read_moves_no_stock(self):
        response = self.client.post(
            ORDERS_URL,
            {
                "customer": self.customer.id,
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "4.00",
                        "unit_price": "315.00",
                        # A client that tries to state the hint is ignored: it is
                        # server-owned, like the other line quantities.
                        "available_qty": "999.00",
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        order = SalesOrder.objects.get(pk=response.data["id"])

        hints = self._hints(order)

        self.assertEqual(hints[self.variant_uom.id], "4.00")
        self.assertEqual(self._on_shelf(), Decimal(100), "nothing was reserved")


class ReturnsDoNotReopenOrderTests(SalesOrderFulfilmentBase):
    """Decision 19 (consequences): a return is a SALE-level correction.

    "Returns of a fulfilment sale follow the normal return rules; they do not reopen the
    order." The refund is priced from the line that actually sold (the order's agreed
    price) by the Phase 3 rule, and the order stays COMPLETED with its `fulfilled_qty`
    exactly where the till left it - a sale that happened cannot be un-happened.
    """

    def test_a_return_of_a_fulfilment_sale_leaves_the_order_completed(self):
        order = self._order(qty="10.00", unit_price="300.00")
        self._open_shift()
        fulfilled = self._fulfil(
            order,
            lines=[self._line(order, "10.00")],
            payments=self._cash("3000.00"),
        )
        self.assertEqual(fulfilled.status_code, 201, fulfilled.data)
        order.refresh_from_db()
        self.assertEqual(order.status, SalesOrder.Status.COMPLETED)
        line = order.items.get()

        response = self.client.post(
            TRANSACTIONS_URL,
            {
                "customer": order.customer_id,
                "source": "RETURN",
                "original_transaction": fulfilled.data["id"],
                "items": [{"variant_id": self.variant_uom.id, "qty": "4.00"}],
                "payment_method": "CASH",
                "reason": "Damaged in transit",
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        refund = SalesTransaction.objects.get(pk=response.data["id"])
        self.assertEqual(refund.source, SalesTransaction.Source.RETURN)
        self.assertEqual(
            refund.items.get().unit_price,
            Decimal("300.00"),
            "refunded at the price it SOLD at, not today's 315.00 catalogue",
        )
        order.refresh_from_db()
        line.refresh_from_db()
        self.assertEqual(
            order.status,
            SalesOrder.Status.COMPLETED,
            "a return does not reopen an order",
        )
        self.assertEqual(
            line.fulfilled_qty, Decimal("10.00"), "what was rung stays rung"
        )
        self.assertEqual(line.cancelled_qty, Decimal("0.00"))
