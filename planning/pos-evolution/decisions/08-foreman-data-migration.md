# Migrating today's foreman data

**Mode:** research · **Status:** ✅ Locked 2026-11-03 (by: delegated — facts from source and dev DB, no product choice)
**Depends on:** [Requisitions after the foreman](./01-requisitions-after-foreman.md).

## Findings (dev DB and source, 2026-11-03)

- Only demo data exists: 1 `Site Foreman` account (`foreman`); 4 requisitions, all `requested_by` the foreman (1 Draft, 1 Submitted, 1 Approved, 1 Released); 2 tokens (1 used).
- The foreman has 4 audit rows; `AuditLog.user` is `on_delete=PROTECT` (`apps/users/models.py:167`) and audit is append-only (audit-remediation Audit depth), so the account **cannot be deleted**.
- `ROLE_SITE_FOREMAN` is used in `apps/users/permissions.py:19,126`, `apps/requisitions/serializers.py:6,106`, and `seed_demo.py:37,45`.

## Decision

1. One schema + data migration: add requester and approver name text fields, copy `requested_by.full_name` / `approved_by.full_name` into them, then drop the two user FKs.
2. Draft and Submitted rows (states the POS can no longer produce) become Cancelled; Approved and Released rows are kept as they are.
3. The `foreman` account is deactivated and removed from `Site Foreman`; the empty group is deleted. The account row stays because its audit rows protect it.
4. `seed_demo` stops creating the foreman and seeds requests as if CPMS had pushed them (one approved, one partly released, one released), so a fresh reseed shows the new flow.
