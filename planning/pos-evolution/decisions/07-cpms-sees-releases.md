# How CPMS learns what was released and owed

**Mode:** grill · **Status:** ✅ Locked 2026-11-03 (by: me — user chose C: a project must be able to know its utang)
**Folds in:** the payables half of open question 4 of [CPMS ↔ POS material-token integration model](../../api-integration/decisions/21-cpms-token-integration-model.md).
**Depends on:** [Releasing when stock is short](./05-short-stock-release.md) (partial releases exist) and [Closing a partly released request](./06-closing-partial-requests.md) (the project manager needs to know what is still outstanding before closing).

## Question

After a release, CPMS knows only what it requested. Does CPMS need to see what was released, what is still outstanding, and what the project owes the store, and if so how does it get it?

## Options

- **A. CPMS does not need it.** The store bills the contractor as today; CPMS tracks only its own requests. The project manager closes a remainder without seeing what was released.
- **B. The POS pushes each release to CPMS.** After a release the POS calls a CPMS endpoint with released quantities and amounts. CPMS is always current, but the POS now makes outbound calls (CPMS endpoint, credentials, retry queue), and a CPMS outage must not block the till.
- **C. CPMS reads it from the POS when it needs it.** The CPMS service account may read, per request and per project: released and outstanding quantities and the project's utang total and balance. No outbound calls from the POS; CPMS asks when the project manager opens a request.

## Recommendation

**C**: keeps the POS free of outbound calls (the till never depends on CPMS, as in decision 02), reuses the one service account, and gives the project manager the outstanding quantities needed before closing.

## Decision

**C. CPMS reads it from the POS when it needs it.** The CPMS service account may read, per request: each line's requested, released and outstanding quantity and the request status; per project: utang total, paid and balance. Read-only, no prices per item beyond what the project owes, no stock. The POS makes no outbound calls.
