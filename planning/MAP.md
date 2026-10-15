# planning/MAP.md — Unbuilt Work Index

Entry point for everything not yet built. Read this first, then open the plan you need.
Roadmap and decisions live **here**; architecture lives in `docs/SYSTEM_ATLAS.md`; the endpoint
contract lives in `ENDPOINTS.md`. None of those three duplicate each other.

**State of the system:** the Django backend is feature-complete. The Flutter client consumes almost
none of it — of 10 feature modules, only `auth` reaches the API. The work below is therefore mostly
*wiring*, not *building*.

## Plans

| # | Plan | Scope | Priority |
| :--- | :--- | :--- | :--- |
| 01 | [API integration](01-api-integration.md) | Replace 27 mock screens with live API calls; fix the frontend models first | **P0** |
| 02 | [Lost work recovery](02-lost-work-recovery.md) | Restore `pos_service.dart` / `pos_repository.dart` dropped by a bad merge | **P1** |
| 03 | [UI gaps](03-ui-gaps.md) | Screens that do not exist for endpoints that do (token flow, utang, receipts) | **P1** |
| 04 | [Cleanup](04-cleanup.md) | Dead files, duplicate stacks, stale branches, config debt | **P2** |

## Priority reasoning

1. **01 first, because it unblocks the demo.** The capstone's visible weakness is that the app shows
   hardcoded data. Fixing the frontend models is a hard prerequisite — shipping API calls against the
   current `product.dart` would fail against the real serializer.
2. **02 alongside 01, because it is free.** The lost commit already contains a working
   `PosService` that calls `/api/v1/products/` and `/api/v1/batches/`. Recovering it is cheaper than
   rewriting it.
3. **03 and 04 can follow** — the demo does not need them, but the grade may (use-case coverage).
4. `04`'s branch consolidation should happen **before** any long-lived integration branch is shared,
   otherwise the same conflicts are paid twice.

## Explicitly deferred (do not build now)

| Item | Why |
| :--- | :--- |
| Settings page backed by the API | Agreed deferral; it is static UI with no backend contract. |
| Reports consolidation (3 screens → 1) | Cosmetic; tracked in `04-cleanup.md`, not a functional gap. |
| Production hardening of secrets | Real, but out of scope for a capstone demo. Listed in `04-cleanup.md`. |

## Verification rule

Every claim in these plans was checked against source, not against older markdown. `README.md`,
`PHASE_*.md` and `ENDPOINTS.md` were **not** trusted for status. Two of them were in fact wrong:

- `ENDPOINTS.md` claimed list endpoints return **unpaginated** arrays. They do not — settings define
  `PAGE_SIZE = 50`, so every list response is a `{count, next, previous, results}` envelope.
- `ENDPOINTS.md` claimed `tests.py` were **empty stubs**. They are not — 546 lines across 5 apps.

Re-verify before acting on a status claim, including the ones here.
