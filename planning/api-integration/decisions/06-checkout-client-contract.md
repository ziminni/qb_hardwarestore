# POS Checkout Client Contract

**Mode:** domain-model · **Status:** ✅ RESOLVED 2026-10-16 · **Opened:** 2026-10-15
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

---

## Resolution (2026-10-16)

Every fact below was read from the code and the running server during this session, not assumed. Phases 1 and 2
are complete, which is the gate this file set for itself ("do not start before Phases 1-2 settle the product and
stock model shapes") — so it is now unblocked.

### 1. Response shape — ANSWERED BY THE CODE

`SalesTransactionViewSet.create` (`apps/pos/views.py:27`) ends with
`return Response(self.get_serializer(txn).data, status=201)`, and `SalesTransactionSerializer` nests
`items` (`SalesItemSerializer`), `payments` (`PaymentSerializer`) and `receipt` (`OfficialReceiptSerializer`) as
read-only children.

**Contract:** the POST response **is** the finished transaction. The receipt screen needs **no second call**. The
client must not re-fetch by id.

### 2. Request shape — ANSWERED BY THE CODE, and one landmine

`create` splits the payload in two halves that behave differently:

```python
ser = self.get_serializer(data=request.data)
ser.is_valid(raise_exception=True)
txn = process_sale(
    customer_id=ser.validated_data['customer'].id,   # validated
    cashier=request.user,                            # server-derived
    items_data=request.data.get('items', []),        # RAW, unvalidated
    payments_data=request.data.get('payments', []),  # RAW, unvalidated
    source=ser.validated_data.get('source', 'WALK_IN'),
)
```

**`items` and `payments` bypass validation entirely.** They are read from raw `request.data`, so a malformed
item is not rejected with a 400 — it reaches `process_sale` and either raises or silently produces a bad sale.
The client must therefore treat its own payload shape as the only guard.

Required keys, from `process_sale`:

| Field | Shape | Notes |
| :--- | :--- | :--- |
| `customer` | int id | **Required.** See below. |
| `source` | `'WALK_IN'` | Optional; server defaults it. |
| `items[]` | `{variant_id, qty, unit_price}` | `variant_id` is a **misnomer** — see the landmine. |
| `payments[]` | `{method, amount_tendered, reference_no}` | `method` defaults `'CASH'`, `reference_no` to `''`. |

### A walk-in sale omits `customer` — no, it cannot

`SalesTransaction.customer` is `models.ForeignKey(Customer, on_delete=PROTECT, related_name='transactions')`
with **no `null=True`**, and `create` reads `validated_data['customer'].id` without a `.get`. So a walk-in sale
still sends a customer id — specifically the **Walk-in Customer** record that `seed_demo` already creates
(`seed_demo.py:245`, `get_or_create(name='Walk-in Customer')`).

**Contract:** the client resolves the Walk-in Customer once and sends its id for anonymous sales. It is not
optional and it is not server-derived.

### Landmine: the cart cannot currently produce a valid payload

The API does `SalesItem.objects.create(variant_uom_id=item_id)` and resolves the variant via
`VariantUOM.objects.filter(pk=item_id)`. **So the item key is a `VariantUOM` id, despite being named
`variant_id`.**

The client's POS catalogue currently **synthesizes** it:

```dart
// pos_transaction_viewmodel.dart
variantUomId: record.variant.id * 100 + index,
```

That is a fabricated number. Sent as `variant_id`, it resolves to the wrong `VariantUOM` or none at all, so
stock would be deducted from the wrong unit or the sale would fail confusingly.

The real ids are already available — `ProductVariant.sellingUoms` carries `VariantUom.id` (parsed from the API's
nested `selling_uoms`) — the cart simply ignores them.

**Contract:** cart lines are keyed by the **real `VariantUom.id`** from `variant.sellingUoms`. This is not a
choice, it is a correction the API shape dictates, and it is Phase 3's first task.

### 3. Failure semantics — RESOLVED (user decision, 2026-10-16)

`transaction.atomic()` wraps the whole sale, so a failure rolls back **wholesale**: no partial transaction, no
orphan receipt. **The client must never clear the cart optimistically.**

The problem: `allocate_fifo` raises `ValueError` on insufficient stock, and **nothing catches it** — `pos/services.py`
contains no `raise` and no `except`, `pos/views.py` catches nothing relevant, and no `EXCEPTION_HANDLER` is
configured. So the single most common expected failure arrives as **HTTP 500**, and under `DEBUG=True` as an
HTML page the client cannot parse. Decision 06's own framing calls this "an expected outcome, not a crash".

**Decision: the backend maps it to 400 with a stable code.** The chosen shape:

```http
HTTP 400
{"code":"INSUFFICIENT_STOCK",
 "detail":"Insufficient stock for Portland Cement — 40kg.",
 "shortfall":"12.00"}
```

This costs one backend change beyond the map's "client-side epic only" invariant — the same situation Phase 2
was already in, and one the user approved there for the same reason: the feature cannot work without it.

**Recoverable vs terminal:**

| Outcome | Status | Client treatment |
| :--- | :--- | :--- |
| Insufficient stock | 400 + `INSUFFICIENT_STOCK` | **Recoverable in place** — identify the offending line, let the cashier reduce the quantity, keep the cart intact. |
| Validation failure (bad `customer`) | 400 | Recoverable — a setup/selection problem, not a sale problem. |
| Anything else (5xx) | 500 | **Terminal for the attempt** — keep the cart, show a generic failure, allow retry. Never silently drop the cart. |
| Underpaid | 201 + `CollectibleLedger` | **Not a failure.** See below. |

`shortfall` is client-derivable too: the response carries `grand_total` and every payment's `amount_tendered`,
so the client can display the utang without a second call.

### 4. Underpayment — RESOLVED (user decision, 2026-10-16)

`process_sale` posts a `CollectibleLedger` (30-day due date, `Status.OPEN`) when `shortfall > 0 and customer_id`.
Because a walk-in still sends a customer (see §2), the ledger always posts.

**Decision: confirm before submitting.** When the entered payments are less than the total, the client shows a
confirmation step naming the customer and the shortfall, and **submits nothing until confirmed**. The cart stays
intact either way.

Why this over submitting straight away: creating a debt is consequential and the receipt is printed *after* the
fact, so a mistyped payment would become a real, recorded obligation the cashier might never notice. The
confirmation is where a typo is still recoverable. The rejected alternative — submit immediately and show the
utang on the receipt — is one tap faster but matches only what the server does, not what the cashier can undo.

Consequence for the state machine below: `building → confirmed` is gated on this confirmation whenever
`total_paid < grand_total`. The client derives the shortfall itself (`grand_total` minus summed `amount_tendered`),
so no extra call is needed.

### 5. Cart state machine

```text
        ┌─────────────────────────────────────────────────────────────┐
        │                                                             │
     [empty] ──add line──> [building] ──submit──> [submitted]         │
        ▲                      ▲                     │              │
        │                      │        ┌────────────┴───────────┐  │
        │                      │        │                        │  │
        │                      │   201 confirmed            400 insufficient
        │                      │        │                        │  │
        │                      │        │                        ▼  │
        │                      │        │                 [rejected: stock]
        │                      │        │                        │  │
        │                      │        │                        └──┘
        │                      │        │        (adjust qty, cart intact)
        │                      │        │
        │                      │   underpaid? ──yes──> [utang confirm]
        │                      │        │                    │
        │                      │        │              cancelled?
        │                      │        │                    │
        │                      │        ▼                    ▼
        │                      │  [confirmed]        back to [building]
        │                      │   │        │         (nothing submitted)
        │                      │   │        ▼
        │                      │   │  [confirmed-with-utang]
        │                      │   │        │
        └────clear cart────────┴───┴────────┘
                        (only here — never on failure)
```

**Invariants:**

- The cart is cleared **only** on a confirmed sale (201). No code path clears it on failure.
- `submitted` is not a modal lock — but the submit action is disabled while in flight, because the sale is one
  atomic server operation and a double-submit would be two sales.
- `rejected: stock` returns to `building` with the offending line identified.

### 6. Edge case found while resolving this: no empty-cart guard

`process_sale` has **no guard on an empty `items` list**, and the serializer does not require `items`. An empty
cart therefore **succeeds**: a transaction and an `OfficialReceipt` are created with `grand_total` 0.

**Contract:** the client disables submit on an empty cart. Recorded as a **server-side gap worth its own fix**
(a zero-value receipt is not a sale), but out of decision 06's scope and not blocking Phase 3.

### 7. Not covered here, deliberately

- **VAT and discounts.** `vat_amount` is written as `0` and never updated; `discount` is hardcoded
  `Decimal('0')`. The contract sends no discount and displays whatever the server returns. Wiring these is
  later work.
- **Held / resumed sales, split payments across methods** — not needed for one demoable cashier outcome.

### Status

**RESOLVED 2026-10-16.** Requests and responses are pinned to the real code, the failure contract is decided, the
underpayment step is decided, and the `variantUomId` landmine is named as Phase 3's first task. Phase 3 is
unblocked.
