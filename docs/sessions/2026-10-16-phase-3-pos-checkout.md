---
date: 2026-10-16
branch: feature/backend-integration
commits:
  - 3fd9e2e  # decision 06 locked; Phase 3 unblocked
  - 102c121  # cart rows keyed by the real selling unit
  - 8a941bf  # the backend suite could not run at all
  - a0da436  # a short-stock sale is a 400 with a code, not a 500
  - 8d46deb  # PosService + PosRepository
  - de04e19  # Walk-in Customer resolution + the Customer model
  - 7f4cb38  # submit path wired; utang confirmed before submitting
  - 1415664  # a stale cart line crashed the POS
  - b2a1ab1  # MAP/AGENTS record Phase 3 done
  - f38f2cc  # dart format, phase 3 files
  - 24bcfdf  # the cart identifies the line that is short
  - 037687a  # dart format, this session's new tests
scope: Phase 3 — the POS completes a real sale against POST /api/v1/transactions/
repo: qb_pos_inventory_system
skills: [wayfinder, executing-plans, test-driven-development, verification-before-completion, save-progress]
---

# Phase 3 — POS checkout (the money path)

## Focus

Replace the POS's local sale simulation with a real server sale. Decision 06 pinned the client contract:
the POST response **is** the finished transaction, `variant_id` is really a `VariantUom` id, a walk-in sale
still sends a customer id, insufficient stock is a **400 with a stable code**, and an underpaid sale stops at a
confirmation step. Six ledgered tasks, executed inline with TDD per step.

## What Was Built / Changed

**Backend** (`backend_django/`)
- `apps/pos/exceptions.py` (new) — a DRF `EXCEPTION_HANDLER` registered in `config/settings.py` that maps
  `InsufficientStock` to `400 {"code", "detail", "shortfall", "variant_id"}`. `InsufficientStock` itself lives in
  `apps/inventory/exceptions.py` and deliberately **subclasses `ValueError`** (10 `except ValueError` sites and 5
  `assertRaises(ValueError)` tests depend on that).
- `apps/pos/serializers.py` — `cashier` is now **read_only**, because `create` already assigns `request.user`.
- `apps/pos/tests.py` (new class `CheckoutApiTests`) — 4 tests incl. a fixture guard asserting the POST is not 403.
- `apps/__init__.py` (new, empty) — without it `manage.py test` ran **zero** tests; now 33.

**Flutter** (`flutter/`)
- `lib/data/services/pos_service.dart` (new) — `PosService.checkout` + `fetchWalkInCustomerId`; `PosCheckoutItem`,
  `PosCheckoutPayment`, `PosCheckoutResult`, `PosServiceException`.
- `lib/data/repositories/pos_repository.dart` — pass-through (the one-data-path invariant).
- `lib/data/models/customer.dart` (new) — minimal `Customer`; the client had none and called `/customers/` nowhere.
- `lib/features/pos/viewmodels/pos_transaction_viewmodel.dart` — `submit()` replaced the synchronous `complete()`;
  cart rows now use the **real `VariantUom.id`**; `insufficientStockLineId` identifies the short row.
- `lib/features/pos/widgets/pos_underpayment_dialog.dart` (new) and `pos_transaction_cart.dart` (short row tinted).
- 6 new test files under `test/features/pos/` and `test/data/services/`.

## Mistakes & Gotchas

- **An unhandled `StateError` in the money path.** The catalogue is a getter rebuilt from live stock that *skips*
  any variant at zero, but a cart line can outlive its row (a `load()`, or a sale on another screen sharing the
  same `InventoryViewmodel`). Every lookup was `_catalog.firstWhere(...)` with no `orElse` → `Bad state: No element`.
  Reproduced before fixing; `addLine` threw first, on the line it was not even looking at. All lookups now go
  through `_rowFor()` and `validate()` refuses by name.
- **The `variantUomId` landmine.** The cart synthesized `variant.id * 100 + index`; the API resolves the field as a
  real `VariantUOM` id. Worse, my own guard test then found variant 19 tracked as both `kg` and `g` while selling
  only one unit — two rows collided on id 19, which would have priced a `g` line as `kg`.
