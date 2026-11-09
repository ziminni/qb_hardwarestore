#!/usr/bin/env python
# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/integration/tests.py: this checker
# runs with a working directory outside the repo, so no pyrightconfig.json is found and
# every `Model.objects` access and `self.client.get(...).status_code` is a false positive
# on valid Django. Django's own `manage.py check` and the test run remain the authority.
"""CPMS boundary tests (Phase 1, Task 3): the material list and the request import.

The fixtures here are the whole contract in one place — one sellable material, one
contractor payer — so each rule of decisions 02 and 04 reads as one test.

The import is RETRY-SAFE by decision 02: the same `cpms_request_id` twice is one copy,
untouched, and the answer says `200` instead of `201`. That is why several tests below
assert "nothing changed" rather than "the second call failed".
"""

import uuid
from contextlib import contextmanager
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.db import IntegrityError

from apps.inventory.models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)
from apps.requisitions import services
from apps.requisitions.models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)
from apps.users.models import AuditLog

from .tests import CPMS_LOGIN, CPMS_URL, CpmsTestCase, make_user

User = get_user_model()

MATERIALS_URL = f'{CPMS_URL}materials/'
REQUESTS_URL = f'{CPMS_URL}requests/'
VERIFY_URL = '/api/v1/tokens/verify/'


class MaterialFixtureMixin:
    """One sellable material (`self.code`) plus one archived unit and one archived product."""

    def make_material(self, product, variant_name, code, uom_code='BAG'):
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=uom_code, defaults={'name': uom_code.title()})
        variant = ProductVariant.objects.create(
            product=product, variant_name=variant_name, base_uom=uom)
        return VariantUOM.objects.create(
            variant=variant, uom=uom, barcode_qr=code,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(280),
        )

    def setUp(self):
        super().setUp()
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        self.product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.vuom = self.make_material(self.product, '40kg', 'QB000001-0')
        self.code = self.vuom.barcode_qr
        # An archived product and an archived variant: the list is "what CPMS may order",
        # so neither of these may appear and neither code may be ordered.
        gone_product = Product.objects.create(
            category=category, brand=brand, base_name='Discontinued Cement',
            is_active=False)
        self.gone_product_unit = self.make_material(
            gone_product, '50kg', 'QB000002-8')
        self.gone_variant_unit = self.make_material(
            self.product, '25kg', 'QB000003-6')
        self.gone_variant_unit.variant.is_active = False
        self.gone_variant_unit.variant.save(update_fields=['is_active'])


class CpmsMaterialListTests(MaterialFixtureMixin, CpmsTestCase):
    def get_rows(self):
        res = self.client.get(MATERIALS_URL, HTTP_AUTHORIZATION=self.cpms_auth())
        self.assertEqual(res.status_code, 200, res.content)
        return res.json()['results']

    def test_lists_the_active_selling_units(self):
        self.assertEqual(self.get_rows(), [{
            'code': 'QB000001-0',
            'product': 'Portland Cement 40kg',
            'unit': 'BAG',
        }])

    def test_an_archived_product_is_hidden(self):
        codes = [row['code'] for row in self.get_rows()]
        self.assertNotIn('QB000002-8', codes)

    def test_an_archived_variant_is_hidden(self):
        codes = [row['code'] for row in self.get_rows()]
        self.assertNotIn('QB000003-6', codes)

    def test_a_row_leaks_no_stock_price_cost_or_id(self):
        for row in self.get_rows():
            self.assertEqual(set(row), {'code', 'product', 'unit'})

    def test_the_list_is_paginated_like_the_customer_list(self):
        res = self.client.get(MATERIALS_URL, HTTP_AUTHORIZATION=self.cpms_auth())
        body = res.json()
        self.assertEqual(set(body), {'count', 'next', 'previous', 'results'})
        self.assertEqual(body['count'], 1)

    def test_the_material_list_requires_a_token(self):
        self.assertEqual(self.client.get(MATERIALS_URL).status_code, 401)

    def test_staff_roles_are_refused(self):
        for role in ('Cashier', 'Stock Manager', 'Store Manager', 'Admin'):
            with self.subTest(role=role):
                auth = self.login(make_user(f'm_{role[:4]}', role).username)
                res = self.client.get(MATERIALS_URL, HTTP_AUTHORIZATION=auth)
                self.assertEqual(res.status_code, 403, res.content)


