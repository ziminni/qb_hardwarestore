# Held Sale Model

**Status:** OPEN · **Mode:** domain-model · **Map:** [cashier-workflow](../MAP.md) · Phase 3

## Question

Tab 4 (Held transactions) from [Cashier Tab Set](./03-cashier-tab-set.md) needs a server shape. A cashier
rings up a partial cart, "holds" it to serve another customer, and resumes it later. What is the model?

## Why it matters

`SalesTransaction.Status` today is COMPLETED · VOID · REFUNDED — all **terminal**. A held sale is an
*in-progress* cart with no stock movement and no receipt yet. Forcing it into `SalesTransaction` risks a
half-committed row that FIFO or the reports sweep could mistake for a real sale. This decision picks the
shape before any migration.

## Starting domain sketch (to validate with the user)

**Option A — a `HELD` status on `SalesTransaction`.** Add HELD to the status enum; a held sale is a
transaction row with status HELD, lines but no payments, no receipt, no FIFO deduction. Resume = edit back
into the till; complete = transition HELD → COMPLETED through `process_sale`. Void = HELD → VOID.
- Risk: every query over `SalesTransaction` (reports sales-summary, history, aging) must now exclude HELD, or
  a held cart inflates totals. One missed filter is a wrong Z-reading.

**Option B — a separate `HeldSale` / `ParkedCart` entity.** A distinct table (cashier, customer?, lines,
created_at) that never touches `SalesTransaction` until completion, when its lines feed `process_sale` to
mint a real transaction. Resume reads the HeldSale; complete deletes it and creates the sale.
- Cleaner separation (no reporting contamination), at the cost of a new table + endpoints.

## Edge cases to pin before locking

- Does a held sale **reserve stock**? (If yes, two cashiers can't oversell the last bag; if no, a resume can
  fail at completion when stock ran out — which is honest but needs a clear message.)
- Who can resume — only the holding cashier, or any cashier on the terminal?
- What happens to held sales at end of shift / log out — expire, persist, or block close?
- Walk-in held sale: allowed? (A walk-in cart with no customer is the common case.)

## Build contract (to be written when locked)

TBD — model/endpoint shape, the client hold/resume/void flow on the till, and the `/pos` route for the
Held-transactions list. Appends tab 4 to `navigatePos` (append-only order, no renumber).
