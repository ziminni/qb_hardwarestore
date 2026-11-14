---
date: 2026-10-17
branch: feature/backend-integration
scope: Phase 5 unlocked and started, plus the Phase 4 test-coverage debt — and a dead feature found by testing
repo: qb_pos_inventory_system
skills: [wayfinder, executing-plans, test-driven-development, verification-before-completion]
commits:
  - 7a905c3  # decision 09 RESOLVED — POS builds the downstream half; MAP 13 locked · 1 open
  - 12f3706  # AGENTS.md index rewritten (it was wrong in five ways)
  - 94dcb28  # the commit count is no longer a constant a commit invalidates
  - 9d0c594  # Phase 5 T1: the requisition transport layer (no create/submit, by design)
  - b552ba7  # task 19: PosUtangPanel (F5) + SalesReceivablesViewmodel
  - 493f12b  # task 19: selectedNavigationIndex on every page
  - f51a06c  # task 19: PosCustomerPickerDialog
  - 18ab81e  # task 19: SalesReceivablesPage + its first viewmodel seam
  - c140116  # task 19: the pay-path seam, and the blocker recorded
  - 7d04bf2  # task 19: DashboardShell ListTile-in-ColoredBox fixed
  - a9f74ec  # task 19: the pay path tested, SystemBrand overflow fixed, the dead feature found
---

# Phase 5 Unlocked, the Coverage Debt Paid, and a Dead Feature Found

## Focus

Close Phase 4 properly (it had been declared done while its screens were untested), resolve the next
open decision on the map, and start Phase 5 — without adding unnecessary churn to the frontend a
teammate authored.

## What Was Built / Changed

**Decision 09 — [Requisition UI Ownership](../../planning/api-integration/decisions/09-requisition-ui-ownership.md)
RESOLVED.** POS builds the **downstream half** (approve · reject · verify token · release); CPMS owns
create and submit. Verified against the code rather than restated: `approve_requisition` MINTS the
token inside one transaction, the token is `OneToOne` and single-use, and **`release_materials` is a
SALE** — it FIFO-deducts through the same `allocate_fifo` the checkout uses, creates a
`SalesTransaction` with `source=REQUISITION`, and **always posts a receivable** because a
construction firm pays later. MAP now reads **13 locked · 1 open**.

**Phase 5 Task 1 — the requisition transport** (`9d0c594`): `requisition.dart`,
`requisition_service.dart`, `requisition_repository.dart`, with **no create or submit method at all**
— the decision made structural, since a service without `createRequisition` cannot grow a button
needing a Site Foreman. RED first (22 compile errors), then 10 tests green.

**Task 19 — the Phase 4 coverage debt.** Flutter **235 → 291**. Five screens now tested, each
verified by mutating the source: `PosUtangPanel` (review F5), `SalesReceivablesViewmodel`,
`SalesReceivablesPage`, `PosCustomerPickerDialog`, and `selectedNavigationIndex` on every page in
`lib/features/sales/views`. Plus `PosTransactionPage` — 2 of 3 of its pay tests red-green verified.

**Two shared-UI defects fixed**, neither in a POS screen, both blocking every widget test under
`DashboardShell`:
- a `ListTile` inside a `ColoredBox` (`dashboard_shell.dart:54`) — Flutter asserts the tile's ink is
  invisible because it paints on a different ancestor than the background. The colour moved onto a
  `Material`.
- an undefended `Row` in `SystemBrand` overflowing the fixed 220px sidebar — `MainAxisSize.min`, no
  `Flexible`, no `overflow`, so a longer subtitle or a larger **accessibility text scale** overflows
  it. Fixed with `Flexible` + ellipsis.

## Mistakes & Gotchas (Do Not Repeat)

