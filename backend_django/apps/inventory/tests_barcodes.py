# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests_catalog_writes.py: this checker
# runs from a working directory outside the repo, so `Model.objects` is a false positive
# on valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which
# pyright reads as `follow=`.

"""Phase 6 Tasks 1-3 — selling-unit codes: integrity, assignment, lookup.

Every selling unit carries one scannable code. Decisions 11/12/16/13 lock the shape:
a factory EAN is kept when it passes the GS1 check digit, everything else gets a
derived `QB{id:06}-{check}` code that nobody may hand-type, blanks are impossible, and
`?barcode=` resolves a scan to the exact unit.

The refusals are all **server-side** and all 400 `{code, detail}`, because each of them
was previously reachable with a well-formed request: two units could hold the same code
(the till then picks one at random), `4800016123456` (a typo) was stored as if scannable,
and a hand-typed `QB000099-0` could later collide with a generated code.

Real JWT logins (no ``force_authenticate``): the permission classes read GROUP
membership, so the login path is part of what is under test.
"""

import threading
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from . import models as inventory_models
from .models import UnitOfMeasure, VariantUOM
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
VARIANT_UOMS_URL = '/api/v1/variant-uoms/'

VALID_EAN = '4800016123450'   # GS1 mod-10 check digit 0 — verified vector
BAD_EAN = '4800016123456'     # same body, wrong check digit


def expected_code(pk: int) -> str:
    """The documented `QB{id:06}-{check}` shape, computed HERE as an independent oracle.

    Deliberately not imported from the app: a test that asks the implementation what it
    should have produced proves nothing.
    """
    digits = f'{pk:06d}'
    total = sum(
        int(char) * (3 if position % 2 == 0 else 1)
        for position, char in enumerate(reversed(digits)))
    return f'QB{digits}-{(10 - total % 10) % 10}'


