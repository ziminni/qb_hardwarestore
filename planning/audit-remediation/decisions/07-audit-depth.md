# Audit Depth

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2 (writers added in each later phase for new events).

## Decision
- `log_audit()` called **inside the same `transaction.atomic`** as: sale, held-cart complete/void, return, release, requisition approve/reject, goods receipt process, stock adjustment, alert resolve, collectible payment, shift open/close, user create/update/deactivate/role change.
- Append-only: model `save()` refuses update of existing row, `delete()` raises; Django admin `has_change/has_delete_permission = False`.
- `user` FK → `PROTECT` + `username_snapshot` field.
- No DB trigger (option rejected).

## Security / RED tests
- Each event writes exactly one row; failed (rolled-back) event writes none.
- Update/delete via ORM raises; admin delete denied.
