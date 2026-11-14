# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/requisitions/tests.py: this checker
# runs with a working directory outside the repo, so no pyrightconfig.json is found and
# every `Model.objects` access and `response.status_code` is a false positive on valid
# Django. `manage.py check` and the test run remain the authority.
"""Phase 1b Task 2 — the store answers a pushed request (decisions 09, 10, 13).

A CPMS push is going to land as `WAITING` (Task 4); until then the import still stores
`ACCEPTED`, so every fixture here builds its `WAITING` row directly instead of pushing
one. What is under test is the STORE's answer: Accept with per-line Not available
reasons, or a whole Decline with one reason. Both are legal only from `WAITING`, both
write their audit row in the same transaction, and both leave stock, sales, ledgers and
shifts alone — accepting promises to serve, it reserves nothing and owes nothing.

The race tests at the bottom are `TransactionTestCase` because two worker threads must
see each other's COMMITTED rows; a `TestCase`'s wrapping transaction would hide them and
the test would then pass on timing instead of on the token→request lock every transition
shares (same pattern as `apps.integration.tests_close.CloseReleaseRaceTests`).
"""

import threading
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TestCase, TransactionTestCase
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand,
    Category,
    InventoryBatch,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)
from apps.pos.models import Customer, SalesTransaction, Shift
from apps.users.models import AuditLog

from .models import MaterialToken, Project, Requisition, RequisitionItem

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
LIST_URL = '/api/v1/requisitions/'
CPMS_URL = '/api/v1/integration/cpms/'

# The fixture password, generated rather than written as a literal: these accounts exist
# only in the throwaway test database.
PASSWORD = get_random_string(20)


def detail_url(requisition_id):
    return f'{LIST_URL}{requisition_id}/'


def accept_url(requisition_id):
    return f'{detail_url(requisition_id)}accept/'


def decline_url(requisition_id):
    return f'{detail_url(requisition_id)}decline/'


def close_url(cpms_request_id):
    return f'{CPMS_URL}requests/{cpms_request_id}/close/'


def make_user(username, group=None):
    user = User.objects.create_user(
        username=username, email=f'{username}@x.com', password=PASSWORD,
        full_name=username)
    if group:
        user.groups.add(Group.objects.get_or_create(name=group)[0])
    return user


def make_selling_unit(base_name, variant_name, uom_code, price):
    """One sellable material: its own product, variant and selling unit (decision 04)."""
    category, _ = Category.objects.get_or_create(name=f'Cat {uom_code}')
    brand, _ = Brand.objects.get_or_create(name=f'Brand {uom_code}')
    uom, _ = UnitOfMeasure.objects.get_or_create(
        code=uom_code, defaults={'name': uom_code})
    product = Product.objects.create(
        category=category, brand=brand, base_name=base_name)
    variant = ProductVariant.objects.create(
        product=product, variant_name=variant_name, base_uom=uom)
    return VariantUOM.objects.create(
        variant=variant, uom=uom, conversion_factor=Decimal('1'),
        default_selling_price=Decimal(price))


def make_project(cpms_project_id='CPMS-P-1'):
    customer = Customer.objects.create(
        name='Dela Cruz Construction',
        customer_type=Customer.Type.CONSTRUCTION_FIRM)
    return Project.objects.create(
        name='House Build', customer=customer,
        cpms_project_id=cpms_project_id)


def make_waiting_request(project, cement, rebar, req_number='REQ-WAIT-0001',
                         cpms_request_id='CPMS-R-1'):
    """A request exactly as the CPMS push will leave it once Task 4 sets WAITING."""
    requisition = Requisition.objects.create(
        project=project, cpms_request_id=cpms_request_id, req_number=req_number,
        status=Requisition.Status.WAITING,
        requester_name='Fore Man', approver_name='Mana Ger')
    RequisitionItem.objects.create(
        requisition=requisition, variant_uom=cement, quantity=Decimal('10'))
    RequisitionItem.objects.create(
        requisition=requisition, variant_uom=rebar, quantity=Decimal('5'))
    MaterialToken.objects.create(requisition=requisition)
    return requisition


