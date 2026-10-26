# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Phase 5 Task 1 — user-write contract locks (decision 04 + grill).

Deactivation and role changes are Store Manager/Admin-only UI actions. The
server already refuses everyone else with 403; these tests pin that refusal
at HTTP level for the exact verbs the new UI uses (PATCH, assign_role,
remove_role), so a later serializer change cannot silently open them.
"""

from .tests_admin_authority import (
    ADMIN_GROUP,
    CASHIER_GROUP,
    LOGIN_URL,
    USERS_URL,
    AdminAuthorityTestBase,
)


class CashierUserWriteForbiddenTests(AdminAuthorityTestBase):
    """A cashier may not touch accounts through any user-write verb."""

    def setUp(self):
        super().setUp()
        self.admin = self.make_user('p5_admin', groups=[ADMIN_GROUP])
        self.target = self.make_user('p5_target', groups=[CASHIER_GROUP])
        self.cashier = self.make_user('p5_cashier', groups=[CASHIER_GROUP])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'p5_cashier', 'password': self.password},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)
        self.auth_header = f"Bearer {login.data['access']}"

    def test_cashier_patch_is_active_is_forbidden_and_changes_nothing(self):
        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.target.refresh_from_db()
        self.assertTrue(self.target.is_active)

    def test_cashier_assign_role_is_forbidden(self):
        res = self.client.post(
            f'{USERS_URL}{self.target.pk}/assign_role/',
            {'group_name': ADMIN_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.assertEqual(
            list(self.target.groups.values_list('name', flat=True)),
            [CASHIER_GROUP],
        )

    def test_cashier_remove_role_is_forbidden(self):
        res = self.client.post(
            f'{USERS_URL}{self.target.pk}/remove_role/',
            {'group_name': CASHIER_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.assertEqual(
            list(self.target.groups.values_list('name', flat=True)),
            [CASHIER_GROUP],
        )


class DeactivateReactivateRoundTripTests(AdminAuthorityTestBase):
    """Deactivation is reversible: the UI offers reactivate on inactive rows."""

    def setUp(self):
        super().setUp()
        self.admin = self.make_user('p5_admin2', groups=[ADMIN_GROUP])
        self.second_admin = self.make_user('p5_admin3', groups=[ADMIN_GROUP])
        self.target = self.make_user('p5_target2', groups=[CASHIER_GROUP])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'p5_admin2', 'password': self.password},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)
        self.auth_header = f"Bearer {login.data['access']}"

    def test_deactivate_then_reactivate_restores_the_account(self):
        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.target.refresh_from_db()
        self.assertFalse(self.target.is_active)

        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'is_active': True},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.target.refresh_from_db()
        self.assertTrue(self.target.is_active)


class StoreManagerUserWriteTests(AdminAuthorityTestBase):
    """Store Manager is an admin-role peer for user writes (decision 06 pattern)."""

    def setUp(self):
        super().setUp()
        from .tests_admin_authority import ADMIN_GROUP as _A  # noqa: F401
        self.store_manager = self.make_user(
            'p5_manager', groups=['Store Manager'])
        self.second_admin = self.make_user('p5_admin4', groups=[ADMIN_GROUP])
        self.target = self.make_user('p5_target3', groups=[CASHIER_GROUP])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'p5_manager', 'password': self.password},
            format='json',
        )
        self.assertEqual(login.status_code, 200, login.data)
        self.auth_header = f"Bearer {login.data['access']}"

    def test_store_manager_may_deactivate_a_cashier(self):
        res = self.client.patch(
            f'{USERS_URL}{self.target.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.target.refresh_from_db()
        self.assertFalse(self.target.is_active)

    def test_store_manager_may_assign_a_role(self):
        res = self.client.post(
            f'{USERS_URL}{self.target.pk}/assign_role/',
            {'group_name': 'Store Manager'},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 200, res.data)

    def test_store_manager_cannot_deactivate_an_admin(self):
        res = self.client.patch(
            f'{USERS_URL}{self.second_admin.pk}/',
            {'is_active': False},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.assertEqual(res.data['code'], 'USER_ADMIN_FORBIDDEN')
        self.second_admin.refresh_from_db()
        self.assertTrue(self.second_admin.is_active)

    def test_store_manager_cannot_grant_the_admin_group(self):
        res = self.client.post(
            f'{USERS_URL}{self.target.pk}/assign_role/',
            {'group_name': ADMIN_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.assertEqual(res.data['code'], 'USER_ADMIN_FORBIDDEN')
        self.assertEqual(
            list(self.target.groups.values_list('name', flat=True)),
            ['Cashier'],
        )

    def test_store_manager_cannot_remove_the_admin_group(self):
        res = self.client.post(
            f'{USERS_URL}{self.second_admin.pk}/remove_role/',
            {'group_name': ADMIN_GROUP},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        self.assertEqual(res.data['code'], 'USER_ADMIN_FORBIDDEN')

    def test_store_manager_cannot_revive_a_deactivated_admin(self):
        from .tests_admin_authority import ADMIN_GROUP as _keep  # noqa: F401
        dormant = self.make_user('p5_dormant', groups=[ADMIN_GROUP])
        dormant.is_active = False
        dormant.save()
        res = self.client.patch(
            f'{USERS_URL}{dormant.pk}/',
            {'is_active': True},
            format='json',
            HTTP_AUTHORIZATION=self.auth_header,
        )
        self.assertEqual(res.status_code, 403, res.data)
        dormant.refresh_from_db()
        self.assertFalse(dormant.is_active)
