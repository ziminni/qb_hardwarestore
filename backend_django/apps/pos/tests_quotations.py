# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6A.1 — the quotation endpoint.

Decision 05 (Sales Stack Reconciliation) ruled that quotations get a REAL backend model, because the
sales role ships a quotations screen and the client stack for it (`sales_module_viewmodel.dart` +
`models/sales_module.dart`) had nothing to call. These tests go through the ENDPOINT rather than
constructing rows by hand, so the contract (URL, auth, payload shape, generated number) is what is
pinned — the same discipline the ledger-payment tests used after the collectibles bug.
"""

from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)
from apps.pos.models import Customer, Quotation, QuotationItem, SalesOrder
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
QUOTATIONS_URL = "/api/v1/quotations/"


class QuotationFixtureCase(TestCase):
    """The catalogue + one customer a quotation needs, and the login helpers.

    Shared by the contract tests and the Phase 6 B1 write-guard tests, so neither class
    re-runs the other's tests.
    """

    def setUp(self):
        # Roles are Django Groups and RoleRequired lets superusers bypass the check, so a
        # superuser keeps this test about the CONTRACT rather than about role wiring.
        self.manager = User.objects.create_superuser(
            username="qmanager", email="q@x.com", password="pass12345"
        )
        # REGULAR: B5 refuses an order for the seeded WALK_IN placeholder.
        self.customer = Customer.objects.create(
            name="Dela Cruz Construction", customer_type=Customer.Type.REGULAR
        )
        category = Category.objects.create(name="Cement")
        brand = Brand.objects.create(name="Rhino")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        product = Product.objects.create(
            category=category, brand=brand, base_name="Portland Cement"
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

    def _login(self):
        response = self.client.post(
            LOGIN_URL, {"username": "qmanager", "password": "pass12345"}, format="json"
        )
        token = response.data.get("access") or response.data.get("token")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        return response

    def _payload(self, **overrides):
        payload = {
            "customer": self.customer.id,
            "notes": "For the Mandaue site",
            "items": [
                {
                    "variant_uom": self.variant_uom.id,
                    "qty": "10.00",
                    "unit_price": "315.00",
                },
            ],
        }
        payload.update(overrides)
        return payload


class QuotationApiTests(QuotationFixtureCase):
    def test_archived_product_refuses_quotation_without_writes(self):
        self._login()
        product = self.variant.product
        product.is_active = False
        product.save(update_fields=["is_active"])

        response = self.client.post(QUOTATIONS_URL, self._payload(), format="json")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self.assertFalse(Quotation.objects.exists())
        self.assertFalse(QuotationItem.objects.exists())
        # The test's own login wrote a LOGIN row; the refused create wrote nothing.
        self.assertFalse(
            AuditLog.objects.exclude(action_type=AuditLog.ActionType.LOGIN).exists()
        )

    def test_archived_variant_refuses_quotation_without_writes(self):
        self._login()
        self.variant.is_active = False
        self.variant.save(update_fields=["is_active"])

        response = self.client.post(QUOTATIONS_URL, self._payload(), format="json")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self.assertFalse(Quotation.objects.exists())
        self.assertFalse(QuotationItem.objects.exists())
        # The test's own login wrote a LOGIN row; the refused create wrote nothing.
        self.assertFalse(
            AuditLog.objects.exclude(action_type=AuditLog.ActionType.LOGIN).exists()
        )

    def test_a_quotation_is_created_with_a_generated_number(self):
        self._login()
        response = self.client.post(QUOTATIONS_URL, self._payload(), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(
            response.data["quotation_no"], "the number must be generated server-side"
        )
        self.assertEqual(response.data["customer"], self.customer.id)
        self.assertEqual(len(response.data["items"]), 1)

    def test_the_list_returns_the_quotation_with_its_items_nested(self):
        self._login()
        self.client.post(QUOTATIONS_URL, self._payload(), format="json")
        response = self.client.get(QUOTATIONS_URL)
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]["items"]), 1)
        self.assertEqual(Decimal(rows[0]["items"][0]["qty"]), Decimal("10.00"))

    def test_an_anonymous_caller_is_refused(self):
        response = self.client.post(QUOTATIONS_URL, self._payload(), format="json")
        self.assertIn(response.status_code, (401, 403))

    def test_a_quotation_without_a_customer_is_refused(self):
        self._login()
        response = self.client.post(
            QUOTATIONS_URL, self._payload(customer=None), format="json"
        )
        self.assertEqual(response.status_code, 400)


class QuotationWriteGuardTests(QuotationFixtureCase):
    """Phase 6 B1 (decision 22 #16): reading a quotation is every sales role's job.

    Rewriting or erasing one is a manager's. A quotation is what the shop promised a
    customer at a price, so a till account that could edit its lines could change the
    promise after it was sent - and a DELETE that left no trail would erase the evidence
    that it was ever made.
    """

    def setUp(self):
        super().setUp()
        self._role_user("qstore", "Store Manager")
        self._role_user("qcashier", "Cashier")

    def _role_user(self, username, group):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@x.com",
            password="pass12345",
            full_name=username,
        )
        user.groups.add(Group.objects.get_or_create(name=group)[0])
        return user

    def _login_as(self, username):
        self.client.credentials()
        response = self.client.post(
            LOGIN_URL, {"username": username, "password": "pass12345"}, format="json"
        )
        token = response.data.get("access") or response.data.get("token")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def _create_quotation(self):
        self._login_as("qstore")
        response = self.client.post(QUOTATIONS_URL, self._payload(), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def test_a_cashier_cannot_update_or_delete_a_quotation(self):
        quotation = self._create_quotation()
        url = f"{QUOTATIONS_URL}{quotation['id']}/"

        self._login_as("qcashier")
        put = self.client.put(url, self._payload(), format="json")
        patch = self.client.patch(url, {"notes": "Cashier rewrite"}, format="json")
        delete = self.client.delete(url)

        for response in (put, patch, delete):
            self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(
            Quotation.objects.get(pk=quotation["id"]).notes, "For the Mandaue site"
        )
        self.assertFalse(
            AuditLog.objects.filter(
                action_type__in=[AuditLog.ActionType.UPDATE, AuditLog.ActionType.DELETE]
            ).exists()
        )

    def test_a_manager_update_is_audited_once(self):
        quotation = self._create_quotation()

        response = self.client.patch(
            f"{QUOTATIONS_URL}{quotation['id']}/",
            {"notes": "Revised with Ana"},
            format="json",
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            Quotation.objects.get(pk=quotation["id"]).notes, "Revised with Ana"
        )
        row = AuditLog.objects.get(action_type=AuditLog.ActionType.UPDATE)
        self.assertIn(quotation["quotation_no"], row.description)

    def test_a_manager_delete_is_audited_once(self):
        quotation = self._create_quotation()

        response = self.client.delete(f"{QUOTATIONS_URL}{quotation['id']}/")

        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(Quotation.objects.filter(pk=quotation["id"]).exists())
        row = AuditLog.objects.get(action_type=AuditLog.ActionType.DELETE)
        self.assertIn(quotation["quotation_no"], row.description)

    def test_status_is_read_only_on_a_quotation(self):
        quotation = self._create_quotation()

        response = self.client.patch(
            f"{QUOTATIONS_URL}{quotation['id']}/", {"status": "ACCEPTED"}, format="json"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Quotation.objects.get(pk=quotation["id"]).status, "DRAFT")
        # Nothing was written, so no row may claim an update either.
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.UPDATE).exists()
        )

    def test_rewriting_nested_items_on_update_is_refused_with_400(self):
        quotation = self._create_quotation()

        response = self.client.patch(
            f"{QUOTATIONS_URL}{quotation['id']}/",
            {
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "99.00",
                        "unit_price": "1.00",
                    },
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(
            QuotationItem.objects.filter(quotation_id=quotation["id"]).count(), 1
        )
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.UPDATE).exists()
        )

    # --- Phase 6 B1 review round 1: the audit row is not a side effect, it is part of
    # the write. If it cannot be written, the write did not happen either.

    @mock.patch("apps.pos.views.audit_request")
    def test_a_failed_audit_rolls_a_quotation_update_back(self, audit_request):
        quotation = self._create_quotation()
        audit_request.side_effect = RuntimeError("audit is down")

        with self.assertRaises(RuntimeError):
            self.client.patch(
                f"{QUOTATIONS_URL}{quotation['id']}/",
                {"notes": "Rewritten"},
                format="json",
            )

        row = Quotation.objects.get(pk=quotation["id"])
        self.assertEqual(row.notes, "For the Mandaue site")
        items = QuotationItem.objects.filter(quotation_id=quotation["id"])
        self.assertEqual(items.count(), 1)
        self.assertEqual(items[0].qty, Decimal("10.00"))
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.UPDATE).exists()
        )

    @mock.patch("apps.pos.views.audit_request")
    def test_a_failed_audit_rolls_a_quotation_delete_back(self, audit_request):
        quotation = self._create_quotation()
        order = self.client.post(
            "/api/v1/sales-orders/",
            {
                "customer": self.customer.id,
                "quotation": quotation["id"],
                "items": [
                    {
                        "variant_uom": self.variant_uom.id,
                        "qty": "1.00",
                        "unit_price": "315.00",
                    }
                ],
            },
            format="json",
        )
        self.assertEqual(order.status_code, 201, order.data)
        audit_request.side_effect = RuntimeError("audit is down")

        with self.assertRaises(RuntimeError):
            self.client.delete(f"{QUOTATIONS_URL}{quotation['id']}/")

        self.assertTrue(Quotation.objects.filter(pk=quotation["id"]).exists())
        self.assertEqual(
            QuotationItem.objects.filter(quotation_id=quotation["id"]).count(), 1
        )
        # The order's FK is SET_NULL, so a DELETE that went through would have emptied
        # it: it still names the quotation only if the whole delete rolled back.
        self.assertEqual(
            SalesOrder.objects.get(pk=order.data["id"]).quotation_id, quotation["id"]
        )
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.DELETE).exists()
        )