class StoreReviewTestBase(TestCase):
    """One WAITING request with two lines, plus one account of every relevant role."""

    def setUp(self):
        self.manager = make_user('manager1', 'Store Manager')
        self.admin = make_user('admin1', 'Admin')
        self.sysadmin = make_user('sysadmin1', 'System Administrator')
        self.cashier = make_user('cashier1', 'Cashier')
        self.stocker = make_user('stocker1', 'Stock Manager')
        self.groupless = make_user('nobody1')
        self.cpms = make_user('cpms1', 'CPMS Service')

        self.project = make_project()
        self.cement = make_selling_unit('Cement', '40kg', 'BAG', '280.00')
        self.rebar = make_selling_unit('Rebar', '16mm', 'PC', '150.00')
        self.requisition = make_waiting_request(self.project, self.cement, self.rebar)
        self.cement_line, self.rebar_line = self.requisition.items.order_by('pk')
        self.token = MaterialToken.objects.get(requisition=self.requisition)
        self._clients = {}

    # -- plumbing ---------------------------------------------------------

    def _login(self, username):
        client = APIClient()
        response = client.post(
            LOGIN_URL, {'username': username, 'password': PASSWORD}, format='json')
        self.assertEqual(response.status_code, 200, response.data)
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {response.data["access"]}')
        return client

    def _auth(self, username):
        """One signed-in client per account, so the fixture writes one LOGIN row each."""
        if username not in self._clients:
            self._clients[username] = self._login(username)
        return self._clients[username]

    def _items(self, *answers):
        return [
            {'id': line_id, 'available': available, 'decline_reason': reason}
            for line_id, available, reason in answers]

    def _both_available(self):
        return self._items(
            (self.cement_line.pk, True, ''),
            (self.rebar_line.pk, True, ''))

    def _mixed(self):
        """One Available line, one Not available line with a padded reason."""
        return self._items(
            (self.cement_line.pk, True, ''),
            (self.rebar_line.pk, False, '  Not stocked  '))

    def _accept(self, body, client=None):
        return (client or self._auth('manager1')).post(
            accept_url(self.requisition.pk), body, format='json')

    def _decline(self, body, client=None):
        return (client or self._auth('manager1')).post(
            decline_url(self.requisition.pk), body, format='json')

    def _snapshot(self):
        """Everything a refused decision must leave exactly as it was."""
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        token = MaterialToken.objects.get(pk=self.token.pk)
        return {
            'status': requisition.status,
            'reason': requisition.decline_reason,
            'lines': [
                (line.available, line.decline_reason)
                for line in requisition.items.order_by('pk')],
            'token': (token.is_used, token.used_at, token.used_by_id),
            'tokens': MaterialToken.objects.count(),
            # The store's own rows; LOGIN rows belong to the fixture.
            'audit': AuditLog.objects.filter(action_type__in=[
                AuditLog.ActionType.REQ_APPROVE,
                AuditLog.ActionType.REQ_REJECT]).count(),
            'sales': SalesTransaction.objects.count(),
            'ledgers': CollectibleLedger.objects.count(),
            'shifts': Shift.objects.count(),
            'batches': InventoryBatch.objects.count(),
        }

    def _assert_untouched(self, before):
        self.assertEqual(self._snapshot(), before, 'a refused answer wrote something')

    def _review_rows(self, action_type=None):
        rows = AuditLog.objects.filter(action_type__in=[
            AuditLog.ActionType.REQ_APPROVE,
            AuditLog.ActionType.REQ_REJECT])
        return rows.filter(action_type=action_type) if action_type else rows


