---
date: 2026-10-17
branch: feature/backend-integration
head: 6dee5c0
---

# Wayfinder complete, and Phase 6 started

## Focus

Two things: (1) confirm the index layer (`AGENTS.md`, `planning/MAP.md`,
`planning/api-integration/MAP.md`, `decisions/`) was still telling the truth, and (2) work the Wayfinder
map to completion — then start Phase 6.

## What Was Built / Changed

**The map is COMPLETE: 18 decisions locked, 0 open, frontier/blocked/fog all empty.**

Five decisions resolved this session, all of which reshaped Phase 6:

| Decision | Ruling |
| :--- | :--- |
| [Sales Stack Reconciliation](../../planning/api-integration/decisions/05-sales-stack-reconciliation.md) | quotations and orders get **REAL backend models** — the sales role ships all seven screens |
| [Customer Returns](../../planning/api-integration/decisions/15-customer-returns.md) | a return is a `SalesTransaction` with `source='RETURN'` and **negative** amounts + an optional `original_transaction` FK; restock the original batch when linked, else the newest active one |
| [The Reports Surface](../../planning/api-integration/decisions/16-reports-surface.md) | **ONE** admin/manager Reports screen; the sales and inventory report screens are deleted |
| [Receiving Stock Through the UI](../../planning/api-integration/decisions/17-receiving-ui.md) | **build** the receiving screen — the only scope decision needing **no** backend work |
| [Product Images](../../planning/api-integration/decisions/18-product-images.md) | leave `image_url` blank; the placeholder widget already exists |

**Built — Phase 6 task 6A.1:** `Quotation` + `QuotationItem` in `apps/pos`, `QuotationSerializer` /
`QuotationItemSerializer`, `QuotationViewSet`, `/api/v1/quotations/`, migration `pos/0002`, and a new
shared `backend_django/common/numbering.py`. Backend **48 → 52 tests**.

**The Phase 6 roadmap** is written in `planning/api-integration/MAP.md`: 6A backend (quotations, orders,
returns — two migrations), 6B screens on existing endpoints (reports, receiving), 6C wire the surviving
sales screens, 6D what is owed from earlier phases.

**Index repairs:** `planning/MAP.md` restated state the map owns; `AGENTS.md` violated its own "do not
duplicate status tables" rule; the map's head contradicted its own phase table; a locked decision (09)
was still marked `open` in that table; the invariant row now reads **SUPERSEDED TWICE**.

## Mistakes & Gotchas (Do Not Repeat)

1. **A claim that outruns its evidence — three times this session.** `analyze clean` asserted before it
   was run; *"the screen does not exist"* written after the screen existed; *"the roadmap below"* written
   before the roadmap existed; and in the final message a test result **carried** from the previous
   message. The class is identical every time: **prose asserting a state the artifact does not have.**
   Rule: if a claim is not followed by its command output **in the same message**, it is unverified.
2. **Anchors must be read from the file as it is now — three times.** A `pumpWidget` line the dart
   formatter had reflowed; a Dart test file whose last line has no trailing newline (so `rindex('});\n')`
   matched the *test's* brace and injected tests inside another test's body — symptoms were "No tests
   match" plus an **unrelated** test breaking); and a `'⚠️ NEW'` anchor copied from `sed` output with its
   2-space display prefix.
3. **A test ERROR is not a RED.** A run that errors proves nothing — same class as a mutation that breaks
   compilation (Flutter reports it as `loading <file>`). Twice: a `duplicate key ... req_number=()`
   error, and a mutation that left `token` used as non-null.
4. **Shell heredocs containing backticks execute them.** A ledger entry was written with `` `token` ``
   and `` `verification?.token ?? ''` `` **empty**, while the command reported success and the commit
   landed. Write ledger prose through python.
5. **`generate_req_number()` takes NO arguments** and is hardcoded to `Requisition`. Assuming a generic
   signature was wrong.
6. **A nested serializer's parent FK must be `read_only`.** Leaving `quotation` writable made it required
   on every nested item, rejecting a legitimate payload with *"quotation: This field is required."*
7. **A fog list is a list of UNKNOWNS.** Two items described **completed** work, which overstates what is
   still unknown. A resolved item belongs in a decision file, not the fog.

## Decisions

- **The map's binding invariant is now SUPERSEDED TWICE** — "no new endpoints, no model or migration
  changes" held exactly across `0052468..HEAD` (0 migrations, 0 models.py, 0 urls.py) and Phase 6 breaks
  it deliberately. The map says so rather than silently contradicting its plan.
- **Document numbering has ONE home** (`common/numbering.py`); `generate_req_number()` delegates and
  keeps its name, so no requisitions caller changed.
- **Quotations live in `apps/pos`**, not a new `apps/sales` — `ENDPOINTS.md` already maps `features/sales`
  → `apps/pos` and `SalesTransaction` already lives there.
- **The plan workspace is NOT deleted**, against the executing-plans instruction: `.superpowers/` is
  gitignored, so the ledger's 82 ruled entries are **not** in git history and deleting it would destroy
  the reasoning behind five phases. Phase 5's rulings were copied into git first.

## Wins & Next Step

**Verified live this session:** `GET /api/v1/quotations/` → **HTTP 200**; `project_customer_name` on the
requisition list; a used token → *"already used"*; a malformed token → `{'token': ['Must be a valid
UUID.']}`; and **`WALK_IN_CANNOT_OWE` firing from the till for the first time**, with the database
byte-identical afterwards (transactions 7/7, ledgers 2/2, batch_v8 95.00/95.00).

Fresh gate at `6dee5c0`: backend **52/52 OK**, `check` 0 issues, flutter **314/314**, `analyze` clean,
tree CLEAN.

**Next step: Phase 6 task 6A.2 — `SalesOrder` + `SalesOrderItem` + endpoint + migration**, which is the
same shape as the `Quotation` just built (copy `apps/pos/models.py`'s Quotation block, the serializers,
the viewset and the router line). Start it in a **fresh session**: this one is nearly out of context, and
`6A.3` (returns), `6B` (reports + receiving), `6C` and `6D` follow it.

**Still owed:** the branch is **unpushed** (a shared-branch side effect — ask first), and `flutter run`
has **never** been executed against the live backend.
