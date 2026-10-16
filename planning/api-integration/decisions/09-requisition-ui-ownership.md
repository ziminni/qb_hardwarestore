# Requisition UI Ownership (POS side vs CPMS side)

**Mode:** grill · **Status:** OPEN · **Opened:** 2026-10-15
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

Building creation UI in POS would therefore duplicate work that belongs to CPMS, and would need a role that POS
will not have. Conversely, skipping approval would break the flow, because POS is where the token gets minted.

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

_Unresolved — Phase 5._
