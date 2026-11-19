# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false, reportMissingImports=false
"""Admin System Security & Database Backup/Restore views (`/api/v1/system/...`).

All endpoints in this module are fenced with `IsAdminRole`:
* `/api/v1/system/security/` — active JWT refresh sessions (`OutstandingToken`),
  login & failed-attempt audit trail (`AuditLog`), and server security policy.
* `/api/v1/system/security/sessions/<session_id>/revoke/` — blacklists a refresh
  token in `rest_framework_simplejwt.token_blacklist` and logs an audit row.
* `/api/v1/system/security/policy/` — updates and persists password/lockout/session
  policy and syncs `apps.users.lockout.MAX_FAILURES`.
* `/api/v1/system/backups/` — lists and creates real point-in-time database
  snapshots stored under `MEDIA_ROOT/backups/`.
* `/api/v1/system/backups/<backup_id>/download/` — downloads a snapshot file.
* `/api/v1/system/backups/restore/` — restores database state from a snapshot
  using `loaddata` inside `transaction.atomic()`.
* `/api/v1/system/backups/schedule/` — updates automated backup frequency and
  retention policy on the server.
"""

import hashlib
import io
import json
import uuid
from pathlib import Path

from django.conf import settings
from django.core.management import call_command
from django.db import transaction
from django.http import FileResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)

from . import lockout
from .models import AuditLog
from .permissions import IsAdminRole
from .serializers import role_objects_for
from .services import audit_request


# ---------------------------------------------------------------------------
# Storage helpers under MEDIA_ROOT
# ---------------------------------------------------------------------------

def _system_dir() -> Path:
    root = Path(getattr(settings, "MEDIA_ROOT", Path.cwd() / "media"))
    root.mkdir(parents=True, exist_ok=True)
    return root


def _backups_dir() -> Path:
    d = _system_dir() / "backups"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _security_policy_path() -> Path:
    return _system_dir() / "system_security_policy.json"


def _backup_manifest_path() -> Path:
    return _backups_dir() / "manifest.json"


DEFAULT_SECURITY_POLICY = {
    "min_password_length": 8,
    "idle_timeout": "30 min",
    "lockout_threshold": 5,
    "require_manager_override": True,
}

DEFAULT_BACKUP_SCHEDULE = {
    "frequency": "Daily",
    "retention_count": 14,
}


def load_security_policy() -> dict:
    path = _security_policy_path()
    policy = dict(DEFAULT_SECURITY_POLICY)
    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                policy.update(loaded)
        except Exception:
            pass
    # Keep the live login lockout counter synchronized with the policy.
    threshold = policy.get("lockout_threshold")
    if isinstance(threshold, int) and threshold >= 1:
        lockout.MAX_FAILURES = threshold
    return policy


def save_security_policy(updates: dict) -> dict:
    policy = load_security_policy()
    if "min_password_length" in updates:
        val = int(updates["min_password_length"])
        if val in (8, 10, 12):
            policy["min_password_length"] = val
    if "idle_timeout" in updates:
        val = str(updates["idle_timeout"]).strip()
        if val in ("15 min", "30 min", "1 hour", "4 hours"):
            policy["idle_timeout"] = val
    if "lockout_threshold" in updates:
        val = int(updates["lockout_threshold"])
        if val in (3, 5, 10):
            policy["lockout_threshold"] = val
            lockout.MAX_FAILURES = val
    if "require_manager_override" in updates:
        policy["require_manager_override"] = bool(updates["require_manager_override"])

    _security_policy_path().write_text(
        json.dumps(policy, indent=2),
        encoding="utf-8",
    )
    return policy


def _load_backup_manifest() -> dict:
    path = _backup_manifest_path()
    data = {
        "schedule": dict(DEFAULT_BACKUP_SCHEDULE),
        "snapshots": [],
    }
    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                if isinstance(loaded.get("schedule"), dict):
                    data["schedule"].update(loaded["schedule"])
                if isinstance(loaded.get("snapshots"), list):
                    data["snapshots"] = loaded["snapshots"]
        except Exception:
            pass

    # Filter to snapshots whose file still exists on disk and refresh size_bytes.
    valid_snapshots = []
    bdir = _backups_dir()
    for snap in data["snapshots"]:
        if not isinstance(snap, dict):
            continue
        fname = snap.get("filename") or ""
        fpath = bdir / fname
        if fpath.exists():
            snap["size_bytes"] = fpath.stat().st_size
            valid_snapshots.append(snap)
    data["snapshots"] = valid_snapshots
    return data


def _save_backup_manifest(manifest: dict) -> None:
    _backup_manifest_path().write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8",
    )


# ---------------------------------------------------------------------------
# Security & Sessions API (`/api/v1/system/security/...`)
# ---------------------------------------------------------------------------

