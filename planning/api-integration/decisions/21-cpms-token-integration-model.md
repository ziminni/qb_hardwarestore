# CPMS ↔ POS material-token integration model

**Mode:** grill + domain-model · **Status:** 🌫️ FOG (opened 2026-10-30, not started) · **Scope:** its own future epic — OUT OF SCOPE for the 2026-10-30 UI refresh and for audit-remediation.
**Refines:** [Requisition UI Ownership](./09-requisition-ui-ownership.md) (locked Option B: POS builds approve + release). This note may move approval itself to CPMS, so it partly reopens 09 — do not treat 09 as final on *who approves* until this is resolved.

## Target gist (product owner, 2026-10-30, verbatim intent)

- The foreman requests materials **inside CPMS**, within a project. The **project manager approves in CPMS**. The foreman is **not** a POS user and must **not** see POS inventory (security: stated needed material only, no catalogue browse).
- On approval, **CPMS generates a token as a QR** (QR preferred over barcode because the two systems are **not physically connected / share no DB** — so the token is the carrier). The POS scanner handles both QR and barcode.
- At the till, the **cashier scans the token**; the POS recognizes it as a project material request via a **jointly-agreed pattern both systems know** (CPMS mints it, POS validates it).
- The integration lives **mostly on the POS side**: a **project behaves like a customer** — the two systems "know each other" through this identity.
- The **collectibles / debt ledger tracks which project has payables** (project-as-customer receivables).
- The **record of who requested** stays on the **CPMS side**.
- After a scan, the requested materials are either **auto-matched to POS catalogue items, or the cashier matches/searches manually** — UNDECIDED.

## Open questions (fog — each needs its own grill before building)

1. **Who approves?** CPMS PM only, or does the POS Store Manager retain an approve action (decision 09 Option B)? This changes whether the POS Approvals screen built in T0 stays.
2. **Token carrier & pattern.** Current POS `MaterialToken` is a server-side `UUID` (`is_used`, `used_by`); the target wants a QR the two systems independently recognize. What is the shared, verifiable pattern (signed payload? namespaced code? check digit)? How does POS validate a token CPMS minted without a shared DB (pre-shared key, API handshake, offline signature)?
3. **Project-as-customer.** Is a CPMS project mapped onto the existing `Customer` model, a new entity, or a flag? How is the project↔customer identity exchanged between systems?
4. **Project payables.** How do released materials post to the collectibles ledger against the project, and how does CPMS learn the balance / settlement?
5. **Material matching.** Auto-match CPMS line items to POS `VariantUOM`s, cashier manual match, or search-assist? What happens on a no-match or partial stock?
6. **Transport.** REST call CPMS→POS at approval, POS→CPMS at release, or token-only (no live link)? This is the crux: "not physically connected" suggests token-only, but payables sync implies some channel.

## Current POS reality (what already exists, as scaffolding)

`Project`, `Requisition`, `RequisitionItem`, `MaterialToken` models in `apps/requisitions/`; endpoints create/submit/approve/reject/verify/release; `seed_demo` mints an APPROVED requisition + token; POS Approvals (Store Manager, T0) + cashier release page are built and demo-working **locally** (foreman = `requested_by` in seed). This local flow is a stand-in for the above target; the epic's job is to decide how much of it moves to CPMS.

## Constraint

CPMS is a **separate repo** (the sibling `qb_project_management_system/`) and was explicitly **not to be inspected or modified** in POS work so far. This epic is the first that legitimately spans both — it needs the product owner to lift that boundary and needs a joint contract doc.
