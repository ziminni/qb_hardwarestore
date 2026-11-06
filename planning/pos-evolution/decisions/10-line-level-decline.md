# Declining single lines of a request

**Mode:** grill · **Status:** ✅ Locked 2026-11-06 (by: me — agent recommendation accepted)
**Depends on:** [The store accepts or declines a pushed request](./09-store-accepts-requests.md).

## Decision

- Accepting a request may mark individual lines **Not available** with a reason (e.g. "we do not carry 16 mm rebar"); those lines never release and read as declined to CPMS, so the PM buys them elsewhere.
- **Decline** of the whole request is for when nothing can be served.
- Accepted lines that run short later still follow [Releasing when stock is short](./05-short-stock-release.md) at the counter, unchanged.
