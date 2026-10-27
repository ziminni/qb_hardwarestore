---
date: 2026-10-26
slug: audit-remediation-phase-5
---

# 2026-10-26 — Audit remediation Phase 5: Store Manager / Admin (inline build)

## Focus

Build Phase 5 of `planning/audit-remediation/MAP.md` from `phase-5-plan.md`, executed inline
(executing-plans, no subagents): Store Manager joins user-write authority, manager-only
unlinked returns get a screen, receivables get status chips, dashboard tiles read the server
summary, and the Inventory Simulator is deleted.

## What Was Built / Changed

| Commit | Change |
|---|---|
| `abc9fb9` | Backend Task 1: `IsUserManagerRole` (Store Manager + Admin) on `UserViewSet`; `USER_ADMIN_FORBIDDEN` guardrails (non-admin callers 403 on admin accounts/grants, deactivated admins included); creation stays Admin-only; Phase 5 contract tests (cashier 403s, deactivate round-trip, manager authority + 4 guardrails, unlinked reason/audit) |
| `804544c` | Flutter Task 2: `UserService.setActive/assignRole` (+403/400 mapping), viewmodel actions reloading from server, per-row Deactivate/Reactivate + Change role with confirms, Create hidden from non-admins, `/admin/users` fence admits `sales`; role compare by GROUP name |
| `a706073` | Flutter Task 3: `ReturnsService.postUnlinkedReturn` (omits `original_transaction`), manager-only Unlinked return dialog (customer + catalogue selling units + lines + reason + tender → summary), receivables All/Current/Due soon/Overdue chips, dashboard tiles from `sales-summary` with honest fallback, simulator deleted |
| `ENDPOINTS.md` | Users rows → Store Manager + Admin with guardrails; unlinked row notes Phase 5 screen |

## Mistakes & Gotchas (Do Not Repeat)

- **MAP scope can contradict shipped permissions.** Phase 5 scope said "Store Manager / Admin" but `IsAdminRole` 403d the manager (RED: 403 != 200). Ruled: widen with guardrails, not open blindly.
- **`dio` is `late final` — a viewmodel that calls it in `initState` crashes stub-only tests with `LateError`.** `loadSummary()` was the first unconditional live-dio touch in a sales test. Fixed with a stub reports repo + fallback assertions (which also proved the honest-fallback behavior).
- **pi-lens post-edit diagnostics went stale repeatedly** on `sales_receivables_viewmodel_test.dart` (flagged missing methods that exist on disk). Settled each time with fresh `dart analyze` (clean), `flutter test` (green), and two live LSP probes (0 diagnostics). A flag the lens itself cannot see on probe is not a blocker.
- **Stale sibling assertions hide in other files.** Opening `/admin/users` to sales broke bounce-tests in both `admin_reports_routing_test.dart` and `admin_requisitions_routing_test.dart` — grep for the route in every routing test when the fence moves.
- **Heritage comment rot:** the returns page comment said the manager screen "is Phase 5" after Phase 5 built it; the dashboard "All recorded transactions" label test needed the summary-fallback story added.

## Decisions (Rulings)

- Task 1: Store Manager joins user-write authority with server guardrails — MAP scope is the binding spec over decision 04's Admin-only endpoint. Cost if wrong: privilege escalation (fixed by guard) or over-locked ops.
- Task 2: fence exception for `/admin/users` (server admits); Create hidden from non-admin; role compare by GROUP name. Cost if wrong: manager locked out or offered a 403 button.
- Task 3: tiles prefer summary with honest fallback caption; tables keep the capped list (loud failure past 2000 — residual scale risk, not silent). Simulator deleted, not wired. Cost if wrong: wrong revenue shown as fact.

## Wins & Next Step

- Gate: backend **468/468** fresh, flutter **769/769**, analyze clean.
- Live API probes (dev DB): manager unlinked 201 + audit names 'unlinked'; no-reason 400; cashier 403; manager deactivate/reactivate cashier 200; manager-vs-admin 403; summary 200 (66 txns, 25220 gross).
- Dev DB has probe rows (shift #19 open for manager, `TRX-20261026-0001` unlinked return). Re-seed for a clean demo.
- **Next:** `git push` (user). Phase 6 grill ([Barcode concept](./decisions/10-barcode-concept.md)), then build Phase 6.
