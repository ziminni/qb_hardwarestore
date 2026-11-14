# pyright: reportAttributeAccessIssue=false
"""Phase 1 Task 4 — the POS no longer requests or approves material (decision 01).

CPMS creates a request and its project manager approves it; the POS keeps a READ-ONLY
copy and the cashier releases it by token. So the requisition, line and project
endpoints answer `list`/`retrieve` only (405 on every write), the four status actions
no longer exist (404 — their URLs are not routed at all), and the `Site Foreman` role is
gone from the source.

These tests build their own fixture instead of reusing `RequisitionTestBase`: the subject
here is which methods a URL answers, and nothing needs stock, a shift or a sale.
"""

from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import SimpleTestCase, TestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.inventory.models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)
from apps.pos.models import Customer

from .models import MaterialToken, Project, Requisition, RequisitionItem

User = get_user_model()

LIST_URL = '/api/v1/requisitions/'
ITEMS_URL = '/api/v1/req-items/'
PROJECTS_URL = '/api/v1/projects/'


class _ReadOnlyBase(TestCase):
    """A Store Manager, a Cashier and one ACCEPTED request as CPMS would leave it."""

    def setUp(self):
        self.password = get_random_string(20)
        self.manager = self._make_user('manager1', 'Mana Ger', 'Store Manager')
        self.cashier = self._make_user('cashier1', 'Cashi Er', 'Cashier')
        self.client = APIClient()

        customer = Customer.objects.create(
            name='Dela Cruz Construction',
            customer_type=Customer.Type.CONSTRUCTION_FIRM)
        self.project = Project.objects.create(
            name='House Build', customer=customer, cpms_project_id='CPMS-P-1')
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code='BAG', defaults={'name': 'Bag'})
        product = Product.objects.create(
            category=Category.objects.create(name='Cement'),
            brand=Brand.objects.create(name='Rhino'),
            base_name='Portland Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        self.vuom = VariantUOM.objects.create(
            variant=variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'))

        # Decision 01/08: the requester and the approver are NAMES CPMS reported, and the
        # request is already approved when it lands here.
        self.requisition = Requisition.objects.create(
            project=self.project,
            cpms_request_id='CPMS-R-1',
            req_number='REQ-READONLY-0001',
            status=Requisition.Status.ACCEPTED,
            requester_name='Rey Quester',
            approver_name='Mana Ger',
        )
        self.req_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal('10'))
        self.token = MaterialToken.objects.create(requisition=self.requisition)

    def _make_user(self, username, full_name, group_name):
        user = User.objects.create_user(
            username=username, email=f'{username}@x.com',
            password=self.password, full_name=full_name)
        user.groups.add(Group.objects.get_or_create(name=group_name)[0])
        return user

    def _login(self, username):
        response = self.client.post('/api/v1/auth/login/', {
            'username': username, 'password': self.password}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        self.client.credentials(
            HTTP_AUTHORIZATION=f'Bearer {response.data["access"]}')
        return self.client


class RequisitionReadTests(_ReadOnlyBase):
    """The manager's read of the CPMS copy is unchanged."""

    def test_a_manager_reads_the_list(self):
        self._login('manager1')

        response = self.client.get(LIST_URL)

        self.assertEqual(response.status_code, 200, response.data)
        row = response.data['results'][0]
        self.assertEqual(row['id'], self.requisition.pk)
        self.assertEqual(row['requested_by_name'], 'Rey Quester')
        self.assertEqual(row['approver_name'], 'Mana Ger')
        # A manager still sees the token: they are the one who hands it over.
        self.assertEqual(row['token'], str(self.token.token))

    def test_a_manager_reads_one_requisition_and_its_lines(self):
        self._login('manager1')

        response = self.client.get(f'{LIST_URL}{self.requisition.pk}/')

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [item['id'] for item in response.data['items']], [self.req_item.pk])
        items = self.client.get(ITEMS_URL)
        self.assertEqual(items.status_code, 200, items.data)
        self.assertEqual(
            [row['id'] for row in items.data['results']], [self.req_item.pk])

    def test_a_cashier_cannot_read_the_requisition_copy(self):
        self._login('cashier1')

        self.assertEqual(self.client.get(LIST_URL).status_code, 403)
        self.assertEqual(
            self.client.get(f'{LIST_URL}{self.requisition.pk}/').status_code, 403)


