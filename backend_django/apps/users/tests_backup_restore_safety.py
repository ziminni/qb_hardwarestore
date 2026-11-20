# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
"""Backup safety: snapshots are private, and a restore is real or refused.

Regressions for the 2026-11-20 review of the admin backup feature:
* snapshots lived under MEDIA_ROOT, which the server hands to anyone, so a full dump
  (password hashes included) downloaded without logging in;
* a restore naming a file the server did not have answered `restored: true`;
* a restore merged the fixture into the live rows instead of replacing them.
"""

import json
import shutil
import tempfile
from pathlib import Path

from django.contrib.auth.models import Group
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from .models import AuditLog, User


class BackupRestoreSafetyTests(APITestCase):
    def setUp(self):
        self.temp = Path(tempfile.mkdtemp(prefix="qb_backup_safety_"))
        self.override = override_settings(
            MEDIA_ROOT=self.temp / "media",
            BACKUP_ROOT=self.temp / "private" / "backups",
        )
        self.override.enable()
        group, _ = Group.objects.get_or_create(name="Admin")
        self.admin = User.objects.create_user(
            username="admin_bk", email="admin_bk@qb.ph", password="StrongPass123!"
        )
        self.admin.groups.add(group)
        self.client.force_authenticate(user=self.admin)

    def tearDown(self):
        self.override.disable()
        shutil.rmtree(self.temp, ignore_errors=True)

    def _snapshot(self):
        res = self.client.post("/api/v1/system/backups/", {"note": "t"}, format="json")
        self.assertEqual(res.status_code, status.HTTP_201_CREATED, res.data)
        return res.data

    def test_snapshot_is_written_outside_media_root(self):
        snap = self._snapshot()
        self.assertTrue((self.temp / "private" / "backups" / snap["filename"]).exists())
        self.assertFalse((self.temp / "media" / "backups").exists())

    def test_legacy_media_backups_are_moved_to_private_storage(self):
        legacy = self.temp / "media" / "backups"
        legacy.mkdir(parents=True)
        (legacy / "manifest.json").write_text(
            json.dumps({"snapshots": [{"id": "bk-old", "filename": "old.dump"}]})
        )
        (legacy / "old.dump").write_text("[]")
        res = self.client.get("/api/v1/system/backups/")
        self.assertEqual([s["id"] for s in res.data["snapshots"]], ["bk-old"])
        self.assertFalse((legacy / "old.dump").exists())
        self.assertTrue((self.temp / "private" / "backups" / "old.dump").exists())

    def test_legacy_backup_collision_preserves_both_copies(self):
        legacy = self.temp / "media" / "backups"
        legacy.mkdir(parents=True)
        (legacy / "old.dump").write_bytes(b"legacy")
        private = self.temp / "private" / "backups"
        private.mkdir(parents=True)
        (private / "old.dump").write_bytes(b"current")
        self.client.get("/api/v1/system/backups/")
        self.assertFalse(legacy.exists())
        self.assertEqual((private / "old.dump").read_bytes(), b"current")
        preserved = [p for p in private.rglob("old.dump") if p.parent != private]
        self.assertEqual(len(preserved), 1)
        self.assertEqual(preserved[0].read_bytes(), b"legacy")

    def test_restore_of_unknown_filename_is_refused_not_reported_restored(self):
        res = self.client.post(
            "/api/v1/system/backups/restore/",
            {"filename": "qb-pos-backup-not-here.dump"},
            format="json",
        )
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(res.data["code"], "BACKUP_NOT_FOUND")
        self.assertNotIn("restored", res.data)

    def test_restore_with_missing_file_is_refused(self):
        snap = self._snapshot()
        (self.temp / "private" / "backups" / snap["filename"]).unlink()
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"backup_id": snap["id"]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_restore_replaces_rows_created_after_the_snapshot(self):
        snap = self._snapshot()
        User.objects.create_user(
            username="later", email="later@qb.ph", password="x" * 12
        )
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"backup_id": snap["id"]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertTrue(res.data["restored"])
        self.assertFalse(User.objects.filter(username="later").exists())
        self.assertTrue(User.objects.filter(username="admin_bk").exists())
        self.assertTrue(
            AuditLog.objects.filter(description__contains="restore").exists()
        )

    def test_restore_takes_a_safety_snapshot_first(self):
        snap = self._snapshot()
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"backup_id": snap["id"]}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        listing = self.client.get("/api/v1/system/backups/").data["snapshots"]
        self.assertTrue(any(s["origin"] == "Pre-restore" for s in listing))
        self.assertIn("safety_backup_id", res.data)

    def test_restore_from_uploaded_file_uses_the_uploaded_contents(self):
        snap = self._snapshot()
        raw = (self.temp / "private" / "backups" / snap["filename"]).read_bytes()
        User.objects.create_user(
            username="later", email="later@qb.ph", password="x" * 12
        )
        upload = SimpleUploadedFile("my-copy.dump", raw, "application/octet-stream")
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"file": upload}, format="multipart"
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK, res.data)
        self.assertFalse(User.objects.filter(username="later").exists())

    def test_restore_of_invalid_upload_is_refused_without_changes(self):
        upload = SimpleUploadedFile("bad.dump", b"not json", "application/octet-stream")
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"file": upload}, format="multipart"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(res.data["code"], "BACKUP_INVALID")
        self.assertTrue(User.objects.filter(username="admin_bk").exists())

    @override_settings(DEBUG=True)
    def test_legacy_files_not_public_even_before_admin_opens_backups(self):
        from django.conf import settings
        from django.test import Client
        from django.test.client import RequestFactory
        from django.urls import Resolver404, resolve
        from django.views.static import serve

        legacy = self.temp / "media" / "backups"
        legacy.mkdir(parents=True)
        (legacy / "manifest.json").write_text('{"snapshots": []}')
        # Force Django's static server as the fallback: normal test URLconf omits
        # debug static routes, so relying on Client's default 404 would be vacuous.
        path = "/media/backups/manifest.json"
        client = Client()
        try:
            resolve(path)
        except Resolver404:
            response = serve(
                RequestFactory().get(path),
                "backups/manifest.json",
                document_root=settings.MEDIA_ROOT,
            )
        else:
            response = client.get(path)
        self.assertEqual(response.status_code, 404)

    def test_empty_fixture_does_not_wipe_database(self):
        upload = SimpleUploadedFile("empty.dump", b"[]", "application/octet-stream")
        res = self.client.post(
            "/api/v1/system/backups/restore/", {"file": upload}, format="multipart"
        )
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=self.admin.pk).exists())

    def test_failed_load_rolls_back_replacement(self):
        from unittest.mock import patch

        from . import system_views

        snap = self._snapshot()
        later = User.objects.create_user(
            username="keep_me", email="keep@qb.ph", password="test-password"
        )
        real_command = system_views.call_command

        def fail_load(command, *args, **kwargs):
            if command == "loaddata":
                raise ValueError("fixture load failed")
            return real_command(command, *args, **kwargs)

        with patch.object(system_views, "call_command", side_effect=fail_load):
            res = self.client.post(
                "/api/v1/system/backups/restore/",
                {"backup_id": snap["id"]},
                format="json",
            )
        self.assertEqual(res.status_code, 400)
        self.assertEqual(res.data["code"], "BACKUP_RESTORE_FAILED")
        self.assertTrue(User.objects.filter(pk=later.pk, username="keep_me").exists())
        self.assertTrue(User.objects.filter(pk=self.admin.pk).exists())

    def test_database_snapshot_never_claims_media_bytes_included(self):
        snap = self._snapshot()
        self.assertFalse(snap["includes_media"])

    def test_security_policy_file_is_private(self):
        res = self.client.patch(
            "/api/v1/system/security/policy/", {"lockout_threshold": 5}, format="json"
        )
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertFalse((self.temp / "media" / "system_security_policy.json").exists())
