# BuildPro — POS / Inventory & Construction System

Dual-business system for **Queen Builders**: a hardware-store **point of sale and inventory** backend
plus the **construction requisition / material-release** flow that draws stock out of that store.

The Django REST API owns all business logic. A Flutter client (MVVM) talks to it over HTTP.

> **Documentation map.** This file is the **setup** home. Do not look for architecture or the endpoint
> list here — see [AGENTS.md](AGENTS.md) for the routing table, then follow the pointer you need.

## Stack

| Layer | Technology |
| --- | --- |
| Backend | Django 5.2 LTS, Django REST Framework 3.15, SimpleJWT |
| Database | PostgreSQL 15 (Docker) |
| Frontend | Flutter / Dart, `go_router`, Dio, MVVM |
| Runtime | Docker Compose |

## Prerequisites

- Docker Engine + Docker Compose v2
- Flutter SDK with Linux desktop support enabled (`flutter doctor`)
- On Linux desktop: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

## 1. Start the backend

> **Phase 1b closed 2026-11-08 with owner-accepted QA limits; contract v0.2 provisional.** Dev (`buildpro_db`, API :8000) is on Phase 1b: migration 0003 applied on a backend restart, then owner-approved `flush` + `seed_demo` on 2026-11-09, so dev now holds the [seed scenarios below](#2-load-demo-data). Final evidence and accepted gaps: [plan Handoff](planning/pos-evolution/phase-1b-plan.md#handoff--known-limits). The entrypoint runs `migrate` on every start; dev is the demo DB, so writes, reseeds and resets there need owner approval. Backend + client + breaking contract must roll out together; see [rollout/rollback safety](docs/integration/CPMS-CONTRACT.md#rollout-and-rollback-boundary).

```bash
cd qb_pos_inventory_system
docker compose up -d --build
docker compose ps
```

Expect two healthy services:

```text
buildpro_backend   Up   0.0.0.0:8000->8000/tcp
buildpro_db        Up   0.0.0.0:5435->5432/tcp   (healthy)
```

Confirm the API is serving:

```bash
curl -s http://127.0.0.1:8000/api/health/
# {"status":"ok","service":"BuildPro API"}
```

Migrations are applied automatically by the container entrypoint. To run them by hand:

```bash
docker compose exec backend python manage.py migrate
```

## 2. Load demo data

```bash
docker compose exec backend python manage.py seed_demo
```

Run on a migrated database. The seed skips existing data sections: re-running is not a migration, reset or repair of existing scenarios. **No automatic flush;** a clean reseed needs `python manage.py flush --noinput` first, which wipes everything (dev requires owner approval). It creates the five accounts below, stocked products, customers, completed sales and unpaid *utang*.

Post-migration fresh-seed requests (validated by Task 5 on the Django test database; dev reseeded to these states 2026-11-09):

| CPMS request id | Expected state | Probe |
| --- | --- | --- |
| `CPMS-R-1001` | `ACCEPTED` | Fully releasable; every eligible line shows FULL |
| `CPMS-R-1002` | `RELEASED` | Completed release history, token spent |
| `CPMS-R-1003` | `PARTIAL` | Short-shelf visit; same token resumes after restock |
| `CPMS-R-1004` | `WAITING` | Store review required; scanning refused |
| `CPMS-R-1005` | `DECLINED` | Reason visible; scanning refused with store-decline code |

Phase 1d packaging demo (test-DB verified; the dev database is still on Phase 1b until an approved migrate + reseed): **Tile Adhesive / Standard** sold loose by `KG` at ₱12.00 or as a whole `BAG` of 25 kg at ₱275.00, with 250 kg received through a real purchase order and Receiving (no opening-stock shortcut). The seed also ensures the 12 standard units (`PC`, `BAG`, `BOX`, `PACK`, `ROLL`, `SHEET` whole; `KG`, `G`, `M`, `CM`, `L`, `ML` measured), including after a `flush`. Fresh-seed totals: 7 products, 9 variants, 10 selling units, 7 transactions, 3 open utang ledgers, 5 requests.

Scanner token UUIDs are random per seed: use the ones **printed in that seed's stdout**; never paste them (or contract example tokens) into docs. QA writes on dev need owner approval each time. QA flow checklist: [QA-PROFILE](docs/testing/QA-PROFILE.md).

## 3. Run the Flutter client

Open a second terminal and leave the backend running:

```bash
cd qb_pos_inventory_system/flutter
flutter pub get
flutter run -d linux
```

Run controls: `r` = hot reload · `R` = hot restart · `q` = quit.

On desktop the client resolves the API to `http://127.0.0.1:8000` automatically — no configuration needed
(see [Connecting the client](#connecting-the-client)).

## Demo accounts

Password is the same for all five. `seed_demo` defines these accounts; this is the canonical credential home. All five logins returned 200 on dev on 2026-11-09.

| Username | Name | Role | Can do |
| --- | --- | --- | --- |
| `admin` | Ada Ministrator | System Administrator | Everything, plus Django admin (`/admin/`) |
| `manager` | Mana Ger | Store Manager | Accept/decline project requests, reports, ledger, users |
| `stocker` | Stock Er | Stock Manager | Inventory writes: products, POs, receipts, adjustments |
| `cashier` | Cashi Er | Cashier | POS transactions, customers, token release, utang payments |
| `cpms_service` | CPMS Service | CPMS Service (machine account, not a POS role) | Only the six integration endpoints; no POS dashboard |

**Password for all: `demo1234`.** Emails follow `<username>@demo.ph`.

> ⚠️ Some historical docs in this repo claim `admin` / `admin123`. That is **wrong** and returns HTTP 400.
> Use `demo1234`.
>
> `foreman` is no longer seeded. CPMS requester/approver names are text, not POS logins. POS roles are unchanged; Store Manager and Admin review via sidebar **Project requests** (page title "Requests from projects"; `/sales/project-requests`, `/admin/project-requests`). CPMS approval does not replace POS acceptance. New imports wait for review; acceptance reserves no stock and books no debt. Cashier/stocker cannot open the review queue.

Django admin: <http://127.0.0.1:8000/admin/> with `admin` / `demo1234`.

### Verify a login

```bash
curl -X POST http://127.0.0.1:8000/api/v1/auth/login/ \
  -H 'Content-Type: application/json' \
  -d '{"username":"cashier","password":"demo1234"}'
# -> {"access": "...", "refresh": "...", "user": {...}}
```

## Ports

| Service | Host | Container | Notes |
| --- | --- | --- | --- |
| Django API | `8000` | `8000` | Matches every frontend default and the API docs |
| PostgreSQL | `5435` | `5432` | Host port is non-default to avoid clashing with a host-installed Postgres |

The database host port is published on **5435** on purpose: a host running its own PostgreSQL commonly
occupies `5432`/`5433`. Only the left-hand host port can conflict, so this mapping is portable. Nothing
inside the compose network is affected — containers still reach the database at `db:5432`.

## Connecting the client

Base URL is resolved in `flutter/lib/core/config/api_config.dart`:

| Target | Base URL |
| --- | --- |
| Flutter Web / Linux desktop / iOS Simulator | `http://127.0.0.1:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| Physical device (Wi-Fi) | `http://<PC_LAN_IP>:8000` |

Override without editing code (physical device, or a non-default port):

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
```

The PC and phone must share a network, and the host firewall must allow inbound TCP `8000`.

Android builds already carry `android.permission.INTERNET` and `android:usesCleartextTraffic="true"`
(dev only — plain `http://` will not pass a release review).

Network layer: `flutter/lib/core/network/api_client.dart` — a Dio singleton that attaches
`Authorization: Bearer <access_token>`, retries once via `POST /api/v1/auth/refresh/` on a 401, and
logs the user out if the refresh fails. Tokens are held in `flutter_secure_storage`.

## Verifying the stack

```bash
# API up
curl -s http://127.0.0.1:8000/api/health/

# Login works
curl -s -X POST http://127.0.0.1:8000/api/v1/auth/login/ \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"demo1234"}' | head -c 120

# Protected read with the access token from the previous call
curl -s http://127.0.0.1:8000/api/v1/products/ -H 'Authorization: Bearer <access_token>'
```

Backend checks inside the container:

```bash
docker compose exec backend python manage.py check
docker compose exec backend python manage.py test
```

## Troubleshooting

**Port already in use.** Only the host port can collide. Re-map it in `docker-compose.yml` and point the
client at the new port with `--dart-define=API_BASE_URL=...`.

**Windows: stale `CMakeCache` path error after moving the project folder.** Run `flutter clean`, then
`flutter run -d windows`.

**`flutter` cannot find a device.** Enable the desktop target once:
`flutter config --enable-linux-desktop`, then `flutter devices`.

**Repeated "unlock keyring" prompt on Linux — FIXED in code (2026-10-20).** On Linux (not web) the client
now stores its JWTs in `shared_preferences` instead of `flutter_secure_storage`, so there is no
`libsecret`/gnome-keyring prompt. macOS (Keychain), Windows (DPAPI), mobile and web are unchanged. The
selection lives in `flutter/lib/core/network/token_store.dart` (`tokenStoreForPlatform`), keyed on
`defaultTargetPlatform`. Trade-off: on Linux the tokens sit in a plaintext prefs file — acceptable for a
demo machine, not for production (production hardening is out of scope). See
`planning/cashier-workflow/decisions/01-linux-token-storage.md`. If you prefer the keyring anyway, give it
an **empty password** (`seahorse`, or delete `~/.local/share/keyrings/Default_keyring.keyring` and
re-create it with both password fields blank).

## Repository layout

```text
qb_pos_inventory_system/
├── backend_django/          Django project
│   ├── config/              settings, root urls, wsgi
│   └── apps/                users · inventory · pos · collectibles · requisitions · reports
├── flutter/                 Flutter client
│   └── lib/
│       ├── core/            config, network (api_client), layout
│       ├── data/            models, services, repositories
│       ├── features/        10 feature modules (views / viewmodels / widgets)
│       └── routes/          go_router route table
├── docs/                    SYSTEM_ATLAS.md + system-atlas.html
├── planning/                unbuilt work and decisions (read MAP.md first)
├── AGENTS.md                routing table — where every fact lives
├── ENDPOINTS.md             API contract: every endpoint, auth and role matrix
└── CONTRIBUTING.md          branch, commit and review conventions
```
