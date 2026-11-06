# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directives and reason as apps/requisitions/services.py: this checker runs without
# django-stubs, so `project_state(...).apps` resolves to a plain `cached_property` and
# `transaction.atomic()` is not seen as a context manager. The test run is the authority.
"""Task 1 — the data migration that turns today's foreman rows into CPMS-shaped rows.

Decision 08 moves the two user FKs on `Requisition` into plain text names and repoints
every line from a `ProductVariant` at the selling unit (`VariantUOM`) CPMS will quote.
That is only safe if the existing rows survive it, so the migration is exercised the way
production will run it: build the OLD schema, seed it with today's shapes, migrate
forward, then look at what is left.
"""

from decimal import Decimal
from typing import Any

from django.db import IntegrityError, connection, transaction
from django.db.migrations.executor import MigrationExecutor
from django.test import TestCase, TransactionTestCase
from django.utils.crypto import get_random_string

from apps.pos.models import Customer

from .models import Project, Requisition

# The two apps this task touches, at their pre-decision-08 shapes. Every other app stays
# where it is: `migrate()` unapplies anything NOT named in its target list, so a target
# list naming only the two apps would also roll inventory and pos back.
TOUCHED_APPS = ('requisitions', 'collectibles')
OLD_LEAVES = {
    'requisitions': '0001_initial',
    'collectibles': '0001_initial',
}


class _MigrationBase(TransactionTestCase):
    """Runs against a database moved back to the pre-decision-08 schema."""

    def _migrate(self, targets):
        executor = MigrationExecutor(connection)
        executor.loader.build_graph()
        executor.migrate(targets)
        return executor

    def _latest_targets(self):
        executor = MigrationExecutor(connection)
        return executor.loader.graph.leaf_nodes()

    def _old_targets(self):
        """Every app at its leaf, except the two this task rewrites."""
        return [
            (app, name) for app, name in self._latest_targets()
            if app not in TOUCHED_APPS
        ] + [(app, name) for app, name in OLD_LEAVES.items()]

    def _state_apps(self, executor, targets) -> Any:
        # `Any`: a historical app registry is built at runtime, so a checker without
        # django-stubs sees `project_state(...).apps` as a bare `cached_property`.
        return executor.loader.project_state(targets).apps


