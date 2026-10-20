# planning/cashier-workflow/MAP.md

**Slug:** `cashier-workflow` · **Opened:** 2026-10-20 · **Status:** 1 locked · 2 open · 1 blocked

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
| :--- | :--- | :--- | :--- |
| 1 | Linux token storage — no keyring prompt | — ([Linux Token Storage](./decisions/01-linux-token-storage.md) locked) | [ ] Pending (ready to build) |
| 2 | POS shell navigation — every tab routes | POS Navigation Wiring, Cashier Tab Set | [ ] Pending |
| 3 | Cashier reach to history & receivables | Cashier Reach to History & Receivables | [ ] Pending |

## Destination

A cashier logs in **once** with no keyring prompt, and every tab in the cashier's sidebar opens either a
live screen or does not exist. No tab does nothing.

## Notes & Invariants

- **Inherited from the [api-integration map](../api-integration/MAP.md)** (complete, closed): one data path
  `View → ViewModel → Repository → Service → ApiClient`; loading/error/empty per decision 07; RED-first
  tests: a test counts only after it has been seen failing without the fix.
- **The cashier shell has never navigated.** `flutter/lib/features/dashboard/widget/dashboard_shell.dart:68`:
  every sidebar `onTap` is `() {}`, and `DashboardNavigationItem` (line 148) has **no route field**. The Notifications
  button (line 125) is also `() {}`. The other three roles' shells navigate: admin uses
  `(label, icon, route)` + `context.go` (`core/layout/admin_skeleton_layout.dart:83-85`), and inventory/sales use an
  ordered `*_navigation.dart` guarded by `test/**/sidebar_index_consistency_test.dart`.
- **The release counter is unreachable from the UI.** `/pos/release` (`routes.dart:61,303`) is referenced only by
  its own route. Commit `e9b0988` claimed a "clickable nav entry" but only added a label.
- **The cashier's two pages disagree about the sidebar:** the till (`pos/views/pos_transaction_page.dart:71-85`)
  lists New transaction · Held transactions · Transaction history · Customers · End of shift, and the
  release page (`pos/views/material_release_page.dart:41-44`) lists New transaction · Release materials ·
  Customers. Only two POS routes exist.
- **Server-side cashier powers** (`backend_django/apps/users/permissions.py`, `apps/*/views.py`):
  transactions + customers read/write (`IsPOSOrReadOnly`, `apps/pos/views.py:23`), ledgers read-only
  (`collectibles/views.py:38`), ledger-payments write (`:103`), material release (`IsPOSRole`,
  `requisitions/views.py:133`). There is **no** held/parked status (`SalesTransaction.Status` = COMPLETED · VOID ·
  REFUNDED) and **no** shift / end-of-day model anywhere.
- **Locked elsewhere, binding here:** [Customer Master-Data Scope](../api-integration/decisions/14-customer-master-data-scope.md)
  deleted the customers screen; utang lives in the checkout panel. That rules out a cashier "Customers"
  tab unless that decision is explicitly reopened. [Receivables Record Payment](../api-integration/decisions/19-receivables-record-payment.md)
  ruled Record payment "BUILD for Cashier+", but the page sits at `/sales/receivables`, which `redirectFor`
  (`routes.dart` `/sales/` fence) blocks for role `pos`. **The cashier half of decision 19 is unenforced.**
- Run harness: `flutter run -d linux` (WSLg) or `-d web-server --web-port 8080` against
  `http://127.0.0.1:8000`; cashier login `cashier` / `demo1234`.

## Decisions So Far

- [Linux Token Storage](./decisions/01-linux-token-storage.md): Linux (non-web) keeps JWTs in
  `shared_preferences`; every other platform keeps `flutter_secure_storage`. The store is injectable for
  tests. Ends the gnome-keyring prompt.

## Active Frontier (Open & Unblocked)

- [ ] POS Navigation Wiring — research. Which existing house pattern the POS shell adopts (route-carrying
  items vs an ordered `pos_navigation.dart` under the consistency test), and what happens to the
  `() {}` Notifications button.
- [ ] Cashier Tab Set — grill. Which tabs the cashier's sidebar keeps: New transaction and Release
  materials have pages; Transaction history has a backend; Customers is ruled out by decision 14 unless
  reopened; Held transactions and End of shift have **no backend at all**.

## Blocked

- [ ] Cashier Reach to History & Receivables — grill (Blocked by: Cashier Tab Set). Whether the cashier
  reaches transaction history and Record payment by a fence exemption (like
  [Approve Queue Route Gate](../api-integration/decisions/20-approve-queue-route-gate.md)) or through POS-native pages,
  and whether decision 19's cashier half is honoured or narrowed.

## Fog of War (Not Yet Specified)

- A held/parked-sale model, **only if** Cashier Tab Set keeps Held transactions (client-only cart parking vs a
  server status: unknown until then).
- A shift / end-of-day model (Z-reading, cash-drawer count), **only if** Cashier Tab Set keeps End of shift.
- The till's subtitle "Frontend transaction and inventory simulation" (`pos_transaction_page.dart:69`) is stale
  copy on a live screen. Cosmetic; it rides along with whichever build touches the till first.

## Out of Scope

- Other roles' gaps in `docs/SYSTEM_ATLAS.md` §3 (suppliers, purchases, audit logs, monitoring, settings,
  categories writes). They belong to later maps.
- Production hardening (secrets, settings split, encrypted Linux token storage). Ruled past this
  destination by [Linux Token Storage](./decisions/01-linux-token-storage.md)'s accepted cost.
