#!/usr/bin/env python
# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/pos/tests.py: this checker runs with
# a working directory outside the repo, so no pyrightconfig.json is found and every
# `Model.objects` access and `self.client.get(...).status_code` is a false positive on
# valid Django. Django's own `manage.py check` and the test run remain the authority.
"""CPMS boundary tests (Phase 1, Task 2): the service account and its fence.

The fence lives in ONE place (the default authentication class, see
`apps/users/authentication.py`), so the sweep below is built from the URL resolver
rather than a hand-written list: a route added next month is covered without anyone
remembering to add it here.
"""

import re
from typing import Any

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
from django.urls import get_resolver

from apps.pos.models import Customer

User = get_user_model()

CPMS_URL = '/api/v1/integration/cpms/'
CUSTOMERS_URL = f'{CPMS_URL}customers/'
LOGIN_URL = '/api/v1/auth/login/'
# Signing in and refreshing are credential endpoints, not POS data: the fence lets the
# account through them (see `CREDENTIAL_PATHS` in apps/users/authentication.py), so the
# sweep below does not ask the fence about them. `test_the_cpms_account_may_still_log_in
# _and_refresh` covers them instead.
UNFENCED_ROUTES = {'/api/v1/auth/login/', '/api/v1/auth/refresh/'}
CPMS_GROUP = 'CPMS Service'
# The fixture credential this suite signs in with - a test password, not a secret.
CPMS_LOGIN = 'cpms-pass-123'


def v1_get_paths():
    """Every leaf route under ``/api/v1/`` with its path params filled with 1.

    Read from the resolver so the fence is checked against the real route table. The
    DRF format-suffix twins (``users.(?P<format>json)``) are the same view in another
    serialization and are skipped, and so is the router's API root.
    """
    paths = []

    def walk(patterns, prefix):
        for pattern in patterns:
            route = prefix + str(pattern.pattern)
            if hasattr(pattern, 'url_patterns'):
                walk(pattern.url_patterns, route)
            elif 'format' not in route:
                # Regex groups `(?P<pk>[^/.]+)` and converters `<int:pk>` both become 1.
                filled = re.sub(r'\(\?P<\w+>[^)]*\)|<[\w:]+>', '1', route)
                paths.append('/' + filled.replace('^', '').replace('$', ''))

    resolver: Any = get_resolver()
    for pattern in resolver.url_patterns:
        name = str(pattern.pattern)
        if name.startswith('api/v1/') and hasattr(pattern, 'url_patterns'):
            walk(pattern.url_patterns, name)
    return sorted(set(paths))


def make_user(username, group=None, password=CPMS_LOGIN):
    user = User.objects.create_user(
        username=username, email=f'{username}@x.com', password=password,
        full_name=username)
    if group:
        user.groups.add(Group.objects.get_or_create(name=group)[0])
    return user


class CpmsTestCase(TestCase):
    """Fixtures shared by every case: one CPMS account plus one of each customer type."""

    def setUp(self):
        self.cpms = make_user('cpms_service', CPMS_GROUP)
        self.contractor = Customer.objects.create(
            name='Reyes Contracting', customer_type=Customer.Type.CONTRACTOR)
        self.firm = Customer.objects.create(
            name='Buildright Construction',
            customer_type=Customer.Type.CONSTRUCTION_FIRM)
        self.walk_in = Customer.objects.create(
            name='Walk-in Customer', customer_type=Customer.Type.WALK_IN)
        self.regular = Customer.objects.create(
            name='Aling Nena Sari-sari', customer_type=Customer.Type.REGULAR)
        self.gone_contractor = Customer.objects.create(
            name='Closed Contracting', customer_type=Customer.Type.CONTRACTOR,
            is_active=False)

    def login(self, username, password=CPMS_LOGIN):
        res = self.client.post(
            LOGIN_URL, {'username': username, 'password': password},
            content_type='application/json')
        self.assertEqual(res.status_code, 200, res.content)
        return f"Bearer {res.json()['access']}"

    def cpms_auth(self):
        return self.login(self.cpms.username)


