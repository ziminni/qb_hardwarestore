# Request states after Accept

**Mode:** domain-model · **Status:** ✅ Locked 2026-11-07 (by: me — all seven recommendations accepted)
**Depends on:** [The store accepts or declines a pushed request](./09-store-accepts-requests.md), [Declining single lines of a request](./10-line-level-decline.md), [When the project starts to owe](./11-when-utang-starts.md).

## Statuses

| Status | Meaning | Set by |
|---|---|---|
| `WAITING` (new) | Pushed by CPMS, store has not answered | POS on import |
| `ACCEPTED` (new; replaces today's `APPROVED`) | Store will serve it; token releases | Store Manager / Admin |
| `DECLINED` (new) | Store can serve none of it; reason required | Store Manager / Admin |
| `PARTIAL` | Some goods left; token still live | cashier release (Phase 1) |
| `RELEASED` | Every Available line fully out; token spent | cashier release (Phase 1) |
| `CLOSED` | CPMS gave up the rest (or withdrew a waiting request); token dead | CPMS (Phase 1) |

```text
import ─► WAITING ─┬─ accept ─► ACCEPTED ─ release ─► PARTIAL ─ release ─► RELEASED
                   ├─ decline ─► DECLINED                 │
                   └─ CPMS close ─► CLOSED   ACCEPTED / PARTIAL ─ CPMS close ─► CLOSED
```

Legacy `DRAFT`, `SUBMITTED`, `REJECTED`, `CANCELLED` stay readable for old rows; nothing new enters them.

## Line rules

- Each line is **Available** or **Not available** (+ reason), set only at Accept.
- Accept needs at least one Available line; none Available = Decline.
- Not available lines never release; CPMS reads them with their reason.
- `RELEASED` = every Available line fully out.

## Edge cases (locked)

1. CPMS may close a `WAITING` request (withdraw) → `CLOSED`.
2. No undo of Accept / Decline; CPMS sends a new request with a new id.
3. A retried push of a `DECLINED` id returns the declined copy (retry-safe); a new attempt needs a new `cpms_request_id`.
4. Expected amount = released total + **current** price × outstanding Available quantity, recomputed on every read (release charges the day's price, so a frozen figure would drift).
5. Existing `APPROVED` rows migrate to `ACCEPTED`.
6. No timeout; the queue sorts oldest first.
7. Store Manager + Admin get one "Requests from projects" screen with a sidebar count marker; cashiers see nothing new; scanning a `WAITING` or `DECLINED` token is refused with a coded answer (`REQUISITION_WAITING`, `REQUISITION_DECLINED`).

## Contract impact (for the Phase 1b plan)

`POST requests/` answers `WAITING`; read-back gains per-line `available` + `decline_reason`, request-level `decline_reason` and `expected_amount`; `close/` also accepts `WAITING`.
