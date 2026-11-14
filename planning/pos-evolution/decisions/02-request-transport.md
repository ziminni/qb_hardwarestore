# How approved requests reach the POS

**Mode:** grill · **Status:** ✅ Locked 2026-11-03, "for now" (by: me — user chose A; revisit if CPMS cannot reach the POS at approval time)
**Folds in:** open questions 2 (token carrier) and 6 (transport) of [CPMS ↔ POS material-token integration model](../../api-integration/decisions/21-cpms-token-integration-model.md).
**Depends on:** [Requisitions after the foreman](./01-requisitions-after-foreman.md) (POS keeps a read-only copy).

## Question

Once the project manager approves in CPMS, how does the POS get the request (project, items, requester name) and the token the cashier will scan?

## Why it matters

It decides which POS endpoint replaces create/submit/approve, whether the POS needs a CPMS service account, and whether a release works when CPMS is unreachable.

## Options

- **A. CPMS pushes on approval.** CPMS calls a new POS endpoint (`POST /api/v1/requisitions/import/` with a CPMS service account) carrying project, items, requester and approver names, and the token. The POS stores the copy; the scan looks it up as today (`/tokens/verify/`). Needs both systems online at approval time; release works offline from CPMS.
- **B. The QR carries everything.** CPMS prints a signed QR (project, items, names, token id, signature with a shared key). The POS creates the copy on first scan after checking the signature. No live link at all; the QR gets dense, and a leaked key lets anyone forge requests.
- **C. POS pulls on scan.** The token is a short id; at scan the POS asks CPMS for the request. Simple data model, but every release depends on CPMS being up.

## Recommendation

**A**: matches the current POS shape (requisition rows + `MaterialToken` verify/release), keeps the trust check server-side with a revocable service account, and the till does not depend on CPMS at scan time.

## Decision

**A. CPMS pushes on approval.** On project-manager approval CPMS calls a new POS endpoint with a CPMS service account, sending the project, the items, requester and approver names, and the token. The POS stores its read-only copy; the cashier scan and release work exactly as today.

## Consequences for the build

- A new POS account type for CPMS (a service account in its own group), allowed to call only the import endpoint; deactivating it cuts CPMS off.
- The import must be safe to retry: the same CPMS request sent twice creates one copy (keyed by a CPMS request id).
- The POS no longer mints tokens on approval (`approve_requisition` goes); it stores the token CPMS sends and keeps the single-use check at release.
- Accepted cost: if the POS is down when the manager approves, CPMS has to retry until it gets through.
