# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Phase 8 B1 (decision 20) — a supplier cheque is Issued until a manager decides it.

What this file pins:

* **The bill still drops at issue.** Decision 20 #3 keeps the supplier rule: the money is
  promised when the cheque is handed over, so `balance_amount` falls immediately - and a
  SUPPLIER cheque therefore starts `ISSUED`, not `CLEARED`.
* **CLEARED moves nothing.** The bank honouring a cheque confirms money the bill already
  counted; only the status changes.
* **BOUNCED puts the amount back** on the bill (and the bill's derived status follows:
  PAID → PARTIAL, or PAID → UNPAID when the cheque was the whole balance).
* **A decision happens ONCE**, under a row lock: a second clear/bounce is a 409 with no
  writes, and a bounce racing a payment can never push the balance above the bill total.
* **Roles fence money.** Store Manager / Admin decide; Stock Manager reads only; a
  Cashier and the CPMS account are refused the whole route set.
* **The row is still append-only.** Only the four decision fields may ever be written to
  a stored payment, and only while it is ISSUED.
"""

import threading
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .exceptions import ImmutablePayableRecord
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    SupplierBill,
    SupplierPayment,
    UnitOfMeasure,
)
from .services import process_goods_receipt
from .tests_supplier_payables import LOGIN_URL, PAYMENTS_URL, PayablesTestBase

User = get_user_model()

CHEQUE_BODY = {
    "method": "CHEQUE",
    "cheque_number": "000123",
    "cheque_bank": "BDO",
    "cheque_date": "2026-11-12",
}


class ChequeTestBase(PayablesTestBase):
    """A 200.00 bill plus the two helpers every cheque test needs."""

    def setUp(self):
        super().setUp()
        po, item = self._po(ordered="10", cost="100")
        self.bill = self._bill(self._receipt(po, [(item, "2")]))  # 200.00

    def _pay(self, user=None, **body):
        payload = {"bill": self.bill.pk, "amount": "50", "method": "CASH"}
        payload.update(body)
        return self._login(user or self.manager).post(
            PAYMENTS_URL, payload, format="json"
        )

    def _cheque(self, amount="200", user=None, **body):
        payload = {"bill": self.bill.pk, "amount": amount, **CHEQUE_BODY}
        payload.update(body)
        response = self._pay(user=user or self.manager, **payload)
        self.assertEqual(response.status_code, 201, response.data)
        return SupplierPayment.objects.get(pk=response.data["id"])

    def _decide(self, payment, action, user=None, **body):
        return self._login(user or self.manager).post(
            f"{PAYMENTS_URL}{payment.pk}/{action}/", body, format="json"
        )

    def _balance(self):
        self.bill.refresh_from_db()
        return self.bill.balance_amount


class ChequeStatusTests(ChequeTestBase):
    """Status is stamped at creation: a cheque is ISSUED, every other method CLEARED."""

    def test_a_new_cheque_is_issued_and_the_bill_still_drops_at_issue(self):
        payment = self._cheque("200")

        self.assertEqual(payment.status, SupplierPayment.Status.ISSUED)
        self.assertIsNone(payment.decided_by_id)
        self.assertIsNone(payment.decided_at)
        self.assertEqual(payment.decision_reason, "")
        self.assertIsNotNone(payment.paid_on)
        # Decision 20 #3: the money is promised at issue, so the bill already counts it.
        self.assertEqual(self._balance(), Decimal("0.00"))
        self.assertEqual(self.bill.status, SupplierBill.Status.PAID)

    def test_a_cash_or_transfer_payment_is_cleared_at_creation(self):
        for method in ("CASH", "BANK_TRANSFER"):
            with self.subTest(method=method):
                response = self._pay(amount="1", method=method)
                self.assertEqual(response.status_code, 201, response.data)
                self.assertEqual(response.data["status"], "CLEARED")

    def test_a_payment_row_saved_without_a_status_is_cleared(self):
        """The migration default: existing rows (cheques included) become CLEARED."""
        payment = SupplierPayment.objects.create(
            bill=self.bill,
            paid_by=self.manager,
            amount=Decimal(10),
            method=SupplierPayment.Method.CASH,
        )

        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)

    def test_the_decision_fields_are_read_only_on_the_wire(self):
        payment = self._cheque("10")

        response = self._login(self.manager).post(
            PAYMENTS_URL,
            {
                "bill": self.bill.pk,
                "amount": "1",
                "method": "CASH",
                "status": "BOUNCED",
                "decided_by": self.manager.pk,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["status"], "CLEARED")
        self.assertEqual(response.data["decided_by"], None)
        self.assertEqual(payment.status, SupplierPayment.Status.ISSUED)

    def test_method_choices_include_credit_but_a_bare_credit_payment_is_refused(self):
        """B1 adds the CHOICE only: applying credit arrives with B3 (decision 20 #3)."""
        self.assertIn("CREDIT", SupplierPayment.Method.values)

        response = self._pay(method="CREDIT")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SUPPLIER_PAYMENT")
        self.assertEqual(self._balance(), Decimal("200.00"))
        self.assertEqual(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CREDIT
            ).count(),
            0,
        )


