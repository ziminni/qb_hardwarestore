# Releasing when stock is short

**Mode:** grill · **Status:** ✅ Locked 2026-11-03 (by: me — user chose A and added closing the remainder)
**Depends on:** [What CPMS sends for each requested item](./04-request-item-matching.md) (product owner: an unavailable item must be handled at release).

## Today (verified in source 2026-11-03)

- `release_materials` (`apps/requisitions/services.py:133`) releases every line's remaining quantity inside one transaction; `allocate_fifo` raises `INSUFFICIENT_STOCK` on any short line, so the **whole release fails**.
- Scaffolding for partial releases already exists but is unused: `RequisitionItem.released_qty`, status `PARTIAL` ("Partially Released"), and the loop skips lines with nothing remaining.
- The token is marked used after the release, so it works once.

## Question

At the till, one or more requested items are out of stock, short, or archived. What happens to the request, the token, and the utang?

## Options

- **A. Release what is there; the rest stays open on the same token.** Lines in stock release now (one sale + one utang entry for what left the store); short lines keep their remaining quantity; the request becomes Partially released and the token stays valid until everything is released. The cashier sees which lines are short before confirming.
- **B. Release what is there and close the rest.** Same first step, but the short quantity is dropped and the request closes; CPMS must raise a new request for the rest (and needs to be told what was not released).
- **C. All or nothing (today).** Refuse the whole release and name the short items; the cashier waits for stock.

## Recommendation

**A**: uses the fields that already exist, nobody re-requests, and each visit's utang matches exactly what left the store. Telling CPMS what is still outstanding joins the fog item "How CPMS learns the balance".

## Decision

**A. Release what is there; the rest stays open on the same token.**

- Lines in stock release now: one sale and one utang entry (tagged with the project) for exactly what left the store.
- Short, out-of-stock or archived lines keep their outstanding quantity; the request shows **Partially released**; the token stays valid until every line is released or the remainder is closed.
- Before confirming, the cashier sees each line as full, short (with what is available), or unavailable.

**Product-owner addition at lock:** the open remainder **can be closed** (for example, the project buys elsewhere because it cannot wait). Closing ends the request and the token; what was already released **stays payable** in utang. Who may close it is its own decision: [Closing a partly released request](./06-closing-partial-requests.md).
