# planning/MAP.md — Unbuilt Work Index

Entry point for everything not yet built. Read this first, then open the plan you need.
Roadmap and decisions live **here**; architecture lives in `docs/SYSTEM_ATLAS.md`; the endpoint
contract lives in `ENDPOINTS.md`. None of those three duplicate each other.

**State of the system:** the Django backend is feature-complete. The Flutter client consumes almost
none of it — of 10 feature modules, only `auth` reaches the API. The work below is therefore mostly
*wiring*, not *building*.

## Active plan

The integration epic runs as a **Wayfinder map** — a low-resolution index plus one file per open decision,
so it stays workable across many sessions without loading everything at once.

**[planning/api-integration/MAP.md](api-integration/MAP.md)** — destination, invariants, four open decisions
and the phase order.

## Reference plans

Supporting material that is not itself on the map's frontier.

| Plan | Scope | Priority |
| :--- | :--- | :--- |
| [Lost work recovery](02-lost-work-recovery.md) | Restore `pos_service.dart` / `pos_repository.dart` dropped by a bad merge — feeds Phase 1 | **P1** |
| [UI gaps](03-ui-gaps.md) | Screens that do not exist for endpoints that do (token flow, utang, receipts) — feeds Phase 5 | **P1** |
| [Cleanup](04-cleanup.md) | Dead files, duplicate stacks, stale branches, config debt | **P2** |

## Priority reasoning

1. **The map's Phase 0 first, because it unblocks the demo.** The capstone's visible weakness is that the app
   shows hardcoded data. Fixing the frontend models is a hard prerequisite — shipping API calls against the
   current `product.dart` would fail against the real serializer. Phase order lives in
   `api-integration/MAP.md`.
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

Every claim in these plans was checked against source, not against older markdown. The old `PHASE_*.md` and
`TEAM_UPDATE.md` files were **not** trusted for status and have since been deleted in the docs consolidation.
Two claims in `ENDPOINTS.md` were in fact wrong:

- `ENDPOINTS.md` claimed list endpoints return **unpaginated** arrays. They do not — settings define
  `PAGE_SIZE = 50`, so every list response is a `{count, next, previous, results}` envelope.
- `ENDPOINTS.md` claimed `tests.py` were **empty stubs**. They are not — 546 lines across 5 apps.

Re-verify before acting on a status claim, including the ones here.
