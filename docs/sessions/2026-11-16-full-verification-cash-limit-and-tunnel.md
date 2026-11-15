# 2026-11-16: full verification, cash-out limit, demo units, CPMS tunnel

Branch `feat/pos-phase1c-and-shift-cash` (not pushed).

## Defects found by re-verifying, fixed

| Commit | Defect | Fix |
|---|---|---|
| `25f7362` | Full suite: 6 errors in requisitions migration tests | `collectibles 0004` depended on `requisitions 0003`; it only needs `0002` (Project) |
| `25f7362` | `docker compose up` ran `seed_demo` on every start, so it could write demo users into a real store database | `seed_demo --if-empty` skips any database that already has users |
| `25f7362` | A cashier could approve/decline CPMS payment receipts (found by live E2E) | Manager-only on the server (`IsManagerRole`, like cheques); button hidden on the cashier screen |

## Changes

- `adb3fcc` **Cash-out limit.** A cashier cannot take out more than the expected drawer cash (`CASH_OUT_EXCEEDS_DRAWER`, nothing written). A Store Manager/Admin may record it, for example when the owner takes more than the count shows. The audit row then says "more than the X expected". The shift row is locked during the check.
- `89ede5e` **Demo units follow the trade.** Cement is sold by `BAG`, GI sheet by `SHEET`, THHN wire by `ROLL`, matching CPMS ("bag"). Barcodes are id-based and unchanged, and existing databases are untouched.
- `da5c784`, `f88c818` **Tunnel for a CPMS on another PC.** Compose profile `tunnel` adds an nginx gateway plus cloudflared. The gateway allows only `POST auth/login|refresh` and `/api/v1/integration/cpms/`, each requiring `X-QB-Gateway-Key`, with rate limits. Anything else gets a 404 without reaching Django, and 404/5xx bodies are replaced so DEBUG pages never leave. The key check is in the compose entrypoint (no key or a short key means it won't start). `scripts/start-tunnel.(sh|ps1)` create the key and print what CPMS needs.

## Evidence

- Backend full suite: 1409 tests OK (after all of the above except the tunnel, which has no Python).
- Flutter: 2446 tests OK, plus the sales folder (233) after the receipt-button gate; analyze clean.
- Live E2E on fresh seeds, real HTTP, no manual setup: CPMS request → POS accept → cashier release (receipt + `OR-…`) → CPMS read-back; payment receipt approve/decline; cash-out + Z-reading + `SHIFT_CASH` audit; `CPMS_SCOPE` fence. Report: `../temp/verify-1116/e2e-report.md` (local only).
- Live tunnel through a real `trycloudflare.com` URL: health 200; admin, users and requisitions 404; sign-in with no key or the wrong key 403; with the key 200. CPMS `PosClient` read customers and materials through it. All resources were removed afterwards.

## Not verified

Windows desktop click-through of these screens; a full `docker compose up` from scratch on a second PC.
