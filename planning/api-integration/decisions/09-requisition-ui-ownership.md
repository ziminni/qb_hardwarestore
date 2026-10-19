# Requisition UI Ownership (POS side vs CPMS side)

**Mode:** grill · **Status:** ✅ RESOLVED 2026-10-17
**Phase:** 5 — born from [Role to Dashboard Routing for All Six Roles](./04-role-dashboard-routing.md).

## The question

Which parts of the requisition lifecycle should the POS client build UI for, now that requisition *creation* is
known to be a CPMS-side action?

## Why it matters

The product owner clarified that a Site Foreman is a CPMS identity that requests material from the store — not a
POS user. But the POS backend implements the **entire** lifecycle, and its permissions are spread across three
different roles:

| Step | POS endpoint | Backend permission |
| :--- | :--- | :--- |
| Create requisition | `POST /api/v1/requisitions/` | Site Foreman / Store Manager / Admin |
| Submit | `POST /api/v1/requisitions/{id}/submit/` | Site Foreman / Store Manager / Admin |
| Approve | `POST /api/v1/requisitions/{id}/approve/` | Store Manager / Admin |
| Reject | `POST /api/v1/requisitions/{id}/reject/` | Store Manager / Admin |
| Verify token | `POST /api/v1/tokens/verify/` | Any authenticated |
| Release materials | `POST /api/v1/tokens/release/` | Cashier / Store Manager / Admin |

Only creation and submission need a Site Foreman — a role that will not log into POS. Everything else is
Store Manager or Cashier work, which are genuine POS roles.

## Options

### A. POS builds the full lifecycle

Create, submit, approve, reject, verify, release — everything the backend exposes.

- **Cost:** requires either a foreman login in POS (which decision 04 ruled out) or letting a manager
  impersonate one, and duplicates CPMS screens.
- **Risk:** two systems owning requisition creation, diverging.

### B. POS builds approval and release only

Store Manager approves or rejects; Cashier verifies and releases. Creation and submission belong to CPMS.

- **Cost:** the POS demo cannot originate a requisition; it depends on `seed_demo` (which already supplies an
  APPROVED requisition with a minted token) or on CPMS calling the API.
- **Risk:** low, and `seed_demo` removes the dependency in practice.

### C. POS builds release only

Even approval moves to CPMS; POS just redeems tokens.

- **Cost:** the Store Manager — a real POS role — loses the approve action the backend grants them.
- **Risk:** contradicts the backend's permission model.

## Recommendation

**Option B.** It matches the role ownership now known: creation and submission need a CPMS identity, while
approval and release are Store Manager and Cashier work — both genuine POS roles. `seed_demo` already creates an
APPROVED requisition with a minted token, so the POS demo path (verify → release) is testable without building
any creation UI.

This also shrinks Phase 5 from "build the requisition module" to "build two screens: approve and release".

## Resolution

**Option B — POS builds the DOWNSTREAM half. Locked 2026-10-17.**

POS owns **approve · reject · verify token · release materials**. CPMS owns **create · submit**. No requisition
creation UI is built in POS, and no CPMS identity logs into POS.

### The contract, verified against the code rather than the table above

Read from `backend_django/apps/requisitions/{models,services,urls}.py` on 2026-10-17:

- **State machine.** `DRAFT → SUBMITTED → APPROVED → RELEASED`, with `REJECTED` as a branch off SUBMITTED/APPROVED.
  Every transition is guarded in `services.py` and raises `ValueError` on an illegal move, so the UI must not
  offer an action the current status forbids — the server will refuse it and the refusal is not distinguishable
  from a bug to a counter clerk.
- **Approve MINTS the token.** `approve_requisition` sets APPROVED, writes `approved_by`/`approved_at`, and
  creates the `MaterialToken` inside one `transaction.atomic()`. A token is `OneToOneField` to its requisition:
  **one token per requisition**, generated exactly once.
- **The token is single-use.** `MaterialToken.is_used` / `used_at` / `used_by`; `verify_token` refuses a used
  token (`'Token has already been used.'`) and refuses one whose requisition is not APPROVED.
