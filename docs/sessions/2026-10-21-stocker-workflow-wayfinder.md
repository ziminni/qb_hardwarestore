---
date: 2026-10-21
slug: stocker-workflow-wayfinder
branch: feature/backend-integration
---

# Session: Stocker-Workflow Wayfinder

## Focus

Open the next Wayfinder epic after cashier-workflow closed: every stocker
(`inventory` role) sidebar tab must open a working screen. Audit which tabs are
broken (Returns / Reports / Settings have no routes), scope the dashboard
no-op buttons ("Add product", "Export"), and verify the teammate's
`ui/frontend-progress` file structure is still recognisable under our changes.

## What Was Built / Changed

- `planning/stocker-workflow/MAP.md` — NEW: Destination (every stocker sidebar
  tab works, zero backend work), Notes & Invariants (IsPOSOrReadOnly read access,
  reports IsManagerRole-gated, settings has no API, button no-op defaults),
  4 locked decisions, empty frontier/blocked, fog (initiate-return form,
  inventory report endpoint, settings save), 4-phase roadmap.
- `planning/stocker-workflow/decisions/01-returns-scope.md` — Option A locked:
  read-only RETURN list reusing `InventorySalesViewmodel` + `?source=RETURN`.
- `planning/stocker-workflow/decisions/02-reports-scope.md` — static "Manager
  access required" banner; no API call.
- `planning/stocker-workflow/decisions/03-settings-scope.md` — static read-only
  form reusing `AdminSettingsForm`, Save button removed.
- `planning/stocker-workflow/decisions/04-dashboard-buttons.md` — "Add product"
  → navigate to `/inventory/products`; "Export" deleted.
- `AGENTS.md` — active map pointer switched from `planning/cashier-workflow/`
  to `planning/stocker-workflow/`; Next set to Phase 1–4 BUILD.
- Commit `a57d21b` (6 files, +258/−7). Tree clean.
- Teammate-structure audit: their 165 `flutter/lib/` files all present under
  same paths; ours adds 42, deletes 19 orphans/mocks only.

## Mistakes & Gotchas (Do Not Repeat)

- `git diff --stat` piped through `cut`/`uniq` mangles the output into counts
  of `+` characters — useless. Use `git diff --name-only` + `cut -d'/'` for
  per-folder audits, and `git ls-tree -r --name-only <ref>` + `comm -23` to
  prove deletions.
- `inventory_returns_page.dart` / `sales_returns_page.dart` / inventory
  reports pages were deleted as orphans — the stocker sidebar labels "Returns /
  Reports / Settings" survived in `inventory_skeleton_layout.dart` with indices
  9/10/11 but `navigateInventory` has no cases 9–11 and `routes.dart` has no
  `inventoryReturns/Reports/Settings` constants → silent no-op tabs.
- Reports backend (`apps/reports/views.py`) is uniformly
  `@permission_classes([IsManagerRole])` — stocker gets 403 on all four
  endpoints. Any stocker Reports design that calls the API will fail.
- `InventoryActionButton.onPressed` defaults to `() {}` — a missing handler
  renders a clickable-looking dead button. Wire or delete, never leave default.

## Decisions

- D-01 Stocker Returns = Option A (read-only RETURN list). `inventory` role
  already has GET via `IsPOSOrReadOnly`. Option C (initiate-return form) → fog.
- D-02 Stocker Reports = static access banner, no viewmodel, no API call.
- D-03 Stocker Settings = static read-only form, no Save button, no backend.
- D-04 Dashboard buttons = "Add product" navigates to products page, "Export"
  deleted (no endpoint exists anywhere in client or API).
- Map Mode chosen (4+ screens, Returns design gates downstream); all decisions
  resolved via Research (repo reads) + user Grill on D-01.

## Wins & Next Step

- Wins: stocker-workflow MAP committed (`a57d21b`), 4/4 decisions locked,
  4-phase roadmap ready, AGENTS.md pointer fresh, teammate-structure question
  answered with file counts.
- Next: `executing-plans BUILD` for stocker-workflow Phases 1–4 (Returns route
  + wrapper page, Reports banner page, Settings static page, dashboard button
  wiring), each phase with nav test + widget test, gate full `flutter test` +
  `flutter analyze` clean.
