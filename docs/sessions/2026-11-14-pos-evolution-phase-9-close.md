# POS evolution Phase 9 close — per-location stock + transfers (Done 2026-11-14)

Decision [21 Per-location stock and transfers](../../planning/pos-evolution/decisions/21-per-location-stock.md). Plan: `planning/pos-evolution/phase-9-plan.md` (all B/F ticked, Task close ticked 2026-11-14).

## What shipped (docs closeout only — no code touched this turn)

Batches carry an immutable `location` (backfilled to each product's `stored_at`, now its home); transfer-born batches copy receipt/cost/price/expiry with `source_batch` set, skipped by receipt sums. Allocator takes home → active → inactive, FIFO within. `GET /stock-on-hand/` is the server quantity read; `/batches/` keeps `location`/`location_name`/`source_batch` for cost/valuation. Sale, release and delivery-slip lines gain `pick_up` (base units when a selling unit splits shelves). One-step `POST /stock-transfers/` (`TR-…`, counter reserved last, append-only, `IsInventoryRole`, `STOCK_TRANSFER` audit). Receiving/adjustment payloads accept optional `location` (omitted = home); inactive shelves refuse additions but allow removals and outward transfers. Valuation gains `by_location`; movements `qty_in` skips transfer copies.

## Gates (controller-owned, local gitignored logs)

- Backend **1306 OK**, `check` clean, drift **No changes detected** (`temp/p9/full/backend.log`).
- Flutter **2224 passed / 241 skipped**, analyze clean (`temp/p9/full/flutter.log`, `temp/p9/full/analyze.log`).
- Goldens **241 passed** with **8 intended masters** inspected (stock/low-stock captions, Transfers rail icons; 233 byte-identical) — `temp/p9/full/golden-final.log`, `temp/p9/golden-final-review.md`.
- Whole-change review **APPROVED** (`qb_ecosystem/temp/p9/whole-review.md`); F2 fix **CONFIRMED** (`temp/p9/f2/review-fix.md`).
- Isolated QA **8 groups PASS, 0 defects**: `temp/p9/phase-close-qa/report.md` + `runtime.log` — Django APIClient in-process (not HTTP/UI) on disposable `qa_phase9_runtime_*` (dropped, `test_db_exists=False`); QA base left at inventory 0014 / users 0007; base DB untouched. Covers backfill totals, receiving destination/default/inactive, split sale + return restoration with matching slip captions, Phase 7 split fulfilment, CPMS import/review/partial release, transfer FIFO/total/number/slip/audit + guards (cashier 403), Phase 8 cross-location return + inactive-source removal, final API-vs-DB match.

## Docs touched this turn

`phase-9-plan.md` (Task close ticked), `AGENTS.md` (Phase 9 Done, next Phase 3), `MAP.md` (phase 9 done), `ENDPOINTS.md` (storage-locations home-shelf note), `SYSTEM_ATLAS.md` + `system-atlas.html` (Phase 9 stock truths), `QA-PROFILE.md` (Phase 9 boundary + gaps), this note. Nothing saved under `temp/`. No commits, no test runs, no DB, no tunnels.

## Residual limits (not passes — do not widen)

- 760px golden cards continue below fold: offscreen cards unverified in PNGs.
- Golden font/platform dependence stands.
- Native (Windows/Linux) and browser UI untested — QA was in-process APIClient only: no browser clicks, no printing/PDF legibility, no 1.3 text-scale, no keyboard traversal, no concurrency races.
- Inherited Phase 5/6/7/8 limits unchanged.

## Next

Phase 3 (Excel catalogue round-trip) is Pending under the same authorization (then 2). No push, no dev startup/migration/reset.