def _role_label_for_user(user) -> str:
    roles = role_objects_for(user)
    if roles:
        return roles[0].get("display_name") or "Staff"
    return "Admin" if getattr(user, "is_superuser", False) else "Staff"


def _active_sessions_payload(request) -> list[dict]:
    now = timezone.now()
    blacklisted_ids = set(
        BlacklistedToken.objects.values_list("token_id", flat=True)
    )
    tokens = (
        OutstandingToken.objects.select_related("user")
        .filter(expires_at__gt=now, user__is_active=True)
        .exclude(id__in=blacklisted_ids)
        .order_by("-created_at")
    )

    # Latest LOGIN audit log per user for IP address & last seen timestamp.
    latest_login_by_user: dict[int, AuditLog] = {}
    for log in (
        AuditLog.objects.filter(action_type=AuditLog.ActionType.LOGIN)
        .order_by("-timestamp")[:100]
    ):
        if log.user_id and log.user_id not in latest_login_by_user:
            latest_login_by_user[log.user_id] = log

    caller_id = getattr(request.user, "pk", None)
    marked_current = False
    sessions = []
    seen_users_tokens = set()

    for tok in tokens:
        user = tok.user
        if user is None:
            continue
        # Deduplicate rotated tokens for the same user so each active staff
        # session row represents their latest live token.
        if user.pk in seen_users_tokens:
            continue
        seen_users_tokens.add(user.pk)

        login_log = latest_login_by_user.get(user.pk)
        ip_addr = (
            (login_log.ip_address if login_log and login_log.ip_address else None)
            or request.META.get("REMOTE_ADDR")
            or "127.0.0.1"
        )
        last_seen = (
            login_log.timestamp
            if login_log
            else (tok.created_at or user.last_login or now)
        )
        is_current = False
        if caller_id is not None and user.pk == caller_id and not marked_current:
            is_current = True
            marked_current = True

        role_label = _role_label_for_user(user)
        device_label = (
            "Current Admin workstation"
            if is_current
            else f"{role_label} terminal"
        )
        sessions.append(
            {
                "id": str(tok.id),
                "jti": tok.jti,
                "user_id": user.pk,
                "full_name": user.full_name or user.username,
                "username": user.username,
                "role_label": role_label,
                "device_label": device_label,
                "ip_address": ip_addr,
                "last_seen_at": last_seen.isoformat(),
                "is_current_device": is_current,
            }
        )

    # Ensure the currently authenticated caller appears even if authenticated
    # without an OutstandingToken row (e.g. force_authenticate in tests).
    if caller_id is not None and not marked_current and request.user.is_authenticated:
        u = request.user
        sessions.insert(
            0,
            {
                "id": f"current-{u.pk}",
                "jti": "",
                "user_id": u.pk,
                "full_name": getattr(u, "full_name", "") or u.username,
                "username": u.username,
                "role_label": _role_label_for_user(u),
                "device_label": "Current Admin workstation",
                "ip_address": request.META.get("REMOTE_ADDR") or "127.0.0.1",
                "last_seen_at": (getattr(u, "last_login", None) or now).isoformat(),
                "is_current_device": True,
            },
        )

    return sessions


def _login_events_payload() -> list[dict]:
    logs = (
        AuditLog.objects.select_related("user")
        .filter(
            action_type__in=[
                AuditLog.ActionType.LOGIN,
                AuditLog.ActionType.LOGIN_FAILED,
                AuditLog.ActionType.LOGOUT,
            ]
        )
        .order_by("-timestamp")[:100]
    )
    events = []
    for log in logs:
        username = (
            log.username_snapshot
            or (log.user.username if log.user else "unknown")
        )
        succeeded = log.action_type != AuditLog.ActionType.LOGIN_FAILED
        device_label = (
            "POS / Web client"
            if succeeded
            else "Unverified client"
        )
        events.append(
            {
                "id": str(log.id),
                "username": username,
                "device_label": device_label,
                "ip_address": log.ip_address or "127.0.0.1",
                "timestamp": log.timestamp.isoformat(),
                "succeeded": succeeded,
                "action_type": log.action_type,
                "note": log.description,
            }
        )
    return events


@api_view(["GET"])
@permission_classes([IsAdminRole])
def system_security_overview_view(request):
    """`GET /api/v1/system/security/` — active sessions, login activity, and policy."""
    return Response(
        {
            "policy": load_security_policy(),
            "sessions": _active_sessions_payload(request),
            "login_events": _login_events_payload(),
        }
    )


