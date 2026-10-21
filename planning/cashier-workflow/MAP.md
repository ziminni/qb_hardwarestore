# planning/cashier-workflow/MAP.md

**Slug:** `cashier-workflow` · **Opened:** 2026-10-20 · **Status:** 6 locked · 0 open

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
| :--- | :--- | :--- | :--- |
| 1 | Linux token storage — no keyring prompt | [Linux Token Storage](./decisions/01-linux-token-storage.md) ✅ | ✅ Done — `3bd0fdb` 2026-10-20 (live WSL check user-pending) |
| 2 | POS shell navigation + reach (tabs 0–3 live) | [POS Navigation Wiring](./decisions/02-pos-navigation-wiring.md) ✅ · [Cashier Tab Set](./decisions/03-cashier-tab-set.md) ✅ · [Cashier Reach](./decisions/04-cashier-reach.md) ✅ | ✅ Done — `95358c1` 2026-10-21 |
| 3 | Held sale (tab 4) | [Held Sale Model](./decisions/05-held-sale-model.md) ✅ | [ ] Pending — **READY TO BUILD** |
| 4 | End of shift / Z-reading (tab 5) | [Shift / Z-Reading Model](./decisions/06-shift-z-reading.md) ✅ | [ ] Pending — **READY TO BUILD** (depends on Phase 3 for held-cart interlock in close advisory) |

## Destination

A cashier logs in **once** with no keyring prompt, and every tab in the cashier's sidebar opens a live
screen. No tab does nothing.

## Notes & Invariants

- **Inherited from the [api-integration map](../api-integration/MAP.md)** (complete, closed): one data path
  `View → ViewModel → Repository → Service → ApiClient`; loading/error/empty per decision 07; RED-first
  tests (a test counts only after it is seen failing without the fix); the POS shell is its own skeleton.
- **Canonical POS tab order (append-only)** from [Cashier Tab Set](./decisions/03-cashier-tab-set.md):
  0 New transaction · 1 Transaction history · 2 Release materials · 3 Record payment · 4 Held transactions ·
  5 End of shift. Tabs 0–3 shipped in Phase 2; 4 appends in Phase 3; 5 appends in Phase 4.
- **Server cashier powers** (`backend_django/apps/users/permissions.py`): transactions + customers R/W
  (`IsPOSOrReadOnly`), ledgers read, ledger-payments write, material release (`IsPOSRole`). Phases 3 and 4
  add held-cart and shift endpoints under the same permissions.
- **Customers is not a cashier tab** — [Customer Master-Data Scope](../api-integration/decisions/14-customer-master-data-scope.md)
  deleted the screen; utang shows in the checkout panel. Not reopened.
- **Phase 4 changes `process_sale`'s contract** — it now requires an open shift. Existing tests must open a
  shift in setUp or the gate rejects with `NO_OPEN_SHIFT`. `seed_demo.py` must open/close a shift too.
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
- [Held Sale Model](./decisions/05-held-sale-model.md): separate `HeldCart` + `HeldCartItem` tables; no
  stock reservation; any cashier resumes; walk-in allowed; persists across shifts. Completion feeds items
  into `process_sale` and deletes the cart. 5 new API endpoints.
- [Shift / Z-Reading Model](./decisions/06-shift-z-reading.md): new `Shift` entity (OPEN/CLOSED), FK on
  `SalesTransaction`; `process_sale` requires an open shift; Z-reading is computed at close (not stored);
  variance = counted − expected, record-and-warn (no block). 5 new + 1 modified API endpoint.

## Active Frontier (Open & Unblocked)

_Empty._ All 6 decisions are locked.

## Blocked

_None._

## Fog of War (Not Yet Specified)

_Empty._ The stale till subtitle was fixed in Phase 2.

## Out of Scope

- Other roles' gaps in `docs/SYSTEM_ATLAS.md` §3 (suppliers, purchases, audit logs, monitoring, settings).
- Production hardening (encrypted Linux token storage, secrets). Ruled past by
  [Linux Token Storage](./decisions/01-linux-token-storage.md).

---

# Implementation Roadmap — ALL PHASES

Phases 1 and 2 are built. Phases 3 and 4 are fully specified. Build Phase 3 before Phase 4 because the
shift close-out advisory lists held carts.

## Phase 1 — Linux Token Storage ✅

