---
date: 2026-10-16
branch: feature/backend-integration
commits:
  - 938547e  # decision 13 locked
  - a5de98b  # phase 2 row marker
  - 363ff74  # InventoryService + InventoryRepository
  - 0f2ac12  # server-authoritative InventoryViewmodel
  - 380cffb  # seed_demo alerts + adjustments
  - 0e86eb3  # dart format after the service work
  - 3df40cd  # screens wired, adjustments POSTed
  - 6011bcf  # the adjustment write is atomic and its actor server-owned
  - 794e83a  # type-checker config
  - 89961a6  # session note, MAP/AGENTS sync, dead imports, pyright directive
  - ATLAS     # truth-matrix refresh for the two rows Phase 2 re-graded in reason
scope: Phase 2 — the server becomes the single authority for inventory state
repo: qb_pos_inventory_system
skills: [wayfinder, executing-plans, test-driven-development, verification-before-completion, save-progress]
---

# Phase 2 — the server owns inventory state

## Focus

Decision 13 made the POS backend the single authority for inventory state: the low-stock screen reads
`GET /api/v1/alerts/`, the movements screen reads `GET /api/v1/adjustments/`, and the adjust dialog POSTs instead
of mutating local batches. Five ledgered tasks, executed inline with TDD per step.

## What Was Built / Changed

| Task | Deliverable |
| :--- | :--- |
| 1 | `data/models/system_alert.dart`, `data/services/inventory_service.dart`, `data/repositories/inventory_repository.dart` — alerts read, adjustments read, adjustment create. `363ff74` |
| 2 | `InventoryViewmodel` becomes server-authoritative: it takes an `InventoryRepository`, `load()` also fetches alerts and adjustments, and `statusForVariant` adopts the server's exact predicate. `0f2ac12` |
| 3 | `seed_demo` gains `_seed_adjustments` — 5 adjustments recorded through the real service path, which also generates the `LOW_STOCK` alert. `380cffb` |
| 4 | The low-stock screen reads `alerts`; `adjustStock` POSTs then re-reads; the movements table renders an em dash where the API has no value. `3df40cd` |
| 5 | Live end-to-end verification — which found two production defects. `6011bcf` |

Net: 190 lines of invented fixture-seeding deleted (`_seedMovements` and its orphaned helper), the client's
adjustment FIFO path deleted, and six tests deleted that had encoded the removed behaviour.

**Two backend changes went beyond decision 13's "seed_demo only" scope, and both are recorded rather than
quiet**: `StockAdjustmentSerializer.user` became read-only (the user chose this over sending the actor from the
client), and `StockAdjustmentViewSet.perform_create` became atomic. Neither was optional — the endpoint could not
succeed from any client without them.

**`docs/SYSTEM_ATLAS.md` and `docs/system-atlas.html` were refreshed incrementally** for the two rows Phase 2
changed. The grades did **not** move (Low stock stayed Live, Stock movements stayed Partial), so the tally is
unchanged at 6 · 4 · 20 · 8 — what changed is the *reason*, and the artifacts had two now-false claims: "derived
in-client" / "/alerts/ still uncalled" and "movement history still `_seedMovements()`".

## Mistakes & Gotchas

- **I fixed the transaction bug in my own code and never asked whether production had it too.** My seeder hit
  `select_for_update cannot be used outside of a transaction` and I wrapped it. The view had the same bug and it
  was worse — it also committed the adjustment row *before* the stock move, so the ledger recorded adjustments
  that never happened. Fixing the instance in front of me instead of the class is the mistake of this session.
- **`zip(plan, variants.values())` paired adjustments with arbitrary variants.** I assumed the first value was the
  low-stock variant. It was not: the adjustments landed on variants 4, 3, 6, 7, 8, `/adjustments/` filled up and
  `/alerts/` stayed empty — a silent half-success invisible to code reading. Fixed by selecting by query.
- **An earlier claim of mine was simply wrong.** I reported "nothing is anywhere near low" after checking
  thresholds and *inferring* stock. Variant 1 sits at 6 against a threshold of 20. The seed creates the low-stock
  situation but never generated the alert.
- **Deleting a Dart method shifts every later line number**, so an analyzer warning at "line 543" named the *next*
  method, not the one just removed.
- **Test-writing:** a `Map` is required, not a pre-encoded `String`, when a fake Dio adapter encodes the body
  itself; fakes returning `List<SystemAlert>`/`List<StockAdjustment>` need both model imports or `analyze` fails
  with `non_type_as_type_argument`.
- **Tooling:** the bundled type-checker reports ~27 false errors per Django file. No repo config was being read —
  `pyrightconfig.json` must sit at the **repo root**, because pyright walks *up* from the file.

## Decisions

- **Ruling: the local movement log is narrowed, not deleted.** Decision 13 assumed the API covers movements. It
  does not: `/api/v1/adjustments/` is the adjustment subset only, while the local log was also fed by POS sales
  and opening stock. Deleting it wholesale would make a demo sale produce no movement row at all. Adjustments are
  server-sourced; a narrowed local list is retained for sales and opening stock.
- **Ruling: Previous / New / Reference render an em dash** on server rows. `StockAdjustmentSerializer` carries a
  delta with no before/after pair or reference. Deriving them client-side is unsound — receipts and sales moved
  stock too. The mock had invented them.
- **Ruling: six tests were deleted, not rewritten in place.** They asserted client-side FIFO that decision 13
  removes. A test encoding removed behaviour is an obstacle, not a regression guard. `sellStock` still deducts
  locally and keeps its own coverage.
- **Ruling: `reportGeneralTypeIssues` stays ON.** It catches real type bugs, and the few false positives on
  `transaction.atomic()` are a codebase-wide pre-existing idiom (5 of its 7 sites predate this work), so they are
  documented rather than suppressed across five unrelated files.
- **User decision:** `user` became read-only on the serializer rather than being sent from the client — the actor
  is not the client's to choose.

## Wins & Next Step

The live probe is the win. `flutter run` had never been executed against the backend, and every previous
verification was widget tests over a fake adapter. POSTing the client's real body to the running server found an
HTTP 400 and an HTTP 500 with a partial write — neither was reachable by reading or by faking.

**Verified:** `flutter analyze` clean, **161/161 tests**, `manage.py check` 0 issues, tree clean, 99 commits
ahead of `origin/master`.

**Honest boundary:** the *contract* is now proven against the real server; the *pixels* are not. `flutter run`
still has not been executed, and the product Add/Edit/Archive paths remain memory-only by decision 12.

**Next step:** Phase 3 — [POS Checkout Client Contract](../../planning/api-integration/decisions/06-checkout-client-contract.md),
the only unblocked frontier item. Worth considering first: adopting `django-stubs` (proven to let both pyright
rules stay on with zero suppressions) as a dev dependency.
