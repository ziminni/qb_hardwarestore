# pyright: reportAttributeAccessIssue=false
"""Phase 3 Task 3 — held carts are an ADVISORY on the shift close, never a gate.

Decision 06 (record-and-warn): a held cart is a parked sale, not lost money — it keeps
belonging to the cashier and can be resumed after the shift closes. Refusing the close
would strand the till open over a cart somebody may settle tomorrow. So the close answers
with the count, the Z-reading carries it, and nothing is blocked or deleted.

The count is the shift's CASHIER's carts, which is why another cashier's carts must not
inflate it.
"""

from decimal import Decimal

from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import User

from .models import HeldCart, Shift
from .tests import POSTestBase

LOGIN_URL = '/api/v1/auth/login/'
SHIFTS_URL = '/api/v1/shifts/'


class ShiftHeldCartAdvisoryTests(POSTestBase):
    def setUp(self):
        super().setUp()
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.password = get_random_string(12)
        self.cashier.set_password(self.password)
        self.cashier.save(update_fields=['password'])
        self.client = APIClient()
        login = self.client.post(
            LOGIN_URL,
            {'username': self.cashier.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, 'the cashier must be able to log in')
        # Explicit keyword, not a `**dict`: the client's own `follow` parameter is typed
        # bool, so unpacking a header dict reads as a type error to a checker.
        self.bearer = f'Bearer {login.data["access"]}'

    def _held_carts(self, count, cashier=None):
        cashier = cashier or self.cashier
        return [
            HeldCart.objects.create(cashier=cashier, notes=f'parked {index}')
            for index in range(count)
        ]

    def _other_cashier(self):
        other = User.objects.create_user(
            username='cashier2', email='c2@x.com',
            password=get_random_string(12))
        other.groups.add(Group.objects.get(name='Cashier'))
        return other

    def test_current_shift_reports_the_cashiers_held_cart_count(self):
        self._held_carts(2)

        response = self.client.get(
            f'{SHIFTS_URL}current/', HTTP_AUTHORIZATION=self.bearer)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['held_cart_count'], 2)

    def test_another_cashiers_held_carts_are_not_counted(self):
        self._held_carts(1)
        self._held_carts(2, cashier=self._other_cashier())

        response = self.client.get(
            f'{SHIFTS_URL}current/', HTTP_AUTHORIZATION=self.bearer)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['held_cart_count'], 1)

    def test_close_succeeds_and_reports_the_held_cart_count(self):
        carts = self._held_carts(2)

        response = self.client.post(
            f'{SHIFTS_URL}{self.shift.id}/close/', {'closing_count': '5000.00'},
            format='json', HTTP_AUTHORIZATION=self.bearer)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['held_cart_count'], 2)
        # The Z-reading the printout uses carries the same advisory.
        self.assertEqual(response.data['z_reading']['held_cart_count'], 2)

        self.shift.refresh_from_db()
        self.assertEqual(self.shift.status, Shift.Status.CLOSED)
        self.assertEqual(
            HeldCart.objects.filter(
                pk__in=[cart.pk for cart in carts]).count(), 2,
            'closing a shift must not delete the parked carts')

    def test_a_shift_without_held_carts_reports_zero(self):
        response = self.client.get(
            f'{SHIFTS_URL}current/', HTTP_AUTHORIZATION=self.bearer)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data['held_cart_count'], 0)
        self.assertEqual(Decimal(response.data['opening_float']), Decimal('5000'))
