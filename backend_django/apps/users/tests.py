"""Users app tests — auth flow, registration rules, users/stats."""

from django.contrib.auth import get_user_model
from django.test import TestCase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
REFRESH_URL = '/api/v1/auth/refresh/'
LOGOUT_URL = '/api/v1/auth/logout/'
ME_URL = '/api/v1/auth/me/'
REGISTER_URL = '/api/v1/auth/register/'
USERS_URL = '/api/v1/users/'
STATS_URL = '/api/v1/users/stats/'


class AuthFlowTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin1', email='admin@x.com', password='pass12345',
            full_name='Ad Min', is_staff=True, is_superuser=True)

    def test_login_with_username(self):
        res = self.client.post(
            LOGIN_URL,
            {'username': 'admin1', 'password': 'pass12345'},
            content_type='application/json')
        self.assertEqual(res.status_code, 200)
        self.assertIn('access', res.json())

    def test_login_with_email(self):
        res = self.client.post(
            LOGIN_URL,
            {'username': 'admin@x.com', 'password': 'pass12345'},
            content_type='application/json')
        self.assertEqual(res.status_code, 200)

    def test_login_wrong_password(self):
        res = self.client.post(
            LOGIN_URL,
            {'username': 'admin1', 'password': 'wrong'},
            content_type='application/json')
        self.assertIn(res.status_code, (400, 401))

    def test_me_requires_auth(self):
        self.assertEqual(self.client.get(ME_URL).status_code, 401)

    def _auth(self, username='admin1', password='pass12345'):
        """Login and return an Authorization header (API is JWT-only)."""
        login = self.client.post(
            LOGIN_URL, {'username': username, 'password': password},
            content_type='application/json').json()
        return f"Bearer {login['access']}"

    def test_refresh_and_logout(self):
        auth = self._auth()
        login = self.client.post(
            LOGIN_URL,
            {'username': 'admin1', 'password': 'pass12345'},
            content_type='application/json').json()
        refresh = self.client.post(
            REFRESH_URL, {'refresh': login['refresh']},
            content_type='application/json')
        self.assertEqual(refresh.status_code, 200)
        logout = self.client.post(
            LOGOUT_URL, {'refresh': login['refresh']},
            content_type='application/json',
            HTTP_AUTHORIZATION=auth)
        self.assertEqual(logout.status_code, 204)

    def test_register_requires_admin(self):
        res = self.client.post(
            REGISTER_URL,
            {'username': 'newbie', 'email': 'n@x.com',
             'password': 'pass12345', 'full_name': 'New Bie'},
            content_type='application/json')
        self.assertEqual(res.status_code, 401)

    def test_register_requires_group_name(self):
        auth = self._auth()
        res = self.client.post(
            REGISTER_URL,
            {'username': 'newbie', 'email': 'n@x.com',
             'password': 'pass12345', 'full_name': 'New Bie'},
            content_type='application/json', HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 400)

    def test_register_with_group_creates_user(self):
        from django.contrib.auth.models import Group
        Group.objects.get_or_create(name='Cashier')
        auth = self._auth()
        res = self.client.post(
            REGISTER_URL,
            {'username': 'newbie', 'email': 'n@x.com',
             'password': 'pass12345', 'full_name': 'New Bie',
             'group_name': 'Cashier'},
            content_type='application/json', HTTP_AUTHORIZATION=auth)
        self.assertEqual(res.status_code, 201)
        self.assertTrue(User.objects.filter(username='newbie').exists())
        self.assertEqual(res.json()['role']['display_name'], 'Cashier')


class UserStatsTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='admin1', email='admin@x.com', password='pass12345',
            is_staff=True, is_superuser=True)
        User.objects.create_user(
            username='u2', email='u2@x.com', password='pass12345')
        User.objects.create_user(
            username='u3', email='u3@x.com', password='pass12345',
            is_active=False)

    def _auth(self):
        login = self.client.post(
            LOGIN_URL,
            {'username': 'admin1', 'password': 'pass12345'},
            content_type='application/json').json()
        return f"Bearer {login['access']}"

    def test_stats_requires_authentication(self):
        self.assertEqual(self.client.get(STATS_URL).status_code, 401)

    def test_stats_counts(self):
        res = self.client.get(STATS_URL, HTTP_AUTHORIZATION=self._auth())
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data['total'], 3)
        self.assertEqual(data['active'], 2)
        self.assertEqual(data['inactive'], 1)

    def test_search_by_username(self):
        res = self.client.get(USERS_URL, {'search': 'u3'},
                              HTTP_AUTHORIZATION=self._auth())
        self.assertEqual(res.status_code, 200)
        results = res.json()
        results = results['results'] if isinstance(results, dict) else results
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]['username'], 'u3')

