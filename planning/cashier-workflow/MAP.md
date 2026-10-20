# planning/cashier-workflow/MAP.md

**Slug:** `cashier-workflow` · **Opened:** 2026-10-20 · **Status:** 4 locked · 2 open (both domain-model)

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
| :--- | :--- | :--- | :--- |
| 1 | Linux token storage — no keyring prompt | [Linux Token Storage](./decisions/01-linux-token-storage.md) ✅ | ✅ Done — `3bd0fdb` 2026-10-20 (live WSL check user-pending) |
| 2 | POS shell navigation + reach (tabs 0–3 live) | [POS Navigation Wiring](./decisions/02-pos-navigation-wiring.md) ✅ · [Cashier Tab Set](./decisions/03-cashier-tab-set.md) ✅ · [Cashier Reach](./decisions/04-cashier-reach.md) ✅ | ✅ Done — `95358c1` 2026-10-21 |
| 3 | Held sale (tab 4) | [Held Sale Model](./decisions/05-held-sale-model.md) — OPEN | [ ] Pending (blocked on decision) |
| 4 | End of shift / Z-reading (tab 5) | [Shift / Z-Reading Model](./decisions/06-shift-z-reading.md) — OPEN | [ ] Pending (blocked on decision) |

## Destination

A cashier logs in **once** with no keyring prompt, and every tab in the cashier's sidebar opens a live
screen. No tab does nothing.

## Notes & Invariants

- **Inherited from the [api-integration map](../api-integration/MAP.md)** (complete, closed): one data path
  `View → ViewModel → Repository → Service → ApiClient`; loading/error/empty per decision 07; RED-first
  tests (a test counts only after it is seen failing without the fix); the POS shell is its own skeleton.
- **The cashier shell has never navigated** — `dashboard_shell.dart:68` `onTap: () {}`, and
  `DashboardNavigationItem` carries no route. [POS Navigation Wiring](./decisions/02-pos-navigation-wiring.md)
  fixes this.
- **Canonical POS tab order (append-only)** from [Cashier Tab Set](./decisions/03-cashier-tab-set.md):
  0 New transaction · 1 Transaction history · 2 Release materials · 3 Record payment · 4 Held transactions ·
  5 End of shift. Tabs 0–3 ship in Phase 2; 4 and 5 are appended by Phases 3 and 4 so no index renumbers.
- **Server cashier powers** (`backend_django/apps/users/permissions.py`): transactions + customers R/W
  (`IsPOSOrReadOnly`), ledgers read, ledger-payments write, material release (`IsPOSRole`). There is **no**
  held/parked status (`SalesTransaction.Status` = COMPLETED · VOID · REFUNDED) and **no** shift model.
- **Customers is not a cashier tab** — [Customer Master-Data Scope](../api-integration/decisions/14-customer-master-data-scope.md)
  deleted the screen; utang shows in the checkout panel. Not reopened.
- Run harness: `flutter run -d linux` (WSLg) or `-d web-server --web-port 8080` vs `http://127.0.0.1:8000`;
  cashier `cashier` / `demo1234`.

## Decisions So Far

- [Linux Token Storage](./decisions/01-linux-token-storage.md): Linux (non-web) keeps JWTs in
  `shared_preferences`, other platforms keep `flutter_secure_storage`; store is injectable. Ends the prompt.
- [POS Navigation Wiring](./decisions/02-pos-navigation-wiring.md): POS adopts the inventory/sales pattern —
  one `pos_navigation.dart` (`navigatePos`), a `DashboardShell.onNavigationSelected` callback, the dead
  Notifications button deleted, POS joins `sidebar_index_consistency_test`.
- [Cashier Tab Set](./decisions/03-cashier-tab-set.md): six tabs (full till); Customers excluded; tabs 0–3
  backend-ready, 4 and 5 are new backend.
- [Cashier Reach](./decisions/04-cashier-reach.md): build POS-native `/pos/history` and `/pos/receivables`
  reusing the existing viewmodels — the cashier never leaves the POS shell (no fence exemption).

## Active Frontier (Open & Unblocked)

- [ ] [Held Sale Model](./decisions/05-held-sale-model.md) — **domain-model.** Server shape behind tab 4: a
  new `HELD` status on `SalesTransaction` vs a separate parked-cart entity; how a held sale serializes,
  resumes into the till, voids, and whether it reserves stock.