class ChequeDecisionTests(ChequeTestBase):
    """Clear moves nothing; bounce puts the amount back; each happens once."""

    def test_clearing_a_cheque_moves_no_money(self):
        payment = self._cheque("200")
        self.assertEqual(self._balance(), Decimal("0.00"))

        response = self._decide(payment, "clear")

        self.assertEqual(response.status_code, 200, response.data)
        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)
        self.assertEqual(payment.decided_by_id, self.manager.pk)
        self.assertIsNotNone(payment.decided_at)
        # The bill already counted the money at issue: clearing confirms, it does not pay.
        self.assertEqual(self._balance(), Decimal("0.00"))
        self.assertEqual(self.bill.status, SupplierBill.Status.PAID)

    def test_a_bounce_puts_the_amount_back_and_the_bill_turns_partial(self):
        # 50 cash leaves 150 owed; a 150 cheque settles the bill.
        self._pay(amount="50")
        payment = self._cheque("150")
        self.assertEqual(self._balance(), Decimal("0.00"))

        response = self._decide(payment, "bounce", reason="Insufficient funds")

        self.assertEqual(response.status_code, 200, response.data)
        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.BOUNCED)
        self.assertEqual(payment.decision_reason, "Insufficient funds")
        self.assertEqual(payment.decided_by_id, self.manager.pk)
        self.assertEqual(self._balance(), Decimal("150.00"))
        self.assertEqual(self.bill.status, SupplierBill.Status.PARTIAL)

    def test_a_bounce_of_the_whole_bill_leaves_it_unpaid_again(self):
        payment = self._cheque("200")

        self._decide(payment, "bounce", reason="Closed account")

        self.assertEqual(self._balance(), Decimal("200.00"))
        self.assertEqual(self.bill.status, SupplierBill.Status.UNPAID)

    def test_a_bounce_without_a_reason_is_refused_and_writes_nothing(self):
        payment = self._cheque("200")

        for reason in ("", "   ", None):
            with self.subTest(reason=reason):
                body = {} if reason is None else {"reason": reason}
                response = self._decide(payment, "bounce", **body)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data["code"], "CHEQUE_REASON_REQUIRED")

        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.ISSUED)
        self.assertIsNone(payment.decided_at)
        self.assertEqual(self._balance(), Decimal("0.00"))
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.CHEQUE_DECISION
            ).count(),
            0,
        )

    def test_a_second_decision_is_a_conflict_with_no_writes(self):
        payment = self._cheque("200")
        self._decide(payment, "clear")

        response = self._decide(payment, "bounce", reason="Too late")

        self.assertEqual(response.status_code, 409, response.data)
        self.assertEqual(response.data["code"], "CHEQUE_ALREADY_DECIDED")
        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)
        self.assertEqual(payment.decision_reason, "")
        self.assertEqual(self._balance(), Decimal("0.00"))
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.CHEQUE_DECISION
            ).count(),
            1,
        )

    def test_a_decision_is_audited_with_the_actor_and_the_reason(self):
        payment = self._cheque("200")

        self._decide(payment, "bounce", reason="Refer to drawer")

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.CHEQUE_DECISION)
        self.assertEqual(row.user_id, self.manager.pk)
        self.assertIn("000123", row.description)
        self.assertIn("BOUNCED", row.description)
        self.assertIn("Refer to drawer", row.description)
        self.assertIn(str(self.bill.pk), row.description)

    def test_an_audit_failure_rolls_back_the_decision_and_the_balance(self):
        payment = self._cheque("200")

        with (
            mock.patch(
                "apps.inventory.views.audit_request",
                side_effect=RuntimeError("audit down"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self._decide(payment, "bounce", reason="Bank says no")

        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.ISSUED)
        self.assertEqual(self._balance(), Decimal("0.00"))

    def test_a_non_cheque_payment_id_is_a_404(self):
        cash = SupplierPayment.objects.get(pk=self._pay().data["id"])

        for action in ("clear", "bounce"):
            with self.subTest(action=action):
                response = self._decide(cash, action, reason="nope")
                self.assertEqual(response.status_code, 404, response.data)

        cash.refresh_from_db()
        self.assertEqual(cash.status, SupplierPayment.Status.CLEARED)
        self.assertEqual(self._balance(), Decimal("150.00"))

    def test_decision_roles(self):
        payment = self._cheque("200")
        stocker = self._login(self.stocker)
        cashier = self._login(self.cashier)
        cpms = self._login(self.cpms)
        url = f"{PAYMENTS_URL}{payment.pk}/clear/"

        self.assertEqual(stocker.post(url, {}, format="json").status_code, 403)
        self.assertEqual(cashier.post(url, {}, format="json").status_code, 403)
        self.assertEqual(cpms.post(url, {}, format="json").status_code, 403)
        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.ISSUED)

        # A Stock Manager still READS the queue, and an Admin decides.
        self.assertEqual(stocker.get(PAYMENTS_URL).status_code, 200)
        self.assertEqual(
            self._decide(payment, "clear", user=self.admin).status_code, 200
        )

    def test_the_list_filters_by_status(self):
        cheque = self._cheque("50")
        self._pay(method="CASH")

        response = self._login(self.stocker).get(
            f"{PAYMENTS_URL}?status=ISSUED", format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual([row["id"] for row in response.data["results"]], [cheque.pk])

        bad = self._login(self.stocker).get(f"{PAYMENTS_URL}?status=PENDING")
        self.assertEqual(bad.status_code, 400, bad.data)
        self.assertIn("status", bad.data)


class ChequeImmutabilityTests(ChequeTestBase):
    """A stored payment is history: only the four decision fields may be written."""

    def test_amount_and_method_edits_are_still_refused(self):
        payment = self._cheque("200")

        for field, value in (
            ("amount", Decimal("1.00")),
            ("method", SupplierPayment.Method.CASH),
            ("cheque_number", "999"),
            ("bill", self.bill),
        ):
            with self.subTest(field=field):
                stored = SupplierPayment.objects.get(pk=payment.pk)
                setattr(stored, field, value)
                with self.assertRaises(ImmutablePayableRecord):
                    stored.save(update_fields=[field])

    def test_a_full_save_without_update_fields_is_refused(self):
        payment = self._cheque("200")
        payment.status = SupplierPayment.Status.CLEARED

        with self.assertRaises(ImmutablePayableRecord):
            payment.save()

    def test_a_decision_update_is_allowed_only_while_issued(self):
        payment = self._cheque("200")
        payment.status = SupplierPayment.Status.CLEARED
        payment.decision_reason = ""
        payment.save(
            update_fields=["status", "decided_by", "decided_at", "decision_reason"]
        )
        payment.refresh_from_db()
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)

        # Decided once: the same door is shut afterwards.
        payment.status = SupplierPayment.Status.BOUNCED
        payment.decision_reason = "second try"
        with self.assertRaises(ImmutablePayableRecord):
            payment.save(update_fields=["status", "decision_reason"])

    def test_a_decision_update_cannot_smuggle_a_money_field(self):
        payment = self._cheque("200")
        payment.status = SupplierPayment.Status.CLEARED
        payment.amount = Decimal("1.00")

        with self.assertRaises(ImmutablePayableRecord):
            payment.save(update_fields=["status", "amount"])

    def test_a_decided_cheque_still_cannot_be_deleted(self):
        payment = self._cheque("200")

        with self.assertRaises(ImmutablePayableRecord):
            payment.delete()

        self.assertEqual(SupplierPayment.objects.filter(pk=payment.pk).count(), 1)


class ConcurrentChequeDecisionTests(TransactionTestCase):
    """A bounce racing a payment: whoever loses, the balance never passes the total."""

    def setUp(self):
        self.password = get_random_string(16)
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
        self.user = User.objects.create_user(
            username="cheque_racer", email="racer@example.com", password=self.password
        )
        self.user.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        supplier = Supplier.objects.create(company_name="Cebu Supply")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.user,
            status=PurchaseOrder.Status.ORDERED,
        )
        item = POItem.objects.create(
            po=po, variant=variant, ordered_qty=Decimal(10), unit_cost=Decimal(100)
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.user)
        GoodsReceiptItem.objects.create(receipt=receipt, po_item=item, qty=Decimal(2))
        process_goods_receipt(receipt=receipt, user=self.user)
        self.bill = SupplierBill.objects.get(receipt=receipt)  # 200.00
        login = APIClient().post(
            LOGIN_URL,
            {"username": self.user.username, "password": self.password},
            format="json",
        )
        self.auth = {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}

    def _post(self, url, body):
        return APIClient().post(url, body, format="json", **self.auth)

    def _workers(self, worker, count=2):
        barrier = threading.Barrier(count, timeout=20)
        results = []
        lock = threading.Lock()

        def run():
            try:
                barrier.wait()
                outcome = worker()
                with lock:
                    results.append(outcome)
            finally:
                connections.close_all()

        threads = [threading.Thread(target=run) for _ in range(count)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=40)
        return results

    def test_a_concurrent_bounce_and_payment_keep_the_balance_within_the_total(self):
        """100.00 cheque on a 200.00 bill, bounced while 100.00 cash is being paid.

        Whichever writer wins the lock, the arithmetic must land on 100.00 owed: paying
        first takes the balance to 0 and the bounce puts 100 back; bouncing first takes it
        to 200 and the payment takes 100 off. Neither can pass the bill total.
        """
        issued = self._post(
            PAYMENTS_URL, {"bill": self.bill.pk, "amount": "100", **CHEQUE_BODY}
        )
        self.assertEqual(issued.status_code, 201, issued.data)
        payment_id = issued.data["id"]
        self.assertEqual(self._fresh_balance(), Decimal("100.00"))

        def bounce():
            return self._post(
                f"{PAYMENTS_URL}{payment_id}/bounce/", {"reason": "No funds"}
            ).status_code

        def pay():
            return self._post(
                PAYMENTS_URL,
                {"bill": self.bill.pk, "amount": "100", "method": "CASH"},
            ).status_code

        results = self._workers(self._either(bounce, pay))

        self.assertEqual(sorted(results), [200, 201], results)
        self.bill.refresh_from_db()
        self.assertEqual(self.bill.balance_amount, Decimal("100.00"))
        self.assertLessEqual(self.bill.balance_amount, self.bill.total_amount)
        self.assertEqual(
            SupplierPayment.objects.get(pk=payment_id).status,
            SupplierPayment.Status.BOUNCED,
        )

    def _either(self, bounce, pay):
        """One thread decides, the other pays - both at the same barrier."""
        counter = {"n": 0}
        lock = threading.Lock()

        def worker():
            with lock:
                counter["n"] += 1
                first = counter["n"] == 1
            return bounce() if first else pay()

        return worker

    def _fresh_balance(self):
        self.bill.refresh_from_db()
        return self.bill.balance_amount
