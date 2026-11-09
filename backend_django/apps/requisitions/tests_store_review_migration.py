# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directives and reason as apps/requisitions/tests_migration.py: this checker runs
# without django-stubs, so `project_state(...).apps` resolves to a plain `cached_property`
# and `transaction.atomic()` is not seen as a context manager. The test run is authority.
"""Phase 1b Task 1 — the store-review schema, run the way production will run it.

Decision 13 renames the stored request state `APPROVED` to `ACCEPTED` (the store, not
CPMS, now makes that call) and adds the store's per-line answer; decision 14 adds a
released-amount accumulator whose historical value is UNKNOWN, never zero. Both decisions
only hold up if existing rows survive the migration, so these tests build the 0002 schema,
seed it with Phase 1 shapes, migrate forward and look at what is left: renamed or kept
status, line intent, and a released amount that stays null wherever money has already
left the store.
"""

from decimal import Decimal
from typing import Any

from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string

# The app this task rewrites. Every other app stays at its leaf, because
# `migrate()` unapplies anything NOT named in its target list.
TOUCHED_APP = 'requisitions'
OLD_LEAF = '0002_selling_unit_and_cpms_ids'

# Every stored status a Phase 1 database can hold, with the release history that decides
# what the migration must do to it. `released` is the line's `released_qty`.
SEEDED_REQUESTS = {
    'APPROVED': Decimal('0'),
    'PARTIAL': Decimal('4'),
    'RELEASED': Decimal('4'),
    'CLOSED': Decimal('0'),
    'CANCELLED': Decimal('0'),
    'DRAFT': Decimal('0'),
}


class _MigrationBase(TransactionTestCase):
    """Runs against a database moved back to the pre-store-review schema."""

    def _migrate(self, targets):
        executor = MigrationExecutor(connection)
        executor.loader.build_graph()
        executor.migrate(targets)
        return executor

    def _latest_targets(self):
        executor = MigrationExecutor(connection)
        return executor.loader.graph.leaf_nodes()

    def _old_targets(self):
        """Every app at its leaf, except the one this task rewrites."""
        return [
            (app, name) for app, name in self._latest_targets()
            if app != TOUCHED_APP
        ] + [(TOUCHED_APP, OLD_LEAF)]

    def _state_apps(self, executor, targets) -> Any:
        # `Any`: a historical app registry is built at runtime, so a checker without
        # django-stubs sees `project_state(...).apps` as a bare `cached_property`.
        return executor.loader.project_state(targets).apps


