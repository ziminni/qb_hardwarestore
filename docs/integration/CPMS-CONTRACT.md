# CPMS ↔ POS contract — the six integration endpoints (Phase 1)

**Status:** draft for product-owner review (Phase 1, Task 11). **Written from the built endpoints**, not from the plan: every shape, code and status below was read in `backend_django/apps/{integration,requisitions,users}/` and called against the dev server on 2026-11-04. **Audience:** the CPMS team, which does not have the POS source.

Decisions behind it: [01](../../planning/pos-evolution/decisions/01-requisitions-after-foreman.md) (POS keeps a read-only copy), [02](../../planning/pos-evolution/decisions/02-request-transport.md) (CPMS pushes), [04](../../planning/pos-evolution/decisions/04-request-item-matching.md) (material list, POS codes), [05](../../planning/pos-evolution/decisions/05-short-stock-release.md) (partial release), [06](../../planning/pos-evolution/decisions/06-closing-partial-requests.md) (CPMS closes), [07](../../planning/pos-evolution/decisions/07-cpms-sees-releases.md) (CPMS reads back).

---

## 1. Purpose and boundary

CPMS owns the material request: it is created and approved there. The POS keeps a **read-only copy** of an approved request, and the cashier releases what the shelf holds when the token is scanned at the till.

| Rule | Detail |
| --- | --- |
| Direction of traffic | **CPMS calls the POS. The POS never calls CPMS** — no outbound HTTP exists in the backend. CPMS learns what was released by asking (endpoint 5), never by being pushed to. |
| One account | A single CPMS service account, a member of the `CPMS Service` group. Nothing else is a CPMS credential. |
| Its whole reach | `/api/v1/integration/cpms/` — the six endpoints below. Every other POS endpoint answers **403** `CPMS_SCOPE`. |
| Exempt paths | `POST /api/v1/auth/login/` and `POST /api/v1/auth/refresh/` — credential endpoints, needed to sign in at all. They read no POS record. |
| POS staff here | Refused: **403** `{"detail": "Only the CPMS service account may call this endpoint."}` |
| Revocation | Deactivate the account (POS admin). See §2.3. |
| Write surface | Only `POST requests/` and `POST requests/{id}/close/`. There is no update, no delete, no cancellation call, and no PC-side edit of a stored copy. Every other verb on these routes is **405**. |

The POS copy never changes once stored, except for `status`, which moves only as §5 describes.

---

## 2. Authentication

### 2.1 Sign in

```
POST /api/v1/auth/login/
Content-Type: application/json

{"username": "cpms_service", "password": "<secret>"}
```

**200**

```json
{
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {"id": 5, "username": "cpms_service", "role_names": ["CPMS Service"], "is_active": true, "...": "..."}
}
```

`identifier` is accepted instead of `username` (either the username or the e-mail address).

Every later call sends the access token:

```
Authorization: Bearer <access>
```

### 2.2 Token lifetime

Read from the POS settings (`SIMPLE_JWT`):

| Token | Lifetime | Rotation |
| --- | --- | --- |
| `access` | **8 hours** | — |
| `refresh` | **7 days** | On: `POST /auth/refresh/` answers a **new** `access` **and** a new `refresh`, and the refresh just used is blacklisted |

Consequences CPMS must implement:

- Refresh before the 8 hours die, and **store the new refresh token every time** — the old one is dead. Reusing it answers `401 {"detail": "Token is blacklisted", "code": "token_not_valid"}`.
- A request without a token answers `401 {"detail": "Authentication credentials were not provided."}`.
- An expired or malformed token answers `401` with SimpleJWT's own `{"detail": ..., "code": "token_not_valid"}`.

### 2.3 Deactivation cuts access

