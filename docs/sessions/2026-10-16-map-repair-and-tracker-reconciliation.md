---
date: 2026-10-16
branch: feature/backend-integration
commits:
  - b0e5705  # docs(planning): put the locked 7-phase route in the map index and close the Phase 4 gap
  - cc7e023  # docs(planning): correct the stale widget_test invariant - it is tracked and works
scope: map integrity, task-tracker reconciliation, verification discipline
repo: qb_pos_inventory_system
skill: wayfinder, save-progress, verification-before-completion
---

# Map repair, tracker reconciliation and a verification pass

## Focus

The previous session ended claiming "Phase 0 is complete". The user pushed back — *"the tasks are still open
though"* — and was right twice: once about the **map's route**, and again about the **task tracker**, which were
two different lists that I had conflated.

This session set out to answer "what is genuinely still open?" from the documents and the code rather than from
memory, repair whatever that exposed, and then verify every claim with fresh evidence before restating it.

## What Was Built / Changed

**The map's route now lives in its own index** (commit `b0e5705`). `planning/api-integration/MAP.md` had no phase
table at all — the 7-phase route lived only inside decision 01, so the map could not answer "what is next". A
`## Phase order` table now names each phase's scope, state and **ticket** (locked decision / open decision / fog
entry), so no phase can be a silent gap.

**Phase 4 stopped being a gap.** "Customers master data" existed only as one row of decision 01's phase table —
no decision file, not on the Active Frontier, not in Fog of War. It is now explicitly tracked in the Fog as
Phase 4's ticket, with a graduation rule (it becomes a `domain-model` frontier decision when Phase 3 resolves),
because its real question is not yet sharp enough to state as a decision.

**Decision 01 no longer contradicts decision 11.** Its closing paragraph instructed registering
`ProductsViewmodel` and `PosTransactionViewmodel` in `main.dart` "so Phases 1 and 3 would work". That premise
was wrong twice over and acting on it would have added the duplicate registration this project already
rejected. The paragraph is struck and quoted inside a `CORRECTED` block pointing at decision 11 — the same
treatment the earlier false "Phase 0 complete" claims received.

**A stale invariant was corrected** (commit `cc7e023`). `MAP.md` still declared
`flutter/test/widget_test.dart` an *"untracked, broken template… the sole error"*. It is in fact **tracked** and
is a real smoke test asserting an unauthenticated launch lands on `LoginPage`.

**The task tracker was reconciled** (no commit — it is harness state). Six items were still marked pending or in
progress for work already committed. Each was verified against `git` and the code before closing, and each now
carries its evidence inline:

| Task | Delivering commit | Verified by |
| :--- | :--- | :--- |
| #2 API-faithful models | `db4ad8f` | 10 members, 0 legacy fields |
| #3 consumers migrated | `6b3852b..db4ad8f` | 0 legacy receiver refs in `lib/` |
| #4 `Paged<T>` + `getList<T>` | `adac3bc` | both symbols present |
| #5 `AsyncView` | `f7359db` | file present |
| #7 routing fix | `3fd1cf1` | page + route present |
| #8 registration + cleanup | `cd8dcef` | 0 `_products` refs, delegation present |

`#9` (Phase 1 products catalogue wiring) was left open — and confirmed empty rather than assumed: **0**
references to `/api/v1/products/` *or* `/api/v1/batches/` exist in `lib/`.

## Mistakes & Gotchas (Do Not Repeat)

- **Two lists, one word.** "Tasks are open" meant the **task tracker**; I answered about the **map's frontier**.
  They are different systems with different numbering, and I did not confirm which one the user meant before
  answering. Read the actual list first.

- **The tracker's numbering does not match the plan's.** The tracker calls Phase 1 wiring "Task 8"; the ledger
  calls Registration "Task 5". Two schemes over the same work is precisely what let a completed task sit "open"
  — the same class of error as the map's twice-wrong status table.

- **A regex silently under-matched.** The pattern `docs/sessions/[0-9-]*[a-z-]*\.md` cannot match
  `2026-10-16-phase-0-complete.md`, because `[a-z-]*` excludes the digit in `phase-0`. It reported "AGENTS.md
  names the staged-swap note as Last session" — which was false; the reference was there the whole time, just
  invisible to the pattern. This repo has a documented history of exactly this trap. **An absence of matches is
  not evidence of absence when the pattern may be wrong.**

- **`grep -c` exiting 1 is not a failure.** After confirming two stale phrases were gone, the shell reported
  `exit code 1` — grep's no-match signal, which was the *desired* outcome. Left unexplained it reads as a
  failed check.

- **I asserted "suite 131/131" without re-running it.** The claim sat in a task's metadata, carried forward
  from an earlier run in the session — the exact violation
  `verification-before-completion` names ("previous run" is not sufficient evidence). It happened to still be
  true, which makes it no less a violation. Re-running it afterwards cost two seconds.

- **An inconclusive check is not a check.** My first pass at `widget_test.dart` used a grep that matched 2 lines
  and told me nothing; I nearly reported `#1` as verified on that basis. Reading the file settled it — and that
  same read is what exposed the stale `MAP.md` invariant.

## Decisions

- **The route belongs in the map's index, not only in a decision file.** A decision file holds the reasoning;
  the index must be able to answer "what is next" without re-surveying the plan. Decision 01 keeps the full
  argument, `MAP.md` now carries the table.

- **A phase whose question is not yet sharp stays in Fog of War, but must be *linked* from the phase table.**
  Phase 4 gets a fog entry naming it as Phase 4's ticket rather than a premature decision file — the same rule
  the map already applies between Fog and Frontier.

- **Superseded instructions are struck, not deleted.** Decision 01's paragraph is quoted inside a `CORRECTED`
  block so a future reader can see what was believed, why it was wrong, and where the live answer is. Deleting
  it would erase the reason decision 11 exists.

- **Task tracker items carry their evidence inline.** A later session should be able to check a completion
  claim, not re-derive it. This is what stops the tracker going stale silently a second time.

## Wins & Next Step

Verified fresh at `cc7e023`, all in one pass: `flutter analyze` → **"No issues found!"**; `flutter test` →
**131 passing, exit code 0**; working tree **clean**; **82** commits ahead of `origin/master`.

State, with the evidence that backs it:

- **Phase 0** — complete; all 7 rows built and re-verified against the code, not the ledger.
- **Map** — route in the index, every phase names a ticket, Phase 4 tracked, decision 01 reconciled,
  `widget_test` invariant corrected. 8 locked decisions · 3 open (05, 06, 09).
- **Task tracker** — 8 completed, 1 open: **`#9 Phase 1 products catalogue wiring`**.
- **TDD evidence** — the RED/GREEN logs for every Phase 0 task are on disk under `.superpowers/sdd/MAP/`,
  including the `hasMore` red log carrying `Expected: false / Actual: <true>`.

**Next step:** run `#9` under `executing-plans` — wire the products catalogue to `GET /api/v1/products/` +
`GET /api/v1/batches/` using the already-built `ApiClient.getList<T>` (returning `Paged<T>`), `AsyncView`
(decision 07) and `assembleCatalogue`. It needs **no new decisions**. Check commit `22c7c26` first — it holds a
salvageable earlier attempt at exactly this wiring (`planning/02-lost-work-recovery.md`). Phases 3, 5 and 6
remain gated by decisions 06, 09 and 05.

Still open and out of scope for the client-only map: the probable backend bug in
`apps/inventory/services.py::apply_stock_adjustment` (a positive adjustment is silently discarded when no batch
has `current_qty > 0`).