- **A DEAD FEATURE, found only by testing the seam between two files.** `PosPaymentDialog`'s
  validator refuses any amount below the total, so `payment.amountPaid < transaction.total` in
  `_pay` can **never** be true. Decision 06 §4's underpayment confirmation is dead code, the entire
  three-way walk-in flow built as Phase 4 T6 is **unreachable through the UI**, and the server's
  `WALK_IN_CANNOT_OWE` refusal can never fire from the till. It hid for a whole phase because the
  dialog looks generous and `_pay` looks like it handles what the dialog prevents — and both were
  reviewed, once by me and once by a fresh-context reviewer, without either noticing.
- **A mutation that breaks COMPILATION proves nothing.** Flutter reports it as
  `loading <file>` in the failing-tests list, which reads exactly like "the test caught it". I twice
  counted that as RED evidence before noticing. Confirm a mutation COMPILES before counting its
  failure.
- **Never build an edit anchor from piped output.** Seven consecutive scripted edits silently did
  nothing because I copied indentation from `sed 's/^/  /'` output, whose 2-space prefix is
  display-only. Every anchor was two spaces too deep, threw *before writing*, and left a suite
  reporting "All tests passed" against unmodified code.
- **Scripts must be grepped, not trusted.** One heredoc died on a regex-escape error and wrote
  nothing; the commit that followed was a no-op reporting "nothing to commit".
- **A test that cannot fail is worse than no test.** Four were found this session: two collectibles
  payment tests that performed the balance arithmetic themselves (which is how a real money bug
  survived — `POST /ledger-payments/` never moved `balance_due` and accepted overpayment), and one
  that drove a failure through an unreachable condition.
- **A commit count recorded in a tracked file is stale the instant it is committed.** AGENTS.md
  claimed "114 commits" through four phases for that reason.

## Decisions

- **POS owns the requisition DOWNSTREAM half** (approve · reject · verify · release); CPMS owns
  create and submit — and the client has no method for the other half.
- **Every approve/verify surface must show where a requisition came from** (`req_number`, project,
  project's customer, requester), because POS approves requests it never created. The data is
  already on the wire.
- **An unrecognised customer type is treated as a NAMED account**, not anonymous: a type added on
  the server is almost certainly a named customer, and falsely refusing to let them owe blocks
  legitimate business. The server remains the authority.
- **A failed load keeps the rows it already had**, on every money screen. Emptying a table states
  "this store is owed nothing" — a far more dangerous claim than "this did not load".
- **Overpayment is refused, not clamped** (`apply_payment_to_ledger`), and `processed_by` is
  read-only: the client was required to supply a value the server overwrote.
- **Two optional `viewmodel` seams were added to pages** (`SalesReceivablesPage`,
  `PosTransactionPage`) — production changes made for testability, matching a convention already
  used four times in this repo.
- **The dead underpayment flow is a PRODUCT question, not a code one**: either the validator is
  wrong (allow a short amount) or the underpayment UI is wrong (delete it). Escalated, not decided.

## Wins & Next Step

**Working and verified (fresh, at `a9f74ec`):** backend **46/46 OK**, `manage.py check` clean,
`flutter analyze` clean, flutter **291/291**, tree CLEAN, **155** commits ahead of `origin/master`,
Atlas score **8 live · 3 partial · 18 mock · 8 dead (37 rows)** recounted in both artifacts.
Decision 09 resolved; Phase 5's transport built and tested; Phase 4's coverage debt paid down to one
unverified test, recorded as unverified.

**Next step — the first thing the next session should do:** answer the product question in
`#21` (the unreachable underpayment flow), because it decides whether the remaining test work is
"cover the underpayment paths" or "delete them". Then build **Phase 5 Task 2**: the approve/reject
queue for the Store Manager, with both actions **gated on status** (the server refuses an illegal
transition with a bare `ValueError` a clerk cannot distinguish from a bug), on a surface that shows
**where each requisition came from**. `seed_demo` already supplies DRAFT, SUBMITTED,
APPROVED-with-token and RELEASED rows, so no creation UI and no CPMS are needed.
