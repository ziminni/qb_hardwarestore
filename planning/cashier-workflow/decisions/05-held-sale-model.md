# Held Sale Model

**Status:** LOCKED 2026-10-21 (user) · **Mode:** domain-model · **Map:** [cashier-workflow](../MAP.md) · Phase 3

## Question

Tab 4 (Held transactions) from [Cashier Tab Set](./03-cashier-tab-set.md) needs a server shape. A cashier
rings up a partial cart, "holds" it to serve another customer, and resumes it later. What is the model?

## Ruling (user, 2026-10-21): Separate `HeldCart` entity

A held sale is stored in a **new `HeldCart` table**, not as a `HELD` status on `SalesTransaction`.
`process_sale` remains the single gateway to real transactions — a `HeldCart` never touches the transaction
table, reports, Z-readings, or FIFO until the cashier completes it.

Rejected: adding `HELD` to `SalesTransaction.Status`. It would require every existing query, report, and
Z-reading to exclude HELD — one missed filter inflates totals silently. The separate table is zero-risk to
existing aggregations.

## Domain Model

### `HeldCart` (new table: `pos_held_cart`)

| Field | Type | Notes |
|---|---|---|
| `id` | auto PK | |
| `cashier` | FK → User (PROTECT) | Who parked it. Any cashier may resume. |
| `customer` | FK → Customer (SET_NULL, null, blank) | Walk-in held sales have no customer — the most common case. |
| `notes` | TextField (blank, default '') | Optional memo ("waiting for wallet"). |
| `created_at` | DateTimeField (auto_now_add) | When the cart was parked. |

### `HeldCartItem` (new table: `pos_held_cart_item`)

| Field | Type | Notes |
|---|---|---|
| `id` | auto PK | |
| `cart` | FK → HeldCart (CASCADE) | Deletion of the cart cascades to its items. |
| `variant_uom` | FK → VariantUOM (PROTECT) | Same FK as `SalesItem`. |
| `qty` | DecimalField (12,2) | Quantity the cashier entered. |
| `unit_price` | DecimalField (12,2) | Price at hold time (the resuming cashier sees the held price; if the price changed, they see the original and can adjust or void). |

### Lifecycle

```
[Till cart] --hold--> HeldCart row + items
                          |
                     [Held list]
                          |
              +-----------+-----------+
              |                       |
         resume                     void
              |                       |
   populate till cart            DELETE HeldCart
   from HeldCart items           (no SalesTransaction)
              |
         cashier completes
              |
     process_sale(...) → SalesTransaction
              |
        DELETE HeldCart
```

- **Hold:** POST creates a `HeldCart` + `HeldCartItem` rows from the till's current items.
- **Resume:** GET the cart + items; populate the till. The `HeldCart` row persists until completion or void.
- **Complete:** `process_sale` creates the real transaction; the `HeldCart` is deleted in the same atomic
  block.
- **Void:** DELETE the `HeldCart`. No transaction, no FIFO, no receipt.

### Edge cases (locked)

| Question | Answer |
|---|---|
| Reserve stock? | **No.** A hold is a memo, not a commitment. If stock runs out, `process_sale` rejects with `INSUFFICIENT_STOCK` on resume. |
| Who resumes? | **Any cashier.** A customer doesn't care who helps them. |
| Held sale at shift close? | **Persist across shifts.** A held sale is a store promise. End-of-shift shows held carts as advisory, doesn't block close (see [Shift / Z-Reading](./06-shift-z-reading.md)). |
| Walk-in held sale? | **Yes.** `customer` is nullable — walk-in is the most common case. |
| Maximum held carts? | **No hard limit.** A cashier with 50 held carts has a workflow problem, not a system problem. |

## API Endpoints (new)

| Method | Path | Permission | Notes |
|---|---|---|---|
| POST | `/api/v1/held-carts/` | `IsPOSOrReadOnly` | Create (hold). Body: `{ customer: id\|null, notes: "", items: [{ variant_uom: id, qty, unit_price }] }`. Returns the HeldCart with items. |
| GET | `/api/v1/held-carts/` | `IsPOSOrReadOnly` | List all (any cashier can see any held cart). |
| GET | `/api/v1/held-carts/{id}/` | `IsPOSOrReadOnly` | Detail with items. |
| POST | `/api/v1/held-carts/{id}/complete/` | `IsPOSRole` | Atomic: feeds items into `process_sale`, deletes the HeldCart. Body: `{ payments: [{ method, amount_tendered }] }`. Returns the created `SalesTransaction`. |
| DELETE | `/api/v1/held-carts/{id}/` | `IsPOSRole` | Void — deletes with no transaction. |

## Cost if wrong

A separate table + 5 endpoints is more migration surface than a status enum change. If the business later
wants held carts to appear in the transaction history (e.g. "this transaction was held for 20 minutes"),
the HeldCart is deleted on completion and the provenance is lost. Mitigation: add a `held_seconds` field
to `SalesTransaction` at completion time, set from `now() - cart.created_at`. Cheap and reversible.

## Build contract (for the executing session)

### Backend
- New `HeldCart` + `HeldCartItem` models in `apps/pos/models.py`, migration.
- `HeldCartSerializer` (nested items), `HeldCartViewSet` with `list`, `create`, `retrieve`, `destroy`,
  and a `@action(detail=True, methods=['post']) complete` that calls `process_sale` and deletes the cart
  atomically.
- Router registration at `/api/v1/held-carts/`.
- Permissions: `IsPOSOrReadOnly` on the viewset; `complete` and `destroy` require `IsPOSRole`.
- RED-first tests: hold a cart (POST 201), list shows it, resume (GET 200 with items), complete (POST 201 →
  SalesTransaction exists + HeldCart deleted), void (DELETE 204 + HeldCart gone), hold with no customer
  (walk-in, 201), complete when stock insufficient (400 INSUFFICIENT_STOCK + HeldCart still exists).

### Flutter
- `HeldCart` + `HeldCartItem` data models.
- `HeldCartService` (CRUD + complete).
- `HeldCartViewmodel` (load list, hold from till, resume into till, void, complete).
- `PosHeldTransactionsPage` (`/pos/held`) — the Held transactions tab (index 4). Lists held carts with
  customer, item count, age. Tap to resume or void.
- Append tab 4 to `posNavigationItems` + `navigatePos` + route + consistency test row.
- Till integration: a "Hold" button on `PosTransactionPage` that posts the current cart to
  `/api/v1/held-carts/` and clears the till.
- RED-first tests: viewmodel hold/resume/void/complete round-trip; widget test for the held list page;
  consistency test extension.
