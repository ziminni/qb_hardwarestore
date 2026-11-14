# Shift / Z-Reading Model

**Status:** LOCKED 2026-10-21 (user) · **Mode:** domain-model · **Map:** [cashier-workflow](../MAP.md) · Phase 4

## Question

Tab 5 (End of shift) from [Cashier Tab Set](./03-cashier-tab-set.md) needs a server shape. A cashier opens a
shift, rings sales during it, and closes it with a cash count and an end-of-day (Z-reading) summary. What is
the model?

## Rulings (user, 2026-10-21)

1. **Shift owns transactions via an explicit FK** on `SalesTransaction` (nullable). Clean queries, no
   midnight ambiguity, no overlap risk. One migration adds the column.
2. **Required shift gate.** `process_sale` checks the cashier has an open shift and attaches the FK. No
   open shift → 400 error. Guarantees every sale is accounted for in a Z-reading.
3. **Variance: record and warn.** A non-zero counted-vs-expected variance is recorded but does NOT block
   close. Management reviews variances in reports.

Rejected:
- Time-window derivation (ambiguous, no FK integrity).
- Optional shift / no gate (orphan sales never appear in a Z-reading).
- Block-on-mismatch (frustrates cashiers, needs a manager-override flow).

## Domain Model

### `Shift` (new table: `pos_shift`)

| Field | Type | Notes |
|---|---|---|
| `id` | auto PK | |
| `cashier` | FK → User (PROTECT) | One open shift per cashier (enforced by unique constraint on open status). |
| `status` | CharField(10) OPEN / CLOSED | |
| `opening_float` | DecimalField (12,2) | Cash in the drawer at open. |
| `closing_count` | DecimalField (12,2, null) | Counted cash at close. Null while open. |
| `opened_at` | DateTimeField (auto_now_add) | |
| `closed_at` | DateTimeField (null) | Set on close. |
| `notes` | TextField (blank, default '') | |

**Constraint:** `UniqueConstraint(fields=['cashier'], condition=Q(status='OPEN'), name='one_open_shift_per_cashier')`.

### `SalesTransaction` (migration)

| Change | Detail |
|---|---|
| New field | `shift = FK → Shift (SET_NULL, null, blank, related_name='transactions')` |
| `process_sale` | Looks up `Shift.objects.get(cashier=cashier, status='OPEN')`. If none → `NoOpenShift` error (400). Sets `shift=shift` on the new transaction. |

### Z-Reading (computed, not stored)

The Z-reading is **derived at close time** from the shift's transactions — not a separate table. It reuses
the same aggregation shape as `/api/v1/reports/sales-summary/` but scoped to one shift's FK:

```
Shift.transactions.filter(status=COMPLETED).aggregate(
    transaction_count, gross_sales, vat, discounts,
    cash_sales   = Sum(payments CASH),
    card_sales   = Sum(payments CARD),
    gcash_sales  = Sum(payments GCASH),
    bank_sales   = Sum(payments BANK_TRANSFER),
)
expected_drawer = opening_float + cash_sales - cash_refunds
variance        = closing_count - expected_drawer
```

The Z-reading is returned as part of the close response and the shift detail. It is **read-only after
close** — recalculating it from the same query is idempotent.

### Lifecycle

```
[Cashier logs in] --open shift--> Shift(OPEN, opening_float)
                                       |
                                  [ring sales]
                                  process_sale sets shift FK
                                       |
                                  [end of shift]
                                       |
                             enter closing_count
                                       |
                              close --> Shift(CLOSED)
                                       Z-reading computed
                                       variance recorded
```

### Interactions with [Held Sale Model](./05-held-sale-model.md)

- **Held carts persist across shifts** (decision 05). Closing a shift does NOT void or complete held carts.
- The close-out endpoint lists held carts as **advisory** ("2 held carts from your shift"), but does not
  block close.
- When a held cart is completed (feeds into `process_sale`), the `shift` FK is set from the **resuming**
  cashier's open shift, not the original holding cashier's shift. The sale counts in the shift that
  completed it.

