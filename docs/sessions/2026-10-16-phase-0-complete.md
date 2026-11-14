---
date: 2026-10-16
branch: feature/backend-integration
commits:
  - adac3bc  # feat(network): add Paged<T>, parsePaged and ApiClient.getList (phase 0 transport)
  - f7359db  # feat(core): add AsyncView for loading, error and empty states (phase 0 presentation)
  - 3fd1cf1  # feat(routing): send unmapped roles to an explicit screen (phase 0 routing)
  - cd8dcef  # refactor(products): make ProductsViewmodel view state only (phase 0 cleanup)
  - 181336f  # style: apply dart format after the phase 0 commits
  - 5edb842  # fix(network): derive hasMore from the next link, not the row count
  - 70a95f3  # test: cover the sign-out path, the empty state and adapter restore
  - f00d248  # style: apply dart format to the phase 0 fix files
scope: Phase 0 of planning/api-integration/MAP.md — transport, presentation, routing, cleanup
repo: qb_pos_inventory_system
skill: executing-plans
---

# Phase 0 complete — transport, presentation, routing, cleanup

## Focus

Execute the five remaining Phase 0 rows from `planning/api-integration/MAP.md` inline (TDD per step, a ledger
for recovery, one whole-branch review at the end), then correct the map's status with verified evidence.

Phase 0 had been recorded as complete once before while only 2 of its 7 rows existed, so the goal here was not
just to build the rows but to **stop the status table claiming things the code did not do**.

## What Was Built / Changed

| Row | Deliverable | Tests |
| :--- | :--- | :--- |
| **Transport** | `lib/core/network/paged.dart` — `Paged<T>` plus the pure `parsePaged<T>` that unwraps the DRF `{count,next,previous,results}` envelope in exactly one place (decision 03) — and `ApiClient.getList<T>` | 15 |
| **Presentation** | `lib/core/widgets/async_view.dart` — `AsyncView`, with the precedence loading > error > empty > data baked into the widget so the builder cannot run without data (decision 07) | 6 |
| **Routing** | `lib/features/auth/views/unsupported_role_page.dart` + `AppRoutes.unsupportedRole` + a **pure** `AppRoutes.redirectFor` replacing the silent bounce to `/login` (decision 04) | 20 |
| **Cleanup** | `ProductsViewmodel` became view state only: no product list, reads the store live, delegates every mutation so `products_page` calls each one once (decision 11) | 20 |
| **Registration** | Dissolved — no code. Neither viewmodel was ever unwired, and decision 11 supersedes registering either in `main.dart` | — |

Suite **65 → 131**. `flutter analyze` clean at every commit.

## Mistakes & Gotchas

- **A stale diagnostic cache fired ~15 times**, claiming `core/network/paged.dart`, `core/widgets/async_view.dart`,
  `data/models/catalogue_item.dart` and `data/services/catalogue_assembler.dart` did not exist. All existed the
  whole time. Disproved each time with the two authorities — `dart analyze` on the named file and a fresh
  `lens_diagnostics` `source=lsp` probe (0 diagnostics, at file and directory scope) — plus the files running
  green and their git blobs being unchanged. **No code was ever changed to silence it** (ruling R27). By the end
  the harness was itself labelling the advisory `[stale — re-run to confirm]`.
- **The review falsified my own `hasMore`, and my own tests had agreed with the bug** (ruling R29). It used
  `total > items.length`, which is true of *any* short page, so page 2 of 137 claimed a page 3 existed. The real
  signal is the envelope's `next` link, which `parsePaged` had been discarding. Worse: two test fixtures
  hardcoded `'next': null` and then asserted `hasMore` was true — **a test can agree with a defect**, and a
  green suite is not evidence against a wrong contract.
- **`git diff -w` cannot prove a `dart format` reflow is cosmetic.** The reviewer asserted the churn was
  whitespace-only on that basis; it was not (git's sense), because `dart format` changes line *structure*. The
  proof has to be `flutter analyze` plus a passing suite.
- **A widget test cannot complete work that awaits a platform channel.** The new sign-out test hung with
  `isLoading` stuck true. Isolated with a throwaway diagnostic that compared a plain-test logout (completed)
  against a widget-test one (did not). Cause: secure storage is a platform channel whose reply arrives on the
  real event loop, which a widget test never yields to, so the unawaited `logout()` parked in the FakeAsync zone
  forever — and `runAsync` could not help because the chain had started in the fake zone. Fixed with the
  package's own double, `FlutterSecureStorage.setMockInitialValues({})`.
- **A multi-edit call PART-APPLIED again.** One entry's `oldText` matched two identical `AuthViewmodel(...)`
  sites, so it was silently dropped while the rest applied, and the analyzer's autofix then removed the
  now-unused import. Anchor on a unique neighbouring comment; after any PARTIAL APPLY read the analyzer output
  first.
- **Reading the wrong layer caused a wrong diagnosis.** Seeing "logout clears tokens" I assumed no network call;
  `AuthRepository.logout` does call `clearTokens`, but `AuthService.logout` *also* POSTs to the backend. Read
  the whole chain, not the first plausible function.

## Decisions

- **R25** — `ApiClient.init()` is not idempotent (`dio` is `late final`), so the fix was in the *test* (init once
  in `setUpAll`, swap only `httpClientAdapter`), not the singleton. Re-initialisation is not a supported
  operation.
- **R26** — the stale-cache advisory is a harness artifact; trust the analyzer and the LSP probe, never change
  working code to satisfy it.
- **R27** — recorded consequence of R26: a stale cache is not proof of a dirty file, just as an empty cache is
  not proof of a clean one.
- **R28** — my own test disposed the viewmodel twice (test body plus `tearDown`); diagnosed from the stack trace,
  not the assertion text.
- **R29** — `hasMore` comes from `next != null`, not the row count.
- **Task 2** — the empty state deliberately offers **no** Retry button: an empty list is a legitimate result, not
  a failure. Now locked by a test rather than a comment.
- **Task 3** — the routing rule was extracted from the router's closure into a pure `redirectFor` because
  rendering a destination dashboard in a widget test trips pre-existing skeleton layout assertions unrelated to
  routing.
- **Task 4** — `archiveSelectedProducts` clears the selection *before* delegating, so the store's per-item
  notifications cannot re-enter a loop still reading the selection.

## Wins & Next Step

**All 7 Phase 0 rows are built and verified row-by-row against the code** — the check that matters, since the
status had been wrong twice in opposite directions. Phase 1 is unblocked.

Not done deliberately, and recorded rather than silently skipped:

- **`lib/data/services/auth_service.dart` is still not `dart format`-clean.** It is the only such file on the
  branch and it is **not mine** — it was already unformatted before this work.
- `UnsupportedRolePage` on a device where logout's POST succeeds is covered; the "storage plugin missing" path
  is not (the test mocks storage, as it must).
- The probable backend bug in `apps/inventory/services.py::apply_stock_adjustment` (a positive adjustment is
  silently discarded when no batch has `current_qty > 0`) remains open and out of scope for this client-only map.
- The seed-data FIFO coverage gap stands: every seeded variant has exactly one batch (8/8), so FIFO crossing a
  batch boundary is only exercisable from the mock (variant 1's two lots).

**Next step:** Phase 1 — wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/` using
`ApiClient.getList<T>` (returning `Paged<T>`) and `AsyncView` (decision 07), then `assembleCatalogue`. A
salvageable earlier attempt sits in commit `22c7c26` — see `planning/02-lost-work-recovery.md`.