class StoreReviewMigrationTests(_MigrationBase):
    def setUp(self):
        self.old_targets = self._old_targets()
        self.executor = self._migrate(self.old_targets)
        old = self._state_apps(self.executor, self.old_targets)
        self._seed(old)

    def tearDown(self):
        # Leave the shared test database at head even when an assertion failed, or every
        # test after this one runs against the 0002 schema.
        self._migrate(self._latest_targets())

    def _seed(self, old):
        User = old.get_model('apps_users', 'User')
        Category = old.get_model('inventory', 'Category')
        Brand = old.get_model('inventory', 'Brand')
        UnitOfMeasure = old.get_model('inventory', 'UnitOfMeasure')
        Product = old.get_model('inventory', 'Product')
        ProductVariant = old.get_model('inventory', 'ProductVariant')
        VariantUOM = old.get_model('inventory', 'VariantUOM')
        Customer = old.get_model('pos', 'Customer')
        Project_ = old.get_model('requisitions', 'Project')
        Requisition_ = old.get_model('requisitions', 'Requisition')
        RequisitionItem_ = old.get_model('requisitions', 'RequisitionItem')
        MaterialToken_ = old.get_model('requisitions', 'MaterialToken')

        self.manager = User.objects.create(
            username='manager', email='m@x.com', full_name='Man Ager',
            password=get_random_string(20))

        customer = Customer.objects.create(name='Dela Cruz Construction')
        self.project = Project_.objects.create(
            name='House Build', customer=customer, cpms_project_id='CPMS-P-1')
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        bag = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=bag)
        self.vuom = VariantUOM.objects.create(
            variant=variant, uom=bag, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'))

        self.requisition_pks = {}
        self.item_pks = {}
        self.token_pks = {}
        for status, released in SEEDED_REQUESTS.items():
            requisition = Requisition_.objects.create(
                req_number=f'REQ-REVIEW-{status}',
                project=self.project,
                cpms_request_id=f'CPMS-REVIEW-{status}',
                requester_name='Rey Quester',
                approver_name='Man Ager',
                status=status,
            )
            item = RequisitionItem_.objects.create(
                requisition=requisition, variant_uom=self.vuom,
                quantity=Decimal('10'), released_qty=released)
            token = MaterialToken_.objects.create(
                requisition=requisition,
                is_used=status in ('RELEASED', 'CLOSED'))
            self.requisition_pks[status] = requisition.pk
            self.item_pks[status] = item.pk
            self.token_pks[status] = token.pk

        # One unchanged extra line, so "the migration left the quantities alone" is not
        # only measured on released rows.
        self.untouched_line_pk = RequisitionItem_.objects.create(
            requisition=Requisition_.objects.get(pk=self.requisition_pks['APPROVED']),
            variant_uom=self.vuom, quantity=Decimal('7')).pk
        self.token_values = {
            status: str(MaterialToken_.objects.get(pk=pk).token)
            for status, pk in self.token_pks.items()
        }

    def _migrate_forward(self):
        targets = self._latest_targets()
        executor = self._migrate(targets)
        return self._state_apps(executor, targets)

    def _requisition(self, new, status):
        Requisition_ = new.get_model('requisitions', 'Requisition')
        return Requisition_.objects.get(pk=self.requisition_pks[status])

    def test_approved_becomes_accepted_and_every_other_status_is_preserved(self):
        new = self._migrate_forward()

        by_status = {
            stored: self._requisition(new, stored).status
            for stored in SEEDED_REQUESTS
        }
        self.assertEqual(by_status['APPROVED'], 'ACCEPTED')
        for status in ('PARTIAL', 'RELEASED', 'CLOSED', 'CANCELLED', 'DRAFT'):
            self.assertEqual(by_status[status], status)

    def test_the_new_states_are_declared_and_approved_is_gone(self):
        new = self._migrate_forward()
        Requisition_ = new.get_model('requisitions', 'Requisition')

        status_field = Requisition_._meta.get_field('status')
        choices = [value for value, _ in status_field.choices]
        self.assertEqual(status_field.default, 'WAITING')
        for state in ('WAITING', 'ACCEPTED', 'DECLINED'):
            self.assertIn(state, choices)
        self.assertNotIn('APPROVED', choices)
        # A retyped decision is read, never rewritten (decision 13, legacy rows).
        for legacy in ('DRAFT', 'SUBMITTED', 'REJECTED', 'CANCELLED'):
            self.assertIn(legacy, choices)

        released_amount = Requisition_._meta.get_field('released_amount')
        self.assertTrue(released_amount.null)
        self.assertEqual(released_amount.max_digits, 20)
        self.assertEqual(released_amount.decimal_places, 2)
        decline_reason = Requisition_._meta.get_field('decline_reason')
        self.assertEqual(decline_reason.max_length, 255)
        self.assertEqual(decline_reason.default, '')

        RequisitionItem_ = new.get_model('requisitions', 'RequisitionItem')
        available = RequisitionItem_._meta.get_field('available')
        self.assertTrue(available.null)
        self.assertIsNone(available.default)
        self.assertEqual(
            RequisitionItem_._meta.get_field('decline_reason').max_length, 255)

    def test_lines_of_a_request_the_store_can_serve_are_available(self):
        new = self._migrate_forward()
        RequisitionItem_ = new.get_model('requisitions', 'RequisitionItem')

        def available(status):
            item = RequisitionItem_.objects.get(pk=self.item_pks[status])
            return item.available

        # Decision 13: these states could already leave the store, so their lines stay
        # releasable instead of turning into "waiting for a review that never happened".
        for status in ('APPROVED', 'PARTIAL', 'RELEASED', 'CLOSED'):
            self.assertIs(available(status), True, status)
        # The store never answered for these, and inventing "available" would let a
        # cancelled line release.
        for status in ('CANCELLED', 'DRAFT'):
            self.assertIsNone(available(status), status)

    def test_a_request_with_released_quantities_has_an_unknown_amount(self):
        new = self._migrate_forward()

        # Decision 14: no sale row names its requisition, so the historical total is
        # unknown. Defaulting it to 0.00 would report "nothing owed" for goods that left.
        for status in ('PARTIAL', 'RELEASED'):
            self.assertIsNone(
                self._requisition(new, status).released_amount, status)
        for status in ('APPROVED', 'CLOSED', 'CANCELLED', 'DRAFT'):
            self.assertEqual(
                self._requisition(new, status).released_amount,
                Decimal('0.00'), status)

    def test_quantities_and_token_credentials_are_untouched(self):
        new = self._migrate_forward()
        RequisitionItem_ = new.get_model('requisitions', 'RequisitionItem')
        MaterialToken_ = new.get_model('requisitions', 'MaterialToken')

        for status, pk in self.item_pks.items():
            item = RequisitionItem_.objects.get(pk=pk)
            self.assertEqual(item.quantity, Decimal('10'), status)
            self.assertEqual(item.released_qty, SEEDED_REQUESTS[status], status)
            # Only the store's answer is empty; the request-level reason too.
            self.assertEqual(item.decline_reason, '', status)
        untouched = RequisitionItem_.objects.get(pk=self.untouched_line_pk)
        self.assertEqual(untouched.quantity, Decimal('7'))
        self.assertEqual(untouched.released_qty, Decimal('0'))

        for status, pk in self.token_pks.items():
            token = MaterialToken_.objects.get(pk=pk)
            # A bearer credential: migrating must not re-mint or spend it.
            self.assertEqual(str(token.token), self.token_values[status], status)
            self.assertEqual(
                token.is_used, status in ('RELEASED', 'CLOSED'), status)

        for status in SEEDED_REQUESTS:
            self.assertEqual(
                self._requisition(new, status).decline_reason, '', status)