class RequisitionWriteRefusalTests(_ReadOnlyBase):
    """Every write the POS used to offer is now a method the URL does not allow."""

    def setUp(self):
        super().setUp()
        self._login('manager1')

    def test_a_manager_cannot_create_a_requisition(self):
        before = Requisition.objects.count()

        response = self.client.post(
            LIST_URL, {'project': self.project.pk, 'notes': 'new request'},
            format='json')

        self.assertEqual(response.status_code, 405, response.data)
        self.assertEqual(Requisition.objects.count(), before)

    def test_a_manager_cannot_patch_or_delete_a_requisition(self):
        patched = self.client.patch(
            f'{LIST_URL}{self.requisition.pk}/', {'notes': 'edited'}, format='json')
        self.assertEqual(patched.status_code, 405, patched.data)
        deleted = self.client.delete(f'{LIST_URL}{self.requisition.pk}/')
        self.assertEqual(deleted.status_code, 405, getattr(deleted, 'data', None))

        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.notes, '')
        self.assertEqual(self.requisition.status, Requisition.Status.ACCEPTED)

    def test_the_submit_approve_and_reject_actions_are_not_routed(self):
        """No URL, no verb: the actions are gone, so the router answers 404."""
        for action in ('submit', 'approve', 'reject'):
            with self.subTest(action=action):
                response = self.client.post(
                    f'{LIST_URL}{self.requisition.pk}/{action}/')
                self.assertEqual(
                    response.status_code, 404, getattr(response, 'data', None))

        # Nothing moved and no second token was minted.
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.ACCEPTED)
        self.assertEqual(
            MaterialToken.objects.filter(requisition=self.requisition).count(), 1)

    def test_a_manager_cannot_write_a_requisition_line(self):
        created = self.client.post(ITEMS_URL, {
            'requisition': self.requisition.pk,
            'variant_uom': self.vuom.pk,
            'quantity': '5.00',
        }, format='json')
        self.assertEqual(created.status_code, 405, created.data)
        patched = self.client.patch(
            f'{ITEMS_URL}{self.req_item.pk}/', {'quantity': '99.00'}, format='json')
        self.assertEqual(patched.status_code, 405, patched.data)
        deleted = self.client.delete(f'{ITEMS_URL}{self.req_item.pk}/')
        self.assertEqual(deleted.status_code, 405, getattr(deleted, 'data', None))

        self.assertEqual(self.requisition.items.count(), 1)
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.quantity, Decimal('10'))


class ProjectReadOnlyTests(_ReadOnlyBase):
    """Projects arrive with a CPMS push, so the POS reads them and writes none."""

    def test_a_manager_reads_projects(self):
        self._login('manager1')

        response = self.client.get(PROJECTS_URL)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['cpms_project_id'] for row in response.data['results']],
            ['CPMS-P-1'])

    def test_a_manager_cannot_write_a_project(self):
        self._login('manager1')

        created = self.client.post(PROJECTS_URL, {
            'name': 'Second Build', 'customer': self.project.customer_id,
        }, format='json')
        self.assertEqual(created.status_code, 405, created.data)
        patched = self.client.patch(
            f'{PROJECTS_URL}{self.project.pk}/', {'name': 'Renamed'}, format='json')
        self.assertEqual(patched.status_code, 405, patched.data)
        deleted = self.client.delete(f'{PROJECTS_URL}{self.project.pk}/')
        self.assertEqual(deleted.status_code, 405, getattr(deleted, 'data', None))

        self.project.refresh_from_db()
        self.assertEqual(self.project.name, 'House Build')
        self.assertEqual(Project.objects.count(), 1)


class ForemanRoleRemovalTests(SimpleTestCase):
    """Decision 01 — the role does not exist any more, in code or in shipped source."""

    def test_the_role_constant_and_its_permission_classes_are_gone(self):
        from apps.users import permissions

        for name in ('ROLE_SITE_FOREMAN', 'IsForemanOrManager',
                     'IsForemanOrManagerOrReadOnly'):
            with self.subTest(name=name):
                self.assertFalse(
                    hasattr(permissions, name),
                    f'{name} must be deleted with the role (decision 01)')

    def test_no_shipped_source_names_the_role(self):
        """A grep, as a test: the string may survive only in migrations and their tests.

        The migrations are the record of what WAS there, so `migrations/` and the
        `tests_migration` modules are excluded; everything else that ships is scanned.
        """
        backend = Path(settings.BASE_DIR)
        offenders = []
        for directory in ('apps', 'config'):
            for path in (backend / directory).rglob('*.py'):
                if 'migrations' in path.parts or path.name.startswith('tests'):
                    continue
                if 'Site Foreman' in path.read_text(encoding='utf-8'):
                    offenders.append(str(path.relative_to(backend)))
        self.assertEqual(sorted(offenders), [])