class StaffReadTests(StoreReviewTestBase):
    """The staff representation carries the store's answer, with useful labels."""

    def test_a_request_reads_the_decision_fields(self):
        response = self._auth('manager1').get(detail_url(self.requisition.pk))

        self.assertEqual(response.status_code, 200, response.data)
        body = response.data
        self.assertEqual(body['decline_reason'], '')
        self.assertEqual(body['status'], Requisition.Status.WAITING)
        line = body['items'][0]
        # Not answered yet is NULL, which is not the same as "not available".
        self.assertIsNone(line['available'])
        self.assertEqual(line['decline_reason'], '')
        self.assertEqual(line['product_name'], 'Cement')
        self.assertEqual(line['unit'], 'BAG')
        # The keys the Flutter model already decodes stay exactly as they were.
        for key in ('id', 'requisition', 'variant_uom', 'variant', 'variant_name',
                    'quantity', 'released_qty', 'notes'):
            with self.subTest(key=key):
                self.assertIn(key, line)
        self.assertEqual(line['variant_name'], '40kg')

    def test_the_list_filter_is_exact(self):
        accepted = make_waiting_request(
            self.project, self.cement, self.rebar,
            req_number='REQ-ACC-0001', cpms_request_id='CPMS-R-2')
        accepted.status = Requisition.Status.ACCEPTED
        accepted.save(update_fields=['status'])
        make_waiting_request(
            self.project, self.cement, self.rebar,
            req_number='REQ-WAIT-0002', cpms_request_id='CPMS-R-3')

        response = self._auth('manager1').get(LIST_URL, {'status': 'WAITING'})

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(
            [row['req_number'] for row in response.data['results']],
            ['REQ-WAIT-0001', 'REQ-WAIT-0002'])

    def test_an_invalid_status_filter_is_a_field_shaped_400(self):
        for value in ('APPROVED', 'waiting', ''):
            with self.subTest(value=value):
                response = self._auth('manager1').get(LIST_URL, {'status': value})
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn('status', response.data)

    def test_the_queue_is_oldest_first_then_by_pk(self):
        second = make_waiting_request(
            self.project, self.cement, self.rebar,
            req_number='REQ-WAIT-0002', cpms_request_id='CPMS-R-2')
        same_instant = timezone.now() - timedelta(days=1)
        ids = [self.requisition.pk, second.pk]
        Requisition.objects.filter(pk__in=ids).update(created_at=same_instant)

        first_read = self._auth('manager1').get(LIST_URL)
        self.assertEqual(
            [row['id'] for row in first_read.data['results']], ids,
            'equal timestamps must break by pk ascending')

        # The OLDER row has the HIGHER pk: created_at decides, not pk.
        Requisition.objects.filter(pk=second.pk).update(
            created_at=same_instant - timedelta(minutes=5))
        second_read = self._auth('manager1').get(LIST_URL)
        self.assertEqual(
            [row['id'] for row in second_read.data['results']], ids[::-1])


