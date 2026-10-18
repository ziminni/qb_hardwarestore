"""Phase 6 task 6A.2 — the sales-order endpoint, and the quotation status vocabulary.

Decision 05 (Sales Stack Reconciliation) made `sales_module_viewmodel.dart` + `models/sales_module.dart`
the CANONICAL stack for quotations and orders, which means the backend's status vocabularies must match
the client's enums. They did not: the client says `SalesQuoteStatus { draft, sent, accepted, expired }`
and the first cut of the Quotation model shipped `REJECTED` where the client has `expired`. A status the
client cannot render shows as "Unknown" — avoidable here, unlike the requisition case where `unknown`
exists because the server may add statuses the client was never taught.
"""
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand, Category, Product, ProductVariant, UnitOfMeasure, VariantUOM,
)
from apps.pos.models import Customer, Quotation

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
ORDERS_URL = '/api/v1/sales-orders/'
QUOTATIONS_URL = '/api/v1/quotations/'


class SalesOrderApiTests(TestCase):
    def setUp(self):
        self.manager = User.objects.create_superuser(
            username='somanager', email='so@x.com', password='pass12345')
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
        self.client.post(LOGIN_URL, {'username': 'somanager', 'password': 'pass12345'}, format='json')
        response = self.client.post(
            LOGIN_URL, {'username': 'somanager', 'password': 'pass12345'}, format='json')
        token = response.data.get('access') or response.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def _payload(self, **overrides):
        payload = {
            'customer': self.customer.id,
            'notes': 'Confirmed by phone',
            'items': [
                {'variant_uom': self.variant_uom.id, 'qty': '10.00', 'unit_price': '315.00'},
            ],
        }
        payload.update(overrides)
        return payload

    def test_an_order_is_created_with_a_generated_number(self):
        response = self.client.post(ORDERS_URL, self._payload(), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data['order_no'], 'the number must be generated server-side')
        self.assertEqual(len(response.data['items']), 1)

    def test_the_list_returns_the_order_with_its_items_nested(self):
        self.client.post(ORDERS_URL, self._payload(), format='json')
        response = self.client.get(ORDERS_URL)
        self.assertEqual(response.status_code, 200)
        rows = response.data['results']
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0]['items']), 1)
        self.assertEqual(Decimal(rows[0]['items'][0]['qty']), Decimal('10.00'))

    def test_the_order_status_vocabulary_matches_the_client_enum(self):
        # SalesOrderStatus { confirmed, processing, ready, completed }
        from apps.pos.models import SalesOrder

        self.assertEqual(
            [value for value, _ in SalesOrder.Status.choices],
            ['CONFIRMED', 'PROCESSING', 'READY', 'COMPLETED'],
        )

    def test_an_order_can_be_linked_to_the_quotation_it_came_from(self):
        quotation = self.client.post(QUOTATIONS_URL, self._payload(), format='json').data
        response = self.client.post(
            ORDERS_URL, self._payload(quotation=quotation['id']), format='json')
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['quotation'], quotation['id'])

    def test_an_anonymous_caller_is_refused(self):
        anonymous = APIClient()
        response = anonymous.post(ORDERS_URL, self._payload(), format='json')
        self.assertIn(response.status_code, (401, 403))


class QuotationStatusVocabularyTests(TestCase):
    def test_the_quotation_status_vocabulary_matches_the_client_enum(self):
        # SalesQuoteStatus { draft, sent, accepted, expired } — NOT rejected.
        self.assertEqual(
            [value for value, _ in Quotation.Status.choices],
            ['DRAFT', 'SENT', 'ACCEPTED', 'EXPIRED'],
        )