class BarcodeTestBase(InventoryTestBase):
    """One user per role, real logins, and two selling units to clash between."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.password = get_random_string(16)
        self.stocker = self._make_user('bc_stocker', 'Stock Manager')
        self.cashier = self._make_user('bc_cashier', 'Cashier')
        self.uom_pc = UnitOfMeasure.objects.create(code='PC', name='Piece')
        self.uom_rl = UnitOfMeasure.objects.create(code='RL', name='Roll')
        # Factor 1 is the base unit; the second unit is a box of 12.
        self.unit = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom,
            conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        self.box = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom_pc,
            conversion_factor=Decimal('12'),
            default_selling_price=Decimal('100'),
        )

    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username, email=f'{username}@example.com',
            password=self.password, full_name=username)
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self, user, client=None):
        login = (client or APIClient()).post(
            LOGIN_URL, {'username': user.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f'Bearer {login.data["access"]}'}

    def _patch_code(self, unit, code, user=None, client=None):
        client = client or APIClient()
        return client.patch(
            f'{VARIANT_UOMS_URL}{unit.pk}/', {'barcode_qr': code},
            format='json', **self._auth(user or self.stocker, client))

    def _refusal(self, response, code):
        """Assert a project-shaped refusal: 400 with the stable code, and its detail."""
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), code, response.data)
        self.assertTrue(response.data.get('detail'), response.data)


class CodeHelperTests(InventoryTestBase):
    """The derived format and the GS1 check digit, against known-answer vectors.

    The helpers are looked up rather than imported so a missing helper fails as an
    ASSERTION (RED against today's code), not as a collection-time ImportError.
    """

    def _helper(self, name):
        """The named model helper, or a RED assertion failure when it does not exist."""
        helper = getattr(inventory_models, name, None)
        if not callable(helper):
            self.fail(f'{name} helper is missing from models')
        return helper

    def test_gs1_check_digit_known_answers(self):
        gs1 = self._helper('gs1_check_digit')
        # The six id digits of the locked vectors: 3 -> 1, 12 -> 3, 13 -> 0, 16 -> 1.
        self.assertEqual(gs1('000003'), 1)
        self.assertEqual(gs1('000012'), 3)
        self.assertEqual(gs1('000013'), 0)
        self.assertEqual(gs1('000016'), 1)
        # A real EAN-13 body: 480001612345 + check digit 0.
        self.assertEqual(gs1('480001612345'), 0)

    def test_derived_code_known_answers(self):
        derive = self._helper('derived_code')
        self.assertEqual(derive(3), 'QB000003-1')
        self.assertEqual(derive(12), 'QB000012-3')
        self.assertEqual(derive(13), 'QB000013-0')
        self.assertEqual(derive(16), 'QB000016-1')

    def test_normalise_barcode_trims_and_uppercases(self):
        normalise = self._helper('normalise_barcode')
        self.assertEqual(normalise('  qb000013-0 '), 'QB000013-0')
        self.assertEqual(normalise(' 4800016123450\t'), VALID_EAN)
        self.assertEqual(normalise(None), '')
        self.assertEqual(normalise(''), '')


class BarcodeIntegrityTests(BarcodeTestBase):
    """Task 1 — one code per unit, normalised, check-digit validated, prefix reserved."""

    def test_duplicate_code_in_another_case_with_padding_is_refused(self):
        first = self._patch_code(self.unit, VALID_EAN)
        self.assertEqual(first.status_code, 200, first.data)

        # Same code, lower case, padded: the same code once normalised.
        second = self._patch_code(self.box, f'  {VALID_EAN.lower()}  ')

        self._refusal(second, 'BARCODE_TAKEN')
        self.assertEqual(
            VariantUOM.objects.filter(barcode_qr__iexact=VALID_EAN).count(), 1,
            'a clashing code must leave nothing saved')
        self.box.refresh_from_db()
        self.assertNotEqual(self.box.barcode_qr.lower(), VALID_EAN)

    def test_bad_ean_check_digit_is_refused_and_names_the_check_digit(self):
        response = self._patch_code(self.unit, BAD_EAN)

        self._refusal(response, 'BARCODE_INVALID')
        self.assertIn('check digit', response.data['detail'].lower())
        self.unit.refresh_from_db()
        self.assertNotEqual(self.unit.barcode_qr, BAD_EAN)

    def test_code_with_an_embedded_space_is_refused(self):
        response = self._patch_code(self.unit, '4800 16123450')

        self._refusal(response, 'BARCODE_INVALID')
        self.unit.refresh_from_db()
        self.assertNotEqual(self.unit.barcode_qr, '4800 16123450')

    def test_code_with_a_control_character_is_refused(self):
        response = self._patch_code(self.unit, 'ABC\u0007DEF')

        self._refusal(response, 'BARCODE_INVALID')

    def test_manual_qb_code_on_another_unit_is_refused(self):
        # A code that LOOKS generated but is not this unit's own derivation.
        response = self._patch_code(self.unit, 'QB000099-0')

        self._refusal(response, 'BARCODE_RESERVED_PREFIX')
        self.unit.refresh_from_db()
        self.assertNotEqual(self.unit.barcode_qr, 'QB000099-0')

    def test_qb_code_on_create_is_refused(self):
        response = self.client.post(
            VARIANT_UOMS_URL,
            {'variant': self.variant.pk, 'uom': self.uom_rl.pk,
             'barcode_qr': 'QB000999-0', 'conversion_factor': '6',
             'default_selling_price': '60'},
            format='json', **self._auth(self.stocker))

        self._refusal(response, 'BARCODE_RESERVED_PREFIX')
        self.assertFalse(
            VariantUOM.objects.filter(barcode_qr='QB000999-0').exists())

    def test_a_unit_may_keep_its_own_derived_code(self):
        own = expected_code(self.unit.pk)

        response = self._patch_code(self.unit, own)

        self.assertEqual(response.status_code, 200, response.data)
        self.unit.refresh_from_db()
        self.assertEqual(self.unit.barcode_qr, own)

    def test_a_cashier_cannot_write_a_barcode(self):
        response = self._patch_code(self.unit, VALID_EAN, user=self.cashier)

        self.assertEqual(response.status_code, 403, response.data)
        self.unit.refresh_from_db()
        self.assertNotEqual(self.unit.barcode_qr, VALID_EAN)


class BarcodeConstraintTests(BarcodeTestBase):
    """The DB constraint is the real guard: a lost pre-check race is still a 400."""

    def test_integrity_error_on_the_unique_constraint_maps_to_400(self):
        first = self._patch_code(self.unit, VALID_EAN)
        self.assertEqual(first.status_code, 200, first.data)

        # Simulate the race the serializer's pre-check cannot win: two requests both
        # read "no holder" and both reach the INSERT. With the check stubbed out the
        # second one must be refused by the DB constraint and answered as the same 400,
        # not a 500.
        from .serializers import VariantUOMSerializer

        with mock.patch.object(
                VariantUOMSerializer, '_barcode_holder', return_value=None):
            response = self._patch_code(self.box, VALID_EAN)

        self._refusal(response, 'BARCODE_TAKEN')
        self.assertEqual(
            VariantUOM.objects.filter(barcode_qr__iexact=VALID_EAN).count(), 1)


class ConcurrentBarcodeTests(TransactionTestCase):
    """Two tills writing the same code at once: exactly one wins.

    `TransactionTestCase` because the two worker threads must see each other's committed
    rows — the wrapped transaction a `TestCase` uses hides them, and then this test would
    pass or fail on timing rather than on the constraint.
    """

    def setUp(self):
        self.password = get_random_string(16)
        category = inventory_models.Category.objects.create(name='Cement')
        brand = inventory_models.Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        uom_pc = UnitOfMeasure.objects.create(code='PC', name='Piece')
        product = inventory_models.Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        variant = inventory_models.ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom,
            min_stock_threshold=Decimal('5'))
        self.units = [
            VariantUOM.objects.create(
                variant=variant, uom=uom if index == 0 else uom_pc,
                conversion_factor=Decimal('1') if index == 0 else Decimal('12'),
                default_selling_price=Decimal('10'))
            for index in (0, 1)
        ]
        self.stocker = User.objects.create_user(
            username='bc_racer', email='racer@example.com',
            password=self.password, full_name='racer')
        self.stocker.groups.add(
            Group.objects.get_or_create(name='Stock Manager')[0])

    def _login(self, client):
        login = client.post(
            LOGIN_URL,
            {'username': self.stocker.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f'Bearer {login.data["access"]}'}

    def test_two_concurrent_patches_of_one_code_have_exactly_one_winner(self):
        barrier = threading.Barrier(2, timeout=20)
        results = []
        lock = threading.Lock()

        def worker(unit):
            client = APIClient()
            auth = self._login(client)
            try:
                barrier.wait()
                response = client.patch(
                    f'{VARIANT_UOMS_URL}{unit.pk}/', {'barcode_qr': VALID_EAN},
                    format='json', **auth)
                with lock:
                    results.append((response.status_code, response.data))
            finally:
                # Each thread owns its own connection; leaving it open would hang the
                # truncation this TestCase does when it finishes.
                connections.close_all()

        threads = [threading.Thread(target=worker, args=(unit,))
                   for unit in self.units]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        statuses = sorted(status for status, _data in results)
        self.assertEqual(len(results), 2, results)
        self.assertEqual(
            statuses, [200, 400],
            f'exactly one writer may win: {results}')
        losing = [data for status, data in results if status == 400][0]
        self.assertEqual(losing.get('code'), 'BARCODE_TAKEN', losing)
        self.assertEqual(
            VariantUOM.objects.filter(barcode_qr__iexact=VALID_EAN).count(), 1)