class ForemanDataMigrationTests(_MigrationBase):
    def setUp(self):
        self.old_targets = self._old_targets()
        self.executor = self._migrate(self.old_targets)
        old = self._state_apps(self.executor, self.old_targets)
        self._seed(old)

    def tearDown(self):
        # Leave the shared test database at head even when an assertion failed, or every
        # test after this one runs against the 0001 schema.
        self._migrate(self._latest_targets())

    def _seed(self, old):
        User = old.get_model('apps_users', 'User')
        Group = old.get_model('auth', 'Group')
        Category = old.get_model('inventory', 'Category')
        Brand = old.get_model('inventory', 'Brand')
        UnitOfMeasure = old.get_model('inventory', 'UnitOfMeasure')
        Product = old.get_model('inventory', 'Product')
        ProductVariant = old.get_model('inventory', 'ProductVariant')
        VariantUOM = old.get_model('inventory', 'VariantUOM')
        Customer_ = old.get_model('pos', 'Customer')
        Project_ = old.get_model('requisitions', 'Project')
        Requisition_ = old.get_model('requisitions', 'Requisition')
        RequisitionItem_ = old.get_model('requisitions', 'RequisitionItem')

        self.foreman_group = Group.objects.create(name='Site Foreman')
        self.manager_group = Group.objects.create(name='Store Manager')
        self.foreman = User.objects.create(
            username='foreman', email='f@x.com', full_name='Fore Man',
            password=get_random_string(20))
        self.foreman.groups.add(self.foreman_group)
        self.manager = User.objects.create(
            username='manager', email='m@x.com', full_name='Man Ager',
            password=get_random_string(20))
        self.manager.groups.add(self.manager_group)

        customer = Customer_.objects.create(name='Builder Corp')
        project = Project_.objects.create(name='House Build', customer=customer)

        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        box = UnitOfMeasure.objects.create(code='BOX', name='Box')
        # A second unit so two factor-1 rows can coexist (uq_variant_uom forbids the
        # same unit twice) and "lowest pk" has something to choose between.
        kilo = UnitOfMeasure.objects.create(code='KG', name='Kilo')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        # A factor-12 row FIRST, so the lowest-pk factor-1 row is neither the first nor
        # the only row: the migration must pick by conversion_factor, then by pk.
        VariantUOM.objects.create(
            variant=variant, uom=box, conversion_factor=Decimal('12'),
            default_selling_price=Decimal('120'))
        base_uom = VariantUOM.objects.create(
            variant=variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'))
        VariantUOM.objects.create(
            variant=variant, uom=kilo, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('11'))
        self.base_uom_pk = base_uom.pk
        self.variant_pk = variant.pk

        # Plain strings: a historical model carries the FIELD, not the nested `Status`
        # helper class, which Django does not serialise into migration state.
        self.requisition_pks = {}
        for index, name in enumerate(
                ('DRAFT', 'SUBMITTED', 'APPROVED', 'RELEASED')):
            approved_by = None if name in ('DRAFT', 'SUBMITTED') else self.manager
            requisition = Requisition_.objects.create(
                req_number=f'REQ-MIG-{index:04d}',
                project=project,
                requested_by=self.foreman,
                approved_by=approved_by,
                status=name,
            )
            RequisitionItem_.objects.create(
                requisition=requisition, variant=variant,
                quantity=Decimal('4'))
            self.requisition_pks[name] = requisition.pk

    def _migrate_forward(self):
        targets = self._latest_targets()
        executor = self._migrate(targets)
        return self._state_apps(executor, targets)

    def test_names_are_copied_and_the_user_links_are_gone(self):
        new = self._migrate_forward()
        Requisition_ = new.get_model('requisitions', 'Requisition')

        rows = Requisition_.objects.order_by('pk')
        self.assertEqual(rows.count(), 4)
        for row in rows:
            self.assertEqual(row.requester_name, 'Fore Man')
        approved = Requisition_.objects.get(pk=self.requisition_pks['APPROVED'])
        released = Requisition_.objects.get(pk=self.requisition_pks['RELEASED'])
        self.assertEqual(approved.approver_name, 'Man Ager')
        self.assertEqual(released.approver_name, 'Man Ager')
        # Never-approved rows keep an empty name, not NULL.
        draft = Requisition_.objects.get(pk=self.requisition_pks['DRAFT'])
        self.assertEqual(draft.approver_name, '')
        field_names = {f.name for f in Requisition_._meta.get_fields()}
        self.assertNotIn('requested_by', field_names)
        self.assertNotIn('approved_by', field_names)

    def test_draft_and_submitted_become_cancelled_and_the_rest_survive(self):
        new = self._migrate_forward()
        Requisition_ = new.get_model('requisitions', 'Requisition')

        by_pk = {pk: Requisition_.objects.get(pk=pk)
                 for pk in self.requisition_pks.values()}
        self.assertEqual(
            by_pk[self.requisition_pks['DRAFT']].status, 'CANCELLED')
        self.assertEqual(
            by_pk[self.requisition_pks['SUBMITTED']].status, 'CANCELLED')
        self.assertEqual(
            by_pk[self.requisition_pks['APPROVED']].status, 'APPROVED')
        self.assertEqual(
            by_pk[self.requisition_pks['RELEASED']].status, 'RELEASED')

    def test_every_line_points_at_the_lowest_pk_factor_one_selling_unit(self):
        new = self._migrate_forward()
        RequisitionItem_ = new.get_model('requisitions', 'RequisitionItem')

        items = list(RequisitionItem_.objects.order_by('pk'))
        self.assertEqual(len(items), 4)
        for item in items:
            self.assertEqual(item.variant_uom_id, self.base_uom_pk)
            # Quantities were base units and the factor-1 unit is base, so they carry over.
            self.assertEqual(item.quantity, Decimal('4'))
        field_names = {f.name for f in RequisitionItem_._meta.get_fields()}
        self.assertNotIn('variant', field_names)

    def test_the_foreman_is_deactivated_and_their_group_is_deleted(self):
        new = self._migrate_forward()
        User = new.get_model('apps_users', 'User')
        Group = new.get_model('auth', 'Group')

        foreman = User.objects.get(pk=self.foreman.pk)
        self.assertFalse(foreman.is_active)
        self.assertEqual(list(foreman.groups.all()), [])
        self.assertFalse(Group.objects.filter(name='Site Foreman').exists())
        # An account whose audit rows protect it cannot be deleted, and everyone else is
        # untouched: only the foreman role was on the way out.
        self.assertTrue(User.objects.filter(pk=self.foreman.pk).exists())
        manager = User.objects.get(pk=self.manager.pk)
        self.assertTrue(manager.is_active)
        self.assertEqual(
            [g.name for g in manager.groups.all()], ['Store Manager'])
        self.assertTrue(Group.objects.filter(name='Store Manager').exists())

    def test_a_line_whose_variant_has_no_factor_one_unit_stops_the_migration(self):
        old_targets = self._old_targets()
        executor = self._migrate(old_targets)
        old = self._state_apps(executor, old_targets)
        Product = old.get_model('inventory', 'Product')
        ProductVariant = old.get_model('inventory', 'ProductVariant')
        UnitOfMeasure = old.get_model('inventory', 'UnitOfMeasure')
        Requisition_ = old.get_model('requisitions', 'Requisition')
        RequisitionItem_ = old.get_model('requisitions', 'RequisitionItem')

        box = UnitOfMeasure.objects.get(code='BOX')
        bare = ProductVariant.objects.create(
            product=Product.objects.get(base_name='Portland Cement'),
            variant_name='50kg', base_uom=box)
        requisition = Requisition_.objects.get(pk=self.requisition_pks['APPROVED'])
        item = RequisitionItem_.objects.create(
            requisition=requisition, variant=bare, quantity=Decimal('1'))

        with self.assertRaises(RuntimeError) as caught:
            self._migrate_forward()
        # The message has to name the line, or a deploy-time failure is unactionable.
        self.assertIn(f'item #{item.pk}', str(caught.exception))
        # The refused migration leaves the item where it was; tearDown migrates to head,
        # so the row that (correctly) blocks it has to go first.
        item.delete()


class CpmsIdUniquenessTests(TestCase):
    """Decision 03/04 — the two CPMS ids are the matching keys, so they must be unique."""

    def setUp(self):
        self.customer = Customer.objects.create(name='Builder Corp')

    def _project(self, cpms_project_id=None, name='House Build'):
        return Project.objects.create(
            name=name, customer=self.customer, cpms_project_id=cpms_project_id)

    def test_two_projects_cannot_share_a_cpms_project_id(self):
        self._project('CPMS-P1')
        with self.assertRaises(IntegrityError), transaction.atomic():
            self._project('CPMS-P1', name='Other Build')

    def test_legacy_projects_may_have_no_cpms_project_id(self):
        self._project()
        self._project(name='Second Build')
        self.assertEqual(
            Project.objects.filter(cpms_project_id__isnull=True).count(), 2)

    def test_two_requisitions_cannot_share_a_cpms_request_id(self):
        project = self._project()
        Requisition.objects.create(
            req_number='REQ-CPMS-0001', project=project, cpms_request_id='CPMS-R1')
        with self.assertRaises(IntegrityError), transaction.atomic():
            Requisition.objects.create(
                req_number='REQ-CPMS-0002', project=project,
                cpms_request_id='CPMS-R1')

    def test_legacy_requisitions_may_have_no_cpms_request_id(self):
        project = self._project()
        Requisition.objects.create(req_number='REQ-CPMS-0003', project=project)
        Requisition.objects.create(req_number='REQ-CPMS-0004', project=project)
        self.assertEqual(
            Requisition.objects.filter(cpms_request_id__isnull=True).count(), 2)
