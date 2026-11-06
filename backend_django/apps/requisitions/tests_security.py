# pyright: reportAttributeAccessIssue=false
"""Requisitions — token secrecy and the read-only audience (Phase 2 task 3, Phase 1 task 4).

The material token is a BEARER credential: whoever holds the UUID releases the goods and
posts the receivable. `GET /api/v1/requisitions/` and `GET /api/v1/tokens/` answered any
authenticated user before that task, so a cashier could release material that was never
handed to them. These tests pin the answers over HTTP because the contract that matters is
the status code and the body the client sees.

Decision 01 removed the POS-side request and approval, so the write-side tests that used
to live here (foreman scoping, self-approval, lock-after-submit, status-by-PATCH, line
ownership) went with the behaviour. `tests_readonly.py` pins the 405/404 answers that
replaced them.
"""

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import Requisition, RequisitionItem
from .serializers import RequisitionSerializer
from .tests import RequisitionTestBase

User = get_user_model()

LIST_URL = '/api/v1/requisitions/'
TOKENS_URL = '/api/v1/tokens/'
ITEMS_URL = '/api/v1/req-items/'
VERIFY_URL = '/api/v1/tokens/verify/'


class _SecurityBase(RequisitionTestBase):
    """Adds the role groups the API checks to `RequisitionTestBase`'s users.

    The Phase 1 fixture creates its users WITHOUT groups because it exercises the
    services directly. Role denial is the subject here, so every account gets the group
    a real deployment seeds.
    """

    def setUp(self):
        super().setUp()
        self.password = get_random_string(12)
        for user in (self.manager, self.cashier):
            user.set_password(self.password)
            user.save(update_fields=['password'])

        self.stocker = self._make_user('stocker1', 'Stock Manager')
        self._add_group(self.manager, 'Store Manager')
        self._add_group(self.cashier, 'Cashier')
        self.client = APIClient()

    def _add_group(self, user, name):
        group, _ = Group.objects.get_or_create(name=name)
        user.groups.add(group)

    def _make_user(self, username, group_name):
        user = User.objects.create_user(
            username=username, email=f'{username}@x.com', password=self.password,
            full_name=f'{username} User')
        self._add_group(user, group_name)
        return user

    def _login(self, username):
        """Point the client at `username`; returns the authenticated client."""
        response = self.client.post('/api/v1/auth/login/', {
            'username': username, 'password': self.password}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        token = response.data.get('access') or response.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')
        return self.client

    def _second_requisition(self):
        return Requisition.objects.create(
            project=self.project, requester_name='Other Quester',
            req_number='REQ-OTHER-0001')


class RequisitionReadScopeTests(_SecurityBase):
    """Only a manager/admin reads the CPMS copy, and with it the bearer tokens."""

    def test_cashier_cannot_list_requisitions(self):
        self._login('cashier1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_stocker_cannot_list_requisitions(self):
        self._login('stocker1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_groupless_user_cannot_list_requisitions(self):
        groupless = User.objects.create_user(
            username='norole1', email='n@x.com', password=self.password)
        self.assertFalse(groupless.groups.exists())
        self._login('norole1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_cashier_cannot_list_tokens(self):
        self._mint_token()
        self._login('cashier1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_stocker_cannot_list_tokens(self):
        self._mint_token()
        self._login('stocker1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_manager_can_list_tokens(self):
        token = self._mint_token()
        self._login('manager1')
        response = self.client.get(TOKENS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['token'] for row in response.data['results']],
            [str(token.token)])

    def test_cashier_cannot_read_requisition_detail(self):
        self._login('cashier1')
        response = self.client.get(f'{LIST_URL}{self.requisition.pk}/')
        self.assertEqual(response.status_code, 403, response.data)

    def test_manager_sees_every_requisition_with_its_token(self):
        token = self._mint_token()
        other = self._second_requisition()
        other_token = self._mint_token(other)
        self._login('manager1')
        response = self.client.get(LIST_URL)
        self.assertEqual(response.status_code, 200, response.data)
        by_id = {row['id']: row for row in response.data['results']}
        self.assertEqual(set(by_id), {self.requisition.pk, other.pk})
        self.assertEqual(by_id[self.requisition.pk]['token'], str(token.token))
        self.assertEqual(by_id[other.pk]['token'], str(other_token.token))

    def test_serializer_token_is_null_without_a_request(self):
        """The key must stay PRESENT: the Flutter Requisition model reads a nullable 'token'."""
        self._mint_token()
        self.requisition.refresh_from_db()
        data = dict(RequisitionSerializer(self.requisition).data)
        self.assertIn('token', data)
        self.assertIsNone(data['token'])


class RequisitionItemScopeTests(_SecurityBase):
    """Lines follow the read rule of their requisition: managers and admins only."""

    def test_cashier_cannot_list_requisition_items(self):
        self._login('cashier1')
        response = self.client.get(ITEMS_URL)
        self.assertEqual(response.status_code, 403, response.data)

    def test_manager_lists_items_of_every_requisition(self):
        other = self._second_requisition()
        other_item = RequisitionItem.objects.create(
            requisition=other, variant_uom=self.vuom, quantity=1)
        self._login('manager1')
        response = self.client.get(ITEMS_URL)
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            {row['id'] for row in response.data['results']},
            {self.req_item.pk, other_item.pk})


class TokenVerifyPermissionTests(_SecurityBase):
    """Verifying a handed-over token is POS work; it must not be open to everyone."""

    def test_cashier_can_verify_a_valid_token(self):
        token = self._mint_token()
        self._login('cashier1')
        response = self.client.post(
            VERIFY_URL, {'token': str(token.token)}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            response.data['requisition']['req_number'],
            self.requisition.req_number)

    def test_stocker_cannot_verify_a_token(self):
        token = self._mint_token()
        self._login('stocker1')
        response = self.client.post(
            VERIFY_URL, {'token': str(token.token)}, format='json')
        self.assertEqual(response.status_code, 403, response.data)
