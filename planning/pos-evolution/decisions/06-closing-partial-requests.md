# Closing a partly released request

**Mode:** grill · **Status:** ✅ Locked 2026-11-03 (by: me — user chose A)
**Depends on:** [Releasing when stock is short](./05-short-stock-release.md) (remainder can be closed; released part stays payable) and [Requisitions after the foreman](./01-requisitions-after-foreman.md) (the POS copy is read-only).

## Question

A request is Partially released and the project decides not to wait. Who closes the remainder, and how does the other system find out?

## Why it matters

Decision 01 makes the POS copy read-only, with CPMS owning the request. A POS-side close breaks that unless it is the only exception; a CPMS-side close needs one more call on the channel chosen in [How approved requests reach the POS](./02-request-transport.md).

## Options

- **A. CPMS closes it.** The project manager closes the remainder in CPMS; CPMS calls the POS (same service account) and the POS marks the request closed and the token dead. The POS stays read-only.
- **B. The store closes it.** A Store Manager closes the remainder in the POS with a reason (audited). CPMS is not told unless the "how CPMS learns the balance" question adds a POS → CPMS channel.
- **C. Either side.** CPMS can close by call; the Store Manager can close in the POS with a reason, for when the project tells the store at the counter.

## Recommendation

**A**: one owner for the request, no new POS screen, and it reuses the push channel already chosen. C if the store regularly hears "we bought elsewhere" at the counter before CPMS is updated.

## Decision

**A. CPMS closes it.** The project manager closes the remainder in CPMS; CPMS calls the POS with the same service account; the POS marks the request closed and the token dead. Released lines and their utang are untouched. The POS copy stays read-only, and no POS screen is added. A close for a request that is already fully released or closed is a no-op (retry-safe).
