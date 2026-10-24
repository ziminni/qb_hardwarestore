# Admin Authority

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2.

## Decision
Admin **group** is the single application authority. Replace `IsAdminUser` with `IsAdminRole` on `register` (`users/views.py:26`), `UserViewSet` (:88), `AuditLogViewSet` (:167). `is_staff` stays only for the Django `/admin` site.

## Security / RED tests
- Admin-group user with `is_staff=False` → 200 on users/audit.
- Staff user without Admin group → 403.
- Non-admin cannot assign Admin group to self via PATCH; admin cannot deactivate the last active admin.
