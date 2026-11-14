# pyright: reportAttributeAccessIssue=false, reportMissingImports=false
#
# Same false-positive class documented in apps/users/models.py: this checker runs with a
# working directory outside the repo, so it resolves neither pyrightconfig.json nor
# django-stubs. `manage.py test` is the authority for these imports.
"""Phase 4 task B3 — several roles per account (decision 18).

``roles[]`` is the multi-role shape: the same role objects ``role`` already returns, one
per recognised group, in a stable order. ``role`` keeps its old meaning (the first group)
so an old client still reads a role; ``roles[]`` is what the area picker reads.

The guards that already existed must hold for EVERY role added or removed, and for a body
that mixes the two fields: ``USER_ADMIN_FORBIDDEN`` (a store manager never grants or
touches admin authority), ``LAST_ADMIN`` (the last active admin cannot be demoted, role
field or ``roles[]``, alone or combined with a deactivation), and the CPMS fence (the
service account holds no staff role and stays outside every POS namespace).
"""

from unittest import mock

from django.contrib.auth.models import Group
from django.db import connection
from django.test.utils import CaptureQueriesContext

from .models import AuditLog, User
from .tests_admin_authority import (
    ADMIN_GROUP,
    CASHIER_GROUP,
    LOGIN_URL,
    ME_URL,
    REGISTER_URL,
    USERS_URL,
    AdminAuthorityTestBase,
)

AUDIT_URL = "/api/v1/audit-logs/"
# Receivables: Cashier / Store Manager / Admin only (a Stock Manager reads sales, not
# customers' debts), so it tells an `inventory`-only account apart from one that also
# holds `sales`.
LEDGERS_URL = "/api/v1/ledgers/"
SALES_URL = "/api/v1/transactions/"
STORE_MANAGER_GROUP = "Store Manager"
STOCK_MANAGER_GROUP = "Stock Manager"
CPMS_GROUP = "CPMS Service"
ALL_GROUPS = (STORE_MANAGER_GROUP, STOCK_MANAGER_GROUP, CPMS_GROUP)


class RolesTestBase(AdminAuthorityTestBase):
    """Real JWT login plus the groups every role code needs to exist."""

    def setUp(self):
        super().setUp()
        for name in ALL_GROUPS:
            Group.objects.get_or_create(name=name)
        self.admin = self.make_user("roles_admin", groups=[ADMIN_GROUP])
        self.second_admin = self.make_user("roles_admin2", groups=[ADMIN_GROUP])
        self.admin_auth = self.auth(self.admin)

    def codes(self, payload):
        return [role["name"] for role in payload["roles"]]

    def only_admin_left(self):
        """Deactivate the second admin so ``self.admin`` is the last active one."""
        User.objects.filter(pk=self.second_admin.pk).update(is_active=False)

    def group_names(self, user):
        return sorted(user.groups.values_list("name", flat=True))


# ---------------------------------------------------------------------------
# Read shape: login, /auth/me/, /users/
# ---------------------------------------------------------------------------


