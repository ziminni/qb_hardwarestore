# POS Checkout Client Contract

**Mode:** domain-model · **Status:** OPEN · **Opened:** 2026-10-15
**Phase:** 3 — graduated from Fog of War when the slice order locked.

## The question

What is the client-side contract for `POST /api/v1/transactions/`, and what does the UI do when a sale
partially fails?

## Why it matters

Checkout is the most complex interaction in the system and it hides behind a single POST. On the server,
`process_sale` (`apps/pos/services.py:28`) does all of this inside one `transaction.atomic()`:

- FIFO stock deduction across `InventoryBatch` rows
- payment allocation across possibly several `Payment` rows
- `OfficialReceipt` generation
- `CollectibleLedger` posting when the sale is underpaid

The client therefore cannot treat this like a CRUD write. Three things need pinning down before coding:

- **Request shape.** Which of `{customer, source, items[], payments[]}` are required, what a walk-in sale
  omits, and what the client must send versus what the server derives.
- **Response shape.** Does the response carry the finished transaction with items, payments and receipt, or
  only an id that must be re-fetched? This decides whether the receipt screen needs a second call.
- **Failure semantics.** `transaction.atomic()` means a failure rolls back wholesale — so the client must not
  optimistically clear the cart. Insufficient stock and underpayment are *expected* outcomes, not crashes, and
  need distinct UI treatment.

## Needs a domain sketch

- Cart state machine: empty → building → submitted → confirmed | rejected(insufficient stock) | confirmed-with-utang.
- Which failures are recoverable in place (adjust quantity, reduce payment) versus terminal.
- Whether an underpaid sale confirms immediately with a ledger entry or requires a confirmation step showing
  the utang being created.

## Resolution

_Unresolved — Phase 3. Do not start before Phases 1-2 settle the product and stock model shapes._
