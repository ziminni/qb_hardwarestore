# The store accepts or declines a pushed request

**Mode:** grill · **Status:** ✅ Locked 2026-11-06 (by: me — teammate's flow, agent recommendation accepted)
**Reopens:** [Requisitions after the foreman](./01-requisitions-after-foreman.md) ("no POS screen") for one small queue.
**Source:** teammate's flow note (2026-11-06): the store must be able to say it does not have the materials before anyone comes to the counter.

## Decision

- A pushed request lands as **Waiting for store**. A Store Manager (or Admin) **accepts** it or **declines** it with a required reason.
- **No stock reservation:** accepting promises to serve, it does not hold stock back from walk-in sales.
- The token only releases after Accept; a scan of a waiting or declined request is refused with a coded answer.
- CPMS learns the answer by reading the request status (decision 7 stands: the POS never calls CPMS). Telling the PM, foreman and the CPMS **client** (a read-only project viewer, CPMS-only) is CPMS's job.
- The QR is printed by **CPMS** at approval; it holds only the token so a 2D scanner types it into Release materials. The POS does not print release slips (teammate's slip in `700171c` dropped at merge, scan hint kept).

## Follow-up resolved

Status names/transitions, migration of APPROVED rows and withdrawal of a waiting request are locked in [Request states after Accept](./13-request-states-after-accept.md). Execution route: [Phase 1b plan](../phase-1b-plan.md).