class AcceptValidationTests(StoreReviewTestBase):
    """Decisions 09/10: an answer that is not a full, exact answer writes nothing."""

    def _refused(self, body, status=400, client=None):
        before = self._snapshot()
        response = self._accept(body, client=client)
        self.assertEqual(
            response.status_code, status, getattr(response, 'data', None))
        self._assert_untouched(before)
        return response

    def test_a_missing_line_is_refused(self):
        self._refused({'items': self._items((self.cement_line.pk, True, ''))})

    def test_a_duplicated_line_is_refused(self):
        self._refused({'items': self._items(
            (self.cement_line.pk, True, ''),
            (self.cement_line.pk, True, ''),
            (self.rebar_line.pk, True, ''))})

    def test_a_foreign_line_id_is_refused(self):
        other = make_waiting_request(
            self.project, self.cement, self.rebar,
            req_number='REQ-WAIT-0002', cpms_request_id='CPMS-R-2')
        foreign = other.items.order_by('pk').first()

        self._refused({'items': self._items(
            (self.cement_line.pk, True, ''),
            (foreign.pk, True, ''))})

    def test_a_quoted_boolean_is_refused(self):
        for value in ('true', 'false', 1, 0, None):
            with self.subTest(value=value):
                self._refused({'items': self._items(
                    (self.cement_line.pk, value, ''),
                    (self.rebar_line.pk, True, ''))})

    def test_an_available_line_with_a_reason_is_refused(self):
        self._refused({'items': self._items(
            (self.cement_line.pk, True, 'Not stocked'),
            (self.rebar_line.pk, True, ''))})

    def test_a_not_available_line_without_a_reason_is_refused(self):
        for reason in ('', '   '):
            with self.subTest(reason=reason):
                self._refused({'items': self._items(
                    (self.cement_line.pk, True, ''),
                    (self.rebar_line.pk, False, reason))})

    def test_a_reason_longer_than_255_characters_is_refused(self):
        self._refused({'items': self._items(
            (self.cement_line.pk, True, ''),
            (self.rebar_line.pk, False, 'x' * 256))})

    def test_all_lines_not_available_is_a_400_pointing_at_decline(self):
        response = self._refused({'items': self._items(
            (self.cement_line.pk, False, 'Not stocked'),
            (self.rebar_line.pk, False, 'Not stocked'))})
        self.assertIn('decline', str(response.data).lower())

    def test_no_items_at_all_is_refused(self):
        for body in ({}, {'items': []}, {'items': 'nope'}):
            with self.subTest(body=body):
                self._refused(body)

    def test_a_quantity_or_price_edit_is_refused(self):
        for field in ('quantity', 'price', 'unit_price', 'status'):
            with self.subTest(field=field):
                self._refused({'items': [
                    {'id': self.cement_line.pk, 'available': True,
                     'decline_reason': '', field: '1.00'},
                    {'id': self.rebar_line.pk, 'available': True,
                     'decline_reason': ''}]})

    def test_a_top_level_status_or_quantity_is_refused(self):
        for extra in ({'status': Requisition.Status.ACCEPTED},
                      {'quantity': '1.00'},
                      {'decline_reason': 'sneaky'}):
            with self.subTest(extra=extra):
                self._refused({'items': self._both_available(), **extra})

    def test_an_unknown_requisition_is_a_404(self):
        before = self._snapshot()
        response = self._auth('manager1').post(
            accept_url(999999), {'items': self._both_available()}, format='json')
        self.assertEqual(response.status_code, 404, getattr(response, 'data', None))
        self._assert_untouched(before)


class AcceptTests(StoreReviewTestBase):
    """Decision 10: one Available line and one Not available line, in one answer."""

    def test_a_mixed_accept_records_every_answer(self):
        response = self._accept({'items': self._mixed()})

        self.assertEqual(response.status_code, 200, response.data)
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        self.assertEqual(requisition.status, Requisition.Status.ACCEPTED)
        cement = RequisitionItem.objects.get(pk=self.cement_line.pk)
        rebar = RequisitionItem.objects.get(pk=self.rebar_line.pk)
        self.assertTrue(cement.available)
        self.assertEqual(cement.decline_reason, '')
        self.assertFalse(rebar.available)
        # Trimmed, so the reason CPMS reads is the sentence, not the padding.
        self.assertEqual(rebar.decline_reason, 'Not stocked')

    def test_the_answer_is_the_staff_representation(self):
        response = self._accept({'items': self._mixed()})

        body = response.data
        self.assertEqual(body['id'], self.requisition.pk)
        self.assertEqual(body['status'], Requisition.Status.ACCEPTED)
        self.assertIn('token', body)
        lines = {line['id']: line for line in body['items']}
        self.assertTrue(lines[self.cement_line.pk]['available'])
        self.assertFalse(lines[self.rebar_line.pk]['available'])
        self.assertEqual(
            lines[self.rebar_line.pk]['decline_reason'], 'Not stocked')
        self.assertEqual(lines[self.rebar_line.pk]['product_name'], 'Rebar')
        self.assertEqual(lines[self.rebar_line.pk]['unit'], 'PC')

    def test_accepting_reserves_no_stock_and_books_no_money(self):
        before = self._snapshot()

        self.assertEqual(self._accept({'items': self._mixed()}).status_code, 200)

        after = self._snapshot()
        for key in ('sales', 'ledgers', 'shifts', 'batches', 'tokens'):
            with self.subTest(key=key):
                self.assertEqual(after[key], before[key])
        # The CPMS token is untouched: accepting neither spends nor mints one.
        self.assertEqual(after['token'], (False, None, None))

    def test_one_audit_row_names_the_request_and_the_excluded_line(self):
        self.assertEqual(self._accept({'items': self._mixed()}).status_code, 200)

        rows = self._review_rows(AuditLog.ActionType.REQ_APPROVE)
        self.assertEqual(rows.count(), 1)
        row = rows.get()
        self.assertEqual(row.user, self.manager)
        self.assertIn('accepted by store', row.description)
        self.assertIn(self.requisition.req_number, row.description)
        self.assertIn('Rebar', row.description)
        self.assertIn('Not stocked', row.description)
        self.assertNotIn(str(self.token.token), row.description)
        self.assertNotIn(str(self.rebar_line.pk), row.description)
        self.assertEqual(
            self._review_rows(AuditLog.ActionType.REQ_REJECT).count(), 0)

    def test_accepting_every_line_is_one_row_without_an_exclusion_list(self):
        self.assertEqual(self._accept({'items': self._both_available()}).status_code, 200)

        row = self._review_rows(AuditLog.ActionType.REQ_APPROVE).get()
        self.assertIn('accepted by store', row.description)


