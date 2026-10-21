# D-01 Audit Logs Scope

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

`AuditLogsPage` reads `AdminMockData.auditLogs` (fake static rows). The backend `AuditLogViewSet` is fully wired at `GET /api/v1/audit-logs/` with `IsAdminUser` permission. What should replace the mock?

## Options Considered

**A — Paginated list, latest-first, load-on-open:** Simple scrollable table via `AdminAuditLogTable`, page 1 of 50 rows, error banner + retry. No filter.

**B — Paginated list with action-type filter dropdown:** Same + a dropdown to filter by `LOGIN | LOGOUT | SALE` etc.

**C — Static placeholder:** Honest "coming soon" banner, zero new service.

## Decision: Option A

Paginated list, latest-first, page 1 (50 rows), load-on-open, error banner + retry. No filter UI — single list is sufficient for capstone demo.

## Wire contract (verified)

`AuditLogSerializer` fields:
- `id` (int)
- `user` (int FK)
- `user_email` (EmailField, source=user.email — may be null if user deleted)
- `action_type` (string: LOGIN/LOGOUT/CREATE/UPDATE/DELETE/SALE/STOCK_ADJUST/RECEIPT/PAYMENT)
- `description` (string)
- `ip_address` (string, nullable)
- `timestamp` (ISO 8601 datetime)

Permission: `IsAdminUser` — admin role only.

## Files affected

- `flutter/lib/data/models/audit_log.dart` (NEW)
- `flutter/lib/data/services/audit_log_service.dart` (NEW)
- `flutter/lib/data/repositories/audit_log_repository.dart` (NEW)
- `flutter/lib/features/admin/views/audit_logs_page.dart` — convert to `StatefulWidget(repository?)`

## Cost if wrong

Shows 50 rows with no filter → user must scroll to find entries. Acceptable for capstone. Filter is Fog of War.
