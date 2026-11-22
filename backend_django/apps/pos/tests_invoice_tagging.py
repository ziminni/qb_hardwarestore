# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests_idempotency.py: the checker resolves its
# config from its WORKING DIRECTORY, so every `Model.objects` access and every
# `self.client.post(..., **self.auth)` is a false positive on valid Django. The test run
# is the authority.
"""Store-ops Phase 1 - tagging a sale with the paper BIR Official Receipt's invoice no.

The shop prints an Order Slip (OS) for every sale; the paper BIR Official Receipt book
has its own Invoice number. When a customer asks for an official receipt the cashier
writes the paper OR and types its number into the system, which is what later lets the
VAT report tell OR-backed sales from the rest.

Two doors into the same rule, so both are pinned here:

* **At checkout** - `invoice_no` on the normal sale body, tagged inside the sale's own
  atomic block (a refused tag rolls the whole sale back).
* **Later** - `POST /transactions/attach-invoice/`, for the customer who comes back days
  after with the slip. The lookup is deliberately NOT scoped to the caller's own sales:
  the customer holds the slip, so knowing the exact number is the authority, and the
  cashier who rings the tag need not be the one who rang the sale.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group

from apps.pos.models import SalesTransaction, Shift
from apps.pos.services import process_return, process_sale
from apps.pos.tests import LOGIN_URL, TRANSACTIONS_URL, POSTestBase
from apps.users.models import AuditLog

User = get_user_model()

ATTACH_URL = "/api/v1/transactions/attach-invoice/"


class InvoiceTaggingBase(POSTestBase):
    """POSTestBase (CF=1, price 10, stock 5@40 + 5@60) plus logged-in tills."""

    def setUp(self):
        super().setUp()
        self.cashier.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        self.auth = self._login("cashier1", "pass12345")

    # -- fixture helpers ---------------------------------------------------
    def _login(self, username, password):
        login = self.client.post(
            LOGIN_URL,
            {"username": username, "password": password},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200, login.content)
        return {"HTTP_AUTHORIZATION": f"Bearer {login.json()['access']}"}

    def _other_cashier_auth(self):
        """A second till: its own account, Cashier role and open shift."""
        other = User.objects.create_user(
            # nosemgrep: the hardcoded-password rule fires on a test fixture. This
            # password exists only in the throwaway test database and is posted straight
            # back to the login endpoint below - same fixture as POSTestBase.
            username="cashier2",
            email="c2@x.com",
            password="pass12345",
            full_name="Second Cashier",
        )
        other.groups.add(Group.objects.get_or_create(name="Cashier")[0])
        Shift.objects.create(cashier=other, opening_float=Decimal(5000))
        return self._login("cashier2", "pass12345")

    def _manager_auth(self):
        manager = User.objects.create_user(
            # nosemgrep: same test-fixture password as above.
            username="manager1",
            email="m@x.com",
            password="pass12345",
            full_name="Store Manager",
        )
        manager.groups.add(Group.objects.get_or_create(name="Store Manager")[0])
        return self._login("manager1", "pass12345")

    def _payload(self, qty="2", tendered="20.00", **extra):
        body = {
            "customer": self.customer.id,
            "source": "WALK_IN",
            "items": [{"variant_id": self.vuom.id, "qty": qty}],
            "payments": [{"method": "CASH", "amount_tendered": tendered}],
        }
        body.update(extra)
        return body

    def _ring(self, *, qty="2", tendered="20.00", auth=None, **extra):
        return self.client.post(
            TRANSACTIONS_URL,
            data=self._payload(qty, tendered, **extra),
            content_type="application/json",
            **(auth or self.auth),
        )  # pyright: ignore[reportArgumentType]

    def _seed_sale(self, qty="2", tendered="20.00"):
        """A sale rung by `self.cashier` straight through the service."""
        return process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[
                {
                    "variant_id": self.vuom.id,
                    "qty": Decimal(qty),
                    "unit_price": Decimal(10),
                }
            ],
            payments_data=[{"method": "CASH", "amount_tendered": Decimal(tendered)}],
        )

    def _attach(self, body, auth=None):
        return self.client.post(
            ATTACH_URL,
            data=body,
            content_type="application/json",
            **(auth or self.auth),
        )  # pyright: ignore[reportArgumentType]

    def _os_number(self, txn):
        return txn.receipt.or_number


class CheckoutWithInvoiceNoTests(InvoiceTaggingBase):
    """A customer who asks at the till: the number rides the sale body."""

    def test_checkout_stores_the_invoice_no_and_who_tagged_it(self):
        response = self._ring(invoice_no="  bir-000123  ")

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["invoice_no"], "BIR-000123")
        txn = SalesTransaction.objects.get(pk=response.json()["id"])
        self.assertEqual(txn.invoice_no, "BIR-000123")
        self.assertIsNotNone(txn.invoice_tagged_at)
        self.assertEqual(txn.invoice_tagged_by, self.cashier)
        self.assertEqual(response.json()["invoice_tagged_by_name"], "Cashy Ir")

    def test_checkout_without_an_invoice_no_leaves_the_sale_untagged(self):
        response = self._ring()

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["invoice_no"], "")
        self.assertIsNone(response.json()["invoice_tagged_at"])

    def test_a_duplicate_invoice_no_at_checkout_rings_no_sale(self):
        self._ring(invoice_no="BIR-000900")

        response = self._ring(qty="1", tendered="10.00", invoice_no="BIR-000900")

        self.assertEqual(response.status_code, 409, response.content)
        self.assertEqual(response.json()["code"], "INVOICE_NO_IN_USE")
        # The refused sale left nothing behind: one transaction, not two.
        self.assertEqual(SalesTransaction.objects.count(), 1)

    def test_an_idempotent_replay_does_not_re_tag(self):
        key = "invoice-replay-1"
        first = self.client.post(
            TRANSACTIONS_URL,
            data=self._payload(invoice_no="BIR-000700"),
            content_type="application/json",
            HTTP_IDEMPOTENCY_KEY=key,
            **self.auth,
        )  # pyright: ignore[reportArgumentType]
        second = self.client.post(
            TRANSACTIONS_URL,
            data=self._payload(invoice_no="BIR-000700"),
            content_type="application/json",
            HTTP_IDEMPOTENCY_KEY=key,
            **self.auth,
        )  # pyright: ignore[reportArgumentType]

        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 200, second.content)
        self.assertEqual(SalesTransaction.objects.count(), 1)
        self.assertEqual(second.json()["invoice_no"], "BIR-000700")


class AttachInvoiceTests(InvoiceTaggingBase):
    """The customer comes back with the slip, days later."""

    def test_attach_by_os_number(self):
        txn = self._seed_sale()

        response = self._attach(
            {"number": self._os_number(txn), "invoice_no": "bir-000123"}
        )

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["invoice_no"], "BIR-000123")
        self.assertEqual(response.json()["transaction_no"], txn.transaction_no)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000123")
        self.assertIsNotNone(txn.invoice_tagged_at)
        self.assertEqual(txn.invoice_tagged_by, self.cashier)
        self.assertTrue(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.UPDATE,
                description__contains="BIR-000123",
            ).exists()
        )

    def test_attach_by_transaction_no(self):
        txn = self._seed_sale()

        response = self._attach(
            {"number": txn.transaction_no.lower(), "invoice_no": "BIR-000456"}
        )

        self.assertEqual(response.status_code, 200, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000456")

    def test_another_cashier_may_tag_a_sale_they_did_not_ring(self):
        txn = self._seed_sale()
        other_auth = self._other_cashier_auth()

        response = self._attach(
            {"number": self._os_number(txn), "invoice_no": "BIR-000789"},
            auth=other_auth,
        )

        self.assertEqual(response.status_code, 200, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000789")
        self.assertEqual(txn.invoice_tagged_by.username, "cashier2")

    def test_the_same_number_again_is_a_no_op_success(self):
        txn = self._seed_sale()

        first = self._attach(
            {"number": self._os_number(txn), "invoice_no": "BIR-000123"}
        )
        second = self._attach(
            {"number": self._os_number(txn), "invoice_no": "BIR-000123"}
        )

        self.assertEqual(first.status_code, 200, first.content)
        self.assertEqual(second.status_code, 200, second.content)
        self.assertEqual(second.json()["invoice_no"], "BIR-000123")

    def test_unknown_number_is_404(self):
        response = self._attach(
            {"number": "OS-DOES-NOT-EXIST", "invoice_no": "BIR-000123"}
        )

        self.assertEqual(response.status_code, 404, response.content)

    def test_blank_invoice_no_is_refused(self):
        txn = self._seed_sale()

        response = self._attach({"number": self._os_number(txn), "invoice_no": "   "})

        self.assertEqual(response.status_code, 400, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "")


class ReplaceInvoiceTests(InvoiceTaggingBase):
    """A typo or a second paper OR: changing a tag is a manager's call."""

    def test_a_second_different_number_without_replace_is_409(self):
        txn = self._seed_sale()
        self._attach({"number": self._os_number(txn), "invoice_no": "BIR-000001"})

        response = self._attach(
            {"number": self._os_number(txn), "invoice_no": "BIR-000002"}
        )

        self.assertEqual(response.status_code, 409, response.content)
        self.assertEqual(response.json()["code"], "INVOICE_ALREADY_TAGGED")
        self.assertEqual(response.json()["invoice_no"], "BIR-000001")
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000001")

    def test_replace_by_a_cashier_is_403(self):
        txn = self._seed_sale()
        self._attach({"number": self._os_number(txn), "invoice_no": "BIR-000001"})

        response = self._attach(
            {
                "number": self._os_number(txn),
                "invoice_no": "BIR-000002",
                "replace": True,
            }
        )

        self.assertEqual(response.status_code, 403, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000001")

    def test_replace_by_a_manager_succeeds_and_is_audited(self):
        txn = self._seed_sale()
        self._attach({"number": self._os_number(txn), "invoice_no": "BIR-000001"})
        manager_auth = self._manager_auth()

        response = self._attach(
            {
                "number": self._os_number(txn),
                "invoice_no": "BIR-000002",
                "replace": True,
            },
            auth=manager_auth,
        )

        self.assertEqual(response.status_code, 200, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "BIR-000002")
        # The audit sentence names BOTH numbers: what the slip carried before, and what
        # the manager put in its place.
        row = AuditLog.objects.filter(
            action_type=AuditLog.ActionType.UPDATE, description__contains="BIR-000002"
        ).latest("id")
        self.assertIn("BIR-000001", row.description)


class InvoiceNoConflictsTests(InvoiceTaggingBase):
    """One paper invoice tags one sale."""

    def test_the_same_invoice_no_on_another_sale_is_409(self):
        first = self._seed_sale()
        second = self._seed_sale()
        self._attach({"number": self._os_number(first), "invoice_no": "BIR-000555"})

        response = self._attach(
            {"number": self._os_number(second), "invoice_no": "BIR-000555"}
        )

        self.assertEqual(response.status_code, 409, response.content)
        self.assertEqual(response.json()["code"], "INVOICE_NO_IN_USE")
        second.refresh_from_db()
        self.assertEqual(second.invoice_no, "")

    def test_a_return_cannot_be_tagged(self):
        original = self._seed_sale()
        txn = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[
                {"variant_id": self.vuom.id, "qty": 1, "unit_price": Decimal(10)}
            ],
            original_transaction_id=original.id,
            reason="one bag back",
        )

        response = self._attach(
            {"number": txn.transaction_no, "invoice_no": "BIR-000999"}
        )

        self.assertEqual(response.status_code, 400, response.content)
        txn.refresh_from_db()
        self.assertEqual(txn.invoice_no, "")


class InvoiceNoSearchTests(InvoiceTaggingBase):
    """`?q=` finds a sale by the invoice number the cashier wrote on the slip."""

    def test_the_q_filter_matches_the_invoice_no(self):
        txn = self._seed_sale()
        self._attach({"number": self._os_number(txn), "invoice_no": "BIR-000321"})

        response = self.client.get("/api/v1/transactions/?q=bir-000321", **self.auth)

        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(response.json()["count"], 1)
        self.assertEqual(response.json()["results"][0]["id"], txn.id)
