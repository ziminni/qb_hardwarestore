# Customer Master-Data Scope (POS side)

**Mode:** domain-model · **Status:** OPEN · **Opened:** 2026-10-16
**Phase:** 4 — **graduated out of Fog of War** when [POS Checkout Client Contract](./06-checkout-client-contract.md)
resolved. That decision proved checkout cannot run without a customer (a walk-in sale still sends the Walk-in
Customer's id, because `SalesTransaction.customer` is `FK(PROTECT)` with no `null=True`), which is what made this
question sharp enough to state.

## The question

**Which slice of customer master data must the POS own**, given that checkout already depends on being able to
identify a customer?

Sub-questions to settle:

- **Select only, or create too?** Does the POS just search and pick from existing customers, or can a cashier
  create one mid-sale (a new utang customer at the counter)? The second is what real counters need, and it is
  where the write path gets interesting.
- **Who owns the customer record?** — **out of scope here.** This map rules CPMS and cross-system integration
  past its destination (see the map's Out of Scope), so Phase 4 decides only what the *POS* does with customers.
  Whether the CPMS later shares them is a separate effort with its own map, and nothing in Phase 4 should
  presuppose its answer.
- **Does utang display belong here?** A customer's outstanding balance and aging are what make "charge it to my
  account" meaningful, but they live in `apps/collectibles`, not `apps/pos`.

## What the code already answers (do not re-research)

| Fact | Where |
| :--- | :--- |
| `Customer` carries `name`, `customer_type` (`WALK_IN` / `REGULAR` / `CONTRACTOR`), `contact_details`, `tin_no`, `total_credit_limit`, `is_active` | `apps/pos/models.py:6` |
| `/api/v1/customers/` is **full CRUD** — `GET/POST/PATCH/DELETE`, authenticated | `ENDPOINTS.md:98` |
| `/api/v1/ledgers/` — `GET` outstanding receivables (**+ nested payments**) | `ENDPOINTS.md:109` |
| `/api/v1/ledgers/aging/` — `GET` aging report, overdue/open grouped by customer | `ENDPOINTS.md:110` |
| Ledger **writes** are Admin-only (`IsAdminOrReadOnly`) | `ENDPOINTS.md:111` |
| `seed_demo` seeds a **Walk-in Customer** plus named customers | `seed_demo.py:245` |
| The client calls `/api/v1/customers/` and `/ledgers/` **nowhere** — zero call sites | measured 2026-10-16 |

So no new endpoint is needed. This is a *scope* decision, not a transport one — the same shape as
[Phase 1 Live Data Home and Mock Retention](./12-phase-1-live-data-home.md).

## Why it matters

Phase 3's checkout will need *some* customer selection to function at all, and the naive answer ("just a picker")
quietly decides that a cashier cannot serve a new utang customer without leaving the till — which is a real
operational gap, not a detail. Whichever way this goes, it also decides what `sales_customers_page.dart` and
`sales_receivables_page.dart` (both currently mock, per `docs/SYSTEM_ATLAS.md`) become: wired, consolidated, or
deleted.

## Needs a domain sketch

- Who can create a customer, and what is the minimum viable customer record at the counter (name? credit limit?
  TIN for a BIR receipt?).
- Whether the POS customer picker and the sales "Customers" screen are **one** screen or two, and whether either
  survives.
- Whether the utang view is a customer-detail panel, a separate collectibles screen, or both.

## Resolution

Unresolved. Resolve in a Phase 4 session, **after Phase 3 is built** — building checkout first will show which
customer operations the counter actually reaches for, and this decision should be informed by that rather than
guessing ahead of it.
