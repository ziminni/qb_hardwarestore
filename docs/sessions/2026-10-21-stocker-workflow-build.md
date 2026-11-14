---
date: 2026-10-21
slug: stocker-workflow-build
map: planning/stocker-workflow/MAP.md
commits: [4a8e778, 93dee71, e738046, 30976b7]
gate: flutter 485/485, analyze clean, backend untouched
---

## Focus

BUILD stocker-workflow Phases 1–4 (executing-plans, inline): Returns tab, Reports tab, Settings tab, dashboard buttons. Single expressive-dev subagent (deepseek-v4.1-flash), hygiene review (glm-5.3-flash), no qa-tester subagent — used inline gates instead. Answer open question: no new backend needed, no extra Wayfinder needed.

## What Was Built / Changed

- `4a8e778` feat(inventory): 3 new pages — `inventory_returns_page.dart` (live `InventorySalesViewmodel.returns`, load-on-open, error banner + retry, empty state), `inventory_reports_page.dart` (static lock-icon access banner, zero API), `inventory_settings_page.dart` (3 disabled TextFormFields, no Save).
- Same commit: 3 route constants + 3 GoRoutes (`/inventory/returns`, `/reports`, `/settings`); `navigateInventory` cases 10/11/12; dashboard Export deleted, Add-product → `context.go(AppRoutes.inventoryProducts)`.
- Sidebar index bug fixed: Returns label sat at slot 9 but map had Receiving=9 → Returns opened Receiving. Corrected order: Receiving=8, Sales=9, Returns=10, Reports=11, Settings=12. Touched `inventory_skeleton_layout.dart` (+Receiving destination), `inventory_sales_page.dart` 8→9, `inventory_receiving_page.dart` 9→8, consistency test updated.
- 16 new tests (469→485): routing tap-through vs sidebar literal, stocker page rows/error/empty/read-only, dashboard Export-absent + Add-product-present.
- `93dee71` docs(icm): MAP phases → Done, D-02 text corrected (banner, not Valuation/Movements tabs), D-03 text corrected (fields inlined, `AdminSettingsForm` NOT reused — unremovable Save button), AGENTS pointer updated.
- `e738046` + `30976b7` style: pi-lens auto-format on 4 flutter files (formatter-only, re-verified after each).

## Mistakes & Gotchas (Do Not Repeat)

- MAP index map wrong: said Returns/Reports/Settings = 9/10/11. Source truth: Receiving already wired at 9 (mis-mapped). Always derive sidebar indices from `InventorySkeletonLayout` literal, never from MAP prose.
- pi-lens LSP fires stale URI errors from RED phase (test written before routes exist). `ls` + fresh `flutter analyze` refutes. Never chase LSP cache without re-running analyzer.
- `InventoryActionButton.onPressed` defaults to `() {}` — future button without handler silently dead. Always pass explicit `onPressed`.
- Spec test used bare `InventoryViewmodel()` → renders spinner, action row absent, assertions vacuous. Dashboard widget tests need stub repos + `await load()` to reach loaded state.
- `InventorySkeletonLayout` body is unbounded `SingleChildScrollView` — no `Expanded`/flex inside pages.
- Parallel subagents would have conflicted: Phases 1–3 all touch `routes.dart` + `inventory_navigation.dart`. One agent for shared files.

## Decisions

- No new Wayfinder, no new backend: Returns reuses `GET /transactions/` (inventory role already admitted via `IsPOSOrReadOnly`); Reports static banner (all `/reports/*` IsManagerRole-gated 403); Settings static (zero backend even for Admin); dashboard buttons pure wiring.
- One subagent for all 4 phases (shared-file conflicts), not 4 parallel.
- D-02 implementation beats written decision (banner > dead tabs that would only render 403 shells) — doc corrected, not code.
- D-03 inlines fields instead of reusing `AdminSettingsForm` (Save button unremovable) — documented in MAP.
- qa-tester subagent skipped: prior 402 failure history + inline `flutter test` + `flutter analyze` + hygiene review sufficed.

## Wins & Next Step

- Wins: all 13 stocker sidebar tabs live, zero dead controls, `flutter test +485`, `flutter analyze No issues found!`, backend untouched, tree clean at `30976b7`.
- Next: user runs `git push` (assistant shell cannot — no SSH key), then Wayfinder next epic (Sales role gaps, Admin monitoring pages, or CPMS repo).
