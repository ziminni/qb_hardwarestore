# Shift / Z-Reading Model

**Status:** OPEN · **Mode:** domain-model · **Map:** [cashier-workflow](../MAP.md) · Phase 4

## Question

Tab 5 (End of shift) from [Cashier Tab Set](./03-cashier-tab-set.md) needs a server shape. A cashier opens a
shift, rings sales during it, and closes it with a cash count and an end-of-day (Z-reading) summary. What is
the model?

## Why it matters

Nothing in the backend models a shift, a cash drawer, or a Z-reading. This is the largest net-new feature on
the map — a new entity, endpoints, and client flow — so its shape must be validated before any migration.

## Starting domain sketch (to validate with the user)

**`Shift` entity (proposed):** `cashier` (FK), `opened_at`, `closed_at` (null while open), `opening_float`
(cash in the drawer at open), `closing_count` (counted cash at close), `status` (OPEN · CLOSED). A shift
**owns the transactions** rung during it: either a `shift` FK on `SalesTransaction`, or derive by
`cashier` + time window.

**Z-reading (close-out summary):** computed at close — total sales, count, by payment method
(CASH/CARD/GCASH), expected drawer (opening_float + cash sales − cash refunds), counted drawer, and the
**variance**. Read-only once the shift closes.

## Edge cases to pin before locking

- **One open shift per cashier?** Block a second open; block login-to-till without an open shift, or allow
  sales outside a shift (and then what owns them)?
- **Which transactions does a shift own** — a `shift` FK (explicit, migration touches `SalesTransaction`) or
  a `cashier` + `opened_at..closed_at` window (no FK, but ambiguous across midnight / overlapping)?
- **Refunds and held sales** inside the window — counted in the Z-reading? (Held sales are not yet real
  sales — see [Held Sale Model](./05-held-sale-model.md).)
- **Who sees the Z-reading** — the cashier, the manager, both? Is it immutable after close?
- **Variance handling** — does a mismatch block close, warn, or just record?

## Interlocks

- [Held Sale Model](./05-held-sale-model.md): if held sales reserve stock or persist across a shift, the
  close-out must decide their fate. Resolve Held Sale first, or pin the interaction here.
- `/api/v1/reports/sales-summary/` already aggregates COMPLETED transactions by date; a Z-reading is a
  per-shift cut of the same data — reuse the aggregation, don't duplicate it.

## Build contract (to be written when locked)

TBD — `Shift` model + migration, open/close endpoints, Z-reading computation, the client open-shift gate and
close-out screen, and the `/pos` route for End of shift. Appends tab 5 to `navigatePos` (append-only order).