class FenceTests(CpmsTestCase):
    """The service account may reach its own namespace and nothing else."""

    def test_the_sweep_covers_the_route_table(self):
        paths = v1_get_paths()
        self.assertGreater(len(paths), 40, paths)
        self.assertIn(CUSTOMERS_URL, paths)

    def test_cpms_account_is_refused_everywhere_outside_its_namespace(self):
        auth = self.cpms_auth()
        refused = []
        for path in v1_get_paths():
            if path.startswith(CPMS_URL) or path in UNFENCED_ROUTES:
                continue
            res = self.client.get(path, HTTP_AUTHORIZATION=auth)
            code = None
            if res.headers.get('Content-Type', '').startswith('application/json'):
                code = res.json().get('code')
            if res.status_code != 403 or code != 'CPMS_SCOPE':
                refused.append((path, res.status_code, code))
        self.assertEqual(refused, [], 'not 403 CPMS_SCOPE')

    def test_the_cpms_account_may_still_log_in_and_refresh(self):
        # The fence must never lock the account out of its own credentials, even when the
        # client sends its OLD token along with the login - the Flutter client attaches
        # one to every request, and a CPMS client written the same way would otherwise
        # be stuck on 403 for ever.
        stale = self.cpms_auth()
        login = self.client.post(
            LOGIN_URL,
            {'username': self.cpms.username, 'password': CPMS_LOGIN},
            content_type='application/json', HTTP_AUTHORIZATION=stale)
        self.assertEqual(login.status_code, 200, login.content)
        res = self.client.post(
            '/api/v1/auth/refresh/', {'refresh': login.json()['refresh']},
            content_type='application/json', HTTP_AUTHORIZATION=stale)
        self.assertEqual(res.status_code, 200, res.content)
        self.assertIn('access', res.json())


class CpmsCustomerListTests(CpmsTestCase):
    def test_lists_active_contractors_and_firms_only(self):
        res = self.client.get(CUSTOMERS_URL, HTTP_AUTHORIZATION=self.cpms_auth())
        self.assertEqual(res.status_code, 200, res.content)
        rows = res.json()['results']
        self.assertEqual(
            [row['name'] for row in rows],
            ['Buildright Construction', 'Reyes Contracting'])

    def test_a_row_carries_no_balance_limit_or_contact(self):
        res = self.client.get(CUSTOMERS_URL, HTTP_AUTHORIZATION=self.cpms_auth())
        for row in res.json()['results']:
            self.assertEqual(set(row), {'id', 'name'})


class StaffCannotCallCpmsTests(CpmsTestCase):
    def test_every_staff_role_is_refused_on_the_cpms_namespace(self):
        for role in ('Cashier', 'Stock Manager', 'Store Manager', 'Admin'):
            with self.subTest(role=role):
                auth = self.login(make_user(role.lower().replace(' ', '_'), role).username)
                res = self.client.get(CUSTOMERS_URL, HTTP_AUTHORIZATION=auth)
                self.assertEqual(res.status_code, 403, res.content)


class UnauthenticatedTests(CpmsTestCase):
    def test_the_customer_list_requires_a_token(self):
        self.assertEqual(self.client.get(CUSTOMERS_URL).status_code, 401)


class DeactivatedCpmsAccountTests(CpmsTestCase):
    """Deactivating the account cuts CPMS off: no new login, no old token."""

    def test_a_deactivated_cpms_account_cannot_log_in(self):
        self.cpms.is_active = False
        self.cpms.save()
        res = self.client.post(
            LOGIN_URL,
            {'username': self.cpms.username, 'password': CPMS_LOGIN},
            content_type='application/json')
        self.assertEqual(res.status_code, 400, res.content)
        self.assertNotIn('access', res.json())

    def test_its_old_token_is_refused(self):
        auth = self.cpms_auth()
        self.cpms.is_active = False
        self.cpms.save()
        res = self.client.get(CUSTOMERS_URL, HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 401, res.content)