class DeclineTests(StoreReviewTestBase):
    """Decision 09/13: a whole Decline answers every line and spends the token."""

    def test_a_decline_answers_every_line_and_spends_the_token(self):
        response = self._decline({'decline_reason': '  Cannot supply this request  '})

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['status'], Requisition.Status.DECLINED)
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        self.assertEqual(requisition.status, Requisition.Status.DECLINED)
        self.assertEqual(requisition.decline_reason, 'Cannot supply this request')
        for line in requisition.items.order_by('pk'):
            with self.subTest(line=line.pk):
                self.assertFalse(line.available)
                self.assertEqual(
                    line.decline_reason, 'Cannot supply this request')

        token = MaterialToken.objects.get(pk=self.token.pk)
        self.assertTrue(token.is_used)
        self.assertIsNotNone(token.used_at)
        self.assertIsNone(token.used_by, 'no cashier handed anything out')

    def test_declining_writes_one_row_and_no_money(self):
        before = self._snapshot()

        self.assertEqual(
            self._decline({'decline_reason': 'Cannot supply'}).status_code, 200)

        after = self._snapshot()
        for key in ('sales', 'ledgers', 'shifts', 'batches', 'tokens'):
            with self.subTest(key=key):
                self.assertEqual(after[key], before[key])
        rows = self._review_rows(AuditLog.ActionType.REQ_REJECT)
        self.assertEqual(rows.count(), 1)
        self.assertIn('declined by store: Cannot supply', rows.get().description)
        self.assertIn(self.requisition.req_number, rows.get().description)
        self.assertNotIn(str(self.token.token), rows.get().description)

    def test_a_missing_blank_or_long_reason_is_refused(self):
        for body in ({}, {'decline_reason': ''}, {'decline_reason': '   '},
                     {'decline_reason': 'x' * 256}):
            with self.subTest(body=body):
                before = self._snapshot()
                response = self._decline(body)
                self.assertEqual(
                    response.status_code, 400, getattr(response, 'data', None))
                self._assert_untouched(before)

    def test_an_extra_field_is_refused(self):
        before = self._snapshot()
        response = self._decline({
            'decline_reason': 'Cannot supply', 'status': Requisition.Status.CLOSED})
        self.assertEqual(response.status_code, 400, response.data)
        self._assert_untouched(before)