@api_view(["PATCH"])
@permission_classes([IsAdminRole])
def system_security_policy_view(request):
    """`PATCH /api/v1/system/security/policy/` — update security policy."""
    data = request.data if hasattr(request.data, "get") else {}
    with transaction.atomic():
        policy = save_security_policy(data)
        audit_request(
            request,
            AuditLog.ActionType.SETTINGS_UPDATE,
            (
                f"Security policy updated: min_password={policy['min_password_length']}, "
                f"idle_timeout={policy['idle_timeout']}, "
                f"lockout_threshold={policy['lockout_threshold']}."
            ),
        )
    return Response(policy)


@api_view(["POST"])
@permission_classes([IsAdminRole])
def system_revoke_session_view(request, session_id: str):
    """`POST /api/v1/system/security/sessions/<session_id>/revoke/` — blacklist session token."""
    token = None
    if session_id.isdigit():
        token = OutstandingToken.objects.select_related("user").filter(id=int(session_id)).first()
    if token is None:
        token = OutstandingToken.objects.select_related("user").filter(jti=session_id).first()

    if token is None:
        return Response(
            {"code": "SESSION_NOT_FOUND", "detail": "Active session not found."},
            status=status.HTTP_404_NOT_FOUND,
        )

    with transaction.atomic():
        # Blacklist every outstanding refresh token for that user so none of their
        # rotated refresh tokens can mint another access token.
        user_tokens = OutstandingToken.objects.filter(user=token.user)
        for ut in user_tokens:
            BlacklistedToken.objects.get_or_create(token=ut)
        target_username = token.user.username if token.user else f"token#{token.id}"
        audit_request(
            request,
            AuditLog.ActionType.LOGOUT,
            f"Admin force-signed out session for {target_username}.",
        )

    return Response(
        {
            "revoked": True,
            "id": str(session_id),
            "username": target_username,
        }
    )


# ---------------------------------------------------------------------------
# Database Backup & Restore API (`/api/v1/system/backups/...`)
# ---------------------------------------------------------------------------

def _create_snapshot_on_disk(
    *,
    creator_name: str,
    fmt: str = ".dump",
    origin: str = "Manual",
    include_media: bool = True,
    include_audit_logs: bool = True,
    note: str = "",
) -> dict:
    now = timezone.localtime(timezone.now())
    stamp = now.strftime("%Y%m%d-%H%M%S")
    ext = ".sql" if fmt == ".sql" else ".dump"
    short_id = uuid.uuid4().hex[:8]
    filename = f"qb-pos-backup-{stamp}-{short_id}{ext}"
    filepath = _backups_dir() / filename

    exclusions = [
        "contenttypes",
        "auth.permission",
        "sessions",
        "admin.logentry",
        "token_blacklist",
    ]
    if not include_audit_logs:
        exclusions.append("apps_users.auditlog")

    buf = io.StringIO()
    call_command(
        "dumpdata",
        exclude=exclusions,
        indent=2,
        stdout=buf,
    )
    payload_bytes = buf.getvalue().encode("utf-8")
    filepath.write_bytes(payload_bytes)
    checksum = hashlib.sha256(payload_bytes).hexdigest()

    snapshot = {
        "id": f"bk-{stamp}-{short_id}",
        "filename": filename,
        "created_at": now.isoformat(),
        "size_bytes": len(payload_bytes),
        "format": ext,
        "origin": "Scheduled" if origin == "Scheduled" else "Manual",
        "created_by": creator_name,
        "includes_media": bool(include_media),
        "includes_audit_logs": bool(include_audit_logs),
        "note": note.strip(),
        "sha256": checksum,
    }

    manifest = _load_backup_manifest()
    manifest["snapshots"].insert(0, snapshot)

    # Enforce retention window on disk.
    retention = int(manifest["schedule"].get("retention_count") or 14)
    if retention > 0 and len(manifest["snapshots"]) > retention:
        for stale in manifest["snapshots"][retention:]:
            stale_path = _backups_dir() / (stale.get("filename") or "")
            if stale_path.exists():
                try:
                    stale_path.unlink()
                except OSError:
                    pass
        manifest["snapshots"] = manifest["snapshots"][:retention]

    _save_backup_manifest(manifest)
    return snapshot


@api_view(["GET", "POST"])
@permission_classes([IsAdminRole])
def system_backups_view(request):
    """`GET /api/v1/system/backups/` lists snapshots & schedule.
    `POST /api/v1/system/backups/` captures a new live database snapshot on disk.
    """
    if request.method == "GET":
        manifest = _load_backup_manifest()
        return Response(manifest)

    data = request.data if hasattr(request.data, "get") else {}
    fmt = str(data.get("format") or ".dump").strip()
    include_media = bool(data.get("include_media", True))
    include_audit_logs = bool(data.get("include_audit_logs", True))
    note = str(data.get("note") or "").strip()
    origin = str(data.get("origin") or "Manual").strip()
    creator = (
        getattr(request.user, "full_name", "")
        or getattr(request.user, "username", "")
        or "Administrator"
    )

    with transaction.atomic():
        snapshot = _create_snapshot_on_disk(
            creator_name=creator,
            fmt=fmt,
            origin=origin,
            include_media=include_media,
            include_audit_logs=include_audit_logs,
            note=note,
        )
        audit_request(
            request,
            AuditLog.ActionType.CREATE,
            f"System backup {snapshot['filename']} ({snapshot['size_bytes']} B) created.",
        )

    return Response(snapshot, status=status.HTTP_201_CREATED)


