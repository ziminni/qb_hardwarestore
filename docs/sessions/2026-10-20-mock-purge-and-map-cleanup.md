---
date: 2026-10-20
branch: feature/backend-integration
status: mock-purge complete, branch unpushed
---

# 2026-10-20 — Mock-purge complete (admin overview + user management live), orphan deletion, map/atlas freshness

## Focus

Finish the mock-purge epic: wire the last two mock-driven surfaces (Admin Overview, user management)
to live endpoints, delete every orphaned dashboard mock/widget, and leave AGENTS.md, the planning maps,
and the system atlas telling the truth about the completed Phases 0–6.

## What Was Built / Changed

- **Admin Overview live** (`7b47db3` + false-zero fix `2d7171d`): new `AdminOverviewViewmodel`
  (today's reports sales-summary + recent transactions + inventory counts/alerts); dropped the
  Active-users card (no wired users endpoint) and derived activity from latest sales (no activity
  endpoint). Deleted 5 dead dashboard files + `dashboard_mock_data.dart`.
- **User management live** (`9e15cd2` + fix pass `89ffb56`): new `UserService`
  (`GET /users/` + `?search=`, `GET /users/stats/`, `POST /auth/register/` with 403-vs-load split),
  `UsersRepository`, `AdminUsersViewmodel` (load/search/client-side role+status filters/clear/local
  validation + reload), hardened `User.fromJson` (null role → `FormatException`), `UserStats`;
  rewritten page (live metrics, wired filters, create dialog with mandatory group, banner + retry).
  15 tests, RED-first incl. a mutation check on the role filter.
- **Orphan deletion** (`f9e7ceb`): 7 zero-consumer pos/sales atomic widgets. Fresh review: clean.
- **Freshness sweep** (`f9e7ceb`, `e827a65`, this note's commit): AGENTS.md mock-purge pending→BUILT,
  `planning/MAP.md` cleanup row, `planning/04-cleanup.md` dead rows→DELETED + widget_test row corrected,
  `planning/api-integration/MAP.md` phase-state contradictions resolved, `docs/SYSTEM_ATLAS.md`
  truth matrix 14 rows corrected (admin/inventory/sales dashboards, transactions, returns,
  quotations, orders, users, reports → Live; 3 deleted files marked).
- Gates held all day: flutter **395/395**, `flutter analyze` clean, backend **89/89**.

## Mistakes & Gotchas (Do Not Repeat)

- **Page-scoped VM + `initState` load = ProviderNotFound.** `initState` cannot `read` a provider the
  page itself creates in `build`. Use the reports pattern: `create: (_) => (vm ?? Default())..load()`.
- **`getList` parses rows eagerly.** A `FormatException` guard around `items.toList()` misses; it throws
  at the `await`. Catch at the outer `catch`. (Proven by a RED test failing as no-throw.)
- **Controller built in `build` reverts typed text** on every unrelated rebuild. Own it in `State`
  (`initState` + `didUpdateWidget` sync on submit/clear).
- **Dart is not Python:** `True`/`None` and a guessed `_page` helper fail compilation — read the test
  file's real helpers (`_json`, `_user`) before writing.
- **Backend containers can vanish** (host restart); `docker compose up -d` restores volumes intact.
  Verify with counts, not assumptions (transactions=7, Maria 4900 + DelaCruz 472 OPEN).
- **Live probe auth:** web login needs hash navigation to keep the session; curl login is simpler
  for contract probes. Register path stays covered by backend tests — never create demo users by hand.
- **A dropped `}` during catch-restructure** broke compilation; ground-truth `sed` reads beat memory.
- **Reviewer "clean + minors" on a deletion** still earned its keep: it caught the `Export` no-op and
  the stale `04-cleanup.md` rows.

## Decisions

- Row view/edit/more buttons deleted, not built — per-row account edits are a specified future
  (backend `assign_role` is the hook), not silent no-ops.
- Role/status filters are client-side over loaded rows; only `?search=` hits the server (the one
  filter the backend offers — no new endpoints per Out of Scope).
- Create errors live in `createError`, separate from `loadError`, so a cancelled dialog leaves no
  stale page banner; success shows a SnackBar (the new row may stay filtered out).
- Fresh review scoped to the deletion change, not the whole branch — every feature commit already
  had its own fresh review.
- Shared `.superpowers` ledger NOT deleted at closeout — it is session-shared memory, not per-plan
  scratch.
- Staff list takes backend page 1 of 50 (server `PAGE_SIZE`); paged follow-up only if staff grows.
  Ledgered here and in fog (owned by decision 03, like the 40-page bound).

## Wins & Next Step

- Wins: zero mock-driven screens remain; zero `*MockData` refs in `flutter/lib`; maps, atlas, and
  AGENTS.md agree Phases 0–6 are built; full gate green on an unpushed branch.
- Next (wayfinder, not build): push decision for `feature/backend-integration`, next build scope
  (specified account edits? paged lists? live re-verify of user management?), and the CPMS repo.