- [ ] [Shift / Z-Reading Model](./decisions/06-shift-z-reading.md) — **domain-model.** New Shift entity:
  open/close, cash-drawer count, end-of-day Z-reading totals, which transactions a shift owns.

## Blocked

_None._ Both open decisions are independent (different backend areas, different tabs).

## Fog of War (Not Yet Specified)

- The till subtitle "Frontend transaction and inventory simulation" (`pos_transaction_page.dart:69`) is stale
  copy on a live screen. Cosmetic; rides along with the Phase 2 build that touches the till.

## Out of Scope

- Other roles' gaps in `docs/SYSTEM_ATLAS.md` §3 (suppliers, purchases, audit logs, monitoring, settings).
- Production hardening (encrypted Linux token storage, secrets). Ruled past by
  [Linux Token Storage](./decisions/01-linux-token-storage.md).

---

# Implementation Roadmap — READY PHASES (1 & 2)

Phases 3 and 4 wait on [Held Sale Model](./decisions/05-held-sale-model.md) and
[Shift / Z-Reading Model](./decisions/06-shift-z-reading.md); their roadmap is written when those decisions
lock. Phases 1 and 2 are fully specified now. Each task's detail lives in its decision's **Build contract**.

## Phase 1 — Linux Token Storage (independent; can build first or in parallel)

Source: [Linux Token Storage](./decisions/01-linux-token-storage.md).

1. **Token-store seam.** Extract an injectable token store behind `ApiClient` over the two existing keys
   (`auth_access_token`, `auth_refresh_token`); selector is `!kIsWeb && Platform.isLinux` → prefs store,
   else secure store. Guard `dart:io` so web still compiles.
   - RED: round-trip test (prefs store injected) for save/restore/clear; selector test driven by an injected
     platform flag. Both fail before the seam exists.
2. **README + live check.** Update README.md:182-187 (prompt fixed in code, why). Verify on WSL:
   `flutter run -d linux`, log in `cashier` → no keyring dialog; restart → still signed in.
   - Ends when: no prompt, session persists, `flutter test` + `flutter analyze` green.

## Phase 2 — POS Navigation + Reach (tabs 0–3 live)

Sources: [POS Navigation Wiring](./decisions/02-pos-navigation-wiring.md),
[Cashier Tab Set](./decisions/03-cashier-tab-set.md), [Cashier Reach](./decisions/04-cashier-reach.md).

1. **`pos_navigation.dart`** — `navigatePos(context, index)` + the shared 4-item list (indices 0–3:
   New transaction → `/pos/dashboard`, Transaction history → `/pos/history`, Release materials →
   `/pos/release`, Record payment → `/pos/receivables`). Single source of POS nav order.
2. **`DashboardShell`** — add `ValueChanged<int>? onNavigationSelected`, call it from the ListTile `onTap`,
   **delete the dead Notifications button**.
3. **POS-native pages** — `PosTransactionHistoryPage` (`/pos/history`, global `InventorySalesViewmodel`) and
   `PosReceivablesPage` (`/pos/receivables`, self-scoped `SalesReceivablesViewmodel()..load()`, Record
   payment per decision 19). Both wrap `DashboardShell`; load-on-open + `LiveLoadErrorBanner` + retry.
4. **Routes** — register `/pos/history`, `/pos/receivables` in the POS-reachable set (not behind `/sales/`);
   both POS pages render the shared 4-item list and pass `navigatePos`; `material_release_page.dart` →
   `selectedNavigationIndex: 2`.
5. **Fix the stale till subtitle** (Fog item) while the till is open.
   - RED-first: extend `sidebar_index_consistency_test.dart` for POS (order ↔ `navigatePos` ↔ `routes.dart`);
     routing test — `pos` reaches `/pos/*`, still bounced from `/sales/*` and `/admin/*`; widget test —
     tapping tab N calls `onNavigationSelected(N)` and the POS receivables page shows live rows + Record
     payment. All fail against today's `() {}` and missing routes.
   - Ends when: as `cashier`, tabs 0–3 each open a live POS-shell screen, none inert; suite green.
