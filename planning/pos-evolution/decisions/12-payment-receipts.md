# Paying project utang with an uploaded receipt

**Mode:** grill · **Status:** ✅ Locked 2026-11-06 in shape (by: me); details in Phase 1c frontier

## Decision

- **Online (mostly GCash / bank transfer):** in CPMS the PM enters amount + reference number and attaches a receipt photo; CPMS sends it to the POS through the service account; it waits as **Payment to verify**.
- A Store Manager **approves** (posted to that project's utang through the existing ledger payment path; partial payments allowed) or **declines** with a reason. CPMS reads the outcome.
- **Offline (cash at the counter):** recorded by the store as today, no upload.

## Open (Phase 1c frontier)

Where the image is stored and its size/type limits; which ledger rows a payment applies to (oldest first?); overpayment; what CPMS sees after a decline.
