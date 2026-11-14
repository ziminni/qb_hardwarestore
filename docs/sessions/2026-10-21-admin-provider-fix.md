---
date: 2026-10-21
slug: admin-provider-fix
map: planning/cashier-workflow/MAP.md
commits: [5cd7386, 96c9217]
gate: {backend: 107/107, flutter: 469/469, analyze: clean}
---

# Session: Admin Provider Fix — 2026-10-21

## Focus

Fix the admin-dashboard crash (`Provider<AdminOverviewViewmodel>` not found) via qa-tester + systematic-debugging for root cause, then expressive-dev + executing-plans for the fix, then verification-before-completion with fresh RED→GREEN proof.

## What Was Built / Changed

- `flutter/lib/routes/routes.dart` — `GoRoute(adminDashboard)` pageBuilder now wraps `AdminDashboard` in route-scoped `ChangeNotifierProvider(create: (_) => AdminOverviewViewmodel())`; added imports for the viewmodel + `provider`.
- `flutter/test/features/admin/admin_dashboard_test.dart` — new route-wiring test `the admin dashboard route provides its own overview viewmodel` (builds real `MyApp` router with app-root providers only, no manual injection).
- `5cd7386 style: pi-lens auto-format` — pre-existing format diffs committed separately.
- `96c9217 fix(admin): provide AdminOverviewViewmodel at admin dashboard route` — the fix commit.

## Mistakes & Gotchas (Do Not Repeat)

- Existing `admin_dashboard_test.dart` tests all injected `AdminOverviewViewmodel` by hand, so widget-level tests passed while route wiring was broken — a route-level test was mandatory.
- `AdminOverviewViewmodel.load()` only catches service exceptions; an uninitialized `ApiClient` throws `LateError`, so the new test needs `ApiClient.instance.init()` + offline adapter or it hangs/fails for the wrong reason.
- `git stash push -- <clean-file>` stashes nothing; to reproduce RED against a committed fix, use `git show HEAD~1:<path> > <path>`, then restore from backup.
- Broad `grep ChangeNotifierProvider` after a revert is misleading — other routes use it too; check the `adminDashboard` block specifically.

## Decisions

- Route-scoped provider (not app-root): dashboard reloads on every open, nothing else reads an overview, and app-root would hide the same bug class; mirrors `AdminUsersViewmodel` pattern. Consumer (`AdminDashboard`) untouched — fix at the supplying layer.
- `AdminDashboard` stays `StatefulWidget` with post-frame reads; provider must sit above it in the route, not in a `Builder` inside the page.

## Wins & Next Step

- RED proven: pre-fix `routes.dart` → new test fails with exact reported error `Could not find the correct Provider<AdminOverviewViewmodel> above this AdminDashboard Widget` (exit 1); fix restored → `+4` admin tests pass.
- Full gates fresh this session: flutter `469/469` (exit 0), `analyze` clean, backend `107/107 OK`, `manage.py check` clean, tree CLEAN.
- Next: `git push` branch, then Wayfinder on `planning/cashier-workflow/MAP.md` to record fog (held-cart close advisory, shift close advisory) and decide next epic.
