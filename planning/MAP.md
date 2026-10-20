# planning/MAP.md — Unbuilt Work Index

Entry point for everything not yet built. Read this first, then open the plan you need.
Roadmap and decisions live **here**; architecture lives in `docs/SYSTEM_ATLAS.md`; the endpoint
contract lives in `ENDPOINTS.md`. None of those three duplicate each other.

**State of the system:** owned by **`docs/SYSTEM_ATLAS.md`** (what is live vs mock) and the phase table
in **`planning/api-integration/MAP.md`** (how far the epic has got). This file deliberately states
neither — it is an index, and a second home for a fact is how the two drift.

## Active plan

Work runs as **Wayfinder maps** — a low-resolution index plus one file per open decision, so each stays
workable across many sessions without loading everything at once.

**[planning/cashier-workflow/MAP.md](cashier-workflow/MAP.md)** — **ACTIVE (opened 2026-10-20).** The cashier
logs in with no keyring prompt and every cashier sidebar tab routes to a live screen or is removed.

**[planning/api-integration/MAP.md](api-integration/MAP.md)** — **COMPLETE, closed.** The integration epic
(Phases 0–6 built). Its invariants still bind new maps.

## Reference plans

Supporting material that is not itself on the map's frontier.

| Plan | Scope | Priority |
| :--- | :--- | :--- |
| [Lost work recovery](02-lost-work-recovery.md) | ~~Restore dropped files~~ **SUPERSEDED** — the POS stack was rebuilt (not recovered) across Phases 1–3; the lost commit's shape survives only as history | — |
| [UI gaps](03-ui-gaps.md) | **LARGELY CONSUMED** — token release, utang, and receiving screens built (Phases 4–5, 6B.2); foreman routing settled by decision 04. Projects / payments / receipts screens were never adopted by the map and stay unplanned | — |
| [Cleanup](04-cleanup.md) | **PARTIALLY CONSUMED** — reports consolidated (6B.1), widget_test compiles, sales stacks reconciled not deleted (decision 05). Remain: skeleton-layout duplication, config debt (orphan dashboard views + widgets deleted 2026-10-20) | **P2** |

## Priority reasoning (historical — Phases 0-4 are now DONE; kept for the why)

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
| Reports consolidation (3 screens → 1) | ~~Deferred~~ **BUILT 6B.1** — one four-tab screen. |
| Production hardening of secrets | Real, but out of scope for a capstone demo. Listed in `04-cleanup.md`. |

## Verification rule

Every claim in these plans was checked against source, not against older markdown. The old `PHASE_*.md` and
`TEAM_UPDATE.md` files were **not** trusted for status and have since been deleted in the docs consolidation.
Two claims in `ENDPOINTS.md` were in fact wrong:

- `ENDPOINTS.md` claimed list endpoints return **unpaginated** arrays. They do not — settings define
  `PAGE_SIZE = 50`, so every list response is a `{count, next, previous, results}` envelope.
- `ENDPOINTS.md` claimed `tests.py` were **empty stubs**. They are not — 546 lines across 5 apps.

Re-verify before acting on a status claim, including the ones here.
