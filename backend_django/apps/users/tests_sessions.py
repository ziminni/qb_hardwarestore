# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/users/tests_audit.py: without django-stubs this
# checker cannot see `User.objects` or that the test client forwards `**extra` kwargs
# (``REMOTE_ADDR``) into the WSGI environ — which is HOW the address is set here.
"""Phase 2 Task 6 — login lockout and session revocation.

Two properties, each of which silently does nothing when it is only half-wired:

* **A password cannot be guessed at speed.** Five failures for one
  ``(identifier, address)`` pair lock that pair for 15 minutes, and the sixth attempt is
  answered 429 **without the password being checked** — a lockout that still validates
  the password is an oracle, not a lockout. The lockout is scoped per client address, so
  one noisy cashier terminal cannot lock the store out, and it is kept in the cache, so
  it expires by itself. Every failure writes a ``LOGIN_FAILED`` audit row and the
  description never contains the password.

* **A session ends when the client says it does.** ``logout`` blacklists the caller's
  own refresh token; a rotated (already-used) refresh token is refused because
  ``BLACKLIST_AFTER_ROTATION`` is active only once the blacklist app is installed; and a
  **deactivated** account's refresh token is refused. Logout itself always answers 204:
  locally, signing out must never fail because of a bad or foreign token.

``cache.clear()`` in ``setUp`` is not optional: the lockout counter is process-wide
state, and a leaked counter makes an unrelated test stop at a 429 days later.
"""

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from django.utils.crypto import get_random_string

from .models import AuditLog

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
REFRESH_URL = '/api/v1/auth/refresh/'
LOGOUT_URL = '/api/v1/auth/logout/'

LOCKED_CODE = 'LOGIN_LOCKED'
LOCKED_DETAIL = 'Too many failed sign-in attempts'
MAX_FAILURES = 5
WINDOW_SECONDS = 15 * 60


