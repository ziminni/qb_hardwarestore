# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# The same directives and reasons as apps/inventory/tests.py: this checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into Django's test client, which
# forwards unknown kwargs into the WSGI environ (pyright reads that string as `follow=`).

"""Phase 2 Task 4 — alert resolution (decision 06 + P2 Ruling).

Two things are being pinned here, and they are different problems:

* **Alerts are system-generated.** Nobody, of any role, may POST/PUT/PATCH/DELETE an
  alert: a hand-written "low stock" row is a lie the dashboard would believe. The
  viewset is read-only, so those verbs answer **405** to everybody — including Admin.
* **Resolving is a business act with a name on it.** The P2 Ruling widened `resolve`
  from Admin-only to the existing `IsInventoryRole` class (Stock Manager + Store
  Manager + Admin), because the stocker is the person who restocks and therefore the
  person who clears the alert. `resolved_by` / `resolved_at` are the audit trail, and a
  second resolve is refused (400 `ALERT_ALREADY_RESOLVED`) instead of silently
  overwriting who actually dealt with it.

Real JWT logins (no ``force_authenticate``) and a random per-run password: the
permission classes read the authenticated user's GROUP membership, so the login path is
part of what is under test.
"""

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from .models import SystemAlert
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
ALERTS_URL = '/api/v1/alerts/'


class AlertResolveTestBase(InventoryTestBase):
    """One user per role, real JWT logins, one unresolved alert."""

    def setUp(self):
        super().setUp()
        # APIClient, not Django's test client: `InventoryTestBase` inherits `TestCase`,
        # whose client cannot encode `format='json'`.
        self.client = APIClient()
        self.password = get_random_string(16)
        self.stocker = self._make_user('alert_stocker', 'Stock Manager')
        self.manager = self._make_user('alert_manager', 'Store Manager')
        self.cashier = self._make_user('alert_cashier', 'Cashier')
        self.foreman = self._make_user('alert_foreman', 'Site Foreman')
        # Deny by default: a user with no role group at all.
        self.nobody = self._make_user('alert_nobody')
        self.alert = SystemAlert.objects.create(
            alert_type=SystemAlert.AlertType.LOW_STOCK,
            variant=self.variant,
            message='Portland Cement 40kg is at 3 bag(s), below the threshold of 5.',
        )

    # -- fixture helpers ---------------------------------------------------
    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username, email=f'{username}@example.com',
            password=self.password, full_name=username)
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self, user):
        login = APIClient().post(
            LOGIN_URL, {'username': user.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f"Bearer {login.data['access']}"}

    def _resolve(self, user):
        return self.client.post(
            f'{ALERTS_URL}{self.alert.pk}/resolve/', format='json',
            **self._auth(user))


class ResolveAllowedTests(AlertResolveTestBase):
    """Stock Manager (the restocker) and Store Manager may resolve."""

    def test_stock_manager_resolve_records_resolver_and_timestamp(self):
        response = self._resolve(self.stocker)

        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['is_resolved'])
        self.assertEqual(response.data['resolved_by'], self.stocker.pk)
        self.assertEqual(response.data['resolved_by_name'], 'alert_stocker')
        self.assertIsNotNone(response.data['resolved_at'])

        self.alert.refresh_from_db()
        self.assertTrue(self.alert.is_resolved)
        self.assertEqual(self.alert.resolved_by, self.stocker)
        self.assertIsNotNone(self.alert.resolved_at)

    def test_store_manager_resolve_records_resolver(self):
        response = self._resolve(self.manager)

        self.assertEqual(response.status_code, 200, response.data)
        self.alert.refresh_from_db()
        self.assertTrue(self.alert.is_resolved)
        self.assertEqual(self.alert.resolved_by, self.manager)


class ResolveDeniedTests(AlertResolveTestBase):
    """Everyone else gets 403 and the alert is untouched."""

    def _assert_denied(self, user):
        response = self._resolve(user)

        self.assertEqual(response.status_code, 403, response.data)
        self.alert.refresh_from_db()
        self.assertFalse(self.alert.is_resolved)
        self.assertIsNone(self.alert.resolved_by)
        self.assertIsNone(self.alert.resolved_at)

    def test_cashier_cannot_resolve(self):
        self._assert_denied(self.cashier)

    def test_foreman_cannot_resolve(self):
        self._assert_denied(self.foreman)

    def test_groupless_user_cannot_resolve(self):
        self._assert_denied(self.nobody)


class ResolveIdempotencyTests(AlertResolveTestBase):
    def test_second_resolve_is_refused_and_keeps_first_resolver(self):
        self.assertEqual(self._resolve(self.stocker).status_code, 200)

        response = self._resolve(self.manager)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'ALERT_ALREADY_RESOLVED')
        self.assertTrue(response.data['detail'])
        # The trail names the person who actually fixed it, not the last caller.
        self.alert.refresh_from_db()
        self.assertEqual(self.alert.resolved_by, self.stocker)

    def test_resolving_an_unknown_alert_is_404(self):
        response = self.client.post(
            f'{ALERTS_URL}999999/resolve/', format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 404)


class AlertWriteForbiddenTests(AlertResolveTestBase):
    """Alerts are system-generated: every non-`resolve` verb is 405, for everyone."""

    def test_post_to_collection_is_method_not_allowed(self):
        response = self.client.post(
            ALERTS_URL,
            {'alert_type': 'LOW_STOCK', 'variant': self.variant.pk,
             'message': 'Hand-written alert'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 405, response.data)
        self.assertEqual(SystemAlert.objects.count(), 1)

    def test_admin_cannot_post_either(self):
        admin = self._make_user('alert_admin', 'Admin')

        response = self.client.post(
            ALERTS_URL,
            {'alert_type': 'LOW_STOCK', 'variant': self.variant.pk,
             'message': 'Hand-written alert'},
            format='json', **self._auth(admin))

        self.assertEqual(response.status_code, 405, response.data)
        self.assertEqual(SystemAlert.objects.count(), 1)

    def test_patch_detail_is_method_not_allowed(self):
        response = self.client.patch(
            f'{ALERTS_URL}{self.alert.pk}/', {'is_resolved': True},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 405, response.data)
        self.alert.refresh_from_db()
        self.assertFalse(self.alert.is_resolved)

    def test_delete_detail_is_method_not_allowed(self):
        response = self.client.delete(
            f'{ALERTS_URL}{self.alert.pk}/', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 405, response.data)
        self.assertTrue(SystemAlert.objects.filter(pk=self.alert.pk).exists())


class AlertReadContractTests(AlertResolveTestBase):
    """The client screens read alerts, so reads stay open to any authenticated user."""

    def test_cashier_can_still_list_alerts(self):
        response = self.client.get(ALERTS_URL, **self._auth(self.cashier))

        self.assertEqual(response.status_code, 200, response.data)
        rows = response.data.get('results', response.data)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['id'], self.alert.pk)

    def test_listed_alert_carries_the_trail_fields_as_null_before_resolve(self):
        response = self.client.get(ALERTS_URL, **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        row = response.data.get('results', response.data)[0]
        self.assertIsNone(row['resolved_by'])
        self.assertIsNone(row['resolved_by_name'])
        self.assertIsNone(row['resolved_at'])

    def test_anonymous_list_is_rejected(self):
        self.assertEqual(self.client.get(ALERTS_URL).status_code, 401)
