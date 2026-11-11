# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directives and reasons as apps/requisitions/tests_migration.py: this checker runs
# without django-stubs, so a historical app registry's `apps` looks like a bare
# `cached_property`. `manage.py test` remains the authority on what these tests prove.
"""Phase 1d Task 1 — the whole-number flag and the standard unit list.

Decision 16 puts the standard units in every database and moves the whole-vs-fractional
knowledge from the Flutter client onto the server. Two things have to hold:

* **The migration never duplicates a unit.** Codes are unique but CASE-SENSITIVE, so a
  database that already holds `kg` must keep that one row rather than gain a `KG` next to
  it, and `RL` (how the seed has always spelled Roll) must become THE Roll row rather than
  sit beside a second one.
* **The API can answer "is this unit whole?" and "is this unit in use?" for a whole list
  in one round trip.** `in_use` is what will let a screen offer "remove" only where
  removal is allowed, so it has to be cheap enough to send with every row.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connection
from django.db.migrations.executor import MigrationExecutor
from django.test import TestCase, TransactionTestCase
from django.test.utils import CaptureQueriesContext
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)

User = get_user_model()

# The last inventory migration BEFORE the flag existed.
BEFORE = '0007_backfill_variantuom_barcodes'
INVENTORY = 'inventory'

UOMS_URL = '/api/v1/uoms/'
VARIANT_UOMS_URL = '/api/v1/variant-uoms/'
PRODUCTS_URL = '/api/v1/products/'

CANONICAL = {
    'PC': ('Piece', True),
    'BAG': ('Bag', True),
    'BOX': ('Box', True),
    'PACK': ('Pack', True),
    'ROLL': ('Roll', True),
    'SHEET': ('Sheet', True),
    'KG': ('Kilogram', False),
    'G': ('Gram', False),
    'M': ('Metre', False),
    'CM': ('Centimetre', False),
    'L': ('Litre', False),
    'ML': ('Millilitre', False),
}


class StandardUnitsMigrationTests(TransactionTestCase):
    """Runs 0008 against a database seeded with the shapes that are there in production."""

    def _migrate(self, targets):
        executor = MigrationExecutor(connection)
        executor.loader.build_graph()
        executor.migrate(targets)
        return executor

    def _leaves(self):
        return MigrationExecutor(connection).loader.graph.leaf_nodes()

    def _before_targets(self):
        """Every app at its leaf, except inventory, which stops before the flag."""
        return [
            (app, BEFORE if app == INVENTORY else name)
            for app, name in self._leaves()
        ]

    def setUp(self):
        self.before_targets = self._before_targets()
        executor = self._migrate(self.before_targets)
        self.before = executor.loader.project_state(self.before_targets).apps
        # The test database was built by migrating to head, so 0008's standard units are
        # already there. Each test states its own starting table instead of inheriting it.
        self.before.get_model(INVENTORY, 'UnitOfMeasure').objects.all().delete()

    def tearDown(self):
        # Leave the shared test database at head even when an assertion failed, or every
        # test after this one runs against the 0007 schema.
        self._migrate(self._leaves())

    def _seed_units(self, rows):
        old = self.before.get_model(INVENTORY, 'UnitOfMeasure')
        for code, name in rows:
            old.objects.create(code=code, name=name)

    def _codes(self):
        return dict(UnitOfMeasure.objects.values_list('code', 'name'))

    def _seed_today(self):
        """What a real database holds: seed units plus a hand-typed lower-case kg."""
        self._seed_units([
            ('BAG', 'Bag'), ('PC', 'Piece'), ('RL', 'Roll'), ('kg', 'kilogram'),
        ])

    def test_existing_rows_keep_code_and_name_and_are_flagged(self):
        self._seed_today()
        self._migrate(self._leaves())

        names = self._codes()
        self.assertEqual(len(names), 12)
        # Existing spellings survive: nothing was re-cased or re-named.
        self.assertEqual(names['BAG'], 'Bag')
        self.assertEqual(names['PC'], 'Piece')
        self.assertEqual(names['RL'], 'Roll')
        self.assertEqual(names['kg'], 'kilogram')
        # RL IS the Roll row (decision 16): no second Roll was created.
        self.assertFalse(UnitOfMeasure.objects.filter(code='ROLL').exists())

        # One row per canonical code, counting case-insensitively. RUN stays `rl` on
        # purpose: RL IS the Roll row (decision 16).
        lowered = sorted(code.lower() for code in names)
        expected = sorted(
            'rl' if code == 'ROLL' else code.lower() for code in CANONICAL)
        self.assertEqual(lowered, expected)

        whole = set(
            UnitOfMeasure.objects.filter(is_whole=True)
            .values_list('code', flat=True))
        # RL stands in for ROLL, so it is whole; kg is the measured one.
        self.assertEqual(whole, {'BAG', 'PC', 'RL', 'BOX', 'PACK', 'SHEET'})
        self.assertFalse(
            UnitOfMeasure.objects.get(code='kg').is_whole)

    def test_empty_database_gets_every_standard_unit(self):
        self._migrate(self._leaves())

        names = self._codes()
        self.assertEqual(names, {code: name for code, (name, _) in CANONICAL.items()})
        flags = dict(UnitOfMeasure.objects.values_list('code', 'is_whole'))
        self.assertEqual(
            flags, {code: whole for code, (_name, whole) in CANONICAL.items()})

    def test_re_running_the_migration_creates_nothing(self):
        self._seed_today()
        self._migrate(self._leaves())
        first = self._codes()

        # Back to 0007 and forward again: the rows the migration created survive the
        # reverse (it is a noop), so the second run must match them rather than add.
        self._migrate(self._before_targets())
        self._migrate(self._leaves())

        self.assertEqual(self._codes(), first)
        self.assertEqual(UnitOfMeasure.objects.count(), 12)


class UnitFlagAPITestBase(TestCase):
    """One catalog and one user, plus a helper for extra selling units."""

    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='units_viewer', email='units@example.com',
            password=get_random_string(16), full_name='Units Viewer')
        self.user.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        self.client.force_authenticate(self.user)
        self.category = Category.objects.create(name='Cement')
        self.brand = Brand.objects.create(name='Rhino')
        # Canonical units already exist: migration 0008 seeds them in every database.
        self.uom_bag = UnitOfMeasure.objects.update_or_create(
            code='BAG', defaults={'name': 'Bag', 'is_whole': True})[0]
        self.uom_kg = UnitOfMeasure.objects.update_or_create(
            code='KG', defaults={'name': 'Kilogram', 'is_whole': False})[0]
        self.product = Product.objects.create(
            category=self.category, brand=self.brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=self.product, variant_name='40kg', base_uom=self.uom_kg)
        self.base_unit = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom_kg,
            conversion_factor=Decimal('1'),
            default_selling_price=Decimal('6.75'))
        self.bag_unit = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom_bag,
            conversion_factor=Decimal('40'),
            default_selling_price=Decimal('270'))

    def _extra_unit(self, code, uom=None):
        uom = uom or UnitOfMeasure.objects.create(code=code, name=code.title())
        return VariantUOM.objects.create(
            variant=self.variant, uom=uom,
            conversion_factor=Decimal('2'),
            default_selling_price=Decimal('10'))

    @staticmethod
    def _rows(response):
        """The list rows: list endpoints are paginated (`results`)."""
        data = response.data
        return data['results'] if isinstance(data, dict) else data


class UnitFlagAPITests(UnitFlagAPITestBase):
    def test_uom_list_exposes_the_whole_number_flag(self):
        response = self.client.get(UOMS_URL)
        self.assertEqual(response.status_code, 200)
        flags = {row['code']: row['is_whole'] for row in self._rows(response)}
        # The seeded standard list, straight through the API: whole in ones, the rest
        # measured.
        self.assertEqual(
            flags, {code: whole for code, (_name, whole) in CANONICAL.items()})

    def test_selling_unit_exposes_uom_is_whole(self):
        response = self.client.get(VARIANT_UOMS_URL)
        self.assertEqual(response.status_code, 200)
        whole = {row['uom_code']: row['uom_is_whole'] for row in self._rows(response)}
        self.assertEqual(whole, {'BAG': True, 'KG': False})

    def test_nested_product_units_carry_both_flags(self):
        response = self.client.get(f'{PRODUCTS_URL}{self.product.pk}/')
        self.assertEqual(response.status_code, 200)
        units = {
            unit['uom_code']: (unit['uom_is_whole'], unit['in_use'])
            for unit in response.data['variants'][0]['selling_uoms']
        }
        self.assertEqual(units, {'BAG': (True, False), 'KG': (False, False)})

    def test_a_write_response_answers_the_flags_without_an_annotation(self):
        # A freshly created row carries no annotation, so the serializer's single-row
        # fallback is what has to answer here.
        uom = UnitOfMeasure.objects.create(code='DRUM', name='Drum', is_whole=True)
        created = self.client.post(VARIANT_UOMS_URL, {
            'variant': self.variant.pk,
            'uom': uom.pk,
            'conversion_factor': '5',
            'default_selling_price': '1',
        }, format='json')
        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(created.data['uom_is_whole'], True)
        self.assertEqual(created.data['in_use'], False)


class UnitInUseTests(UnitFlagAPITestBase):
    """`in_use` is true for each of the five tables that PROTECT a selling unit."""

    def _in_use(self):
        response = self.client.get(VARIANT_UOMS_URL)
        self.assertEqual(response.status_code, 200)
        return {row['id']: row['in_use'] for row in self._rows(response)}

    def test_sale_line_marks_the_unit_in_use(self):
        from apps.pos.models import Customer, SalesItem, SalesTransaction

        transaction = SalesTransaction.objects.create(
            cashier=self.user,
            customer=Customer.objects.create(name='Walk-in Customer'),
            transaction_no='T-1')
        SalesItem.objects.create(
            transaction=transaction, variant_uom=self.bag_unit,
            qty=Decimal('1'), unit_price=Decimal('270'),
            subtotal=Decimal('270'))

        self.assertTrue(self._in_use()[self.bag_unit.pk])
        self.assertFalse(self._in_use()[self.base_unit.pk])

    def test_held_cart_line_marks_the_unit_in_use(self):
        from apps.pos.models import HeldCart, HeldCartItem

        cart = HeldCart.objects.create(cashier=self.user)
        HeldCartItem.objects.create(
            cart=cart, variant_uom=self.bag_unit,
            qty=Decimal('1'), unit_price=Decimal('270'))

        self.assertTrue(self._in_use()[self.bag_unit.pk])

    def test_quotation_line_marks_the_unit_in_use(self):
        from apps.pos.models import Customer, Quotation, QuotationItem

        quotation = Quotation.objects.create(
            customer=Customer.objects.create(name='Acme Builders'),
            created_by=self.user)
        QuotationItem.objects.create(
            quotation=quotation, variant_uom=self.bag_unit,
            qty=Decimal('2'), unit_price=Decimal('270'))

        self.assertTrue(self._in_use()[self.bag_unit.pk])

    def test_sales_order_line_marks_the_unit_in_use(self):
        from apps.pos.models import Customer, SalesOrder, SalesOrderItem

        order = SalesOrder.objects.create(
            customer=Customer.objects.create(name='Acme Builders'),
            created_by=self.user)
        SalesOrderItem.objects.create(
            order=order, variant_uom=self.bag_unit,
            qty=Decimal('2'), unit_price=Decimal('270'))

        self.assertTrue(self._in_use()[self.bag_unit.pk])

    def test_requisition_line_marks_the_unit_in_use(self):
        from apps.pos.models import Customer
        from apps.requisitions.models import Project, Requisition, RequisitionItem

        project = Project.objects.create(
            name='Harbour Tower',
            customer=Customer.objects.create(
                name='Acme Builders',
                customer_type=Customer.Type.CONTRACTOR))
        requisition = Requisition.objects.create(
            project=project, req_number='REQ-0001')
        RequisitionItem.objects.create(
            requisition=requisition, variant_uom=self.bag_unit,
            quantity=Decimal('2'))

        self.assertTrue(self._in_use()[self.bag_unit.pk])


class UnitListQueryCountTests(UnitFlagAPITestBase):
    """The flags travel with the rows: adding units and references adds no queries."""

    def _count(self, url, rows):
        with CaptureQueriesContext(connection) as captured:
            response = self.client.get(url)
            self.assertEqual(response.status_code, 200)
            self.assertEqual(len(self._rows(response)), rows)
        return len(captured)

    def test_selling_unit_list_query_count_is_flat(self):
        baseline = self._count(VARIANT_UOMS_URL, 2)
        for index in range(3):
            self._extra_unit(f'X{index}')
        with_references = self._count(VARIANT_UOMS_URL, 5)
        self.assertEqual(with_references, baseline)

    def test_product_list_query_count_is_flat(self):
        baseline = self._count(PRODUCTS_URL, 1)
        for index in range(3):
            self._extra_unit(f'Y{index}')
        second_product = Product.objects.create(
            category=self.category, brand=self.brand, base_name='Nails')
        ProductVariant.objects.create(
            product=second_product, variant_name='1in', base_uom=self.uom_bag)
        self.assertEqual(self._count(PRODUCTS_URL, 2), baseline)
