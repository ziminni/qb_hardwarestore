# pyright: reportAttributeAccessIssue=false
"""Decision 04 — the Admin GROUP is the application authority, not ``is_staff``.

Phase 2, Task 1. ``is_staff`` keeps exactly one meaning: "may log into Django
``/admin``". Every user-management refusal here is a stable ``{code, detail}``
400 and the account itself survives — users are deactivated, never deleted.
"""

from unittest import mock

from django.contrib.auth.models import Group
from django.db import connection
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import User

LOGIN_URL = '/api/v1/auth/login/'
ME_URL = '/api/v1/auth/me/'
REGISTER_URL = '/api/v1/auth/register/'
USERS_URL = '/api/v1/users/'
STATS_URL = '/api/v1/users/stats/'
AUDIT_URL = '/api/v1/audit-logs/'

ADMIN_GROUP = 'Admin'
CASHIER_GROUP = 'Cashier'


class AdminAuthorityTestBase(TestCase):
    """Real JWT login (no ``force_authenticate``), random per-run password."""

    def setUp(self):
        self.password = get_random_string(16)
        self.client = APIClient()
        for name in (ADMIN_GROUP, CASHIER_GROUP):
            Group.objects.get_or_create(name=name)

    def make_user(self, username, *, groups=(), is_staff=False, is_active=True,
                  is_superuser=False):
        user = User.objects.create_user(
            username=username,
            email=f'{username}@example.com',
            password=self.password,
            is_staff=is_staff,
            is_active=is_active,
            is_superuser=is_superuser,
        )
        for name in groups:
            group, _ = Group.objects.get_or_create(name=name)
            user.groups.add(group)
        return user

    def auth(self, user):
        """Log in and return an Authorization header (the API is JWT-only)."""
        login = self.client.post(
            LOGIN_URL,
            {'username': user.username, 'password': self.password},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)
        return f"Bearer {login.data['access']}"


