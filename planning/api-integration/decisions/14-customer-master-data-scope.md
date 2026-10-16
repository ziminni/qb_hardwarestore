# Customer Master-Data Scope (POS side)

**Mode:** domain-model · **Status:** ✅ RESOLVED 2026-10-16 · **Opened:** 2026-10-16
**Phase:** 4 — **graduated out of Fog of War** when [POS Checkout Client Contract](./06-checkout-client-contract.md)
resolved. That decision proved checkout cannot run without a customer (a walk-in sale still sends the Walk-in
Customer's id, because `SalesTransaction.customer` is `FK(PROTECT)` with no `null=True`), which is what made this
question sharp enough to state.

## The question

**Which slice of customer master data must the POS own**, given that checkout already depends on being able to
identify a customer?

- **Select only, or create too?** → **Create too**, mid-sale, on a minimal record.
- **Who owns the customer record?** — still **out of scope**. This map rules CPMS and cross-system integration
  past its destination, so Phase 4 decides only what the *POS* does. Nothing here presupposes how the CPMS will
  share customers.
- **Does utang display belong here?** → **Yes**, at the point of sale, as a customer detail panel.

---

## Facts, all re-verified in code on 2026-10-16 (three corrections to the stub)

| Fact | Where |
| :--- | :--- |
| `Customer` carries `name`, `customer_type`, `contact_details`, `tin_no`, `total_credit_limit`, `is_active` | `apps/pos/models.py:6` |
| Broadened below — **three corrections the stub got wrong or incomplete** | **this decision** |

**Correction 1 — there are FOUR customer types, not three.** The stub lists `WALK_IN` / `REGULAR` /
`CONTRACTOR`. The model and the migration both carry **`CONSTRUCTION_FIRM`** as well
(`apps/pos/models.py:8-12`, `migrations/0001_initial.py:24`), and `seed_demo` seeds
`Dela Cruz Construction` with it. That type is the link to the construction side of the business, so a Phase 4
picker that hardcodes three types would silently mislabel every firm customer.

**Correction 2 — `/api/v1/customers/` writes are already open to a Cashier.** The stub says "full CRUD —
authenticated". It is `CustomerViewSet(BaseViewSet)` (`apps/pos/views.py:24`), and `BaseViewSet` carries
`permission_classes = [IsPOSOrReadOnly]` with the docstring *"Read requires auth; write requires POS role
(Cashier+)"* (`apps/pos/views.py:18-21`). So **mid-sale creation needs no backend permission change**. This is
what makes the chosen option cheap.

**Correction 3 — the utang surface the stub lists as available is BROKEN, two ways.**
`Customer` has **no `full_name`**; the project's `User` **does**. One wrong assumption was copied from the other
model, and it breaks four sites:

| Site | Failure (verified live) |
| :--- | :--- |
| `apps/collectibles/views.py:59` `entry.customer.full_name` | **Fatal** — `GET /api/v1/ledgers/aging/` returns **HTTP 500 `AttributeError`** |
| `apps/collectibles/serializers.py:36` `ReadOnlyField(source='customer.full_name')` | **Silent** — every ledger row returns `customer_name: null` |
| `apps/collectibles/admin.py:13` `search_fields = ['customer__full_name', ...]` | **Latent** — Django admin search on collectibles raises `FieldError` |
| `apps/collectibles/serializers.py:12` `source='processed_by.full_name'` | **Fine** — that is `User.full_name`, which exists. Do not "fix" it. |

Confirmed by direct call: `/api/v1/ledgers/aging/` → **500**; `/api/v1/ledgers/` → **200** with
`customer_name=None` on both rows.

**And the live database already contains the flaw the walk-in rule below addresses:**
`CollectibleLedger id=1 → customer='Walk-in Customer', type=WALK_IN, balance=₱4,900.00, status=OPEN`.

Other verified facts, unchanged from the stub: `/ledgers/` (`GET`, with nested payments),
`/ledgers/aging/` (`GET`, **exists** — an `@action` at `apps/collectibles/views.py:42` — but 500s),
ledger writes Admin-only via `IsAdminOrReadOnly` (`apps/collectibles/views.py:29`), `seed_demo` seeds the
Walk-in Customer plus `Maria Santos` (REGULAR) and `Dela Cruz Construction` (CONSTRUCTION_FIRM)
(`seed_demo.py:244-251`), and the client called `/customers/` nowhere before Phase 3.

---

## Domain sketch — identity at the counter

The whole decision turns on **whether a sale's customer is a person or a placeholder**. Two kinds of sale exist
and they must not be conflated:

| | **Anonymous (walk-in)** | **Account sale** |
| :--- | :--- | :--- |
| Who | Someone buying for cash and leaving | A named customer, possibly owing |
| Record | **The seeded `Walk-in Customer`, reused** — no new row, no details asked | A real `Customer` row |
| Payment | Must be **paid in full** | May underpay → `CollectibleLedger` |
| Why | You cannot collect from an anonymous walker, so a "receivable" against them is a fiction | The debt belongs to someone chaseable |

### Invariants

1. **A walk-in creates nothing.** Anonymous sales reuse the single seeded `Walk-in Customer`. The counter never
   asks an anonymous buyer for a name, contact or TIN.
2. **A walk-in cannot go into utang.** `process_sale` refuses `shortfall > 0` when the customer is
   `customer_type == WALK_IN`, with a stable machine-readable code (the same shape as Phase 3's
   `INSUFFICIENT_STOCK`). *Today it is allowed, and ₱4,900 is already booked against Walk-in — that row is
   pre-existing demo data and is not repaired by this decision; it is a consequence of the old behaviour.*
3. **Every debt is owed by a named customer.** If a walker wants to owe, the cashier records a customer on the
   spot (chosen above) — the debt is then collectable and the aging report is honest.
4. **A credit limit is advisory, never a hard block.** `total_credit_limit` defaults to `0`, and a hard block
   would refuse a sale a manager might approve. The panel *warns*; the server does not enforce.
5. **The POS never deletes a customer.** `DELETE /customers/` exists and is Cashier-permitted, but removing a
   customer with transactions would break the FK (`on_delete=PROTECT`) and destroy the audit trail. Phase 4 wires
   no delete.

### State machine — the checkout customer step

```text
   [no customer selected]
        │  default state; a sale may proceed as Anonymous
        │
        ├── pick existing ──────────> [selected: named]
        │                                 │  panel shows balance + aging + limit warning
        │                                 │  may underpay -> CollectibleLedger on THAT customer
        │                                 │
        └── + New customer ──> [create form: name + type, minimal]
                                   │  POST /customers/
                                   └──> [selected: named]  (form stays open on failure)

   Anonymous sale + underpaid
        └── REFUSED by the server
              ├── "Collect the full amount"        -> back to payment entry, nothing submitted
              └── "Record a customer for this utang" -> create form, then submit
```

---

## Locked decisions

1. **Create mid-sale, minimal record.** The counter form captures **name + customer_type only**. `contact_details`,
   `tin_no` and `total_credit_limit` keep their model defaults; a cashier is not asked to set a credit limit.
   *Rationale:* a new utang customer must not require leaving the till or an Admin, and the backend already
   permits it (correction 2). Rejected: select-only (leaves the gap), and a full-record form (slower at the
   counter and puts credit control in the cashier's hands).
2. **The picker offers all four types**, including `CONSTRUCTION_FIRM` (correction 1).
3. **Utang lives in a customer detail panel** on the checkout screen: name, type, outstanding balance, open and
   overdue counts, and a credit-limit warning. *Rationale:* "charge it to my account" is only meaningful if the
   balance is visible where the decision is made. Rejected: a separate screen only (the cashier cannot see the
   balance while deciding).
4. **A walk-in cannot utang**, and the underpayment dialog offers to name the customer inline.
5. **`sales_customers_page.dart` is DELETED; `sales_receivables_page.dart` is WIRED** to `/ledgers/`.
   *Rationale:* the POS picker is the single customer surface, so a separate mock customer list is a second home
   for one fact — exactly the vibe-debt the Atlas tracks. The receivables screen has no POS equivalent.
6. **The three `full_name` defects are fixed inside Phase 4** (correction 3), as a **backend change beyond the
   map's "client-side epic only" invariant** — the same situation Phases 2 and 3 were in, and recorded the same
   way. The aging panel cannot display a working balance otherwise.

## Deliberately not covered

- **VAT / BIR receipt fields.** `tin_no` is captured on the model but Phase 4 does not surface it and the receipt
  does not print it. Wiring BIR compliance is later work.
- **Editing or archiving customers**, and any delete path (invariant 5).
- **Repairing the existing ₱4,900 Walk-in ledger row.** The rule changes future behaviour; whether to reclassify
  or write off that historical demo row is a data question, not a client-contract question, and it belongs with
  the collectibles/utang work.
- **Who owns customers across POS and CPMS.** Out of the map's scope entirely.

## File impact

**Backend** (small, and only what the panel needs)
- `apps/collectibles/views.py:59` — `customer.full_name` → `customer.name`.
- `apps/collectibles/serializers.py:36` — point `customer_name` at `customer.name` (or drop the field; do not
  leave a silently-null key).
- `apps/collectibles/admin.py:13` — `customer__full_name` → `customer__name`.
- `apps/pos/services.py` `process_sale` — refuse `shortfall > 0` on a `WALK_IN` customer, with a stable code, via
  the existing `apps/pos/exceptions.py` handler pattern.
- Tests for both, in the established style.

**Flutter** (new, under `features/pos/`)
- `data/services/customer_service.dart` + `data/repositories/customer_repository.dart` — list, create, and the
  ledger lookup for one customer (one data path, as with every other service).
- `data/models/customer.dart` — extend the Phase 3 minimal model with `customerType` as a real enum covering four
  values, plus the balance/aging shape.
- The checkout customer step: a picker, a minimal create form, and the detail panel.
- The underpayment dialog gains the inline "record a customer" path.
- `sales/views/sales_receivables_page.dart` — wire to `/ledgers/`; delete `sales_customers_page.dart`.
- `data/models/sales_module.dart` — the mock customer rows go with the deleted screen; check what else reads it.

## Phase 4 tasks (outcome-driven)

1. **Fix the three `full_name` defects** + a regression test that `/ledgers/aging/` returns 200 and a ledger row
   carries a real `customer_name`. Nothing else can be verified until this is true.
2. **Refuse walk-in utang server-side**, with a stable code and a test proving an underpaid walk-in sale is
   rejected while an underpaid named-customer sale still succeeds.
3. **CustomerService/CustomerRepository** — list + create + one customer's ledger, on the one-data-path invariant.
4. **The checkout customer step** — picker over live customers, default Anonymous (walk-in), minimal create form.
5. **The utang detail panel** — balance, open/overdue counts, credit-limit warning.
6. **The underpayment flow change** — an underpaid anonymous sale stops and offers the two routes, submitting
   nothing until resolved.
7. **Wire receivables, delete the mock customers screen**, and let the Atlas reflect both.
8. **Live end-to-end verification** — create a customer at the till, sell to them on account, confirm the ledger
   and the panel agree with the server, and confirm an anonymous underpaid sale is refused.

## Status

**RESOLVED 2026-10-16.** The scope is locked: the POS can select **and** create customers mid-sale on a minimal
record, utang is shown at the till, walk-ins stay anonymous and cannot borrow, and the three `full_name` defects
are fixed as part of the phase. Phase 4 is ready to build.