Built as `3bd0fdb` (2026-10-20). See [Linux Token Storage](./decisions/01-linux-token-storage.md).

## Phase 2 — POS Navigation + Reach ✅

Built as `95358c1` (2026-10-21). See decisions [02](./decisions/02-pos-navigation-wiring.md),
[03](./decisions/03-cashier-tab-set.md), [04](./decisions/04-cashier-reach.md).

## Phase 3 — Held Sale (tab 4)

Source: [Held Sale Model](./decisions/05-held-sale-model.md).

### Backend
1. **Models + migration.** `HeldCart` + `HeldCartItem` in `apps/pos/models.py`. New migration.
2. **Serializer + ViewSet.** `HeldCartSerializer` (nested items), `HeldCartViewSet` with CRUD + a
   `@action complete` that calls `process_sale` atomically and deletes the cart.
3. **Router.** `/api/v1/held-carts/` in `apps/pos/urls.py`.
4. **RED-first backend tests.** Hold (201), list, resume (GET with items), complete (201 + cart deleted),
   void (DELETE 204), walk-in hold (no customer), complete when insufficient stock (400 + cart persists).

### Flutter
5. **Data models.** `HeldCart` + `HeldCartItem` in a new `lib/data/models/held_cart.dart`.
6. **Service.** `HeldCartService` (CRUD + complete) in `lib/data/services/held_cart_service.dart`.
7. **Viewmodel.** `HeldCartViewmodel` (load list, hold from till, resume, void, complete).
8. **Page.** `PosHeldTransactionsPage` at `/pos/held` (tab 4). Lists held carts; tap → resume or void.
9. **Till integration.** "Hold" button on `PosTransactionPage` → POST + clear till.
10. **Nav + routes.** Append tab 4 to `posNavigationItems` + `navigatePos` + route + consistency test.
11. **RED-first Flutter tests.** Viewmodel hold/resume/void/complete; widget test for the held list page;
    consistency test extension.
- **Commit:** `feat(pos): held-sale model, endpoints, and till integration (cashier-workflow phase 3)`
- **Gate:** backend suite + flutter suite + analyze clean.

## Phase 4 — End of Shift / Z-Reading (tab 5)

Source: [Shift / Z-Reading Model](./decisions/06-shift-z-reading.md).

### Backend
1. **Models + migration.** `Shift` in `apps/pos/models.py` + `SalesTransaction.shift` FK. One migration.
2. **`NoOpenShift` exception** in `apps/pos/exceptions.py`.
3. **`process_sale` gate.** Look up the cashier's open shift; attach FK; raise `NoOpenShift` if none.
4. **`compute_z_reading(shift)`** in `apps/pos/services.py`.
5. **Serializer + ViewSet.** `ShiftSerializer`, `ShiftViewSet` with `open`, `close`, `current` actions +
   list/retrieve.
6. **Router.** `/api/v1/shifts/` in `apps/pos/urls.py`.
7. **`seed_demo.py` update.** Open a shift before seeding transactions; close it after.
8. **Existing test fix.** Add a `setUp` helper that opens a shift for the cashier in every test that calls
   `process_sale`, so the gate doesn't break them.
9. **RED-first backend tests.** Open (201), double-open (400), sale-without-shift (400), sale-with-shift
   (201 + FK set), close (shift CLOSED + Z-reading), Z totals match, variance computation.

### Flutter
10. **Data model.** `Shift` in `lib/data/models/shift.dart`.
11. **Service.** `ShiftService` (open, close, current, list).
12. **Viewmodel.** `ShiftViewmodel` (open/close flow, current state, Z-reading display).
13. **Page.** `PosEndOfShiftPage` at `/pos/shift` (tab 5). Shows current shift, close form, Z-reading.
14. **Shift gate.** POS shell checks for an open shift on mount. If none → "Open shift" prompt (opening
    float field) before the till activates.
15. **Nav + routes.** Append tab 5 to `posNavigationItems` + `navigatePos` + route + consistency test.
16. **RED-first Flutter tests.** Viewmodel open/close; widget test for the page; gate test (till blocked);
    consistency test extension.
- **Commit:** `feat(pos): shift model, Z-reading, and process_sale gate (cashier-workflow phase 4)`
- **Gate:** backend suite + flutter suite + analyze clean.