- **Release is a SALE, not a stock adjustment.** `release_materials` FIFO-deducts stock through the SAME
  `apps.inventory.services.allocate_fifo` the POS checkout uses, **creates a `SalesTransaction` with
  `source=REQUISITION`**, then marks the token used and the requisition RELEASED. So a release produces a
  receivable-bearing sale the moment the customer is in utang, and it fails with the same
  `INSUFFICIENT_STOCK` contract (carrying `variant_id`) that Phase 3 already taught the cart to mark.
- **Provenance is available.** `verify_token` returns requisition details using
  `select_related('requisition__project__customer')`, and `Requisition` carries `req_number`, `project`,
  `requested_by` and `approved_by`. This matters because POS did not originate the requisition.

### The provenance requirement (the risk this decision accepts)

Because a requisition appears in a POS queue that POS never created, **every approve/verify surface must show
where it came from**: `req_number`, the project, that project's customer, and the requesting foreman. A store
manager approving an anonymous-looking list of material requests is the failure mode this decision creates, and
showing the origin is the whole mitigation. The data is on the wire; nothing needs adding to the API.

### What Phase 5 shrinks to

1. **Approve / reject queue** (Store Manager) — the SUBMITTED requisitions, with items, project and requester,
   and the two actions gated on status.
2. **Verify and release** (Cashier, at the counter) — token entry/scan, the verified requisition shown for
   confirmation, then release. A used token must read as *already used*, not as *not found*: they are different
   things and the second one makes a cashier think they mistyped.

`seed_demo` supplies DRAFT, SUBMITTED, APPROVED-with-token and RELEASED requisitions, so both screens are
testable with no creation UI and no CPMS involvement.

### Accepted costs

- **POS cannot originate a requisition.** In the demo this is invisible (`seed_demo`), but a real deployment
  needs CPMS to call `POST /api/v1/requisitions/`.
- **Two systems now own one lifecycle**, split at submit/approve. The split point is the SUBMITTED status — the
  one state CPMS can produce and POS must consume — so that status is the integration seam and should be treated
  as a contract, not an implementation detail.

### Not decided here

- Whether the approve queue paginates or filters by project (a UI question once the screen exists).
  Still open as minor polish; the service already follows pages, so this is filter UI only.
  **Resolved 2026-10-19 (wayfinder grill): leave unfiltered.** The queue stays newest-first with no
  filter control — filtering gates nothing and even a client-side search would only cover fetched
  rows. Reopen only with a concrete foreman complaint, not a hypothetical one.
- The payment-posting UI for receivables. `POST /ledger-payments/` was fixed on 2026-10-17 so it finally moves
  `balance_due` and refuses overpayment, which makes such a screen viable for the first time — but it is a
  collectibles question, not a requisition one, and it stays in the Fog of War.
  **Resolved 2026-10-18 by [Receivables Record Payment](./19-receivables-record-payment.md): BUILD for Cashier+.**
  The note above is history now, not an open item — kept so the audit trail survives.


---

## Amendment — 2026-10-17: the queue needs a field the list endpoint did not return

Resolving this decision required the approve queue to show **the project's customer**, but the queue's
only data source, `GET /api/v1/requisitions/`, carried `project_name` and `requested_by_name` and **no
customer at all**. The requirement and the contract disagreed, and nothing had noticed because decision
09 was written from the domain, not from the serializer.

**Ruling (user, 2026-10-17): add a read-only representation field.**

- `RequisitionSerializer.project_customer_name = CharField(source='project.customer.name', read_only=True)`.
- This adds **no endpoint** and touches **no model or migration**, so the map's binding backend
  invariant — *no new endpoints, no model or migration changes* — still holds exactly. It is a
  representation change, which is the one kind of backend edit the invariant permits.
- Pinned by `apps.requisitions.tests.RequisitionProvenanceTests`, which asserts all **four**
  provenance facts together (`req_number`, `project_name`, `requested_by_name`,
  `project_customer_name`) because the row is only useful if the set is complete. It went RED with
  `KeyError: 'project_customer_name'` while the first three asserts passed — evidence the test is
  not vacuous.

**The rejected alternatives, and why**, because both will be proposed again:

- *Show the customer only at release time* would have required amending this decision's own
  provenance rule, and it re-creates the anonymous-looking approval the rule exists to prevent: a
  Store Manager would approve without seeing who the requisition is for.
- *Client-side N+1 fetches* needs a `GET /api/v1/projects/` dependency and can render a row
  half-loaded — a project with a blank customer on a partial failure, which reads as "no customer"
  rather than "not loaded".
