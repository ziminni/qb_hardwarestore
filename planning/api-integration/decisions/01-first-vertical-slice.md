# First Vertical Slice & Ordering Lens

**Mode:** grill · **Status:** LOCKED 2026-10-15 · **Opened:** 2026-10-15

## The question

27 screens sit on mock data across 10 modules. Which one do we wire first — and what criterion decides the
rest of the order? Pick the lens and every later session inherits it.

## Why it matters

The order looks forced by the data model. It is not. The 36 foreign keys do form a clean dependency DAG, but
`seed_demo` already supplies products, stock, customers, sales and an approved requisition — so the chain
**does not** force you to build a stock-receiving UI before POS. Ordering is a product decision, and it
decides what "progress" means for every session that follows.

## The dependency reality

Six layers, verified from `backend_django/apps/*/models.py`:

```text
0  User                                                          <- live today
1  Category · Brand · UnitOfMeasure · Supplier · Customer        <- leaves, nothing points down at them
2  Product (-> Category, Brand)
   ProductVariant (-> Product, UnitOfMeasure)
   VariantUOM (-> ProductVariant, UnitOfMeasure)
3  PurchaseOrder (-> Supplier) -> POItem -> GoodsReceipt -> InventoryBatch (-> ProductVariant)
   StockAdjustment · SystemAlert (-> ProductVariant)
4  SalesTransaction (-> Customer, User) -> SalesItem (-> VariantUOM) · Payment · OfficialReceipt
5  CollectibleLedger (-> Customer, SalesTransaction) -> CollectiblePayment
6  Project (-> Customer) -> Requisition -> RequisitionItem (-> ProductVariant) · MaterialToken
```

Two hubs carry most of the weight: **`ProductVariant`** (6 dependents, in layers 3, 4 and 6) and
**`Customer`** (3 dependents, spanning POS, collectibles and projects). Get either one wrong in the client
and every layer above it inherits the mistake.

## Options

### A. Cashier journey — products, then stock, then checkout and receipt

Highest demo value. Exercises both hubs in one pass, ends each phase with something visible (a catalogue,
then live stock, then a completed sale with a receipt), and `seed_demo` already supplies everything it needs.

- **Cost:** checkout is the single most complex call in the API — FIFO deduction, payment allocation, receipt
  generation and ledger posting all happen behind one POST.
- **Risk:** if the variant model shape is wrong, several screens need rework at once.

### B. Reference-data foundation — categories, brands, UoMs, then products and customers

Strictly leaves-first, so nothing is built on a wrong assumption. Unblocks every later layer cleanly.

- **Cost:** no demoable moment for the first two or three sessions.
- **Risk:** low technical risk, real motivational risk — it is invisible work.

### C. Requisition and material-token release — the dual-business differentiator

The only flow where the hardware store and the construction firm actually meet (UC-20/21/22). If the project
is graded on telling that story, this is the most distinctive thing in the system.

- **Cost:** the longest dependency chain of any option — projects, products, stock, plus the role routing fix.
- **Risk:** blocked today, because a Site Foreman cannot reach a dashboard at all (see
  [Role to Dashboard Routing for All Six Roles](./04-role-dashboard-routing.md)).

### D. Admin screens — users, audit logs, stats

Mirrors the one pattern that already works, so it is the lowest-risk start. Seven screens share a single mock
object, so one substitution updates all of them.

- **Cost:** proves nothing new, and the layout is the least interesting part of the system.
- **Risk:** very low. Also very low value.

## Recommendation

**Option A, executed in dependency order inside the slice** — products → stock → checkout → receipt — with a
short Phase 0 for the two cross-cutting prerequisites.

Why: `seed_demo` removes the data-creation prerequisite that would otherwise force option B first, both hubs
get exercised early, and every phase ends in something showable. Option B front-loads the work with nothing to
demonstrate; option C is currently blocked by the routing gap; option D is safe but teaches the team nothing.

The ordering criterion this locks: **prove the pattern on the highest-value read, then walk the dependency
chain, shipping a demoable outcome every phase.**

## Phase order (locked 2026-10-15)

| Phase | Scope | Why here |
| :--- | :--- | :--- |
| 0 | Substrate: product/variant model, pagination helper, role routing, register the 2 unregistered viewmodels | Blocks everything; small and unglamorous |
| 1 | Products module | The `ProductVariant` hub; highest-connectivity read |
| 2 | Inventory: stock list, low stock, movements | Needs the batch-vs-adjustment model distinction |
| 3 | POS checkout + receipt | The money path; the demo centrepiece |
| 4 | Customers master data | Completes the `Customer` hub |
| 5 | Requisitions + token release | The differentiator; needs phases 1-2 and routing |
| 6 | Admin, reports, sales | Bulk wiring at low risk once the pattern is proven |

## Resolution — LOCKED 2026-10-15

**Option A: the Cashier journey, executed in dependency order within the slice.**

The lens this locks, for every session on this map: **prove the pattern on the highest-value read, then walk
the dependency chain, shipping a demoable outcome each phase.**

Why A over the alternatives:

- **vs. B (reference data first):** `seed_demo` already supplies products, stock and customers, so the
data-creation prerequisite that would justify leaves-first does not exist. B spends two or three sessions
producing nothing demonstrable.
- **vs. C (requisition first):** C is blocked today — a Site Foreman cannot reach a dashboard at all (see
  [Role to Dashboard Routing for All Six Roles](./04-role-dashboard-routing.md)) — and it needs products and
  stock regardless, making it strictly downstream of A's Phases 1-2.
- **vs. D (admin first):** lowest risk, but teaches nothing about products, stock or checkout and leaves the
expensive unknowns untouched.

Accepted risk: Phase 3 hits the most complex call in the API — `process_sale` does FIFO deduction, payment
allocation, receipt generation and ledger posting behind one POST. Mitigated because Phases 1-2 settle the
product and stock model shapes before checkout depends on them.

The Phase 0 prerequisite that is easy to forget: `ProductsViewmodel` and `PosTransactionViewmodel` exist but
are **not registered** in `flutter/lib/main.dart` — only 6 of 8 viewmodels are wired, so Phases 1 and 3 would
appear to do nothing until they are added.
