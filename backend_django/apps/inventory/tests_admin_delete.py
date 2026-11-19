# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Owner 2026-11-18: Admin settings may DELETE a category or supplier nobody uses.

Anything in use is refused with 400 `IN_USE` naming what uses it (archive instead);
only an Admin may delete; adding and editing keep their existing roles.
"""

from decimal import Decimal

from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .models import Category, PurchaseOrder, Supplier
from .tests import InventoryTestBase


class AdminDeleteTests(InventoryTestBase):
    def setUp(self):
        super().setUp()
        self.admin = self.user.__class__.objects.create_user(
            username="boss", email="b@x.com", password="pass12345"
        )
        self.admin.groups.add(Group.objects.get_or_create(name="Admin")[0])
        self.user.groups.add(Group.objects.get_or_create(name="Stock Manager")[0])
        self.api = APIClient()

    def _delete(self, path, user=None):
        self.api.force_authenticate(user or self.admin)
        return self.api.delete(path)

    def test_an_unused_category_is_deleted_and_audited(self):
        spare = Category.objects.create(name="Paint")
        response = self._delete(f"/api/v1/categories/{spare.pk}/")
        self.assertEqual(response.status_code, 204)
        self.assertFalse(Category.objects.filter(pk=spare.pk).exists())
        self.assertTrue(
            AuditLog.objects.filter(
                action_type="DELETE", description__contains="Paint"
            ).exists()
        )

    def test_a_category_with_products_is_refused_and_kept(self):
        response = self._delete(f"/api/v1/categories/{self.category.pk}/")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data["code"], "IN_USE")
        self.assertIn("1 products", response.data["detail"])
        self.assertTrue(Category.objects.filter(pk=self.category.pk).exists())

    def test_an_unused_supplier_is_deleted(self):
        supplier = Supplier.objects.create(company_name="Never Used Co")
        self.assertEqual(
            self._delete(f"/api/v1/suppliers/{supplier.pk}/").status_code, 204
        )
        self.assertFalse(Supplier.objects.filter(pk=supplier.pk).exists())

    def test_a_supplier_with_orders_is_refused(self):
        supplier = Supplier.objects.create(company_name="Busy Co")
        PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.user, status=PurchaseOrder.Status.DRAFT
        )
        response = self._delete(f"/api/v1/suppliers/{supplier.pk}/")
        self.assertEqual(response.data["code"], "IN_USE")
        self.assertIn("purchase order", response.data["detail"])
        self.assertTrue(Supplier.objects.filter(pk=supplier.pk).exists())

    def test_only_an_admin_may_delete(self):
        spare = Category.objects.create(name="Tools")
        response = self._delete(f"/api/v1/categories/{spare.pk}/", user=self.user)
        self.assertEqual(response.status_code, 403)
        self.assertTrue(Category.objects.filter(pk=spare.pk).exists())

    def test_the_stock_manager_still_adds_and_edits(self):
        self.api.force_authenticate(self.user)
        created = self.api.post("/api/v1/categories/", {"name": "Roofing"})
        self.assertEqual(created.status_code, 201, created.data)
        renamed = self.api.patch(
            f"/api/v1/categories/{created.data['id']}/", {"name": "Roof"}
        )
        self.assertEqual(renamed.status_code, 200, renamed.data)
        supplier = self.api.post(
            "/api/v1/suppliers/",
            {"company_name": "New Co", "terms_days": 30},
        )
        self.assertEqual(supplier.status_code, 201, supplier.data)
        self.assertEqual(Decimal(supplier.data["terms_days"]), 30)
