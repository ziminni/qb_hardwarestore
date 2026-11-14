# POS Navigation Wiring

**Status:** LOCKED 2026-10-20 (research) · **Mode:** research · **Map:** [cashier-workflow](../MAP.md)

## Question

The POS shell's sidebar does nothing (`dashboard_shell.dart:68`, `onTap: () {}`). *How* should it route —
which of the two house patterns does POS adopt, and what single source holds the nav order? (The *contents*
of the list are [Cashier Tab Set](./03-cashier-tab-set.md), not this decision.)

## Findings (verified in source, 2026-10-20)

- `DashboardShell` is **POS-only**: consumed by `pos_transaction_page.dart`, `material_release_page.dart`
  and `test/features/pos/pos_transaction_pay_test.dart`. It is NOT one of the three
  `core/layout/*_skeleton_layout.dart`. Blast radius of editing it is the POS feature alone.
- Two house patterns exist:
  - **Admin:** items are records `(label, icon, route)`; the shell self-routes with `context.go(item.$3)`
    when no `onNavigationSelected` is given (`core/layout/admin_skeleton_layout.dart:24-31,83-85`).
  - **Inventory / Sales (dominant — 8+ pages):** a free function `navigate<Area>(context, index)` maps
    index → route (`features/inventory/widgets/inventory_navigation.dart:5-19`), wired through the shell's
    `onNavigationSelected` callback (`products_page.dart:200`, etc.), and guarded by
    `test/**/sidebar_index_consistency_test.dart`.
- The POS pages hardcode **two different inline lists** (`pos_transaction_page.dart:71-85` has 5 items,
  `material_release_page.dart:41-44` has 3) with no shared source — exactly the drift the consistency test
  was built to stop, except POS was never added to it.
- `DashboardNavigationItem` (`dashboard_shell.dart:148`) carries only `(label, icon)` — no route.
- The `Notifications` button (`dashboard_shell.dart:125`) is also `onTap: () {}`. There is no notifications
  feature, viewmodel, or endpoint anywhere in `lib/` or the backend.

## Ruling

**POS adopts the inventory/sales pattern.** Specifically:

1. **One source of POS nav order:** a new `features/pos/widgets/pos_navigation.dart` with
   `void navigatePos(BuildContext context, int index)` switching index → route (the same shape as
   `navigateInventory`). It is the single home for the POS tab order; the item labels/icons list it drives
   lives beside it so the two cannot drift.
2. **`DashboardShell` gains `ValueChanged<int>? onNavigationSelected`** and calls it from the ListTile
   `onTap` (replacing `() {}`), mirroring `admin_skeleton_layout`. Both POS pages pass
   `onNavigationSelected: (i) => navigatePos(context, i)` and the **same** shared item list + their own
   `selectedNavigationIndex`.
3. **The dead `Notifications` button is removed,** not wired. No notifications feature exists; a button that
   does nothing is the anti-pattern the mock-purge already deleted elsewhere. If notifications are ever
   scoped, they return as a real feature.
4. **POS joins `sidebar_index_consistency_test.dart`:** the test asserts `navigatePos`'s index→route switch
   matches the shared item-list order and that every route it names exists in `routes.dart`. This is what
   makes a future "add a tab" safe.

This is the dominant pattern (8+ pages already use it) and the one already covered by a regression test, so
POS stops being the one shell nobody guards.

## Cost if wrong

If the admin self-routing pattern would have been simpler, we carry one extra free function and a callback
hop. Reversible: both patterns are small. The consistency-test coverage is pure upside.

## Build contract (for the executing session)

- New `features/pos/widgets/pos_navigation.dart`: `navigatePos(context, index)` + the shared item list
  (`List<DashboardNavigationItem>` or equivalent) that both POS pages render.
- `dashboard_shell.dart`: add `onNavigationSelected`, call it from the ListTile `onTap`, delete the
  `Notifications` button.
- Both POS pages: drop their inline lists, render the shared one, pass `navigatePos`.
- **The routes `navigatePos` maps to are fixed by [Cashier Tab Set](./03-cashier-tab-set.md)** — do not build
  this until that decision is locked, or the index→route switch has nothing to point at.
- **RED-first tests:** (1) extend `sidebar_index_consistency_test.dart` so POS order ↔ `navigatePos` ↔
  `routes.dart` agree; (2) a widget test that tapping tab N on the POS shell calls `onNavigationSelected(N)`
  (and, with a real router, lands on the mapped route). Both must fail against today's `() {}`.
- Verify live on WSL: as `cashier`, every sidebar tab changes the screen; none is inert.
