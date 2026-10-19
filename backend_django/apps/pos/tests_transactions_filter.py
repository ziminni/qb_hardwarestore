# pyright: reportAttributeAccessIssue=false
"""Phase 6 task 6C.1 — GET /transactions/ filters by source.

Decision 15's amendment wires the returns page over
GET /api/v1/transactions/?source=RETURN; without a filter the page cannot
isolate returns from sales.
"""
from decimal import Decimal

from django.contrib.auth.models import Group

from apps.pos.services import process_return, process_sale
from apps.pos.tests import LOGIN_URL, POSTestBase


class TransactionSourceFilterTests(POSTestBase):
    def setUp(self):
        super().setUp()
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'cashier1', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200)
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _get(self, query=''):
        return self.client.get(f'/api/v1/transactions/{query}', **self.auth)

    def _seed(self):
        sale = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 2,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH', 'amount_tendered': Decimal('20')}])
        process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 1,
                         'unit_price': Decimal('10')}],
            original_transaction_id=sale.id)
        return sale

    def test_source_filter_isolates_returns(self):
        self._seed()

        response = self._get('?source=RETURN')

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data['results']
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['source'], 'RETURN')

    def test_no_filter_returns_everything(self):
        self._seed()

        response = self._get()

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['count'], 2)