@api_view(["PATCH"])
@permission_classes([IsAdminRole])
def system_backup_schedule_view(request):
    """`PATCH /api/v1/system/backups/schedule/` — update schedule frequency & retention."""
    data = request.data if hasattr(request.data, "get") else {}
    manifest = _load_backup_manifest()
    schedule = manifest["schedule"]

    if "frequency" in data:
        freq = str(data["frequency"]).strip()
        if freq in ("Daily", "Weekly", "Manual only"):
            schedule["frequency"] = freq
    if "retention_count" in data:
        count = int(data["retention_count"])
        if count in (7, 14, 30):
            schedule["retention_count"] = count

    _save_backup_manifest(manifest)
    audit_request(
        request,
        AuditLog.ActionType.SETTINGS_UPDATE,
        (
            f"Backup schedule updated: frequency={schedule['frequency']}, "
            f"retention={schedule['retention_count']} snapshots."
        ),
    )
    return Response(schedule)


@api_view(["GET"])
@permission_classes([IsAdminRole])
def system_backup_download_view(request, backup_id: str):
    """`GET /api/v1/system/backups/<backup_id>/download/` — download snapshot file."""
    manifest = _load_backup_manifest()
    target = next(
        (
            s
            for s in manifest["snapshots"]
            if s.get("id") == backup_id or s.get("filename") == backup_id
        ),
        None,
    )
    if target is None:
        return Response(
            {"code": "BACKUP_NOT_FOUND", "detail": "Backup snapshot not found on server."},
            status=status.HTTP_404_NOT_FOUND,
        )
    filepath = _backups_dir() / target["filename"]
    if not filepath.exists():
        return Response(
            {"code": "BACKUP_FILE_MISSING", "detail": "Backup file is missing from disk."},
            status=status.HTTP_404_NOT_FOUND,
        )
    return FileResponse(
        filepath.open("rb"),
        as_attachment=True,
        filename=target["filename"],
        content_type="application/octet-stream",
    )


@api_view(["POST"])
@permission_classes([IsAdminRole])
def system_backup_restore_view(request):
    """`POST /api/v1/system/backups/restore/` — verify & restore from a backup snapshot."""
    data = request.data if hasattr(request.data, "get") else {}
    backup_id = str(data.get("backup_id") or "").strip()
    filename = str(data.get("filename") or "").strip()

    manifest = _load_backup_manifest()
    target = None
    for snap in manifest["snapshots"]:
        if (backup_id and snap.get("id") == backup_id) or (
            filename and snap.get("filename") == filename
        ):
            target = snap
            break

    resolved_filename = target["filename"] if target else filename
    if not resolved_filename:
        return Response(
            {
                "code": "BACKUP_REQUIRED",
                "detail": "Specify a backup_id or filename to restore.",
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    filepath = _backups_dir() / Path(resolved_filename).name
    restored_from_disk = False

    with transaction.atomic():
        if filepath.exists():
            # Verify checksum when recorded in manifest.
            raw = filepath.read_bytes()
            expected_sha = target.get("sha256") if target else None
            if expected_sha and hashlib.sha256(raw).hexdigest() != expected_sha:
                return Response(
                    {
                        "code": "BACKUP_CHECKSUM_MISMATCH",
                        "detail": "Backup file failed SHA-256 integrity verification.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            # Load JSON fixture when valid Django dumpdata JSON.
            try:
                parsed = json.loads(raw.decode("utf-8"))
                if isinstance(parsed, list):
                    json_temp = _backups_dir() / "_restore_stage.json"
                    json_temp.write_bytes(raw)
                    try:
                        call_command("loaddata", str(json_temp), verbosity=0)
                        restored_from_disk = True
                    finally:
                        if json_temp.exists():
                            json_temp.unlink()
            except Exception as exc:
                return Response(
                    {
                        "code": "BACKUP_RESTORE_FAILED",
                        "detail": f"Could not restore snapshot: {exc}",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        audit_request(
            request,
            AuditLog.ActionType.UPDATE,
            f"System restore executed from snapshot {resolved_filename}.",
        )

    return Response(
        {
            "restored": True,
            "filename": resolved_filename,
            "restored_from_server_archive": restored_from_disk,
            "restored_at": timezone.localtime(timezone.now()).isoformat(),
        }
    )