class ImportTestBase(MaterialFixtureMixin, CpmsTestCase):
    """The one payload every import test starts from."""

    def setUp(self):
        super().setUp()
        self.cashier = make_user('cashier_import', 'Cashier')
        self.token = uuid.uuid4()
        # Signed in ONCE: every push below reuses this token, so the trail's only LOGIN
        # row is this one and the audit assertions count what the import wrote.
        self.auth = self.cpms_auth()

    def payload(self, **overrides):
        body = {
            'cpms_request_id': 'CPMS-REQ-0001',
            'token': str(self.token),
            'project': {
                'cpms_project_id': 'CPMS-PRJ-0001',
                'name': 'House Build',
                'payer': self.contractor.id,
            },
            'requester_name': 'Fore Man',
            'approver_name': 'Mana Ger',
            'notes': 'Deliver to site gate',
            'items': [{'code': self.code, 'quantity': '10'}],
        }
        body.update(overrides)
        return body

    def push(self, **overrides):
        return self.client.post(
            REQUESTS_URL, self.payload(**overrides), content_type='application/json',
            HTTP_AUTHORIZATION=self.auth)

    def counts(self):
        return (
            Project.objects.count(), Requisition.objects.count(),
            RequisitionItem.objects.count(), MaterialToken.objects.count(),
        )

    def import_rows(self):
        """Every REQUISITION audit row the import wrote (LOGIN rows are the fixture's)."""
        return AuditLog.objects.filter(
            action_type=AuditLog.ActionType.REQ_APPROVE)


class ImportHappyPathTests(ImportTestBase):
    def test_a_new_push_answers_201_with_the_stored_copy(self):
        res = self.push()
        self.assertEqual(res.status_code, 201, res.content)
        body = res.json()
        self.assertEqual(set(body), {'id', 'req_number', 'cpms_request_id', 'status',
                                     'items'})
        self.assertEqual(body['cpms_request_id'], 'CPMS-REQ-0001')
        self.assertEqual(body['status'], Requisition.Status.WAITING)
        self.assertEqual(body['items'], [{'code': self.code, 'quantity': '10.00'}])
        req = Requisition.objects.get(pk=body['id'])
        self.assertEqual(body['req_number'], req.req_number)
        self.assertTrue(req.req_number.startswith('REQ-'), req.req_number)

    def test_the_copy_names_the_people_and_the_project(self):
        self.assertEqual(self.push().status_code, 201)
        req = Requisition.objects.get()
        self.assertEqual(req.requester_name, 'Fore Man')
        self.assertEqual(req.approver_name, 'Mana Ger')
        self.assertEqual(req.notes, 'Deliver to site gate')
        self.assertEqual(req.project.name, 'House Build')
        self.assertEqual(req.project.cpms_project_id, 'CPMS-PRJ-0001')
        self.assertEqual(req.project.customer, self.contractor)
        # Site foremen are names now (decision 08), never POS accounts.
        self.assertFalse(User.objects.filter(full_name='Fore Man').exists())

    def test_the_token_is_stored_unused_with_the_lines(self):
        body = self.push().json()
        token = MaterialToken.objects.get(requisition_id=body['id'])
        self.assertEqual(token.token, self.token)
        self.assertFalse(token.is_used)
        item = RequisitionItem.objects.get(requisition_id=body['id'])
        self.assertEqual(item.variant_uom, self.vuom)
        self.assertEqual(item.quantity, Decimal(10))
        self.assertEqual(item.released_qty, Decimal(0))

    def test_the_imported_token_verifies_at_the_cashier_endpoint(self):
        body = self.push().json()
        # Phase 1b (decision 13): a push waits for the store, so the token only works
        # once the store has accepted the lines — through the real service.
        services.accept_requisition(
            requisition_id=body['id'],
            items=[{'id': line.pk, 'available': True, 'decline_reason': ''}
                   for line in RequisitionItem.objects.filter(
                       requisition_id=body['id']).order_by('pk')])
        auth = self.login(self.cashier.username, password=CPMS_LOGIN)
        res = self.client.post(
            VERIFY_URL, {'token': str(self.token)}, content_type='application/json',
            HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 200, res.content)
        info = res.json()
        self.assertEqual(info['requisition']['req_number'], body['req_number'])
        self.assertEqual(info['items'][0]['remaining'], '10.00')

    def test_a_lower_case_padded_code_is_the_same_material(self):
        res = self.push(items=[{'code': f'  {self.code.lower()} ', 'quantity': '2'}])
        self.assertEqual(res.status_code, 201, res.content)
        self.assertEqual(res.json()['items'], [{'code': self.code, 'quantity': '2.00'}])


