---
date: 2026-10-22
slug: sales-manager-workflow-build
map: planning/sales-manager-workflow/MAP.md
commits: [9cbeb9a]
gate: flutter 512/512, analyze clean, backend untouched
---

## Focus

BUILD sales-manager-workflow Phases 1–3: Sales Reports tab in sales shell, View detail sheets on quotations/orders/transactions, live admin monitoring pages. Single expressive-dev subagent (deepseek-v4.1-flash), hygiene review (glm-5.3-flash).

## What Was Built / Changed

- `9cbeb9a` feat(sales): all 3 phases, one commit (485→512, +27 tests).
- Phase 1: NEW `sales_reports_page.dart` — `ChangeNotifierProvider<AdminReportsViewmodel>..load()` → `SalesSkeletonLayout(idx 6)` → shared `ReportsContent`. `reports_page.dart` refactored: `_ReportsView` now wraps EXTRACTED `ReportsContent` (admin shell kept). Route `/sales/reports` + `navigateSales` index 6. Routing test 11/11 (incl. real GoRouter tap-through).
- Phase 2: dead `onPressed: () {}` on 3 pages → `_show*Sheet` bottom sheets. Shared `sales_document_sheet.dart` read-only renderer. `SalesQuotation`/`SalesOrderRecord` gained `items` + `notes` (reused existing `QuotationLineItem`/`OrderLineItem` from `sale_transaction.dart`). Transactions sheet shows payments (`InventorySalePayment` mapped in `_saleOf`). View-buttons test 6/6.
- Phase 3: both monitoring pages → `StatefulWidget(repository?)` post-frame `_load()`. Sales chart from `SalesSummary.days`; inventory metrics from `InventoryValuation`. Deleted `AdminMockData.salesValues/labels/inventoryMetrics` (file kept — settings pages use store fields). Monitoring test 9/9.
- MAP phases → Done; AGENTS pointer → sales-manager BUILT.

## Mistakes & Gotchas (Do Not Repeat)

- pi-lens LSP resolves relative paths against `/home/yaji/projects/qb_ecosystem` (no `client` package) → ~20 false "URI doesn't exist / no named parameter" reports all session. `dart analyze` + `flutter test` authoritative. Absolute-path probes clean. Do NOT chase LSP cache without re-running analyzer.
- Mission text said "add QuotationLineItem to sales_module.dart" — models already existed in `sale_transaction.dart`. Duplicates would collide on import. Agent correctly reused.
- Mission said copy 400 lines of tab bodies — agent extracted `ReportsContent` instead. Better call, less duplication.
- `AdminSalesChart` calls `values.reduce` → throws on empty list. Pages guard with "No data for this period." Always check chart widgets for reduce/fold on possibly-empty lists.
- `context.read<InventoryViewmodel?>()` nullable lookup returns null gracefully (provider 6.1.5) — no try/catch needed.
- `sidebar_index_consistency_test` hard-asserted sales nav length 6 → updated to 7. Length assertions on nav lists break on every tab addition; prefer contains-checks.

## Decisions

- One subagent for all 3 phases (shared files: routes.dart, sales_navigation.dart) — same pattern as stocker build.
- Single combined commit vs MAP's one-per-phase: accepted, message accurate.
- RED-state evidence gap (reviewer warning #2): new tests use injection seams that didn't exist pre-fix, so literal pre-fix RED run impossible without partial harness. Tests assert real runtime behavior (retry counts, sheet content, mapped values) — accepted as genuine. Future BUILD prompts should require agent to log RED output in commit message or ledger.
- Deferred minors (reviewer #4–6): `_shortDate` triplication, `variantUomName` per-line catalogue rebuild, "Batches" vs "Batch count" label, tendered-vs-applied display. Next-touch polish, not fix-pass.

## Wins & Next Step

- Wins: all 7 sales sidebar tabs live, zero dead View buttons, monitoring charts real data, `flutter test +512`, analyze clean, backend untouched, tree clean at `9cbeb9a`.
- Next: user runs `git push`; then Wayfinder next epic (Admin monitoring remaining gaps, CPMS repo) or `executing-plans` if new MAP opens.
