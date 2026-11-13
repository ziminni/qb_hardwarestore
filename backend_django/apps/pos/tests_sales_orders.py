# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6A.2 — the sales-order endpoint, and the quotation status vocabulary.

Decision 05 (Sales Stack Reconciliation) made `sales_module_viewmodel.dart` + `models/sales_module.dart`
the CANONICAL stack for quotations and orders, which means the backend's status vocabularies must match
the client's enums. They did not: the client says `SalesQuoteStatus { draft, sent, accepted, expired }`
and the first cut of the Quotation model shipped `REJECTED` where the client has `expired`. A status the
client cannot render shows as "Unknown" — avoidable here, unlike the requisition case where `unknown`
exists because the server may add statuses the client was never taught.
"""

from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
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
from apps.pos.models import (
    Customer,
    Delivery,
    Quotation,
    SalesOrder,
    SalesOrderItem,
)
from apps.users.models import AuditLog

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
ORDERS_URL = "/api/v1/sales-orders/"
QUOTATIONS_URL = "/api/v1/quotations/"


def _delivery_body(**overrides):
    body = {
        "address": "12 Mabini St, Barangay San Roque, Quezon City",
        "contact_name": "Ana Reyes",
        "contact_phone": "0917-555-0100",
        "scheduled_date": "2026-12-01",
        "fee": "20.00",
    }
    body.update(overrides)
    return body


class SalesOrderApiTests(TestCase):
    def setUp(self):
        self.manager = User.objects.create_superuser(
            username="somanager", email="so@x.com", password="pass12345"
        )
        # REGULAR, not the model's WALK_IN default: Phase 7 B5 refuses an order on the
        # walk-in placeholder (decision 19's "walk-in orders are already impossible").
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
        self.client.post(
            LOGIN_URL, {"username": "somanager", "password": "pass12345"}, format="json"
        )
        response = self.client.post(
            LOGIN_URL, {"username": "somanager", "password": "pass12345"}, format="json"
        )
        token = response.data.get("access") or response.data.get("token")
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def _payload(self, **overrides):
        payload = {
            "customer": self.customer.id,
            "notes": "Confirmed by phone",
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

    def test_archived_product_refuses_order_without_writes(self):
        product = self.variant.product
        product.is_active = False
        product.save(update_fields=["is_active"])

        response = self.client.post(
            ORDERS_URL, self._payload(delivery=_delivery_body()), format="json"
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self.assertFalse(SalesOrder.objects.exists())
        self.assertFalse(SalesOrderItem.objects.exists())
        self.assertFalse(Delivery.objects.exists())
        # The test's own login wrote a LOGIN row; the refused create wrote nothing.
        self.assertFalse(
            AuditLog.objects.exclude(action_type=AuditLog.ActionType.LOGIN).exists()
        )

    def test_archived_variant_refuses_order_without_writes(self):
        self.variant.is_active = False
        self.variant.save(update_fields=["is_active"])

        response = self.client.post(ORDERS_URL, self._payload(), format="json")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INACTIVE_SELLING_UNIT")
        self.assertFalse(SalesOrder.objects.exists())
        self.assertFalse(SalesOrderItem.objects.exists())
        # The test's own login wrote a LOGIN row; the refused create wrote nothing.
        self.assertFalse(
            AuditLog.objects.exclude(action_type=AuditLog.ActionType.LOGIN).exists()
        )

    def test_an_order_is_created_with_a_generated_number(self):
        response = self.client.post(ORDERS_URL, self._payload(), format="json")
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(
            response.data["order_no"], "the number must be generated server-side"
        )
        self.assertEqual(len(response.data["items"]), 1)

    def test_the_list_returns_the_order_with_its_items_nested(self):
        self.client.post(ORDERS_URL, self._payload(), format="json")
        response = self.client.get(ORDERS_URL)
        self.assertEqual(response.status_code, 200)
        rows = response.data["results"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]["items"]), 1)
        self.assertEqual(Decimal(rows[0]["items"][0]["qty"]), Decimal("10.00"))

    def test_the_order_status_vocabulary_matches_the_client_enum(self):
        # Phase 7 B1 (decision 19): the lifecycle adds PARTIAL and CANCELLED. PROCESSING
        # and READY stay as choices for the legacy rows Phase 5 wrote; they are never
        # written again and read as CONFIRMED (`SalesOrder.effective_status`).
        from apps.pos.models import SalesOrder

        self.assertEqual(
            [value for value, _ in SalesOrder.Status.choices],
            [
                "CONFIRMED",
                "PROCESSING",
                "READY",
                "PARTIAL",
                "COMPLETED",
                "CANCELLED",
            ],
        )

    def test_an_order_can_be_linked_to_the_quotation_it_came_from(self):
        quotation = self.client.post(
            QUOTATIONS_URL, self._payload(), format="json"
        ).data
        response = self.client.post(
            ORDERS_URL, self._payload(quotation=quotation["id"]), format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data["quotation"], quotation["id"])

    def test_an_anonymous_caller_is_refused(self):
        anonymous = APIClient()
        response = anonymous.post(ORDERS_URL, self._payload(), format="json")
        self.assertIn(response.status_code, (401, 403))

    # --- Phase 6 B1 (decision 22 #16): Phase 5's create-only contract is the contract.
    # Phase 7 B3 (decision 19 #4) superseded the PATCH half of it: a Store Manager/Admin
    # now EDITS an order that has not been fulfilled. PUT and DELETE stay unrouted.

    def test_put_and_delete_of_an_order_are_not_routed(self):
        created = self.client.post(ORDERS_URL, self._payload(), format="json")
        self.assertEqual(created.status_code, 201, created.data)
        url = f"{ORDERS_URL}{created.data['id']}/"

        put = self.client.put(url, self._payload(status="READY"), format="json")
        delete = self.client.delete(url)

        for response in (put, delete):
            self.assertEqual(response.status_code, 405, response.data)
        order = SalesOrder.objects.get(pk=created.data["id"])
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)

    def test_patch_is_the_routed_edit_and_still_cannot_write_a_status(self):
        # B3: PATCH is a manager's edit, so it answers (400 for the missing `reason`
        # here) instead of 405 - but the status stays the server's to write.
        created = self.client.post(ORDERS_URL, self._payload(), format="json")
        url = f"{ORDERS_URL}{created.data['id']}/"

        patch = self.client.patch(url, {"status": "READY"}, format="json")

        self.assertEqual(patch.status_code, 400, patch.data)
        self.assertEqual(patch.data["code"], "SALES_ORDER_REASON_REQUIRED")
        order = SalesOrder.objects.get(pk=created.data["id"])
        self.assertEqual(order.status, SalesOrder.Status.CONFIRMED)

    def test_deleting_an_order_with_a_delivery_is_a_405_not_a_500(self):
        created = self.client.post(
            ORDERS_URL, self._payload(delivery=_delivery_body()), format="json"
        )
        self.assertEqual(created.status_code, 201, created.data)

        response = self.client.delete(f"{ORDERS_URL}{created.data['id']}/")

        self.assertEqual(response.status_code, 405, response.data)
        self.assertTrue(SalesOrder.objects.filter(pk=created.data["id"]).exists())
        self.assertTrue(
            Delivery.objects.filter(sales_order_id=created.data["id"]).exists()
        )

    def test_creating_an_order_writes_one_create_audit_row(self):
        response = self.client.post(ORDERS_URL, self._payload(), format="json")
        self.assertEqual(response.status_code, 201, response.data)

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.CREATE)
        self.assertIn(response.data["order_no"], row.description)
        self.assertIn("Dela Cruz Construction", row.description)
        self.assertIn("1 line,", row.description)
        self.assertIn("delivery: no", row.description)

    def test_an_order_with_a_delivery_is_audited_as_one_with_a_delivery(self):
        response = self.client.post(
            ORDERS_URL, self._payload(delivery=_delivery_body()), format="json"
        )
        self.assertEqual(response.status_code, 201, response.data)

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.CREATE)
        self.assertIn(response.data["order_no"], row.description)
        self.assertIn("delivery: yes", row.description)

    def test_a_refused_order_writes_neither_the_order_nor_an_audit_row(self):
        # The delivery fee is refused INSIDE the create transaction, after the order row
        # exists: the audit row has to roll back with it or the trail claims an order
        # that was never created.
        response = self.client.post(
            ORDERS_URL,
            self._payload(delivery=_delivery_body(fee="20.005")),
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertFalse(SalesOrder.objects.exists())
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.CREATE).exists()
        )

    @mock.patch("apps.pos.views.audit_request")
    def test_a_failed_audit_rolls_the_order_and_its_delivery_back(self, audit_request):
        # The audit row is part of the write, not a side effect of it: an order whose
        # CREATE row cannot be written must not exist, and neither must its lines or its
        # delivery slip.
        audit_request.side_effect = RuntimeError("audit is down")

        with self.assertRaises(RuntimeError):
            self.client.post(
                ORDERS_URL, self._payload(delivery=_delivery_body()), format="json"
            )

        self.assertFalse(SalesOrder.objects.exists())
        self.assertFalse(SalesOrderItem.objects.exists())
        self.assertFalse(Delivery.objects.exists())
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.CREATE).exists()
        )


class QuotationStatusVocabularyTests(TestCase):
    def test_the_quotation_status_vocabulary_matches_the_client_enum(self):
        # SalesQuoteStatus { draft, sent, accepted, expired } — NOT rejected.
        self.assertEqual(
            [value for value, _ in Quotation.Status.choices],
            ["DRAFT", "SENT", "ACCEPTED", "EXPIRED"],
        )