class ImportRetryTests(ImportTestBase):
    def test_the_same_request_id_again_answers_200_with_the_unchanged_copy(self):
        first = self.push().json()
        before = self.counts()
        res = self.push(
            items=[{'code': self.code, 'quantity': '999'}],
            project={'cpms_project_id': 'CPMS-PRJ-0001',
                     'name': 'Somewhere Else', 'payer': self.firm.id},
            requester_name='Other Name', notes='second try')
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json(), first)
        self.assertEqual(self.counts(), before)
        req = Requisition.objects.get()
        self.assertEqual(req.notes, 'Deliver to site gate')
        self.assertEqual(req.requester_name, 'Fore Man')
        self.assertEqual(req.project.name, 'House Build')
        self.assertEqual(req.items.get().quantity, Decimal(10))

    def test_a_retry_writes_no_audit_row(self):
        self.push()
        rows = self.import_rows().count()
        self.push()
        self.assertEqual(self.import_rows().count(), rows)

    def test_two_racing_identical_pushes_make_one_row(self):
        # The losing push is simulated by blinding the retry SHORTCUT for its FIRST read
        # only: the winner's row is already there, so the retry check misses it and the
        # service must still answer 200 with the winner rather than 409 or 500.
        winner = self.push().json()
        before = self.counts()
        existing = Requisition.objects.get(pk=winner['id'])
        reads = []

        def blind_once(*args, **kwargs):
            reads.append(args)
            return None if len(reads) == 1 else existing

        with mock.patch.object(services, '_existing_requisition', blind_once):
            res = self.push(items=[{'code': self.code, 'quantity': '3'}])
        self.assertGreater(len(reads), 1, 'the race was not exercised')
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json(), winner)
        self.assertEqual(self.counts(), before)


@contextmanager
def blind_import_reads(misses=1):
    """Make both of the import's READ guards miss, so the WRITE is what refuses.

    That is the case `except IntegrityError` exists for: at the instant the loser reads,
    the winner's row is not visible yet, so neither the retry lookup nor the token
    collision can stop it — only the unique constraints can. Yields the two read logs;
    `misses` reads per guard are blinded, every later read (the branch's own recovery
    lookups) is real.
    """
    real_lookup = services._existing_requisition
    real_filter = MaterialToken.objects.filter
    lookups, token_reads = [], []

    def blind_lookup(*args, **kwargs):
        lookups.append(args)
        return None if len(lookups) <= misses else real_lookup(*args, **kwargs)

    def blind_token_filter(*args, **kwargs):
        query = real_filter(*args, **kwargs)
        token_reads.append(args)
        # Same shape, no rows: the winner's token is not visible at this instant.
        return query.none() if len(token_reads) <= misses else query

    with (
        mock.patch.object(services, '_existing_requisition', blind_lookup),
        mock.patch.object(MaterialToken.objects, 'filter', blind_token_filter),
    ):
        yield lookups, token_reads


class ImportInsertRaceTests(ImportTestBase):
    """The loser of a race where the READ guards miss and the WRITE meets a constraint.

    `ImportRetryTests.test_two_racing_identical_pushes_make_one_row` stops at the pre-token
    re-read; these start where that one ends, so every arm of `import_request`'s
    `except IntegrityError` is executed.
    """

    def test_an_identical_loser_meets_the_constraint_and_answers_the_winner(self):
        winner = self.push().json()
        before = self.counts()
        with blind_import_reads() as (lookups, token_reads):
            res = self.push(items=[{'code': self.code, 'quantity': '3'}])
        self.assertEqual(len(lookups), 2, 'pre-check, then the recovery read')
        self.assertEqual(len(token_reads), 1, token_reads)
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json(), winner)
        self.assertEqual(self.counts(), before)

    def test_a_loser_holding_a_taken_token_is_409_and_rolls_its_writes_back(self):
        self.assertEqual(self.push().status_code, 201)
        before = self.counts()
        with blind_import_reads() as (lookups, token_reads):
            # Different request id, so the row it would write is new; the project fields
            # below do change, and the token insert is what refuses them.
            res = self.push(
                cpms_request_id='CPMS-REQ-0002',
                project={'cpms_project_id': 'CPMS-PRJ-0001',
                         'name': 'House Build (loser)', 'payer': self.firm.id})
        self.assertEqual(len(lookups), 2, 'pre-check, then the recovery read')
        self.assertEqual(len(token_reads), 2, 'pre-check, then the recovery read')
        self.assertEqual(res.status_code, 409, res.content)
        self.assertEqual(res.json()['code'], 'TOKEN_TAKEN')
        self.assertEqual(self.counts(), before)
        project = Project.objects.get()
        self.assertEqual(project.name, 'House Build')
        self.assertEqual(project.customer, self.contractor)

    def test_an_unrelated_integrity_error_is_not_answered_as_a_retry(self):
        # No winner and no token holder, so nothing explains the constraint and the
        # error has to reach the caller instead of becoming a 200 or a 409.
        with (
            mock.patch.object(services, '_upsert_project',
                              side_effect=IntegrityError('unrelated constraint')),
            self.assertRaises(IntegrityError),
        ):
            self.push()
        self.assertEqual(self.counts(), (0, 0, 0, 0))


