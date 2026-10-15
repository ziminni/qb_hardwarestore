# 03 — UI Gaps: Endpoints With No Screen

**Priority: P1.** The backend implements these; the client has no screen for them at all. For a capstone
graded on use-case coverage, these are the cheapest points available — the hard part is already done.

Source of truth for which endpoints exist: `ENDPOINTS.md`. Rows marked "no UI" in the Truth Matrix
(`docs/SYSTEM_ATLAS.md`) are the gap.

## The gaps

| Capability | Endpoints (all live, none called) | Value |
| :--- | :--- | :--- |
| **Material token release** | `POST /api/v1/tokens/verify/`, `POST /api/v1/tokens/release/` | **Highest** — this is the dual-business story (UC-20/21/22) |
| **Utang / collectibles** | `GET /api/v1/ledgers/`, `/ledgers/aging/`, `POST /api/v1/ledger-payments/` | High — receivable tracking is a headline feature |
| **Goods receiving** | `POST /api/v1/goods-receipts/{id}/process/` | High — without it there is no way to create stock through the UI |
| **Projects** | `GET/POST /api/v1/projects/` | Medium — needed before a requisition can be created |
| **Payments / receipts** | `GET /api/v1/payments/`, `GET /api/v1/receipts/` | Medium — receipt lookup after a sale |
| **Catalog reference data** | `/api/v1/brands/`, `/uoms/`, `/variant-uoms/` | Low — admin convenience |

## Blocker before the requisition flow

The requisition flow starts with a **Site Foreman** creating a requisition — but the `foreman` account
currently cannot reach any screen. Verified across all four layers:

| Layer | What it does |
| :--- | :--- |
| `apps/users/permissions.py:19` | Defines the role `Site Foreman`. |
| `apps/users/serializers.py:39-41` | The role→segment map has **no** `Site Foreman` entry, so the fallback `group.name.lower().replace(' ', '_')` yields `site_foreman`. |
| `flutter/lib/routes/routes.dart:68` | `dashboardForRole()` matches only `admin`, `inventory`, `pos`, `sales`; everything else returns `null`. |
| `flutter/lib/routes/routes.dart:120-121` | `if (dashboard == null) return isLogin ? null : login;` — so a logged-in user with an unmapped role is sent back to `/login`. |

**Net effect:** the foreman authenticates successfully (HTTP 200, JWT issued) and is immediately bounced
back to the login page. The Flutter client contains **zero** references to `foreman`. This is a client
routing gap, not a backend permission problem — `permissions.py` handles `Site Foreman` correctly.

Fix by giving `site_foreman` a case in `dashboardForRole()` (or mapping the role to an existing dashboard),
then build the requisition screens below. Until then, drive the flow as `admin`, which is a superuser and
so maps to the admin dashboard regardless of role.

## Start here: the requisition token flow

This is the most valuable gap because it is the only place the two halves of the business meet, and it is
already seeded so it can be tested the moment a screen exists.

Flow the backend already implements end to end:

1. Foreman creates a requisition, submits it.
2. Store Manager approves → the backend **mints a `MaterialToken`** (a UUID, one-to-one with the
   requisition) and returns it.
3. Cashier scans/enters the token → `POST /api/v1/tokens/verify/` returns the project, the items and the
   remaining quantity to release.
4. Cashier confirms → `POST /api/v1/tokens/release/` FIFO-deducts stock, creates a `SalesTransaction`
   (source `REQUISITION`), generates an official receipt, and posts the balance to the utang ledger.

`seed_demo` already creates an **APPROVED requisition with a printed token**, so step 3 can be exercised
immediately with no data setup. Run `docker compose exec backend python manage.py seed_demo`.

Token request bodies are `{"token": "<uuid>"}` for both endpoints.

### Design note

`MaterialToken` is a **UUIDField minted by the backend** on approval — it is one-to-one with the
requisition and single-use. The UI must **display and scan a token the server already created**; it must
not generate token values client-side. Any client that invents its own token format will never be
redeemable, because only the server's UUID is accepted by `verify_token`.

## Secondary: stock cannot be created from the UI today

`planning/api-integration/MAP.md` wires screens that *read* stock. Nothing lets a user *add* stock. The missing link
is Purchase Order → Goods Receipt → `POST /api/v1/goods-receipts/{id}/process/`, which creates the FIFO
`InventoryBatch` rows everything else depends on.

Consequence for the demo: with a fresh database and no seed, the store has no stock, so POS checkout and
token release both fail — not because they are broken, but because there is nothing to deduct. Either
always run `seed_demo` before demoing, or build the receiving screen.

## Acceptance

- A cashier can complete verify → release from the UI and see the resulting sale and ledger entry.
- A user can receive stock through the UI, making goods-receipt `process` reachable without curl.
- These screens handle the loading/error/empty states their peers are missing (see
  `planning/api-integration/MAP.md`).