class RoleListReadTests(RolesTestBase):
    def test_login_and_me_carry_every_role_in_stable_order(self):
        multi = self.make_user(
            "roles_multi", groups=[CASHIER_GROUP, STOCK_MANAGER_GROUP, ADMIN_GROUP]
        )

        login = self.client.post(
            LOGIN_URL,
            {"username": "roles_multi", "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200, login.data)
        self.assertEqual(self.codes(login.data["user"]), ["admin", "inventory", "pos"])
        self.assertEqual(login.data["user"]["role"]["name"], "admin")

        me = self.client.get(
            ME_URL, HTTP_AUTHORIZATION=f"Bearer {login.data['access']}"
        )
        self.assertEqual(me.status_code, 200, me.data)
        self.assertEqual(self.codes(me.data), ["admin", "inventory", "pos"])
        self.assertEqual(
            [role["display_name"] for role in me.data["roles"]],
            [ADMIN_GROUP, STOCK_MANAGER_GROUP, CASHIER_GROUP],
        )
        self.assertTrue(multi.is_active)

    def test_role_objects_keep_the_existing_shape(self):
        cashier = self.make_user("roles_shape", groups=[CASHIER_GROUP])
        res = self.client.get(
            f"{USERS_URL}{cashier.pk}/", HTTP_AUTHORIZATION=self.admin_auth
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(
            sorted(res.data["roles"][0]), ["display_name", "id", "name", "permissions"]
        )
        self.assertEqual(res.data["roles"][0]["name"], "pos")
        self.assertEqual(
            res.data["roles"][0]["id"],
            Group.objects.get(name=CASHIER_GROUP).pk,
        )
        self.assertEqual(res.data["role"], res.data["roles"][0])

    def test_role_field_keeps_the_first_group_for_old_clients(self):
        """``role`` is unchanged: the lowest-id group, never the widest code."""
        user = self.make_user("roles_legacy", groups=[CASHIER_GROUP])
        user.groups.add(Group.objects.get(name=STOCK_MANAGER_GROUP))
        res = self.client.get(
            f"{USERS_URL}{user.pk}/", HTTP_AUTHORIZATION=self.admin_auth
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["role"]["display_name"], CASHIER_GROUP)
        self.assertEqual(self.codes(res.data), ["inventory", "pos"])

    def test_roleless_historical_account_reads_empty_roles_and_null_role(self):
        legacy = self.make_user("roles_none")
        res = self.client.get(
            f"{USERS_URL}{legacy.pk}/", HTTP_AUTHORIZATION=self.admin_auth
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["roles"], [])
        self.assertIsNone(res.data["role"])

    def test_superuser_without_groups_reads_the_admin_area(self):
        root = self.make_user("roles_root", is_superuser=True, is_staff=True)
        res = self.client.get(
            f"{USERS_URL}{root.pk}/", HTTP_AUTHORIZATION=self.admin_auth
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.codes(res.data), ["admin"])
        self.assertEqual(res.data["roles"][0]["id"], 0)

    def test_cpms_service_account_carries_no_staff_roles(self):
        cpms = self.make_user("roles_cpms", groups=[CPMS_GROUP])
        res = self.client.get(
            f"{USERS_URL}{cpms.pk}/", HTTP_AUTHORIZATION=self.admin_auth
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(res.data["roles"], [])
        self.assertEqual(res.data["role"]["display_name"], CPMS_GROUP)


# ---------------------------------------------------------------------------
# Write paths: register, PATCH, assign_role, remove_role
# ---------------------------------------------------------------------------


class MultiRoleWriteTests(RolesTestBase):
    def test_register_accepts_roles_and_grants_every_group(self):
        res = self.client.post(
            REGISTER_URL,
            {
                "username": "roles_new",
                "email": "roles_new@example.com",
                "password": "pass12345",
                "full_name": "New Hire",
                "roles": ["pos", "inventory"],
            },
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 201, res.data)
        self.assertEqual(self.codes(res.data), ["inventory", "pos"])
        created = User.objects.get(username="roles_new")
        self.assertEqual(
            self.group_names(created), sorted([CASHIER_GROUP, STOCK_MANAGER_GROUP])
        )

    def test_patch_roles_replaces_memberships(self):
        target = self.make_user("roles_patch", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["pos", "sales"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.codes(res.data), ["sales", "pos"])
        self.assertEqual(
            self.group_names(target),
            sorted([CASHIER_GROUP, STORE_MANAGER_GROUP]),
        )

    def test_assign_role_accepts_roles(self):
        target = self.make_user("roles_assign", groups=[CASHIER_GROUP])
        res = self.client.post(
            f"{USERS_URL}{target.pk}/assign_role/",
            {"roles": ["pos", "inventory"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.codes(res.data["user"]), ["inventory", "pos"])
        self.assertEqual(
            self.group_names(target),
            sorted([CASHIER_GROUP, STOCK_MANAGER_GROUP]),
        )

    def test_remove_role_accepts_roles(self):
        target = self.make_user(
            "roles_remove", groups=[CASHIER_GROUP, STOCK_MANAGER_GROUP]
        )
        res = self.client.post(
            f"{USERS_URL}{target.pk}/remove_role/",
            {"roles": ["inventory"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])
        self.assertEqual(self.codes(res.data["user"]), ["pos"])

    def test_legacy_group_name_still_assigns_one_role(self):
        target = self.make_user("roles_legacy_write", groups=[CASHIER_GROUP])
        res = self.client.post(
            f"{USERS_URL}{target.pk}/assign_role/",
            {"group_name": STOCK_MANAGER_GROUP},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.group_names(target), [STOCK_MANAGER_GROUP])
        self.assertEqual(self.codes(res.data["user"]), ["inventory"])

    def test_multi_role_account_reaches_both_areas(self):
        """The permission helpers must see both groups, not just the first one."""
        user = self.make_user("roles_areas", groups=[STOCK_MANAGER_GROUP])
        auth = self.auth(user)
        self.assertEqual(
            self.client.get(SALES_URL, HTTP_AUTHORIZATION=auth).status_code, 200
        )
        # A stock manager does not read receivables.
        self.assertEqual(
            self.client.get(LEDGERS_URL, HTTP_AUTHORIZATION=auth).status_code, 403
        )

        res = self.client.patch(
            f"{USERS_URL}{user.pk}/",
            {"roles": ["inventory", "sales"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)

        auth = self.auth(user)
        self.assertEqual(
            self.client.get(LEDGERS_URL, HTTP_AUTHORIZATION=auth).status_code, 200
        )
        self.assertEqual(
            self.client.get(SALES_URL, HTTP_AUTHORIZATION=auth).status_code, 200
        )


# ---------------------------------------------------------------------------
# Payload validation
# ---------------------------------------------------------------------------


class RolePayloadValidationTests(RolesTestBase):
    def assert_roles_refused(self, response, *, status_code=400):
        self.assertEqual(response.status_code, status_code, response.data)
        self.assertIn("roles", response.data, response.data)

    def test_empty_roles_is_refused(self):
        target = self.make_user("roles_empty", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": []},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_roles_refused(res)
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_unknown_role_code_is_refused(self):
        target = self.make_user("roles_unknown", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["warehouse"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_roles_refused(res)
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_duplicate_role_is_refused(self):
        target = self.make_user("roles_dupe", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["pos", "pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_roles_refused(res)
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_mixed_group_name_and_roles_is_refused_on_register(self):
        res = self.client.post(
            REGISTER_URL,
            {
                "username": "roles_mixed_reg",
                "email": "roles_mixed_reg@example.com",
                "password": "pass12345",
                "full_name": "Mixed",
                "group_name": CASHIER_GROUP,
                "roles": ["pos"],
            },
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data["code"], "ROLES_CONFLICT")
        self.assertFalse(User.objects.filter(username="roles_mixed_reg").exists())

    def test_mixed_payload_on_assign_role_is_refused(self):
        target = self.make_user("roles_mixed_assign", groups=[CASHIER_GROUP])
        res = self.client.post(
            f"{USERS_URL}{target.pk}/assign_role/",
            {"group_name": CASHIER_GROUP, "roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data["code"], "ROLES_CONFLICT")
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_mixed_payload_on_patch_is_refused(self):
        target = self.make_user("roles_mixed_patch", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"group_name": CASHIER_GROUP, "roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(res.data["code"], "ROLES_CONFLICT")
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_cpms_cannot_be_created_beside_a_staff_role(self):
        res = self.client.post(
            REGISTER_URL,
            {
                "username": "roles_cpms_mixed",
                "email": "roles_cpms_mixed@example.com",
                "password": "pass12345",
                "full_name": "Machine",
                "roles": ["cpms", "pos"],
            },
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_roles_refused(res)
        self.assertFalse(User.objects.filter(username="roles_cpms_mixed").exists())

    def test_cpms_cannot_be_added_to_a_staff_account(self):
        target = self.make_user("roles_cpms_add", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["pos", "cpms"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_roles_refused(res)
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])

    def test_cpms_role_change_keeps_the_account_non_staff_and_fenced(self):
        """A role write must not turn the service account into staff or a superuser."""
        target = self.make_user("roles_cpms_only", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["cpms"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        target.refresh_from_db()
        self.assertEqual(self.group_names(target), [CPMS_GROUP])
        self.assertFalse(target.is_staff)
        self.assertFalse(target.is_superuser)

        auth = self.auth(target)
        fenced = self.client.get(USERS_URL, HTTP_AUTHORIZATION=auth)
        self.assertEqual(fenced.status_code, 403, fenced.data)
        self.assertEqual(fenced.data["code"], "CPMS_SCOPE")


# ---------------------------------------------------------------------------
# Store Manager cannot reach admin authority through either field
# ---------------------------------------------------------------------------


class ManagerRoleGuardTests(RolesTestBase):
    def setUp(self):
        super().setUp()
        self.manager = self.make_user("roles_manager", groups=[STORE_MANAGER_GROUP])
        self.manager_auth = self.auth(self.manager)
        self.target = self.make_user("roles_managed", groups=[CASHIER_GROUP])

    def assert_forbidden(self, response):
        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data["code"], "USER_ADMIN_FORBIDDEN")

    def test_manager_cannot_grant_admin_through_roles(self):
        res = self.client.patch(
            f"{USERS_URL}{self.target.pk}/",
            {"roles": ["pos", "admin"]},
            format="json",
            HTTP_AUTHORIZATION=self.manager_auth,
        )
        self.assert_forbidden(res)
        self.assertEqual(self.group_names(self.target), [CASHIER_GROUP])

    def test_manager_cannot_mix_fields_to_reach_admin(self):
        res = self.client.post(
            f"{USERS_URL}{self.target.pk}/assign_role/",
            {"group_name": CASHIER_GROUP, "roles": ["admin"]},
            format="json",
            HTTP_AUTHORIZATION=self.manager_auth,
        )
        self.assert_forbidden(res)
        self.assertEqual(self.group_names(self.target), [CASHIER_GROUP])

    def test_manager_cannot_reach_admin_on_patch_with_mixed_fields(self):
        res = self.client.patch(
            f"{USERS_URL}{self.target.pk}/",
            {"group_name": "Admin", "roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.manager_auth,
        )
        self.assert_forbidden(res)
        self.assertEqual(self.group_names(self.target), [CASHIER_GROUP])

    def test_manager_cannot_replace_the_roles_of_an_admin_account(self):
        res = self.client.patch(
            f"{USERS_URL}{self.second_admin.pk}/",
            {"roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.manager_auth,
        )
        self.assert_forbidden(res)
        self.assertEqual(self.group_names(self.second_admin), [ADMIN_GROUP])

    def test_manager_may_assign_two_non_admin_roles(self):
        res = self.client.patch(
            f"{USERS_URL}{self.target.pk}/",
            {"roles": ["pos", "inventory"]},
            format="json",
            HTTP_AUTHORIZATION=self.manager_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(
            self.group_names(self.target),
            sorted([CASHIER_GROUP, STOCK_MANAGER_GROUP]),
        )


# ---------------------------------------------------------------------------
# LAST_ADMIN for every role path
# ---------------------------------------------------------------------------


class LastAdminRoleTests(RolesTestBase):
    def assert_last_admin(self, response):
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "LAST_ADMIN")

    def test_patch_roles_cannot_demote_the_last_admin(self):
        self.only_admin_left()
        res = self.client.patch(
            f"{USERS_URL}{self.admin.pk}/",
            {"roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_last_admin(res)
        self.assertEqual(self.group_names(self.admin), [ADMIN_GROUP])

    def test_assign_role_roles_cannot_demote_the_last_admin(self):
        self.only_admin_left()
        res = self.client.post(
            f"{USERS_URL}{self.admin.pk}/assign_role/",
            {"roles": ["sales"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_last_admin(res)
        self.assertEqual(self.group_names(self.admin), [ADMIN_GROUP])

    def test_remove_role_roles_cannot_drop_the_last_admins_admin(self):
        self.only_admin_left()
        res = self.client.post(
            f"{USERS_URL}{self.admin.pk}/remove_role/",
            {"roles": ["admin"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_last_admin(res)
        self.assertEqual(self.group_names(self.admin), [ADMIN_GROUP])

    def test_deactivate_and_demote_in_one_patch_is_refused(self):
        self.only_admin_left()
        res = self.client.patch(
            f"{USERS_URL}{self.admin.pk}/",
            {"is_active": False, "roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assert_last_admin(res)
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.is_active)
        self.assertEqual(self.group_names(self.admin), [ADMIN_GROUP])

    def test_demoting_one_of_two_admins_through_roles_is_allowed(self):
        res = self.client.patch(
            f"{USERS_URL}{self.second_admin.pk}/",
            {"roles": ["pos"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        self.assertEqual(self.group_names(self.second_admin), [CASHIER_GROUP])

    def test_patch_roles_locks_the_admin_rows_first(self):
        """Same decide-under-lock rule as the deactivation path (review F3)."""
        self.only_admin_left()

        with CaptureQueriesContext(connection) as captured:
            res = self.client.patch(
                f"{USERS_URL}{self.admin.pk}/",
                {"roles": ["pos"]},
                format="json",
                HTTP_AUTHORIZATION=self.admin_auth,
            )

        self.assert_last_admin(res)
        locks = [
            query["sql"]
            for query in captured.captured_queries
            if "FOR UPDATE" in query["sql"].upper() and "apps_users" in query["sql"]
        ]
        self.assertTrue(locks, "a role change must lock the rows it decides on")


# ---------------------------------------------------------------------------
# Audit trail
# ---------------------------------------------------------------------------


class RoleAuditTests(RolesTestBase):
    def role_rows(self):
        return AuditLog.objects.filter(action_type=AuditLog.ActionType.ROLE_CHANGE)

    def test_assign_role_roles_writes_one_row_naming_every_role(self):
        target = self.make_user("roles_audit_assign", groups=[CASHIER_GROUP])
        res = self.client.post(
            f"{USERS_URL}{target.pk}/assign_role/",
            {"roles": ["pos", "inventory"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        rows = self.role_rows()
        self.assertEqual(rows.count(), 1)
        self.assertIn("inventory", rows.first().description)
        self.assertIn("pos", rows.first().description)

    def test_patch_roles_writes_one_role_change_row(self):
        target = self.make_user("roles_audit_patch", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["pos", "sales"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 200, res.data)
        rows = self.role_rows()
        self.assertEqual(rows.count(), 1)
        self.assertEqual(rows.first().username_snapshot, "roles_admin")
        self.assertIn("sales", rows.first().description)

    def test_refused_role_change_writes_no_row(self):
        target = self.make_user("roles_audit_refused", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["nope"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        self.assertEqual(self.role_rows().count(), 0)

    def test_refused_role_change_writes_no_audit_row_in_the_feed(self):
        target = self.make_user("roles_audit_feed", groups=[CASHIER_GROUP])
        res = self.client.patch(
            f"{USERS_URL}{target.pk}/",
            {"roles": ["pos", "nope"]},
            format="json",
            HTTP_AUTHORIZATION=self.admin_auth,
        )
        self.assertEqual(res.status_code, 400, res.data)
        feed = self.client.get(AUDIT_URL, HTTP_AUTHORIZATION=self.admin_auth)
        self.assertEqual(feed.status_code, 200, feed.data)
        rows = feed.data["results"] if isinstance(feed.data, dict) else feed.data
        self.assertEqual(
            [
                row["action_type"]
                for row in rows
                if row["action_type"] == AuditLog.ActionType.ROLE_CHANGE
            ],
            [],
        )


# ---------------------------------------------------------------------------
# Phase 6 B5 item 1: a bug is a server fault, not a client refusal
# ---------------------------------------------------------------------------


class RoleChangeUnexpectedErrorTests(RolesTestBase):
    """An unexpected error must surface, not be re-served as a 400 refusal.

    `resolve_role_change` calls `parse_role_codes`, whose only expected failure is
    `serializers.ValidationError`. A broad `except Exception` turned every real bug into
    the same 400 a bad body gets, which hides the fault from the client and the logs.
    """

    def test_an_unexpected_error_is_not_masked_as_a_refusal(self):
        target = self.make_user("roles_bug", groups=[CASHIER_GROUP])
        with (
            mock.patch(
                "apps.users.views.parse_role_codes", side_effect=RuntimeError("boom")
            ),
            self.assertRaises(RuntimeError),
        ):
            self.client.post(
                f"{USERS_URL}{target.pk}/assign_role/",
                {"roles": ["pos"]},
                format="json",
                HTTP_AUTHORIZATION=self.admin_auth,
            )
        self.assertEqual(self.group_names(target), [CASHIER_GROUP])