Deactivating the service account (the POS admin's normal offboarding) ends CPMS access at three points:

1. `POST /auth/login/` is refused (`400`, "This account is disabled.") — a deactivated account is also counted as a login failure for the lockout, so a script that keeps trying locks the pair out.
2. An access token already issued stops working: authentication answers `401` for an inactive user before any view runs.
3. `POST /auth/refresh/` answers `401` (`no_active_account`), with rotation blacklisting the token it was given.

There is no separate "revoke token" call; deactivation is the switch.

### 2.4 The fence, live

```
GET /api/v1/requisitions/     (with the CPMS token)   -> 403
{"code": "CPMS_SCOPE",
 "detail": "The CPMS service account may only call /api/v1/integration/cpms/ endpoints; /api/v1/requisitions/ is outside its scope."}
```

The refusal is in the authentication class, so it covers **every** route outside the namespace, including ones added later. CPMS should treat `CPMS_SCOPE` as a bug in its own request, never as a signal to retry.

---

## 3. Conventions

| Topic | Convention |
| --- | --- |
| Base URL (dev) | `http://127.0.0.1:8000` (the dev container publishes port 8000) |
| JSON only | Bodies and answers are `application/json`. |
| Lists are paginated | Both list endpoints answer DRF's page envelope: `{"count", "next", "previous", "results": [...]}`, **50 rows per page**, `?page=N`. Read `results`; follow `next` while it is not null. |
| Quantities | Always **2-decimal strings** in answers (`"8.00"`). Send at most 2 decimals, between `0.01` and `9999999999.99`. |
| Money | 2-decimal strings (`"57032.00"`). |
| Refusals | A business refusal is `{"code": "<STABLE_CODE>", "detail": "<sentence for a human>"}`. Branch on `code`, never on `detail`. |
| Validation refusals | Field-shaped, DRF style: `{"items": {"0": {"quantity": ["Ensure this value is greater than or equal to 0.01."]}}}` — for a payload that does not even have the right shape. |
| Ids | `cpms_request_id` and `cpms_project_id` are **CPMS's own strings** (≤100 chars) and travel in the path. The integer `id` in a request answer is the POS row id and is informational only. |
| Time | Server time, no client timestamps are accepted. |

---

## 4. The six endpoints

Below, `POS` is the base URL and `TOKEN` the access token.

```
POS=http://127.0.0.1:8000/api/v1/integration/cpms
TOKEN=<access token from §2.1>
```

### 4.1 `GET customers/` — who a request may bill

The payers a push may name. Active **contractor** and **construction-firm** customers only: walk-in and regular customers are not project payers. Each row is an `id` and a `name`, and nothing else — no balance, no credit limit, no contact detail.

**Request:** no body, no query parameters.

**200**

```json
{"count": 1, "next": null, "previous": null,
 "results": [{"id": 3, "name": "Dela Cruz Construction"}]}
```

**Errors:** `401` (no/invalid token), `403` (a POS account on this endpoint).

**Retry:** a plain `GET`; retry freely.

**Curl (run: 200)**

```bash
curl -s "$POS/customers/" -H "Authorization: Bearer $TOKEN"
```

> An empty `results` means the store has no active contractor yet. CPMS should not push a request then: every `payer` it could send would answer `400 UNKNOWN_PAYER`.

### 4.2 `GET materials/` — what may be ordered

Every selling unit CPMS can order: an **active variant of an active product**. A row is the code to send, the label to show, and the unit of measure.

**200**

```json
{"count": 8, "next": null, "previous": null,
 "results": [
   {"code": "QB000008-6", "product": "Circuit Breaker 20A 1-pole", "unit": "PC"},
   {"code": "QB000001-7", "product": "Portland Cement 40kg", "unit": "PC"}
 ]}
```

| Field | Meaning |
| --- | --- |
| `code` | The **selling unit's** scan code (`VariantUOM.barcode_qr`) — the same string the till scans. This is what `items[].code` must carry. |
| `product` | Human label: product name plus variant name. For display only; never send it back. |
| `unit` | UOM code (`PC`, `KG`, …). The unit the quantity is counted in. |

Ordered by product, then variant, then unit. **This list is exactly the import's accept list**: a code taken from here never answers `UNKNOWN_MATERIAL`. A code from an earlier page may disappear later (product archived) — re-read the list before a push if a code has been sitting around.

**Never in this body:** stock on hand, price, cost, or the numeric ids. CPMS orders materials; it does not trade them (decision 04).

**Errors:** `401`, `403`.

**Retry:** a plain `GET`; retry freely.

**Curl (run: 200)**

```bash
curl -s "$POS/materials/" -H "Authorization: Bearer $TOKEN"
```

### 4.3 `POST requests/` — push one approved request

Called **once per approved CPMS request**. The POS stores its copy: the project, the lines, the token, the two names as text, and the notes.

**Request**

```json
{
  "cpms_request_id": "CPMS-R-1001",
  "token": "172231a0-976f-49c8-818b-8f69a36c7f7d",
  "project": {"cpms_project_id": "CPMS-P-1001", "name": "2-Storey House - Mandaue", "payer": 3},
  "requester_name": "Rey Quester",
  "approver_name": "Mana Ger",
  "notes": "Deliver to site gate 2",
  "items": [{"code": "QB000001-7", "quantity": "8"}]
}
```

| Field | Rules |
| --- | --- |
| `cpms_request_id` | Required, ≤100 chars, **CPMS's own key**. The retry key (see below). |
| `token` | Required, a **UUID**. CPMS mints it; the POS has never seen it. It is the credential the cashier scans, and it must be unique across the whole POS — one token releases one request. |
| `project.cpms_project_id` | Required, ≤100 chars. The same id later finds and **updates** the same POS project (name and payer follow CPMS). |
| `project.name` | Required, ≤255 chars. |
| `project.payer` | Required, integer. A POS customer id **read from `GET customers/`** (§4.1). Anything else — unknown, deactivated, walk-in, regular — is `400 UNKNOWN_PAYER`. |
| `requester_name` | Required, ≤255 chars. Plain text; the POS has no foreman account (decision 01). |
| `approver_name` | Required, ≤255 chars. Plain text. |
| `notes` | Optional, may be blank. Defaults to `""`. |
| `items[]` | At least one line. `code` from §4.2 (trimmed and case-insensitive: `qb000001-7` finds the same unit). `quantity` in that line's selling unit, `0.01`–`9999999999.99`, at most 2 decimals. **The same code twice in one request is refused**, not merged. |

**201 — a new request was stored**

```json
{"id": 1, "req_number": "REQ-20261104-0001", "cpms_request_id": "CPMS-R-1001",
 "status": "APPROVED",
 "items": [{"code": "QB000001-7", "quantity": "8.00"}]}
```

**200 — the same `cpms_request_id` pushed again** (the retry path; live answer below is a retry of the seeded `CPMS-R-1001`)

```json
{"id": 1, "req_number": "REQ-20261104-0001", "cpms_request_id": "CPMS-R-1001",
 "status": "APPROVED",
 "items": [{"code": "QB000001-7", "quantity": "8.00"}]}
```

**Errors**

| Status | Code | When |
| --- | --- | --- |
| 400 | `UNKNOWN_PAYER` | `project.payer` names no active contractor / construction firm |
| 400 | `UNKNOWN_MATERIAL` | one or more codes are not in §4.2; **every** offending code is named in `detail`, so one retry can fix them all |
| 400 | `DUPLICATE_MATERIAL` | the same code on two lines |
| 400 | *(field shape)* | missing field, empty `items`, `token` not a UUID, 3-decimal quantity, quantity below `0.01` |
| 409 | `TOKEN_TAKEN` | that token already belongs to another request. Mint a new one; do **not** reuse the id. |
| 401 | — | no or invalid token |
| 403 | — | a POS account on this endpoint |
| 405 | — | any verb other than `POST` on `requests/` |

**Retry semantics — read this before writing the retry loop**

1. **Keyed by `cpms_request_id` only.** A second push with an id the POS already holds answers **200** with the **first** copy, byte for byte — even if the payload differs, even if it arrives days later.
2. **Nothing is updated on a retry.** A request the till may already have released against can never be rewritten, so a corrected request needs a **new** `cpms_request_id` and a **new** token. Fix in CPMS, push again under a new id.
3. **A retry needs no state.** Send the stored payload, any 2xx means "the POS has it", stop retrying. Treat `200` and `201` the same.
4. **A timeout is not a failure.** If the connection drops, retry the same id. The POS either stored it (you get `200`) or did not (`201`).
5. **`TOKEN_TAKEN` means the token, not the request.** The POS looks the request id up again before refusing, so a retry of *your own* request stays `200`. A `409` therefore means a genuinely foreign token — new token, same `cpms_request_id`.
6. **Refusals write nothing.** Each of them runs before the first write, in one transaction: no project row, no request, no line, no token.

**Curl (retry of a stored request — run: 200; the same call with a new id and a valid payload answers 201)**

```bash
curl -s -X POST "$POS/requests/" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{
    "cpms_request_id": "CPMS-R-1001",
    "token": "172231a0-976f-49c8-818b-8f69a36c7f7d",
    "project": {"cpms_project_id": "CPMS-P-1001", "name": "2-Storey House - Mandaue", "payer": 3},
    "requester_name": "Rey Quester",
    "approver_name": "Mana Ger",
    "notes": "",
    "items": [{"code": "QB000001-7", "quantity": "8"}]
  }'
```

**Curl — the refusals (all run on the dev DB; a refusal writes nothing, so they are safe to repeat)**

```bash
# unknown payer
curl -s -X POST "$POS/requests/" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"cpms_request_id":"PROBE","token":"<uuid>","project":{"cpms_project_id":"CPMS-P-1001","name":"x","payer":999999},"requester_name":"R","approver_name":"A","items":[{"code":"QB000001-7","quantity":"1"}]}'
# -> 400 {"code": "UNKNOWN_PAYER", "detail": "Payer 999999 is not an active contractor or construction firm."}

# unknown material code
# -> 400 {"code": "UNKNOWN_MATERIAL", "detail": "Unknown material code(s): NOPE-0000. Pick a code from GET materials/."}

# the same code on two lines
# -> 400 {"code": "DUPLICATE_MATERIAL", "detail": "The same material appears more than once: QB000001-7. Send one line per material."}

# a token that already belongs to another request
# -> 409 {"code": "TOKEN_TAKEN", "detail": "This token already belongs to another requisition. Mint a new token for this request."}

# empty items / a 3-decimal quantity
# -> 400 {"items": {"non_field_errors": ["This list may not be empty."]}}
# -> 400 {"items": {"0": {"quantity": ["Ensure that there are no more than 2 decimal places."]}}}
```

> **The token is a bearer credential.** Whoever holds the UUID can take goods out on the project's credit. It is printed on the CPMS side and never read back by CPMS from the POS: no integration endpoint returns it, and no POS audit row ever records it.

### 4.4 `GET requests/{cpms_request_id}/` — status and quantities

Decision 07: the project manager reads this before deciding to close, and again afterwards.

**Request:** no body. `cpms_request_id` in the path.

**200**

```json
{"cpms_request_id": "CPMS-R-1003",
 "req_number": "REQ-20261104-0003",
 "status": "PARTIAL",
 "items": [{"code": "QB000003-1", "requested": "106.00", "released": "101.00", "outstanding": "5.00"}]}
```

| Field | Meaning |
| --- | --- |
| `status` | `APPROVED`, `PARTIAL`, `RELEASED`, `CLOSED`, or `CANCELLED` (§5) |
| `req_number` | The POS document number, for support conversations |
| `items[].code` | The code CPMS sent, normalised (`QB…`) |
| `items[].requested` | What CPMS asked for, in the selling unit |
| `items[].released` | What has left the store so far |
| `items[].outstanding` | `requested - released`, **even for a CLOSED request** — see §6 |

Lines are in the order they were pushed. **No prices, no stock, no money** — what the project *owes* is §4.6.

**Errors:** `404 REQUEST_NOT_FOUND` (this POS never stored that id — a push that never landed, or a typo), `401`, `403`.

**Retry:** a plain `GET`; retry freely.

**Curl (run: 200, 200, 200 for the three seeded requests; 404 for an unknown id)**

```bash
curl -s "$POS/requests/CPMS-R-1003/" -H "Authorization: Bearer $TOKEN"
curl -s "$POS/requests/CPMS-R-9999/" -H "Authorization: Bearer $TOKEN"
# -> 404 {"code": "REQUEST_NOT_FOUND", "detail": "No request is stored for CPMS request id CPMS-R-9999."}
```

### 4.5 `POST requests/{cpms_request_id}/close/` — close the open remainder

The one call CPMS makes on the POS's state (decision 06). The project manager closes the remainder in CPMS; the POS marks the request `CLOSED` and **spends the token**, so the till can no longer release against it.

**Request:** no body. `cpms_request_id` in the path.

**200** — the answer is exactly the read-back body of §4.4, so CPMS sees what the close left behind:

```json
{"cpms_request_id": "CPMS-R-1003", "req_number": "REQ-20261104-0003", "status": "CLOSED",
 "items": [{"code": "QB000003-1", "requested": "106.00", "released": "101.00", "outstanding": "5.00"}]}
```

| Stored status | Result |
| --- | --- |
| `APPROVED` | → `CLOSED`, token spent |
| `PARTIAL` | → `CLOSED`, token spent; the released lines and their utang are untouched |
| `RELEASED` | **no-op**, `200` with `RELEASED` — the request was fully served, nothing to close |
| `CLOSED` | **no-op**, `200` with `CLOSED` |
| `CANCELLED` | `409 REQUEST_CANCELLED` — the request was already given up here; a close must not paper over it |

**Errors**

| Status | Code | When |
| --- | --- | --- |
| 404 | `REQUEST_NOT_FOUND` | no copy stored for that id (same answer as §4.4) |
| 409 | `REQUEST_CANCELLED` | the request is `CANCELLED`; it stays cancelled |
| 401 / 403 | — | as everywhere |

**Retry semantics:** **idempotent**. Closing twice answers `200` with the same body, changes nothing and writes no second audit row. So a timed-out close is retried with the same path, no state needed. A close **never** moves stock, never writes a sale, never touches a ledger row.

**Curl (run: 404 for an unknown id — the no-op and the success path are covered by the integration tests, `apps/integration/tests_close.py`)**

```bash
curl -s -X POST "$POS/requests/CPMS-R-9999/close/" -H "Authorization: Bearer $TOKEN"
# -> 404 {"code": "REQUEST_NOT_FOUND", "detail": "No request is stored for CPMS request id CPMS-R-9999."}
```

> Closing from `APPROVED` is legal even though nothing was released: the project bought elsewhere before coming to the store. Nothing is owed for it, and the request can never release anything.

### 4.6 `GET projects/{cpms_project_id}/payables/` — what the project owes

Decision 07. The project's utang, read from the POS ledger rows that releases carry.

**200**

```json
{"cpms_project_id": "CPMS-P-1001", "total": "57032.00", "paid": "0.00", "balance": "57032.00"}
```

| Field | Meaning |
| --- | --- |
| `total` | Everything ever owed on this project's releases (sum of `original_amount`) |
| `paid` | `total - balance`: money already settled, by any route (payments, return credits) |
| `balance` | Still owed right now (sum of `balance_due`) |

A project with no releases yet answers `{"total": "0.00", "paid": "0.00", "balance": "0.00"}` — it exists, nothing is owed. Money is per **project**, which the contractor still pays; the contractor's credit limit and its other projects' utang are not visible here.

**Errors:** `404 PROJECT_NOT_FOUND` (this POS never stored that project — it is created by the first push naming it), `401`, `403`.

**Retry:** a plain `GET`; retry freely.

**Curl (run: 200; 404 for an unknown project)**

```bash
curl -s "$POS/projects/CPMS-P-1001/payables/" -H "Authorization: Bearer $TOKEN"
curl -s "$POS/projects/CPMS-P-9999/payables/" -H "Authorization: Bearer $TOKEN"
# -> 404 {"code": "PROJECT_NOT_FOUND", "detail": "No project is stored for CPMS project id CPMS-P-9999."}
```

---

## 5. Request lifecycle

```
                 (CPMS pushes)                  (cashier releases what is on the shelf)
   ─────────────────────────▶  APPROVED  ──────────────▶  PARTIAL  ──────────────▶  RELEASED
                                  │                          │
                    (CPMS closes) │            (CPMS closes)  │
                                  ▼                          ▼
                               CLOSED ◀───────────────────────┘
```

| Status | Set by | Meaning to CPMS |
| --- | --- | --- |
| `APPROVED` | the push | Stored, nothing released yet. The token is live. |
| `PARTIAL` | a cashier release | Some lines left the store, some quantity is still outstanding. **The same token is live** for a second visit. |
| `RELEASED` | a cashier release | Every line is fully out. The token is spent. Terminal. |
| `CLOSED` | `POST …/close/` | CPMS ended it. The token is spent; whatever was released is owed. Terminal. |
| `CANCELLED` | **never CPMS** | Legacy POS rows migrated when the foreman was removed (decision 08). A push builds only `APPROVED`. A close on it is `409`. Terminal. |

Releases happen only at the till, in `APPROVED` or `PARTIAL`. Every release is a separate visit: one sale, one utang entry tagged with the project, for exactly what left the store. Two scans of one token are two releases; the request becomes `PARTIAL` and then `RELEASED` when the last line is out.

---

## 6. What "outstanding" means after `CLOSED`

`outstanding` is the **true unreleased quantity**, and closing does not zero it.

- A request closed with `requested 106.00 / released 101.00` keeps reading `outstanding "5.00"` forever. That number is the shortfall the project manager accepted when closing — the material the project did not get from the store.
- Nothing can be released after the close: the token is spent, so `outstanding` can never drop again.
- CPMS must therefore read `status` **and** `outstanding` together: `CLOSED` with `outstanding > 0` is "partly served, remainder given up", not an error.
- `RELEASED` always has `outstanding 0.00` on every line. `APPROVED` has `released 0.00` on every line.

---

## 7. Units

- **A quantity is always in the selling unit of its `code`** — the same unit `GET materials/` reports in `unit`. `"quantity": "3"` against a code whose unit is `PC` means three pieces; against one sold per `KG`, three kilograms.
- The POS deducts stock by that unit's **conversion factor** (a unit of 12 pieces takes 12 pieces off the shelf per 1 released), exactly as a till sale does.
- Only the POS knows the conversion factor, the stock and the price. CPMS never sends a unit and never needs to: the code carries it.
- A whole-count unit (`PC`, `BAG`, `BOX`, `SHEET`, `ROLL`, `PACK`) releases in whole numbers only; a measured unit releases to 2 decimals. Rounding is always **down**, never above what is on the shelf.
- What actually leaves the store at one visit is bounded by the shelf: the request goes `PARTIAL` when it is less than the outstanding quantity. CPMS learns the result from §4.4, not from a response to a release (CPMS does not release).

---

## 8. What CPMS never sees

| Never exposed | Where it is refused |
| --- | --- |
| Stock on hand, batch/expiry data, stock alerts | nowhere — no integration endpoint carries a stock figure |
| Selling prices, unit cost, margins, sale totals per item | ditto; the material list is deliberately id-less and price-less |
| The money of a specific line | §4.4 carries quantities only |
| The contractor's credit limit, its other projects, other customers' utang | §4.6 is per project |
| Sales, receipts, shifts, staff accounts, audit rows | outside the namespace → `403 CPMS_SCOPE` |
| The token of any stored request | no integration endpoint returns it (CPMS minted it, so it already has it) |

---

## 9. Error codes — the full list

| Status | `code` | Meaning | Retry? |
| --- | --- | --- | --- |
| 400 | `UNKNOWN_PAYER` | `project.payer` is not an active contractor / construction firm | No — fix the payload (§4.1) |
| 400 | `UNKNOWN_MATERIAL` | at least one code is not in §4.2; all offenders named | No — re-read §4.2 |
| 400 | `DUPLICATE_MATERIAL` | one code on two lines | No — send one line per material |
| 400 | *(field shape)* | body/field validation, detail names the field | No |
| 401 | `token_not_valid` / none | no, expired or revoked token | Refresh, then retry once |
| 403 | `CPMS_SCOPE` | the path is outside `/api/v1/integration/cpms/` | No — it is CPMS's bug |
| 403 | *(detail only)* | a POS account called an integration endpoint | No |
| 404 | `REQUEST_NOT_FOUND` | no copy stored for that `cpms_request_id` | Only after re-pushing (§4.3) |
| 404 | `PROJECT_NOT_FOUND` | no project stored for that `cpms_project_id` | Only after a push naming it |
| 409 | `TOKEN_TAKEN` | the token belongs to another request | No — mint a new token |
| 409 | `REQUEST_CANCELLED` | the stored request is `CANCELLED` | No |
| 405 | *(detail only)* | wrong verb on a route | No |

A `5xx` is a POS failure. Retry with backoff, always with the same `cpms_request_id` (push) or the same path (close): both are safe to repeat.

---

## 10. The call sequence CPMS will make

```bash
POS=http://127.0.0.1:8000/api/v1/integration/cpms

# 1. sign in (200)
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/api/v1/auth/login/ \
  -H 'Content-Type: application/json' \
  -d '{"username": "cpms_service", "password": "<secret>"}' | jq -r .access)

# 2. who may be billed (200)                 results[].id  -> project.payer
curl -s "$POS/customers/" -H "Authorization: Bearer $TOKEN"

# 3. what may be ordered (200)               results[].code -> items[].code
curl -s "$POS/materials/" -H "Authorization: Bearer $TOKEN"

# 4. push the approved request (201 new / 200 retry)
curl -s -X POST "$POS/requests/" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d @request.json

# 5. later: what happened? (200)
curl -s "$POS/requests/CPMS-R-1004/" -H "Authorization: Bearer $TOKEN"

# 6. the project decides not to wait: close the remainder (200, idempotent)
curl -s -X POST "$POS/requests/CPMS-R-1004/close/" -H "Authorization: Bearer $TOKEN"

# 7. what the project owes (200)
curl -s "$POS/projects/CPMS-P-1001/payables/" -H "Authorization: Bearer $TOKEN"
```

Step 4 is the only call that must happen while the till needs it; steps 5 and 7 are reads CPMS may make whenever a project manager opens a screen, and step 6 is a decision made in CPMS. If the POS is unreachable when the manager approves, retry step 4 — the till's own release does not depend on CPMS being up.

---

## 11. What was verified, and where the code lives

| Claim | Source |
| --- | --- |
| Endpoints, verbs, paths | `backend_django/apps/integration/urls.py`, `config/urls.py` |
| Bodies, allowlists, validation | `apps/integration/serializers.py` |
| Status codes, `{code, detail}`, retry rules | `apps/integration/views.py`, `apps/requisitions/services.py`, `apps/requisitions/exceptions.py` |
| The fence, `CPMS_SCOPE`, credential exemptions | `apps/users/authentication.py`, `apps/users/permissions.py` |
| Lifecycle, `outstanding` after close, payables | `apps/requisitions/services.py` (`import_request`, `close_requisition`, `request_read_back`, `project_payables`) |
| Behaviour under test | `apps/integration/tests_import.py`, `tests_close.py`, `tests.py` |
| Live answers (2026-11-04) | The dev container, account `cpms_service`, seeded `CPMS-R-1001..1003` / `CPMS-P-1001`: both lists, all three read-backs, the payables, the retry, every refusal in §4.3, the `CPMS_SCOPE` fence and the unknown-id `404`s of §4.4–§4.6 were **called and their status codes recorded**. The two write paths that create or close state — the `201` of §4.3 and the successful `close` of §4.5 — were answered from the integration test suite (`tests_import.py`, `tests_close.py`), not from the live call: this document was written against a database that may not be written to. |
