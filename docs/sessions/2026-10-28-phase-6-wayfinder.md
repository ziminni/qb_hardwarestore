---
date: 2026-10-28
branch: feature/backend-integration
range: f9ac275..HEAD
gates: backend 468/468, flutter 771/771, analyze clean
---

## Focus

Fix the admin Sales monitoring red screen the user hit in `flutter run -d linux`, then Wayfinder Phase 6 (barcode) end to end: research, grill every open question, write the build plan.

## What Was Built / Changed

- **Crash fix `b5cfc33`:** `admin_sales_chart.dart` passed `values[i] / maximum` to `FractionallySizedBox.heightFactor`; an all-zero week gives `0/0 = NaN` and a refund-heavy day goes negative → assertion `heightFactor >= 0`. Now `range = maximum <= 0 ? 1 : maximum`, factor clamped `0..1`. 2 RED tests (all-zero, negative) failed pre-fix; file 11/11; full flutter 771/771. Formatter follow-up `c57c676`.
- **Phase 6 decisions** (`planning/audit-remediation/decisions/`): 11 Barcode baseline (research), 12 Code source & format, 13 Scan resolution, 14 Label printing, 15 Camera scanning, 16 Code assignment, 17 Scan-to-cart, 18 Selling-unit codes UI. Decision 10 now a pointer to these.
- **Plan:** `planning/audit-remediation/phase-6-plan.md` — Task 0 printing spike → T1–3 backend → T4–7 Flutter → gate → close.
- MAP row 6 → Ready to build; frontier/blocked/fog empty; non-Phase-6 fog moved to Out of Scope. AGENTS stale lines replaced.

## Mistakes & Gotchas (Do Not Repeat)

- **Example check digits were invented, and wrong.** The draft decisions had `QB000013-4`, `QB000003-5`, and the two EAN examples swapped between valid and invalid. Recomputed with GS1 mod-10 and fixed before commit. Known-answer vectors now live in plan Task 1. Never write a check-digit example without computing it.
- **MAP said the till "already supports" scanning — true but misleading.** `findByBarcode` exists, but (F3) each catalogue line carries the *variant's* first code, not its own unit's, and (F4) the dialog preselects `options.first`. Scanning a box label could sell a piece.
- **Latent truncation (F5):** `ProductsService.fetchCatalogue` uses `getList` (one page, `PAGE_SIZE` 50) for products *and* batches. Invisible in dev (9/17 rows); in a real store, product #51 is unsellable by search or scan and batch #51+ understates stock.
- **"RFID" in user speech meant barcode stickers.** Clarified before locking; a real RFID choice would have reopened every locked decision.
- AGENTS carried a paragraph from an older map ("Phase 6 is built and pushed… no build phase remains"). Removed.

## Decisions

All user-chosen via grill (recommended option each time unless noted):

- Hybrid codes: factory EAN/UPC kept; else `QB` + 6-digit id + `-` + GS1 check, Code 128 labels, `QB` prefix reserved.
- Every unit always has a code: model `save()` derives `QB`; PATCH `''` restores it; data migration backfills.
- Scan: complete loaded catalogue first; miss → `GET /variant-uoms/?barcode=` → reload.
- Whole units add 1 instantly; measured units open dialog with scanned unit preselected.
- USB/BT keyboard-wedge scanners only (camera needs HTTPS).
- **User-directed:** thermal barcode stickers (not A4 sheets, not RFID); label-sized PDF via OS print dialog; 50×30 mm; no price; Products + post-Receiving entry.
- Show + edit codes for every existing selling unit; no create-unit UI.

## Wins & Next Step

- Admin Sales monitoring tab no longer red-screens on zero/negative weeks.
- Phase 6 is fully specified with abuse cases and verified test vectors.
- **Next:** `git push` (user); then BUILD Phase 6, **Task 0 first** (`pdf` + `printing` spike on Linux desktop and web) before any label UI.