class AlreadyReviewedTests(StoreReviewTestBase):
    """Decision 13: only from WAITING; no undo, no second review, no write on refusal."""

    def test_accepting_an_accepted_request_is_409(self):
        self.assertEqual(self._accept({'items': self._mixed()}).status_code, 200)
        before = self._snapshot()

        second = self._accept({'items': self._both_available()})

        self.assertEqual(second.status_code, 409, second.data)
        self.assertEqual(second.data['code'], 'REQUEST_ALREADY_REVIEWED')
        self.assertIn('detail', second.data)
        self._assert_untouched(before)

    def test_declining_a_declined_request_is_409(self):
        self.assertEqual(self._decline({'decline_reason': 'None stocked'}).status_code, 200)
        before = self._snapshot()

        second = self._decline({'decline_reason': 'Changed my mind'})

        self.assertEqual(second.status_code, 409, second.data)
        self.assertEqual(second.data['code'], 'REQUEST_ALREADY_REVIEWED')
        self._assert_untouched(before)

    def test_the_opposite_answer_after_a_decision_is_409(self):
        self.assertEqual(self._accept({'items': self._both_available()}).status_code, 200)
        before = self._snapshot()

        self.assertEqual(self._decline({'decline_reason': 'Too late'}).status_code, 409)
        self._assert_untouched(before)

        self._decline({'decline_reason': 'Too late'})
        self.assertEqual(self._accept({'items': self._mixed()}).status_code, 409)
        self._assert_untouched(before)

    def test_a_closed_request_cannot_be_reviewed(self):
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        requisition.status = Requisition.Status.CLOSED
        requisition.save(update_fields=['status'])
        before = self._snapshot()

        self.assertEqual(self._decline({'decline_reason': 'Gone'}).status_code, 409)
        self.assertEqual(self._accept({'items': self._mixed()}).status_code, 409)
        self._assert_untouched(before)


class ReviewAccessTests(StoreReviewTestBase):
    """Decision 09: Store Manager and Admin answer; nobody else may."""

    def test_the_three_manager_roles_may_accept(self):
        for user, group in (
                (self.manager, 'Store Manager'), (self.admin, 'Admin'),
                (self.sysadmin, 'System Administrator')):
            with self.subTest(role=group):
                request_row = make_waiting_request(
                    self.project, self.cement, self.rebar,
                    req_number=f'REQ-ACC-{group[:4]}', cpms_request_id=f'CPMS-R-{group[:4]}')
                response = self._auth(user.username).post(
                    accept_url(request_row.pk),
                    {'items': [
                        {'id': line.pk, 'available': True, 'decline_reason': ''}
                        for line in request_row.items.order_by('pk')]},
                    format='json')
                self.assertEqual(response.status_code, 200, response.data)
                request_row.refresh_from_db()
                self.assertEqual(request_row.status, Requisition.Status.ACCEPTED)

    def test_the_three_manager_roles_may_decline(self):
        for user, group in (
                (self.manager, 'Store Manager'), (self.admin, 'Admin'),
                (self.sysadmin, 'System Administrator')):
            with self.subTest(role=group):
                request_row = make_waiting_request(
                    self.project, self.cement, self.rebar,
                    req_number=f'REQ-DEC-{group[:4]}', cpms_request_id=f'CPMS-D-{group[:4]}')
                response = self._auth(user.username).post(
                    decline_url(request_row.pk), {'decline_reason': 'Not stocked'},
                    format='json')
                self.assertEqual(response.status_code, 200, response.data)
                request_row.refresh_from_db()
                self.assertEqual(request_row.status, Requisition.Status.DECLINED)

    def test_disallowed_staff_get_403_and_write_nothing(self):
        before = self._snapshot()
        for user, label in (
                (self.cashier, 'Cashier'), (self.stocker, 'Stock Manager'),
                (self.groupless, 'groupless')):
            for url, body in (
                    (accept_url(self.requisition.pk), {'items': self._mixed()}),
                    (decline_url(self.requisition.pk),
                     {'decline_reason': 'Not stocked'})):
                with self.subTest(role=label, url=url):
                    response = self._auth(user.username).post(
                        url, body, format='json')
                    self.assertEqual(response.status_code, 403, response.data)
        self._assert_untouched(before)

    def test_the_cpms_account_is_out_of_scope(self):
        before = self._snapshot()

        for url, body in (
                (accept_url(self.requisition.pk), {'items': self._mixed()}),
                (decline_url(self.requisition.pk), {'decline_reason': 'Not stocked'})):
            with self.subTest(url=url):
                response = self._auth(self.cpms.username).post(
                    url, body, format='json')
                self.assertEqual(response.status_code, 403, response.data)
                self.assertEqual(response.data['code'], 'CPMS_SCOPE')
        self._assert_untouched(before)

    def test_both_actions_need_a_token(self):
        before = self._snapshot()
        for url, body in (
                (accept_url(self.requisition.pk), {'items': self._mixed()}),
                (decline_url(self.requisition.pk), {'decline_reason': 'Not stocked'})):
            with self.subTest(url=url):
                response = APIClient().post(url, body, format='json')
                self.assertEqual(response.status_code, 401, response.data)
        self._assert_untouched(before)