class ImportRefusalTests(ImportTestBase):
    def assert_nothing_written(self):
        self.assertEqual(self.counts(), (0, 0, 0, 0))

    def test_an_unknown_code_is_named(self):
        res = self.push(items=[{'code': 'NOPE-1', 'quantity': '1'}])
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()['code'], 'UNKNOWN_MATERIAL')
        self.assertIn('NOPE-1', res.json()['detail'])
        self.assert_nothing_written()

    def test_an_archived_material_is_unknown(self):
        for code in ('QB000002-8', 'QB000003-6'):
            with self.subTest(code=code):
                res = self.push(items=[{'code': code, 'quantity': '1'}])
                self.assertEqual(res.status_code, 400, res.content)
                self.assertEqual(res.json()['code'], 'UNKNOWN_MATERIAL')
        self.assert_nothing_written()

    def test_every_unknown_code_is_named_at_once(self):
        res = self.push(items=[{'code': 'NOPE-1', 'quantity': '1'},
                               {'code': 'NOPE-2', 'quantity': '1'}])
        self.assertEqual(res.json()['code'], 'UNKNOWN_MATERIAL')
        self.assertIn('NOPE-1', res.json()['detail'])
        self.assertIn('NOPE-2', res.json()['detail'])

    def test_the_same_code_twice_in_one_request_is_refused(self):
        res = self.push(items=[{'code': self.code, 'quantity': '1'},
                               {'code': self.code.lower(), 'quantity': '2'}])
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()['code'], 'DUPLICATE_MATERIAL')
        self.assert_nothing_written()

    def test_an_unknown_payer_is_refused(self):
        res = self.push(project={'cpms_project_id': 'CPMS-PRJ-0001',
                                 'name': 'House Build', 'payer': 999999})
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()['code'], 'UNKNOWN_PAYER')
        self.assert_nothing_written()

    def test_a_non_contractor_payer_is_refused(self):
        for customer in (self.walk_in, self.regular, self.gone_contractor):
            with self.subTest(payer=customer.name):
                res = self.push(project={'cpms_project_id': 'CPMS-PRJ-0001',
                                         'name': 'House Build', 'payer': customer.id})
                self.assertEqual(res.status_code, 400, res.content)
                self.assertEqual(res.json()['code'], 'UNKNOWN_PAYER')
        self.assert_nothing_written()

    def test_a_token_already_held_by_another_request_is_409(self):
        self.assertEqual(self.push().status_code, 201)
        res = self.push(cpms_request_id='CPMS-REQ-0002')
        self.assertEqual(res.status_code, 409, res.content)
        self.assertEqual(res.json()['code'], 'TOKEN_TAKEN')
        self.assertEqual(Requisition.objects.count(), 1)

    def test_a_token_held_by_a_pos_side_requisition_is_409(self):
        # A row the POS already holds (a legacy approval) owns the token.
        project = Project.objects.create(name='Legacy Job', customer=self.contractor)
        legacy = Requisition.objects.create(project=project, req_number='REQ-LEGACY-1')
        MaterialToken.objects.create(requisition=legacy, token=self.token)
        res = self.push()
        self.assertEqual(res.status_code, 409, res.content)
        self.assertEqual(res.json()['code'], 'TOKEN_TAKEN')
        self.assertEqual(Requisition.objects.count(), 1)

    def test_a_bad_token_uuid_is_a_400(self):
        not_a_uuid = 'not-a-uuid'
        res = self.push(token=not_a_uuid)
        self.assertEqual(res.status_code, 400, res.content)
        self.assert_nothing_written()

    def test_no_items_is_a_400(self):
        self.assertEqual(self.push(items=[]).status_code, 400)
        self.assert_nothing_written()

    def test_a_zero_or_negative_quantity_is_a_400(self):
        for quantity in ('0', '-3', '0.00'):
            with self.subTest(quantity=quantity):
                res = self.push(items=[{'code': self.code, 'quantity': quantity}])
                self.assertEqual(res.status_code, 400, res.content)
        self.assert_nothing_written()

    def test_more_than_two_decimals_is_a_400(self):
        res = self.push(items=[{'code': self.code, 'quantity': '1.005'}])
        self.assertEqual(res.status_code, 400, res.content)
        self.assert_nothing_written()

    def test_a_missing_required_key_is_a_400(self):
        body = self.payload()
        del body['approver_name']
        res = self.client.post(
            REQUESTS_URL, body, content_type='application/json',
            HTTP_AUTHORIZATION=self.auth)
        self.assertEqual(res.status_code, 400, res.content)
        self.assert_nothing_written()