class AdminGroupAuthorityTests(AdminAuthorityTestBase):
    """Authority comes from the Admin group; ``is_staff`` grants nothing."""

    def setUp(self):
        super().setUp()
        self.group_admin = self.make_user(
            'group_admin', groups=[ADMIN_GROUP], is_staff=False)
        self.staff_only = self.make_user(
            'staff_only', groups=[CASHIER_GROUP], is_staff=True)
        self.cashier = self.make_user('cashier1', groups=[CASHIER_GROUP])

    def test_admin_group_without_is_staff_reads_users_stats_audit(self):
        auth = self.auth(self.group_admin)
        self.assertEqual(
            self.client.get(USERS_URL, HTTP_AUTHORIZATION=auth).status_code, 200)
        self.assertEqual(
            self.client.get(STATS_URL, HTTP_AUTHORIZATION=auth).status_code, 200)
        self.assertEqual(
            self.client.get(AUDIT_URL, HTTP_AUTHORIZATION=auth).status_code, 200)

    def test_admin_group_without_is_staff_can_register(self):
        auth = self.auth(self.group_admin)
        res = self.client.post(
            REGISTER_URL,
            {'username': 'newbie', 'email': 'newbie@example.com',
             'password': get_random_string(16), 'full_name': 'New Bie',
             'group_name': CASHIER_GROUP},
            format='json',
            HTTP_AUTHORIZATION=auth,
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertTrue(User.objects.filter(username='newbie').exists())

    def test_staff_without_admin_group_is_forbidden(self):
        auth = self.auth(self.staff_only)
        self.assertEqual(
            self.client.get(USERS_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        self.assertEqual(
            self.client.get(STATS_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        self.assertEqual(
            self.client.get(AUDIT_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        res = self.client.post(
            REGISTER_URL,
            {'username': 'sneaky', 'email': 'sneaky@example.com',
             'password': get_random_string(16), 'full_name': 'Sneaky',
             'group_name': ADMIN_GROUP},
            format='json',
            HTTP_AUTHORIZATION=auth,
        )
        self.assertEqual(res.status_code, 403)
        self.assertFalse(User.objects.filter(username='sneaky').exists())

    def test_cashier_is_forbidden(self):
        auth = self.auth(self.cashier)
        self.assertEqual(
            self.client.get(USERS_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        self.assertEqual(
            self.client.get(STATS_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        self.assertEqual(
            self.client.get(AUDIT_URL, HTTP_AUTHORIZATION=auth).status_code, 403)
        self.assertEqual(
            self.client.post(
                REGISTER_URL,
                {'username': 'nah', 'email': 'nah@example.com',
                 'password': get_random_string(16), 'full_name': 'Nah',
                 'group_name': CASHIER_GROUP},
                format='json',
                HTTP_AUTHORIZATION=auth,
            ).status_code,
            403,
        )


class UserWriteHardeningTests(AdminAuthorityTestBase):
    """``is_staff`` is read-only over the API and accounts are never deleted."""

    def setUp(self):
        super().setUp()
        self.admin = self.make_user('admin1', groups=[ADMIN_GROUP])
        self.target = self.make_user('target1', groups=[CASHIER_GROUP])

    def test_patch_cannot_grant_django_admin_access(self):
        auth = self.auth(self.admin)
        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'is_staff': True},
            format='json',
            HTTP_AUTHORIZATION=auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.target.refresh_from_db()
        self.assertFalse(self.target.is_staff)

    def test_patch_still_applies_other_fields(self):
        auth = self.auth(self.admin)
        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'full_name': 'Renamed Person'},
            format='json',
            HTTP_AUTHORIZATION=auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.target.refresh_from_db()
        self.assertEqual(self.target.full_name, 'Renamed Person')

    def test_delete_user_is_method_not_allowed(self):
        auth = self.auth(self.admin)
        res = self.client.delete(
            f'{USERS_URL}{self.target.pk}/', HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 405, res.data)
        self.assertTrue(User.objects.filter(pk=self.target.pk).exists())


class LastAdminGuardTests(AdminAuthorityTestBase):
    """No change may leave the system with zero active admins."""

    def setUp(self):
        super().setUp()
        self.admin = self.make_user('admin1', groups=[ADMIN_GROUP])
        self.second_admin = self.make_user('admin2', groups=[ADMIN_GROUP])
        # A second admin exists for every test that must succeed; the "only
        # admin" tests deactivate it first so exactly one active admin remains.
        self.admin_auth = self.auth(self.admin)

    def _only_admin_left(self):
        """Deactivate admin2 so ``self.admin`` is the last active admin."""
        User.objects.filter(pk=self.second_admin.pk).update(is_active=False)

    def test_deactivating_only_admin_is_refused(self):
        self._only_admin_left()
        res = self.client.patch(
            f'{USERS_URL}{self.admin.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data['code'], 'LAST_ADMIN')
        self.assertTrue(res.data['detail'])
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.is_active)

    def test_demoting_only_admin_is_refused(self):
        self._only_admin_left()
        res = self.client.post(
            f'{USERS_URL}{self.admin.pk}/assign_role/',
            {'group_name': CASHIER_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data['code'], 'LAST_ADMIN')
        self.assertEqual(
            list(self.admin.groups.values_list('name', flat=True)), [ADMIN_GROUP])

    def test_removing_only_admins_admin_group_is_refused(self):
        self._only_admin_left()
        res = self.client.post(
            f'{USERS_URL}{self.admin.pk}/remove_role/',
            {'group_name': ADMIN_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data['code'], 'LAST_ADMIN')
        self.assertEqual(
            list(self.admin.groups.values_list('name', flat=True)), [ADMIN_GROUP])

    def test_deactivating_one_of_two_admins_is_allowed(self):
        res = self.client.patch(
            f'{USERS_URL}{self.second_admin.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.second_admin.refresh_from_db()
        self.assertFalse(self.second_admin.is_active)

    def test_demoting_one_of_two_admins_is_allowed(self):
        res = self.client.post(
            f'{USERS_URL}{self.second_admin.pk}/assign_role/',
            {'group_name': CASHIER_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(
            list(self.second_admin.groups.values_list('name', flat=True)),
            [CASHIER_GROUP],
        )

    def test_deactivating_a_non_admin_is_allowed_even_with_one_admin(self):
        self._only_admin_left()
        cashier = self.make_user('cashier2', groups=[CASHIER_GROUP])
        res = self.client.patch(
            f'{USERS_URL}{cashier.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        cashier.refresh_from_db()
        self.assertFalse(cashier.is_active)

    def test_removing_a_non_admin_group_is_allowed_with_one_admin(self):
        self._only_admin_left()
        cashier = self.make_user('cashier3', groups=[CASHIER_GROUP])
        res = self.client.post(
            f'{USERS_URL}{cashier.pk}/remove_role/',
            {'group_name': CASHIER_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)

    def test_active_superuser_counts_as_an_admin(self):
        """A superuser is an admin for guard purposes even without the group."""
        superuser = self.make_user(
            'root1', groups=[ADMIN_GROUP], is_staff=True, is_superuser=True)
        self._only_admin_left()
        res = self.client.patch(
            f'{USERS_URL}{self.admin.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertTrue(User.objects.get(pk=superuser.pk).is_active)


class LastAdminGuardIsLockedTests(AdminAuthorityTestBase):
    """The last-admin guard decides under a row lock (review F3).

    ``last_admin_refusal`` used to run OUTSIDE any transaction: it asked "is another
    active admin alive?", got `yes`, and only then wrote. Two concurrent requests —
    deactivate admin A, deactivate admin B — could both read `yes` and both write, and
    the system was left with **zero** admins and no way back in through the API. The
    guard now runs inside `transaction.atomic()` AFTER `select_for_update` has locked
    the target and every other active-admin candidate, so the state it decides on
    cannot be invalidated before its own write commits.

    What these tests prove deterministically: the request issues a `SELECT ... FOR
    UPDATE` over the user rows, and the guard's decision point is only reached after
    that lock is held (the probe fails if no lock query came first). What only a REAL
    two-connection run can prove is that Postgres BLOCKS the loser: the second request
    waits on the lock and then re-reads committed state. A single-threaded test can show
    the ordering, not the blocking.
    """

    def setUp(self):
        super().setUp()
        self.admin = self.make_user('lock_admin1', groups=[ADMIN_GROUP])
        self.second_admin = self.make_user('lock_admin2', groups=[ADMIN_GROUP])
        self.admin_auth = self.auth(self.admin)

    def _only_admin_left(self):
        User.objects.filter(pk=self.second_admin.pk).update(is_active=False)

    def _admin_locks(self, queries):
        """Every captured statement that row-locks the user table."""
        return [
            q['sql'] for q in queries
            if 'FOR UPDATE' in q['sql'].upper() and 'apps_users' in q['sql']
        ]

    def test_deactivating_the_only_admin_row_locks_the_admin_rows_first(self):
        self._only_admin_left()

        with CaptureQueriesContext(connection) as captured:
            res = self.client.patch(
                f'{USERS_URL}{self.admin.pk}/',
                {'is_active': False},
                format='json',
                HTTP_AUTHORIZATION=self.admin_auth,
            )

        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data['code'], 'LAST_ADMIN')
        self.assertTrue(
            self._admin_locks(captured.captured_queries),
            'the last-admin guard must lock the rows it decides on')

    def test_the_guard_decides_while_it_holds_the_lock(self):
        """The probe runs at the guard's decision point (inside `last_admin_refusal`).

        It asserts a `FOR UPDATE` on the admin rows has ALREADY been issued when the
        guard asks "does another admin exist?". Without the fix the guard is reached
        with no lock held at all, so the assertion fails — the check-then-act bug stated
        as an assertion.
        """
        from apps.users import services

        real = services.other_active_admin_exists

        def probe(user):
            self.assertTrue(
                self._admin_locks(connection.queries),
                'the guard must decide after the admin rows are locked, not before')
            return real(user)

        with CaptureQueriesContext(connection), mock.patch(
                'apps.users.views.other_active_admin_exists', probe):
            res = self.client.patch(
                f'{USERS_URL}{self.second_admin.pk}/',
                {'is_active': False},
                format='json',
                HTTP_AUTHORIZATION=self.admin_auth,
            )

        self.assertEqual(res.status_code, 200, res.data)

    def test_assign_role_and_remove_role_take_the_same_lock(self):
        cashier = self.make_user('lock_cashier', groups=[CASHIER_GROUP])

        with CaptureQueriesContext(connection) as assign_captured:
            assigned = self.client.post(
                f'{USERS_URL}{cashier.pk}/assign_role/',
                {'group_name': CASHIER_GROUP},
                format='json',
                HTTP_AUTHORIZATION=self.admin_auth,
            )
        self.assertEqual(assigned.status_code, 200, assigned.data)
        self.assertTrue(
            self._admin_locks(assign_captured.captured_queries),
            'assign_role must lock the admin rows before deciding')

        with CaptureQueriesContext(connection) as remove_captured:
            removed = self.client.post(
                f'{USERS_URL}{cashier.pk}/remove_role/',
                {'group_name': CASHIER_GROUP},
                format='json',
                HTTP_AUTHORIZATION=self.admin_auth,
            )
        self.assertEqual(removed.status_code, 200, removed.data)
        self.assertTrue(
            self._admin_locks(remove_captured.captured_queries),
            'remove_role must lock the admin rows before deciding')


class DeactivatedUserTokenTests(AdminAuthorityTestBase):
    """Deactivation takes effect on tokens already handed out."""

    def test_deactivated_users_access_token_is_rejected(self):
        cashier = self.make_user('cashier4', groups=[CASHIER_GROUP])
        auth = self.auth(cashier)
        self.assertEqual(
            self.client.get(ME_URL, HTTP_AUTHORIZATION=auth).status_code, 200)

        User.objects.filter(pk=cashier.pk).update(is_active=False)

        self.assertEqual(
            self.client.get(ME_URL, HTTP_AUTHORIZATION=auth).status_code, 401)