### Edge cases (locked)

| Question | Answer |
|---|---|
| One open shift per cashier? | **Yes.** Enforced by a unique partial index. A second open → 400. |
| Who sees Z-readings? | **Cashier sees their own; manager sees all.** Viewset permission: `IsPOSOrReadOnly` for own, `IsManagerRole` for list-all. |
| Immutable after close? | **Yes.** The shift status moves OPEN → CLOSED and never back. The Z-reading is recomputed from the same query — identical every time. |
| Refunds in the Z-reading? | **Yes.** REFUNDED transactions have negative `grand_total` (decision 15); they net out of gross_sales naturally. VOID transactions are excluded (status ≠ COMPLETED). |
| Sales from held carts? | Counted in the **completing** shift, not the holding shift (see above). |

## API Endpoints (new + modified)

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/api/v1/shifts/open/` | `IsPOSRole` | Create a shift. Body: `{ opening_float }`. Returns the Shift. 400 if one is already open. |
| POST | `/api/v1/shifts/{id}/close/` | `IsPOSRole` | Close the shift. Body: `{ closing_count }`. Returns the Shift + Z-reading summary. |
| GET | `/api/v1/shifts/` | `IsPOSOrReadOnly` (own) / `IsManagerRole` (all) | List. Cashier sees only their own; manager sees all. |
| GET | `/api/v1/shifts/{id}/` | same | Detail with Z-reading (computed). |
| GET | `/api/v1/shifts/current/` | `IsPOSRole` | The cashier's current open shift, or 404. |
| **Modified** | `process_sale` | — | Now requires an open shift; attaches `shift` FK. New exception `NoOpenShift`. |

## Cost if wrong

The FK on `SalesTransaction` is a schema migration on the widest table. If the gate proves too strict during
testing (e.g. seed_demo needs a shift), the gate can be relaxed to `shift=null` allowed without dropping
the column — the migration is not destructive. Reversible: remove the column, drop the Shift table.

The required-shift gate changes `process_sale`'s contract — every existing test that calls it must either
open a shift first or the gate must be skipped in a test-only flag. The build contract below addresses this.

## Build contract (for the executing session)

### Backend
- New `Shift` model in `apps/pos/models.py`, migration (includes the `SalesTransaction.shift` FK).
- `ShiftSerializer`, `ShiftViewSet` with `open`, `close`, `current` actions, list/retrieve.
- `NoOpenShift` exception in `apps/pos/exceptions.py`.
- `process_sale` gate: `Shift.objects.get(cashier=cashier, status='OPEN')` or raise `NoOpenShift`.
- Z-reading: a `compute_z_reading(shift)` function in `apps/pos/services.py` returning the summary dict.
- Router registration at `/api/v1/shifts/`.
- Update `seed_demo.py`: open a shift for the cashier before seeding transactions, close it after.
- RED-first tests:
  - Open a shift (201), second open → 400.
  - Sale without a shift → 400 `NO_OPEN_SHIFT`.
  - Sale with a shift → 201, transaction has `shift` FK.
  - Close with `closing_count` → shift CLOSED, Z-reading in response.
  - Z-reading totals match manual sum of the shift's completed transactions.
  - Variance = `closing_count - expected_drawer`.
  - Existing tests: add a `setUp` helper that opens a shift for the cashier so they keep passing.

### Flutter
- `Shift` data model.
- `ShiftService` (open, close, current, list).
- `ShiftViewmodel` (open/close flow, current shift state, Z-reading display).
- `PosEndOfShiftPage` (`/pos/shift`) — the End of shift tab (index 5). Shows current shift status, a
  "Close shift" form with the cash count field, and the Z-reading summary after close.
- Shift gate in the POS shell: if no open shift, show an "Open shift" prompt before the till. The cashier
  enters the opening float; the till becomes available after.
- Append tab 5 to `posNavigationItems` + `navigatePos` + route + consistency test row.
- RED-first tests: viewmodel open/close round-trip; widget test for the end-of-shift page; gate test
  (till blocked without an open shift); consistency test extension.
