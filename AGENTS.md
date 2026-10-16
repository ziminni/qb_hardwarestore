# qb_pos_inventory_system — Routing Table (ICM)

Rule: **One home per fact.** A fact lives in exactly one file and is linked from everywhere else.
Do not duplicate schemas, endpoint lists or status tables here — follow the pointers below instead of
grepping the codebase, and never paste a copy of a fact that already has a home.

## Where Everything Lives

| Concern | Canonical file / path |
| :--- | :--- |
| Setup, run, demo credentials, ports | `README.md` |
| System architecture & Live/Mock matrix | `docs/SYSTEM_ATLAS.md` |
| Interactive architecture cockpit | `docs/system-atlas.html` |
| API contract: endpoints, auth, role matrix | `ENDPOINTS.md` |
| Unbuilt work, decisions, roadmap | `planning/MAP.md` (index) → active map: `planning/api-integration/MAP.md` |
| Session history & gotchas | `docs/sessions/` — newest date first |
| Branch, commit & review conventions | `CONTRIBUTING.md` |
| Django backend (6 apps + `services.py`) | `backend_django/apps/{users,inventory,pos,collectibles,requisitions,reports}/` |
| Flutter MVVM client (10 features) | `flutter/lib/features/` — shared models in `flutter/lib/data/models/` |
| Network layer (Dio, JWT, refresh-on-401) | `flutter/lib/core/network/api_client.dart` |
| Route table (single source of navigation) | `flutter/lib/routes/routes.dart` |

Every pointer above must resolve. A pointer to a file that does not exist is a bug — fix or remove it in
the same commit that breaks it.

## Current Status & Next Step

- **Active branch:** `feature/backend-integration` — 114 commits ahead of `origin/master`, unpushed.
- **Active plan:** `planning/api-integration/MAP.md` — the integration epic as a Wayfinder map. The slice order is
  **locked** (Cashier journey) and the map reads **11 locked · 2 open**. **Phases 0-3 are COMPLETE.** Phase 0's 7
  rows are built (the map's "Phase 0 — status" table is the authority, and it was re-verified against the CODE
  after being wrong twice in opposite directions); Phase 1's products catalogue renders live API data; Phase 2
  made the **server the authority for inventory state**; and Phase 3 made the POS **complete a real sale**. The map
  carries the **7-phase route** with each phase's ticket attached, so "what is next" is answerable from the index
  alone. Resolving decision 06 also **graduated the Phase 4 question out of the Fog of War** into a real frontier
  item ([decision 14](./planning/api-integration/decisions/14-customer-master-data-scope.md)); Phases 5 and 6 wait
  on the other two.
- **Last session:** `docs/sessions/2026-10-16-phase-3-pos-checkout.md` — **built Phase 3, the money path.** The POS
  no longer simulates a sale: it POSTs to `/api/v1/transactions/`, keys cart rows by the real `VariantUom.id`, sends
  the resolved Walk-in Customer, clears the cart **only** on a 201, and confirms an underpaid sale before submitting
  it. **Five defects fell out that reading and tests had missed** — the cart sent a fabricated unit id; `cashier`
  was writable, so a valid sale got `400 {"cashier": ["This field is required."]}`; `manage.py test` ran **zero**
  tests (`apps/` lacked `__init__.py`); a cart line whose variant left the catalogue crashed with
  `StateError: Bad state: No element`; and decision 06 §3 was only half-implemented. **192 tests pass; `flutter
  analyze` is clean; 33 backend tests pass; `manage.py check` reports 0 issues.** Verified fresh in the closing
  message: analyze clean, **192/192**, tree clean, **114** commits ahead. Decision 06 was then checked **clause by
  clause: 11/11 met** — the earlier "Phase 3 complete" claim had rested on tests written from my own reading and
  had missed §3. Two things are owed before merge: a **fresh-context reviewer** (both dispatches failed on
  `402: insufficient credits`, so the review was a self-review) and an **Atlas refresh**. Earlier:
  `docs/sessions/2026-10-16-phase-2-inventory-authority.md` built Phase 2;
  `docs/sessions/2026-10-16-map-repair-and-tracker-reconciliation.md` repaired the map's route in the index and
  reconciled the task tracker; `docs/sessions/2026-10-16-phase-0-complete.md` built the five remaining Phase 0 rows
  and had `Paged.hasMore` falsified by review;
  `docs/sessions/2026-10-16-staged-model-swap-complete.md` finished the staged model swap;
  `docs/sessions/2026-10-16-staged-swap-blockers-and-location-store.md` locked decision 10;
  `docs/sessions/2026-10-16-phase-0-decisions.md` locked the six Phase 0 decisions;
  `docs/sessions/2026-10-15-integration-map.md` opened the map.
- **Current state:** `docs/SYSTEM_ATLAS.md` is the authority, and its tally is **STALE as of Phase 3** — it last
  read 38 screens scored **6 live · 4 partial · 20 mock · 8 dead**, but Phase 3 moved POS checkout from mock to
  live, so both the tally and the checkout row need a refresh (see the session note). Still true: auth, products,
  stock, low stock, stock movements, and now checkout all read the server.
- **Next step:** **resolve decision 14 (Customer Master-Data Scope) in domain-model mode** — Phase 4's question,
  which checkout sharpened by making the customer id mandatory on every sale. Phases 5 and 6 remain gated by
  decisions 09 and 05. Two items are owed **before the branch merges**: a fresh-context review of Phase 3, and the
  Atlas refresh above.
- **Known unfixed, carried forward:** the products toolbar overflows — `A RenderFlex overflowed by 9.7 pixels on
  the right` from `products_toolbar.dart:113` and `products_catalog_overview.dart:156` — pre-existing, visible at
  ~1600px window widths, found while testing Phase 1 and deliberately not fixed (UI work outside that phase's
  scope). The products page's Add / Edit / Archive paths are **memory-only** until a later phase wires the writes
  (decision 12's accepted cost). And **`flutter run` against the live backend has still not been executed** — the
  API contract is verified by probing the server, and the wiring by widget tests, but not the running app.
- **Open backend issues:** (1) `apps/inventory/services.py::apply_stock_adjustment` silently discards a positive
  adjustment when no batch has `current_qty > 0`, so a count correction on a depleted variant is lost with no
  error. (2) `process_sale` has **no guard on an empty items list** and the serializer does not require `items`, so
  a zero-value sale succeeds and mints an `OfficialReceipt` for `grand_total` 0 — the client disables submit on an
  empty cart, but a zero-value receipt is not a sale (decision 06 §6 records this as its own future fix).
