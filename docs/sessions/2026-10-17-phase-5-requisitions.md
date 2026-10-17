# Phase 5 — the requisition lifecycle's downstream half

**Date:** 2026-10-17 · **Branch:** `feature/backend-integration` (unpushed) · **Decision:** 09 (locked
2026-10-17, plus an amendment) · **Range:** `9d0c594^..a8c2c12`

## What this phase built

POS owns the **downstream** half of the requisition lifecycle — approve, reject, verify token, release.
CPMS owns create and submit. The split is **structural, not conventional**: `RequisitionService` has no
`createRequisition` and no `submit` method at all, so it cannot grow a button needing a Site Foreman, a
CPMS-only identity that never logs into POS.

| Piece | File |
|---|---|
| Transport | `data/models/requisition.dart`, `data/services/requisition_service.dart`, `data/repositories/requisition_repository.dart` |
| Approve/reject queue | `features/admin/viewmodels/admin_requisitions_viewmodel.dart` + `features/admin/views/requisitions_page.dart` (live) |
| Release counter | `features/pos/viewmodels/material_release_viewmodel.dart` + `features/pos/views/material_release_page.dart`, routed at `/pos/release` |
| Backend | `RequisitionSerializer.project_customer_name` (read-only) + a `select_related` fix |

## Verified live (not against stubs) — 2026-10-17

```
login as manager                    -> HTTP 200
GET  /requisitions/                 -> 200, project_customer_name='Dela Cruz Construction'
POST /tokens/verify/ (unused token) -> 200, REQ-20260925-0003, item remaining 8.00
POST /tokens/verify/ (USED token)   -> 400 'Token has already been used.'   <- not "not found"
POST /tokens/verify/ (malformed)    -> 400 {'token': ['Must be a valid UUID.']}
POST /transactions/ underpaid anon  -> 400 WALK_IN_CANNOT_OWE, shortfall '215.00'
     DB before/after: transactions 7/7, ledgers 2/2, batch_v8 95.00/95.00  <- byte-identical
```

The last line is the point: **`WALK_IN_CANNOT_OWE` had never been observed firing from the till.** The
client's underpayment path was dead code until #21 was resolved (below), so the guard was unreachable.

## The three defects this phase found — all in the same gap

Every one was invisible to reading either file alone, and survived because **nothing tested the SEAM**:

1. **The underpayment flow was dead code** (`#21`). `PosPaymentDialog`'s validator rejected any amount
   below the total, so `payment.amountPaid < transaction.total` in `_pay` could never be true — making
   decision 06 §4, Phase 4 T6's three-way walk-in flow, and `WALK_IN_CANNOT_OWE` all unreachable.
2. **`admin_skeleton_layout.dart`** had a `ListTile` inside a coloured `Container`, tripping Flutter's
   "background color or ink splashes may be invisible" assertion and making **every admin page
   untestable**. The same defect had already been fixed in `dashboard_shell.dart`.
3. **The list endpoint did two queries per row** — `project.customer` (a second hop the amendment
   introduced) and `token` (a reverse OneToOne). Found by the author's own review pass.

## Review outcome

A fresh reviewer (glm-5.3-flash, 28 tool uses) returned **Critical: none** and confirmed the binding
backend invariant held — a read-only serializer field and a `select_related` change, no new endpoint, no
model or migration. Three **Important** findings, each fixed RED→GREEN:

- a drifted success body **froze the release screen** (`FormatException` escaped the guarded conversion);
- a **malformed token blamed the requisition list** (DRF's `{'token': [...]}` carries no `detail`);
- a **second in-flight press was sent** on the admin queue (the release viewmodel guarded this; the
  admin one did not).

## Rulings made (the reasoning, preserved because the ledger is gitignored)

1. **The validator was wrong, not the flow** (`#21`) — a short amount records an utang, so the dialog
   warns and accepts. Deleting the flow would have orphaned decision 14's utang panel, its credit-limit
   warning and its `nameCustomer` path. *Cost if wrong: a mistyped amount records an unintended receivable.*
2. **Route the counter AND give it a nav entry** — a registered route with no clickable path is still an
   orphan to a real user. *Cost if wrong: one nav entry to remove.*
3. **The Atlas row stayed ⚫ Dead until both existed** — marking it live earlier would have been the same
   overstatement as the stale phase-state duplication repaired this phase. *Cost if wrong: a truthful
   "dead" that understates progress.*
4. **Fix the queryset, not drop the field** — decision 09's amendment requires the customer; the queryset
   was wrong. *Cost if wrong: two joins, cheaper than N+1.*
5. **Anchors must be read from the file as it is now** — proven three times this phase, each time by a
   script asserting on text a previous read had shown (the dart formatter reflows; a file's last line may
   have no trailing newline). *Cost if wrong: a half-written tree.*
6. **A test error is not a RED** — a run that errors proves nothing, exactly like a mutation that breaks
   compilation. *Cost if wrong: a fix that "passed" a test that never asserted anything.*

## Deferred minors (deliberately not fixed)

- `PARTIAL` and `CANCELLED` exist on the server **today** and are absent from `RequisitionStatus`, so
  they render "Unknown". The `unknown` mechanism handles them correctly (row kept, no button).
- A failed refresh hides the queue although the viewmodel deliberately kept the stale rows.
- The minted token is dropped by the queue; nothing in POS displays one.
- `material_release_page_test.dart`'s `failVerify` is a dead stub knob.
- `sidebar_index_consistency_test.dart` covers only the sales/inventory sidebars — the two new screens
  sit outside the one test built for that regression class.

## Still not done

**`flutter run` has never been executed against the live backend.** Every contract above was probed over
HTTP; the pixels are unverified. That remains the honest gap, and it is now the only one.