class SessionTestCase(TestCase):
    """Two active accounts plus the request helpers every case needs."""

    def setUp(self):
        cache.clear()
        self.password = get_random_string(12)
        self.other_password = get_random_string(12)
        self.user = User.objects.create_user(
            username='cashier_a', email='a@x.com', password=self.password,
            full_name='Cash A')
        self.other = User.objects.create_user(
            username='cashier_b', email='b@x.com', password=self.other_password,
            full_name='Cash B')

    def login(self, identifier, password, **extra):
        return self.client.post(
            LOGIN_URL, {'identifier': identifier, 'password': password},
            content_type='application/json', **extra)

    def tokens(self, user, password):
        res = self.login(user.username, password)
        self.assertEqual(res.status_code, 200, res.content)
        return res.json()

    def refresh(self, token):
        return self.client.post(
            REFRESH_URL, {'refresh': token}, content_type='application/json')

    def logout(self, access, body):
        return self.client.post(
            LOGOUT_URL, body, content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {access}')

    def failures(self):
        return AuditLog.objects.filter(action_type=AuditLog.ActionType.LOGIN_FAILED)


class LoginLockoutTests(SessionTestCase):
    def test_five_failures_lock_the_pair_even_for_the_correct_password(self):
        for _ in range(MAX_FAILURES):
            self.assertEqual(self.login('cashier_a', 'wrong-password').status_code, 400)

        res = self.login('cashier_a', self.password)

        self.assertEqual(res.status_code, 429)
        body = res.json()
        self.assertEqual(body['code'], LOCKED_CODE)
        self.assertIn(LOCKED_DETAIL, body['detail'])
        self.assertGreater(body['retry_after'], 0)
        self.assertLessEqual(body['retry_after'], WINDOW_SECONDS)
        # The password was never checked, so no session was issued.
        self.assertNotIn('access', body)
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.LOGIN).exists())

    def test_lockout_is_scoped_to_the_client_address(self):
        for _ in range(MAX_FAILURES):
            self.login('cashier_a', 'wrong-password', REMOTE_ADDR='10.0.0.1')

        locked = self.login('cashier_a', self.password, REMOTE_ADDR='10.0.0.1')
        self.assertEqual(locked.status_code, 429)

        elsewhere = self.login('cashier_a', self.password, REMOTE_ADDR='10.0.0.2')
        self.assertEqual(elsewhere.status_code, 200)

    def test_success_resets_the_counter(self):
        for _ in range(MAX_FAILURES - 1):
            self.assertEqual(self.login('cashier_a', 'wrong-password').status_code, 400)

        self.assertEqual(self.login('cashier_a', self.password).status_code, 200)

        # Four more failures would reach the limit only if the success had not reset it.
        for _ in range(MAX_FAILURES - 1):
            self.assertEqual(self.login('cashier_a', 'wrong-password').status_code, 400)
        self.assertEqual(self.login('cashier_a', self.password).status_code, 200)

    def test_lockout_lifts_when_the_counter_is_gone(self):
        for _ in range(MAX_FAILURES):
            self.login('cashier_a', 'wrong-password')
        self.assertEqual(self.login('cashier_a', self.password).status_code, 429)

        cache.clear()  # what the 15-minute window does on its own

        self.assertEqual(self.login('cashier_a', self.password).status_code, 200)

    def test_each_failure_is_audited_without_the_password(self):
        for _ in range(MAX_FAILURES):
            self.login('cashier_a', 'pw-MARKER-12345')

        rows = self.failures()
        self.assertEqual(rows.count(), MAX_FAILURES)
        for row in rows:
            self.assertEqual(row.user_id, self.user.pk)
            self.assertEqual(row.username_snapshot, 'cashier_a')
            self.assertNotIn('pw-MARKER-12345', row.description)

        # The locked attempt is refused before the password is checked: no new row.
        self.login('cashier_a', self.password)
        self.assertEqual(self.failures().count(), MAX_FAILURES)

    def test_unknown_identifier_is_recorded_by_snapshot_only(self):
        ghost = 'ghost-' + get_random_string(200)

        self.assertEqual(self.login(ghost, 'pw-MARKER-12345').status_code, 400)

        row = self.failures().get()
        self.assertIsNone(row.user_id)
        self.assertEqual(row.username_snapshot, ghost[:150])
        self.assertNotIn('pw-MARKER-12345', row.description)

    def test_unknown_user_and_wrong_password_are_indistinguishable(self):
        unknown = self.login('no-such-user', 'pw-MARKER-12345')
        wrong = self.login('cashier_a', 'pw-MARKER-12345')

        self.assertEqual(unknown.status_code, 400)
        self.assertEqual(unknown.status_code, wrong.status_code)
        self.assertEqual(unknown.content, wrong.content)

    def test_disabled_account_attempts_count_as_failures(self):
        User.objects.filter(pk=self.other.pk).update(is_active=False)

        for _ in range(MAX_FAILURES):
            res = self.login('cashier_b', self.other_password)
            self.assertEqual(res.status_code, 400)
            self.assertIn('disabled', res.content.decode())

        res = self.login('cashier_b', self.other_password)
        self.assertEqual(res.status_code, 429)
        self.assertEqual(res.json()['code'], LOCKED_CODE)
        self.assertEqual(
            self.failures().filter(user=self.other).count(), MAX_FAILURES)


class SessionRevocationTests(SessionTestCase):
    def test_logout_blacklists_the_callers_refresh_token(self):
        pair = self.tokens(self.user, self.password)

        res = self.logout(pair['access'], {'refresh': pair['refresh']})

        self.assertEqual(res.status_code, 204)
        self.assertEqual(self.refresh(pair['refresh']).status_code, 401)
        self.assertTrue(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.LOGOUT).exists())

    def test_rotated_refresh_token_cannot_be_reused(self):
        pair = self.tokens(self.user, self.password)

        rotated = self.refresh(pair['refresh'])
        self.assertEqual(rotated.status_code, 200)
        self.assertNotEqual(rotated.json()['refresh'], pair['refresh'])

        self.assertEqual(self.refresh(pair['refresh']).status_code, 401)
        self.assertEqual(self.refresh(rotated.json()['refresh']).status_code, 200)

    def test_logout_ignores_another_users_refresh_token(self):
        mine = self.tokens(self.user, self.password)
        theirs = self.tokens(self.other, self.other_password)

        res = self.logout(mine['access'], {'refresh': theirs['refresh']})

        self.assertEqual(res.status_code, 204)
        self.assertEqual(self.refresh(theirs['refresh']).status_code, 200)

    def test_logout_always_succeeds(self):
        pair = self.tokens(self.user, self.password)

        for body in ({}, {'refresh': ''}, {'refresh': 'not-a-token'}, {'refresh': 42}):
            self.assertEqual(self.logout(pair['access'], body).status_code, 204)

    def test_deactivated_users_refresh_token_is_refused(self):
        pair = self.tokens(self.user, self.password)

        User.objects.filter(pk=self.user.pk).update(is_active=False)

        res = self.refresh(pair['refresh'])
        self.assertEqual(res.status_code, 401)
