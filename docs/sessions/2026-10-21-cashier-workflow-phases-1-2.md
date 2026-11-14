---
date: 2026-10-21
slug: cashier-workflow-phases-1-2
map: planning/cashier-workflow/MAP.md
branch: feature/backend-integration
gate: backend 89/89 · flutter 417/417 · analyze clean
---

## Focus

Build Phases 1 and 2 of the cashier-workflow map: kill the gnome-keyring prompt on Linux,
then make every POS sidebar tab navigate to a live screen (tabs 0–3).

## What Was Built / Changed

**Phase 1 — Linux Token Storage** (`3bd0fdb`)
- `flutter/lib/core/network/token_store.dart`: `TokenStore` abstract + `SecureTokenStore` (macOS/Windows/mobile/web) + `PrefsTokenStore` (Linux non-web) + `tokenStoreForPlatform` selector.
- `flutter/lib/core/network/api_client.dart`: `_storage` → `_store` seam; `@visibleForTesting set tokenStore` setter; 4 call sites migrated.
- `flutter/test/core/network/token_store_test.dart`: 6 tests (prefs round-trip, selector ×4, ApiClient round-trip).
- `README.md`: troubleshooting section updated — prompt fixed in code.

**Phase 2 — POS Navigation + Reach** (`95358c1`)
- `flutter/lib/features/pos/widgets/pos_navigation.dart`: `posNavigationItems` (4 items, append-only order) + `navigatePos(context, index)`.
- `flutter/lib/features/dashboard/widget/dashboard_shell.dart`: `onNavigationSelected` callback replaces dead `onTap: () {}`; Notifications button deleted.
- `flutter/lib/features/pos/views/pos_transaction_history_page.dart`: new — POS-shell wrapper over global `InventorySalesViewmodel`.
- `flutter/lib/features/pos/views/pos_receivables_page.dart`: new — POS-shell wrapper with `SalesReceivablesViewmodel` + Record payment dialog.
- `flutter/lib/routes/routes.dart`: `/pos/history`, `/pos/receivables` registered; imports added.
- `flutter/lib/features/pos/views/pos_transaction_page.dart`: inline 5-item nav list → shared `posNavigationItems`; stale subtitle "Frontend transaction and inventory simulation" → "New transaction".
- `flutter/lib/features/pos/views/material_release_page.dart`: inline 3-item list → shared; `selectedNavigationIndex` 1 → 2.
- `flutter/test/routes/pos_navigation_routing_test.dart`: 7 tests (pos reaches all /pos/*, bounced from /sales/ /admin/ /inventory/).
- `flutter/test/routes/sidebar_index_consistency_test.dart`: extended for POS (scans `lib/features/pos/views/`, marker `posNavigationItems`).

## Mistakes & Gotchas (Do Not Repeat)

1. **pi-lens LSP stale cache on new files.** `pos_navigation.dart` showed `UNDEFINED_GETTER` for `posHistory`/`posReceivables` even after routes.dart was edited and saved. Both `dart analyze` and `flutter analyze` reported zero issues. The LSP cache never caught up during the session. Trust `flutter analyze` over the LSP overlay when they disagree on a newly-created file.
2. **`InventorySale` has `.total` (computed from lines), not `.grandTotal`.** The wire model's `grandTotal` lives on `SalesTransaction` (the raw API shape), not on the mapped `InventorySale`. Also `InventorySalesStatusBadge` is a named-factory (`InventorySalesStatusBadge.sale(status:)`), not a direct constructor.
3. **`SalesRecordsTable` requires `emptyMessage`** — a required named param missed on first write. Rows must be `List<Widget>`, not `List<dynamic>`.
4. **`defaultTargetPlatform` defaults to `android` in `flutter test`**, not the host OS. This is *good* — it means existing tests that use `FlutterSecureStorage.setMockInitialValues` keep the secure path (no regression), while the real Linux desktop gets the prefs path. `dart:io Platform.isLinux` would have reported the host OS even in tests, breaking them.
5. **Workspace basename collision.** `planning/cashier-workflow/MAP.md` and `planning/api-integration/MAP.md` both have basename `MAP`, so the SDD workspace script would point both to `.superpowers/sdd/MAP/`. Used `.superpowers/sdd/cashier-workflow/` instead.

## Decisions

All four decisions (01–04) were locked in the previous wayfinder session. This session executed them.
- **Ruling (build-time):** selector uses `defaultTargetPlatform` (flutter/foundation) instead of `dart:io Platform.isLinux`. Cost if wrong: a dev forcing TargetPlatform override sees prefs.

## Wins & Next Step

**Wins:**
- The gnome-keyring prompt is dead in code (live WSL check user-pending — user must run `flutter run -d linux` as `cashier`).
- All 4 POS sidebar tabs navigate to live screens. No tab does nothing.
- Gate: backend 89/89, flutter 417/417, analyze clean.
- Both phases passed fresh-context review (glm-5.3-flash) with 0 Critical, 0 Important.

**Next:**
- Push `feature/backend-integration` (user's terminal — SSH unavailable in the environment).
- Verify the live WSL check for Phase 1.
- To unlock Phases 3–4: Wayfinder to resolve decisions 05 (held sale model) and 06 (shift/Z-reading). Or ship tabs 0–3 as the capstone deliverable if the timeline is tight.
