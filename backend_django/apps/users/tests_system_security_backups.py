# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
"""Tests for Admin System Security & Database Backup/Restore endpoints."""

import shutil
import tempfile
from pathlib import Path

from django.contrib.auth.models import Group
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)
from rest_framework_simplejwt.tokens import RefreshToken

from . import lockout
from .models import AuditLog, User


class SystemSecurityAndBackupsTests(APITestCase):
    def setUp(self):
        self.temp_media = tempfile.mkdtemp(prefix="qb_system_test_")
        self.override = override_settings(MEDIA_ROOT=Path(self.temp_media))
        self.override.enable()

        self.admin_group, _ = Group.objects.get_or_create(name="Admin")
        self.cashier_group, _ = Group.objects.get_or_create(name="Cashier")

        self.admin = User.objects.create_user(
            username="admin_sys",
            email="admin_sys@qb.ph",
            password=" StrongPass123! ",
            full_name="Ada Admin",
        )
        self.admin.groups.add(self.admin_group)

        self.cashier = User.objects.create_user(
            username="rosa_cashier",
            email="rosa@qb.ph",
            password="CashierPass123!",
            full_name="Rosa Cruz",
        )
        self.cashier.groups.add(self.cashier_group)

    def tearDown(self):
        lockout.MAX_FAILURES = 5
        self.override.disable()
        shutil.rmtree(self.temp_media, ignore_errors=True)

    def test_non_admin_is_refused_on_security_and_backup_endpoints(self):
        self.client.force_authenticate(user=self.cashier)
        r1 = self.client.get("/api/v1/system/security/")
        r2 = self.client.get("/api/v1/system/backups/")
        self.assertEqual(r1.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(r2.status_code, status.HTTP_403_FORBIDDEN)

    def test_security_overview_lists_sessions_login_events_and_revokes_session(self):
        # Mint real refresh tokens so OutstandingToken rows exist in the DB.
        _admin_refresh = RefreshToken.for_user(self.admin)
        cashier_refresh = RefreshToken.for_user(self.cashier)
        cashier_token_row = OutstandingToken.objects.filter(user=self.cashier).first()
        self.assertIsNotNone(cashier_token_row)

        AuditLog.objects.create(
            user=self.cashier,
            username_snapshot=self.cashier.username,
            action_type=AuditLog.ActionType.LOGIN,
            description="rosa_cashier logged in.",
            ip_address="192.168.1.42",
        )
        AuditLog.objects.create(
            user=None,
            username_snapshot="intruder",
            action_type=AuditLog.ActionType.LOGIN_FAILED,
            description="Failed login for intruder.",
            ip_address="192.168.1.99",
        )

        self.client.force_authenticate(user=self.admin)
        res = self.client.get("/api/v1/system/security/")
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        sessions = res.data["sessions"]
        usernames = [s["username"] for s in sessions]
        self.assertIn("admin_sys", usernames)
        self.assertIn("rosa_cashier", usernames)

        events = res.data["login_events"]
        event_users = [e["username"] for e in events]
        self.assertIn("rosa_cashier", event_users)
        self.assertIn("intruder", event_users)

        # Revoke the cashier's active session.
        revoke_res = self.client.post(
            f"/api/v1/system/security/sessions/{cashier_token_row.id}/revoke/"
        )
        self.assertEqual(revoke_res.status_code, status.HTTP_200_OK)
        self.assertTrue(revoke_res.data["revoked"])
        self.assertTrue(
            BlacklistedToken.objects.filter(token=cashier_token_row).exists()
        )

        # Cashier no longer appears in active sessions.
        after_res = self.client.get("/api/v1/system/security/")
        after_usernames = [s["username"] for s in after_res.data["sessions"]]
        self.assertNotIn("rosa_cashier", after_usernames)
        _ = cashier_refresh

    def test_security_policy_patch_persists_and_updates_lockout_threshold(self):
        self.client.force_authenticate(user=self.admin)
        res = self.client.patch(
            "/api/v1/system/security/policy/",
            {
                "min_password_length": 12,
                "idle_timeout": "15 min",
                "lockout_threshold": 10,
                "require_manager_override": False,
            },
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data["min_password_length"], 12)
        self.assertEqual(res.data["idle_timeout"], "15 min")
        self.assertEqual(res.data["lockout_threshold"], 10)
        self.assertFalse(res.data["require_manager_override"])
        self.assertEqual(lockout.MAX_FAILURES, 10)

    def test_create_list_download_schedule_and_restore_system_backup(self):
        self.client.force_authenticate(user=self.admin)

        # 1. Create a real snapshot on disk.
        create_res = self.client.post(
            "/api/v1/system/backups/",
            {
                "format": ".dump",
                "include_media": True,
                "include_audit_logs": True,
                "note": "Pre-deployment backup",
            },
            format="json",
        )
        self.assertEqual(create_res.status_code, status.HTTP_201_CREATED)
        snap = create_res.data
        self.assertTrue(snap["filename"].endswith(".dump"))
        self.assertGreater(snap["size_bytes"], 100)
        self.assertEqual(snap["note"], "Pre-deployment backup")

        # 2. List backups returns the created snapshot.
        list_res = self.client.get("/api/v1/system/backups/")
        self.assertEqual(list_res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(list_res.data["snapshots"]), 1)
        self.assertEqual(list_res.data["snapshots"][0]["id"], snap["id"])

        # 3. Download snapshot streams bytes.
        dl_res = self.client.get(f"/api/v1/system/backups/{snap['id']}/download/")
        self.assertEqual(dl_res.status_code, status.HTTP_200_OK)
        body = b"".join(dl_res.streaming_content)
        self.assertEqual(len(body), snap["size_bytes"])

        # 4. Update schedule & retention.
        sched_res = self.client.patch(
            "/api/v1/system/backups/schedule/",
            {"frequency": "Weekly", "retention_count": 30},
            format="json",
        )
        self.assertEqual(sched_res.status_code, status.HTTP_200_OK)
        self.assertEqual(sched_res.data["frequency"], "Weekly")
        self.assertEqual(sched_res.data["retention_count"], 30)

        # 5. Modify a record, then restore from the snapshot and verify restoration.
        self.cashier.full_name = "Modified Name"
        self.cashier.save(update_fields=["full_name"])

        restore_res = self.client.post(
            "/api/v1/system/backups/restore/",
            {"backup_id": snap["id"]},
            format="json",
        )
        self.assertEqual(restore_res.status_code, status.HTTP_200_OK)
        self.assertTrue(restore_res.data["restored"])
        self.assertTrue(restore_res.data["restored_from_server_archive"])

        self.cashier.refresh_from_db()
        self.assertEqual(self.cashier.full_name, "Rosa Cruz")