- **`manage.py test` ran 0 tests.** `apps/` was a namespace package, so discovery raised
  `TypeError: expected str, bytes or os.PathLike object, not NoneType`. Five `tests.py` files had never executed.
- **A documented payload was rejected by a server-owned field.** `cashier` was writable while the view assigned
  it, so a valid sale got `400 {"cashier": ["This field is required."]}`. Same class as Phase 2's `user` bug.
- **"Tests pass" is not "spec met".** The first "Phase 3 complete" claim rested on tests written from my own
  reading. A clause-by-clause check against decision 06 found §3 half-implemented (see Decisions). Always build
  the checklist against the binding document.
- **The pi-lens inline report is a stale cache.** It repeatedly claimed `submit`/`submitError`/`isSubmitting`/
  `pos` were undefined, on files that were Dart-clean; it eventually self-labelled "[stale — re-run to confirm]".
  `flutter analyze` and the test run are the authority. Its `Temporary failure in name resolution` is its own
  fetch to pub.dev. Separately, its hardcoded-password hit on `pass12345` is a known false positive.
- **`dart format` drift lands after a "clean tree" claim.** Twice this session. Proof it was cosmetic: five files
  were byte-identical to `dart format` of HEAD's own content, and the rest were settled by an in-repo
  formatter-cleanliness control — formatting a copy in `/tmp` gives wrong answers, because there is no `pubspec`
  there to pick the package's language version from.
- **A fake repository must override `walkInCustomerId` too.** `submit` resolves the Walk-in Customer *before*
  checking out, so a stub that overrides only `checkout` still reaches the real service and dies on the
  uninitialised `ApiClient.dio` (`LateInitializationError`).

## Decisions

- **A short-stock sale is recoverable in place.** The 400 carries `code`, `detail`, `shortfall` **and
  `variant_id`**; the cart maps the server's *variant* onto the cart's *VariantUom* line and tints the row
  ("Not enough stock — reduce this line."). A terminal 5xx marks nothing, so the cart never accuses an innocent
  row. Publishing `variant_id` was a real gap: the exception carried it all along, unused.
- **The cart is cleared only on a 201.** No failure path clears it, because `process_sale` is one
  `transaction.atomic()` and a rejected sale rolls back wholesale.
- **An underpaid sale is confirmed before anything is submitted** — creating a debt is consequential and the
  receipt prints after the fact.
- **`isInsufficientStock` is never inferred from the HTTP status** — a 400 can also mean a bad customer, and
  telling a cashier to shrink a quantity because the server 500'd would misstate the cause.
- **`PosRepository` stays a pass-through** — the server owns the sale; client-side policy would be a second
  authority over money.
- **The plan's workspace was kept**, not deleted, because `.superpowers/sdd/MAP/` is the record for the whole
  multi-phase map rather than for one phase.
- **The final review was a self-review.** Both fresh-context reviewer dispatches failed with
  `402: insufficient credits` (it requests ~926k tokens against a much smaller balance). Weaker than a fresh
  reviewer — and this session proved the cost, since the spec checklist caught what the review would have passed.

## Wins & Next Step

Live end-to-end verification against the running server, all three paths: a valid sale returned **201** with
`TRX-20261016-0001`, nested items/payments/receipt (no second fetch) and moved real FIFO stock 95.0 → 93.0;
`cashier` was assigned **server-side**; insufficient stock returned **400 `INSUFFICIENT_STOCK`** with the stock
unchanged (was a 500); an underpaid sale moved the ledger 2 → 3. Demo state was restored exactly.

Closing gate: `flutter analyze` clean, **192/192** Flutter tests, **33/33** backend tests, `manage.py check`
clean, tree clean. Decision 06 verified clause by clause: **11/11 met**.

**Next step: resolve decision 14 (Customer Master-Data Scope) in domain-model mode** — Phase 4's question, which
checkout sharpened by making the customer id mandatory. Two things are owed before merge: a **fresh-context
reviewer** (the self-review is weaker), and a **`docs/SYSTEM_ATLAS.md` / `docs/system-atlas.html` refresh** —
Phase 3 moved POS checkout from mock to live, so the Truth Matrix tally (last recorded as 6 live · 4 partial ·
20 mock · 8 dead) and the checkout row are now stale. `flutter run` has still never been executed.
