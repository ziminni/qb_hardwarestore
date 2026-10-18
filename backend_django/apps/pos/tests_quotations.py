# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6A.1 — the quotation endpoint.

Decision 05 (Sales Stack Reconciliation) ruled that quotations get a REAL backend model, because the
sales role ships a quotations screen and the client stack for it (`sales_module_viewmodel.dart` +
`models/sales_module.dart`) had nothing to call. These tests go through the ENDPOINT rather than
constructing rows by hand, so the contract (URL, auth, payload shape, generated number) is what is
pinned — the same discipline the ledger-payment tests used after the collectibles bug.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand, Category, Product, ProductVariant, UnitOfMeasure, VariantUOM,
)
from apps.pos.models import Customer

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
QUOTATIONS_URL = '/api/v1/quotations/'


class QuotationApiTests(TestCase):
    def setUp(self):
        # Roles are Django Groups and RoleRequired lets superusers bypass the check, so a
        # superuser keeps this test about the CONTRACT rather than about role wiring.
        self.manager = User.objects.create_superuser(
            username='qmanager', email='q@x.com', password='pass12345')
        self.customer = Customer.objects.create(name='Dela Cruz Construction')
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        self.variant_uom = VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('315'))
        self.client = APIClient()

    def _login(self):
        response = self.client.post(
            LOGIN_URL, {'username': 'qmanager', 'password': 'pass12345'}, format='json')
        token = response.data.get('access') or response.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return response

    def _payload(self, **overrides):
        payload = {
            'customer': self.customer.id,
            'notes': 'For the Mandaue site',
            'items': [
                {'variant_uom': self.variant_uom.id, 'qty': '10.00', 'unit_price': '315.00'},
            ],
        }
        payload.update(overrides)
        return payload

    def test_a_quotation_is_created_with_a_generated_number(self):
        self._login()
        response = self.client.post(QUOTATIONS_URL, self._payload(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data['quotation_no'], 'the number must be generated server-side')
        self.assertEqual(response.data['customer'], self.customer.id)
        self.assertEqual(len(response.data['items']), 1)

    def test_the_list_returns_the_quotation_with_its_items_nested(self):
        self._login()
        self.client.post(QUOTATIONS_URL, self._payload(), format='json')
        response = self.client.get(QUOTATIONS_URL)
        self.assertEqual(response.status_code, 200)
        rows = response.data['results']
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]['items']), 1)
        self.assertEqual(Decimal(rows[0]['items'][0]['qty']), Decimal('10.00'))

    def test_an_anonymous_caller_is_refused(self):
        response = self.client.post(QUOTATIONS_URL, self._payload(), format='json')
        self.assertIn(response.status_code, (401, 403))

    def test_a_quotation_without_a_customer_is_refused(self):
        self._login()
        response = self.client.post(
            QUOTATIONS_URL, self._payload(customer=None), format='json')
        self.assertEqual(response.status_code, 400)