class ImportProjectTests(ImportTestBase):
    def test_a_second_push_to_the_same_cpms_project_updates_that_row(self):
        self.assertEqual(self.push().status_code, 201)
        res = self.push(
            cpms_request_id='CPMS-REQ-0002', token=str(uuid.uuid4()),
            project={'cpms_project_id': 'CPMS-PRJ-0001',
                     'name': 'House Build (Phase 2)', 'payer': self.firm.id})
        self.assertEqual(res.status_code, 201, res.content)
        project = Project.objects.get()
        self.assertEqual(project.name, 'House Build (Phase 2)')
        self.assertEqual(project.customer, self.firm)
        self.assertEqual(Requisition.objects.count(), 2)

    def test_a_different_cpms_project_makes_a_new_row(self):
        self.push()
        self.push(cpms_request_id='CPMS-REQ-0002', token=str(uuid.uuid4()),
                  project={'cpms_project_id': 'CPMS-PRJ-0002',
                           'name': 'Warehouse', 'payer': self.contractor.id})
        self.assertEqual(Project.objects.count(), 2)

    def test_the_payer_swaps_without_touching_earlier_requests(self):
        self.push()
        self.push(cpms_request_id='CPMS-REQ-0002', token=str(uuid.uuid4()),
                  project={'cpms_project_id': 'CPMS-PRJ-0001',
                           'name': 'House Build', 'payer': self.firm.id})
        # The project's payer moves; the copy each request made keeps its own lines.
        self.assertEqual(
            Requisition.objects.filter(project__customer=self.firm).count(), 2)


class ImportAuditTests(ImportTestBase):
    def test_one_audit_row_names_the_request_and_the_cpms_id(self):
        body = self.push().json()
        rows = self.import_rows()
        self.assertEqual(rows.count(), 1)
        row = rows.get()
        self.assertEqual(row.user, self.cpms)
        self.assertIn(body['req_number'], row.description)
        self.assertIn('CPMS-REQ-0001', row.description)

    def test_the_audit_row_never_carries_the_token(self):
        self.push()
        self.assertNotIn(str(self.token), self.import_rows().get().description)

    def test_a_refused_push_writes_no_audit_row(self):
        self.push(items=[{'code': 'NOPE-1', 'quantity': '1'}])
        self.assertEqual(self.import_rows().count(), 0)


class ImportAccessTests(ImportTestBase):
    def test_staff_roles_cannot_push(self):
        for role in ('Cashier', 'Stock Manager', 'Store Manager', 'Admin'):
            with self.subTest(role=role):
                auth = self.login(make_user(f'p_{role[:4]}', role).username)
                res = self.client.post(
                    REQUESTS_URL, self.payload(), content_type='application/json',
                    HTTP_AUTHORIZATION=auth)
                self.assertEqual(res.status_code, 403, res.content)
        self.assertEqual(Requisition.objects.count(), 0)

    def test_an_anonymous_push_is_401(self):
        res = self.client.post(
            REQUESTS_URL, self.payload(), content_type='application/json')
        self.assertEqual(res.status_code, 401, res.content)

    def test_a_deactivated_cpms_account_cannot_push(self):
        auth = self.cpms_auth()
        self.cpms.is_active = False
        self.cpms.save()
        res = self.client.post(
            REQUESTS_URL, self.payload(), content_type='application/json',
            HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 401, res.content)
        self.assertEqual(Requisition.objects.count(), 0)