class RouteFenceTests(StoreReviewTestBase):
    """The generic verbs and the retired actions stay exactly as they were."""

    def test_generic_writes_are_still_405(self):
        client = self._auth('manager1')
        url = detail_url(self.requisition.pk)

        self.assertEqual(
            client.post(LIST_URL, {'notes': 'new'}, format='json').status_code, 405)
        for method in ('put', 'patch', 'delete'):
            with self.subTest(method=method):
                response = getattr(client, method)(
                    url, {'notes': 'edited'}, format='json')
                self.assertEqual(response.status_code, 405, response.data)

        requisition = Requisition.objects.get(pk=self.requisition.pk)
        self.assertEqual(requisition.status, Requisition.Status.WAITING)
        self.assertEqual(requisition.notes, '')

    def test_the_retired_actions_are_still_404(self):
        client = self._auth('manager1')
        for action in ('submit', 'approve', 'reject'):
            with self.subTest(action=action):
                response = client.post(f'{detail_url(self.requisition.pk)}{action}/')
                self.assertEqual(response.status_code, 404)


class StoreReviewRaceTests(TransactionTestCase):
    """Two answers to one request cannot both land (one lock order, one decision).

    Accept, Decline and CPMS Close all take the token row lock and then the request row
    lock, so exactly one of the two callers can move a `WAITING` request. Whatever the
    interleaving, the outcome must be ONE decision with ONE audit row.
    """

    def setUp(self):
        self.manager = make_user('race_manager', 'Store Manager')
        self.admin = make_user('race_admin', 'Admin')
        self.cpms = make_user('race_cpms', 'CPMS Service')
        self.project = make_project('CPMS-P-RACE')
        self.cement = make_selling_unit('Cement', '40kg', 'BAG', '280.00')
        self.rebar = make_selling_unit('Rebar', '16mm', 'PC', '150.00')
        self.requisition = make_waiting_request(
            self.project, self.cement, self.rebar,
            req_number='REQ-RACE-0001', cpms_request_id='CPMS-R-RACE')
        self.lines = list(self.requisition.items.order_by('pk'))
        self.token = MaterialToken.objects.get(requisition=self.requisition)
        self.manager_auth = self._bearer(self.manager.username)
        self.admin_auth = self._bearer(self.admin.username)
        self.cpms_auth = self._bearer(self.cpms.username)

    def _bearer(self, username):
        client = APIClient()
        login = client.post(
            LOGIN_URL, {'username': username, 'password': PASSWORD}, format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return f'Bearer {login.data["access"]}'

    def _both_available(self):
        return [
            {'id': line.pk, 'available': True, 'decline_reason': ''}
            for line in self.lines]

    def _race(self, calls):
        """Run `(name, url, body, bearer)` calls at the same instant, collect answers."""
        barrier = threading.Barrier(len(calls), timeout=20)
        results = {}
        lock = threading.Lock()

        def worker(name, url, body, bearer):
            client = APIClient()
            try:
                barrier.wait()
                response = client.post(
                    url, body, format='json', HTTP_AUTHORIZATION=bearer)
                with lock:
                    results[name] = (
                        response.status_code, getattr(response, 'data', None))
            finally:
                # Each thread owns its own connection; leaving it open hangs the
                # truncation this TransactionTestCase does when it finishes.
                connections.close_all()

        threads = [threading.Thread(target=worker, args=call) for call in calls]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(set(results), {call[0] for call in calls}, results)
        return results

    def _review_rows(self, action_type):
        return AuditLog.objects.filter(action_type=action_type)

    def test_two_accepts_produce_one_decision(self):
        results = self._race([
            ('first', accept_url(self.requisition.pk),
             {'items': self._both_available()}, self.manager_auth),
            ('second', accept_url(self.requisition.pk),
             {'items': self._both_available()}, self.admin_auth),
        ])

        statuses = sorted(status for status, _ in results.values())
        self.assertEqual(statuses, [200, 409], results)
        refusal = next(body for status, body in results.values() if status == 409)
        self.assertEqual(refusal['code'], 'REQUEST_ALREADY_REVIEWED')

        requisition = Requisition.objects.get(pk=self.requisition.pk)
        self.assertEqual(requisition.status, Requisition.Status.ACCEPTED)
        self.assertEqual(
            self._review_rows(AuditLog.ActionType.REQ_APPROVE).count(), 1)
        self.assertEqual(
            self._review_rows(AuditLog.ActionType.REQ_REJECT).count(), 0)
        self.assertFalse(MaterialToken.objects.get(pk=self.token.pk).is_used)
        for line in requisition.items.order_by('pk'):
            with self.subTest(line=line.pk):
                self.assertTrue(line.available)

    def test_an_accept_racing_a_decline_makes_one_decision(self):
        results = self._race([
            ('accept', accept_url(self.requisition.pk),
             {'items': self._both_available()}, self.manager_auth),
            ('decline', decline_url(self.requisition.pk),
             {'decline_reason': 'Cannot supply'}, self.admin_auth),
        ])

        self.assertEqual(
            sorted(status for status, _ in results.values()), [200, 409], results)
        accept_status = results['accept'][0]
        decline_status = results['decline'][0]
        self.assertNotEqual(accept_status, decline_status)

        requisition = Requisition.objects.get(pk=self.requisition.pk)
        token = MaterialToken.objects.get(pk=self.token.pk)
        if accept_status == 200:
            self.assertEqual(requisition.status, Requisition.Status.ACCEPTED)
            self.assertEqual(requisition.decline_reason, '')
            self.assertFalse(token.is_used)
            self.assertEqual(
                self._review_rows(AuditLog.ActionType.REQ_APPROVE).count(), 1)
            self.assertEqual(
                self._review_rows(AuditLog.ActionType.REQ_REJECT).count(), 0)
        else:
            self.assertEqual(requisition.status, Requisition.Status.DECLINED)
            self.assertEqual(requisition.decline_reason, 'Cannot supply')
            self.assertTrue(token.is_used)
            self.assertIsNone(token.used_by)
            self.assertEqual(
                self._review_rows(AuditLog.ActionType.REQ_APPROVE).count(), 0)
            self.assertEqual(
                self._review_rows(AuditLog.ActionType.REQ_REJECT).count(), 1)
        for line in requisition.items.order_by('pk'):
            with self.subTest(line=line.pk):
                self.assertIsNotNone(line.available)

    def test_an_accept_racing_a_cpms_close_cannot_answer_a_closed_request(self):
        results = self._race([
            ('accept', accept_url(self.requisition.pk),
             {'items': self._both_available()}, self.manager_auth),
            ('close', close_url('CPMS-R-RACE'), {}, self.cpms_auth),
        ])

        self.assertEqual(results['close'][0], 200, results['close'])
        accept_status, accept_body = results['accept']
        self.assertIn(accept_status, (200, 409), accept_body)

        requisition = Requisition.objects.get(pk=self.requisition.pk)
        token = MaterialToken.objects.get(pk=self.token.pk)
        # WAITING and ACCEPTED both close; a closed request is never reviewed.
        self.assertEqual(requisition.status, Requisition.Status.CLOSED)
        self.assertTrue(token.is_used)
        self.assertIsNone(token.used_by)
        approval_rows = self._review_rows(
            AuditLog.ActionType.REQ_APPROVE).count()
        if accept_status == 200:
            self.assertEqual(approval_rows, 1)
            for line in requisition.items.order_by('pk'):
                with self.subTest(line=line.pk):
                    self.assertTrue(line.available)
        else:
            self.assertEqual(accept_body['code'], 'REQUEST_ALREADY_REVIEWED')
            self.assertEqual(approval_rows, 0)
            for line in requisition.items.order_by('pk'):
                with self.subTest(line=line.pk):
                    self.assertIsNone(
                        line.available, 'a refused accept must not answer a line')
        self.assertEqual(SalesTransaction.objects.count(), 0)
