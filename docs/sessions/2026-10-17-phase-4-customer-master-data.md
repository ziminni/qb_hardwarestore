---
date: 2026-10-17
branch: feature/backend-integration
scope: Phase 4 — customer master data, then its review
repo: qb_pos_inventory_system
skills: [wayfinder, executing-plans, requesting-code-review, test-driven-development]
commits:
  - df908a9  # the three Customer.full_name defects (aging 500 -> 200)
  - 07f955b  # a walk-in cannot go into utang (400 WALK_IN_CANNOT_OWE, wholesale rollback)
  - 1330a31  # CustomerService, CustomerRepository, the four-type Customer model
  - e6a81c4  # absolute cross-app import
  - 88f3fc6  # the viewmodel half of the customer step
  - 44fba8c  # the picker, the counter create form, the cart row
  - 3e56b9a  # the utang panel with its advisory credit limit
  - b3875aa  # the code review's Important findings
  - 86f294d  # read every page of customers, not just the first 50
  - 300c049  # formatting
  - 9882e0f  # T6: the underpaid walk-in flow
  - 9994ba9  # T7: the receivables screen on the real ledger
  - 2426955  # the phase table correction
  - 98049aa  # review: the sidebar regression and the WALK_IN dead end
  - 0575794  # review: a payment must move the ledger
  - 33d18d8, 03b3b2a, 3a8f05d  # review: the record-integrity findings
  - 730d0e9  # review: make the F1 test able to fail
  - 56b1435  # phase 4 closed, coverage debt recorded
---

# Phase 4 — Customer Master Data

## Destination

Make decision 14 usable at the counter: the cashier can see who is paying, record a customer who is not in the
system yet, see what that customer owes, and **cannot** book a debt against nobody.

## What was built

| Task | Outcome |
| :--- | :--- |
| 1 | The three `Customer.full_name` defects. `GET /ledgers/aging/` went **500 → 200**; `customer_name` had been **absent**, not null, from every ledger row (DRF skips a `ReadOnlyField` whose source is missing) |
| 2 | A walk-in cannot go into utang: `400 WALK_IN_CANNOT_OWE` with a stable code, raised at the shortfall site inside the sale's `transaction.atomic()`, so the refusal rolls back wholesale |
| 3 | `CustomerService` (no delete — the FK is `PROTECT`), `CustomerRepository`, and a `Customer` model carrying **all four** types plus an `unknown` fallback |
| 4 | The checkout customer step, inside the existing cart card rather than a new screen |
| 5 | `PosUtangPanel`: balance, open and overdue counts, and a **credit-limit warning that is advisory, never a block** (`0` means *not set*, not *no credit*) |
| 6 | The underpaid walk-in flow: a three-way choice — collect the full amount, or record a customer to owe it |
| 7 | `sales_receivables_page.dart` reads the real ledger; `sales_customers_page.dart` deleted with its route |
| 8 | Live end-to-end verification as the **cashier**, plus a fresh-context review |

## What the review found

The phase was reviewed by a fresh-context agent over `3e56b9a..9994ba9`. It returned 13 findings;
**12 are fixed**. The two that mattered most:

- **A money bug, live the whole time.** `POST /ledger-payments/` saved the payment and **never moved
  `balance_due`**, so a paid-in-full customer still read as owing everything — on the aging report, the utang
  panel, and the receivables screen built in this very phase. It also **accepted overpayment**: ₱600 against a
  ₱500 debt returned `201` and swallowed ₱100.
- **A regression this phase introduced.** Deleting the sales customers page renumbered the **inventory** sidebar,
  which had lost nothing, so an inventory user opening Sales saw *Suppliers* highlighted. No test covers
  `selectedNavigationIndex`, which is why it reached a commit.

## The lesson worth carrying

**Three tests were found that could not fail**, each written by someone who believed it covered the behaviour:

1. Two `collectibles` payment tests performed the balance arithmetic **themselves** —
   `balance_due = balance_due - amount_paid` — asserting that *the test* could subtract. They passed for as long
   as the application could not, which is exactly how the money bug survived.
2. The F1 test drove a failure through a condition (`lateFailureFor != customerId`) that was **unreachable**,
   because the caller always requests the currently selected id — so it failed the customer while that customer
   was still selected, which is *correct* behaviour. It took three attempts to make it fail, the second of which
   also could not fail: the stub read the failure flag *after* a gate the test then cleared, so the "failing"
   request actually succeeded.

**The standard adopted:** a test is not accepted as covering a fix until it has been run against the code
**without** the fix and seen to fail.

## Verification

- **Live, as the cashier**: record a customer → `201` (credit limit 0.00, unsettable by a cashier); sell on
  account underpaid → `201`; the debt readable **two ways that agree** (`/ledgers/?customer=` and `/ledgers/aging/`,
  whose totals moved 5372.00 → 5373.00); an anonymous underpaid sale → `400 WALK_IN_CANNOT_OWE` **having written
  nothing**. Probe removed and the state restored byte-identically.
- **Gate:** backend **46 OK**, `manage.py check` clean, `flutter analyze` clean, flutter **235/235**, tree CLEAN.
- **Atlas:** 8 live · 3 partial · 18 mock · 8 dead (37 rows), recounted from the rows and asserted in both
  artifacts — a recount that also reconciled a long-standing miscount, because the table grades dead rows with
  **two** spellings (`⚫ Orphaned` ×2 and `⚫ Dead` ×6) and a tally recognising one reported 2 where the figure
  had always meant 8.

## Not done, recorded rather than implied

- **The Phase 4 screens have no widget tests.** The services are covered; the screens are not — including
  `PosTransactionPage._pay`, which holds the entire "submit nothing" invariant, and `selectedNavigationIndex`,
  whose absence is how the sidebar regression got through. Tracked as its own task.
- **The ₱4,900 Walk-in ledger row** is untouched by design (decision 14 scopes the rule to future behaviour) and
  is now visible in the receivables screen. It is a data question, not a code one.
- **`flutter run` has never been executed against the live backend.** Contracts are probed; the pixels are not.

## Next step

Phase 5 is unlocked. [Requisition UI Ownership](./../planning/api-integration/decisions/09-requisition-ui-ownership.md)
resolved on 2026-10-17: POS builds the downstream half — approve, reject, verify token, release — and CPMS owns
create and submit.
