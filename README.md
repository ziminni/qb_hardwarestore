# BuildPro — POS / Inventory System

Hardware-store point of sale and inventory for Queen Builders. The Flutter desktop client talks to a Django REST API backed by PostgreSQL. Construction project management (CPMS) lives in a separate repository; ordinary store operations do not require CPMS to be online.

This file owns **installation, startup, demo credentials and ports**. See [AGENTS.md](AGENTS.md) for the documentation map, [SYSTEM_ATLAS.md](docs/SYSTEM_ATLAS.md) for architecture, and [ENDPOINTS.md](ENDPOINTS.md) for the API.

> **Local development/demo setup only.** Compose uses Django's development server, `DEBUG=True`, permissive hosts/CORS and known demo credentials. Ports are published on all host interfaces by default. Do not expose this stack to the internet or use it as a production deployment. Keep it on a trusted machine/network with appropriate firewall rules.

## Stack and prerequisites

| Component | Requirement |
|---|---|
| Backend | Python 3.12 + Django 5.2 LTS + Django REST Framework, installed inside Docker |
| Database | PostgreSQL 15, installed inside Docker |
| Containers | Docker Desktop running Linux containers; current Docker Compose v2 |
| Client | Flutter SDK with Dart **3.11 or compatible 3.x newer** (`flutter/pubspec.yaml`) |
| Windows build tools | Visual Studio 2022 with **Desktop development with C++**, including Windows SDK and CMake tools; VS Code alone is not enough |
| Source control | Git |
| Excel test | Microsoft Excel or another `.xlsx` editor; Windows Excel round-trip was user-verified |

Use **Windows PowerShell**, not WSL, to build and run the native Windows app. Docker Desktop may use WSL2 internally. Do not start a second copy of the same Compose stack from WSL; fixed container names and ports would clash.

Check tools:

```powershell
git --version
docker version
docker compose version
flutter --version
flutter doctor -v
```

Resolve Windows desktop toolchain errors reported by `flutter doctor` before launching the client. No host Python or PostgreSQL installation is needed.

## 1. Get the latest source

### First installation

```powershell
git clone https://github.com/ziminni/qb_hardwarestore.git qb_pos_inventory_system
cd qb_pos_inventory_system
git switch master
git pull --ff-only origin master
```

### Existing checkout

Close the running Flutter app, open PowerShell in your Windows repository, then:

```powershell
cd "C:\path\to\qb_pos_inventory_system"
git status
```

If you have uncommitted work, stop and preserve it before switching branches or pulling. Otherwise, stop the backend before changing its bind-mounted source:

```powershell
docker compose stop backend
git switch master
git pull --ff-only origin master
git log -3 --oneline
```

Stop on any command error. Updating source does not itself migrate the database; starting the backend does.

**Product photos (added after the first Windows install):** the backend now needs the Pillow library, so rebuild the backend image once when you pull this change: `docker compose build backend`. Uploaded photos are stored as files in `backend_django\media\product-images`, **not in the database**, so the database backup below does not contain them. Copy that folder too if you want photos in your backup.

## 2. Existing database: back up before starting updated backend

**Do not delete the database volume or reset data to install an update.** The backend startup runs all pending migrations automatically, including changes newer than the previous installation. A previous Windows database may be behind even when the source is current.

Start only PostgreSQL:

```powershell
docker compose up -d db
docker compose ps
```

Wait until `db` is **healthy**. If this is a genuinely new installation with no data to preserve, continue to step 3. Otherwise, back up the existing database:

```powershell
$backupDir = Join-Path $env:USERPROFILE "BuildProBackups"
New-Item -ItemType Directory -Force $backupDir
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupFile = Join-Path $backupDir "pos-$stamp.dump"

docker compose exec -T db pg_dump -U admin -d buildpro_pos -Fc -f /tmp/pre-update.dump
if ($LASTEXITCODE -ne 0) { throw "Database backup failed. Do not start backend." }

docker cp buildpro_db:/tmp/pre-update.dump $backupFile
if ($LASTEXITCODE -ne 0) { throw "Backup copy failed. Do not start backend." }

Get-Item $backupFile
```

This copies a binary PostgreSQL archive without PowerShell output-redirection encoding problems. Backups live **outside the repository**; protect them because they contain store data. Keep the backup before proceeding. These commands match the database/user/container names in the supplied Compose file; adjust if your installation deliberately changed them.

Never use `docker compose down -v` or `python manage.py flush` as an update step: they destroy stored data. If migration fails, retain the backup and capture the error; do not improvise a reset or rollback.

## 3. Build and start the backend

From the repository root:

```powershell
docker compose up -d --build backend
docker compose ps
docker compose logs --tail=80 backend
```

Compose also starts PostgreSQL if needed and waits for its health check. The backend runs `migrate` before serving the API. Expect:

| Container | Purpose | Host port |
|---|---|---|
| `buildpro_backend` | Django API | `8000` |
| `buildpro_db` | PostgreSQL | `5435` (container port `5432`) |

Verify startup:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health/
docker compose exec backend python manage.py check
docker compose exec backend python manage.py showmigrations --plan
```

Expected health: `status: ok`, `service: BuildPro API`. System check should report no issues; applied migrations show `[X]`. If health is unavailable, inspect backend logs rather than repeatedly reseeding.

## 4. Demo data and credentials

On every `docker compose up -d` the backend runs `migrate`, then `seed_demo --if-empty`, which seeds demo data **only when the database has no users yet**. An existing store database is never touched by the seed. To seed a fresh disposable database manually:

```powershell
docker compose exec backend python manage.py seed_demo
```

The seed creates users, catalogue/packaging units, Store/Bodega locations, stocked batches, transfers, sample sales, receivables and CPMS request examples. Existing sections are skipped; it is **not a reset, repair or password-reset command**. Do not expect old demo data to be rewritten into every newest scenario. No flush is required for normal updates.

| Username | Role | Password on a fresh seed |
|---|---|---|
| `admin` | System Administrator | `demo1234` |
| `manager` | Store Manager | `demo1234` |
| `stocker` | Stock Manager | `demo1234` |
| `cashier` | Cashier | `demo1234` |
| `cpms_service` | Machine integration account; no POS dashboard | `demo1234` |

Emails use `<username>@demo.ph`. Existing accounts keep their existing passwords. Historical `admin123` instructions are incorrect for the seed. Django admin is at <http://127.0.0.1:8000/admin/>.

Seed output includes random material-release tokens; keep them private and do not commit logs containing them. Demo passwords must not be used for real store accounts.

## 5. Run the native Windows client

Leave Docker running. Open a second PowerShell terminal:

```powershell
cd "C:\path\to\qb_pos_inventory_system\flutter"
flutter config --enable-windows-desktop
flutter pub get
flutter devices
flutter run -d windows
```

Desktop defaults to `http://127.0.0.1:8000` (pass `--dart-define=API_BASE_URL=http://127.0.0.1:8000` to override explicitly; use the **host root** without `/api/v1`).

Login using an existing account or fresh-seed credentials above. Single-area accounts retain their own menus. Accounts assigned multiple POS areas land on **Needs you**, with one grouped sidebar and shared destinations shown once. Multiple roles must be assigned to the account; the seed does not automatically make every user multi-role.

### Key Cashier, Manager & CPMS Integration Workflows

- **Shift & Mid-Shift Cash Drawer Log (`Cash in / out`):** Open a shift with an opening float. If the owner or cashier removes cash mid-shift (safe drop, petty cash) or adds change coins, click **Cash in / out** on the **Shift** screen to record `CASH_OUT` or `CASH_IN` with a reason. Expected drawer cash (`Opening float + Cash sales - Cash refunds + Cash in - Cash out`) updates automatically on the Shift screen, closing dialog, Z-reading, and audit log (`SHIFT_CASH`). A cashier cannot take out more than the expected cash in the drawer; if that really happens (for example the owner takes more than the count shows), a **Store Manager** records it, and the audit log marks it as more than expected.
- **CPMS Material Requests & Counter Release:** Approved own-store requisitions pushed from CPMS appear in **Requests** (Store Manager approval/rejection) and on the cashier's **Release** search (`R-####` or release code). Releasing items deducts FIFO inventory batches and posts the charge to the contractor's receivable ledger tagged with the CPMS project.
- **CPMS Online Payment Receipts (Phase 1c):** When CPMS submits a bank transfer / GCash / cheque payment receipt against project payables, **Sales → Receivables** displays a **Review CPMS payment receipts** button so the **Store Manager** (not the cashier) can approve (full or partial amount, applied oldest-first across open project ledgers) or decline with a reason.
- **Inventory & Batch Expiry Alerts:** Low stock, out-of-stock, near-expiry (within 30 days) and expired batch alerts are generated automatically onto the **Alerts** feed.

Press `q` in the Flutter terminal to stop the app. For normal backend shutdown without deleting data:

```powershell
# Run from repository root.
docker compose stop
```

For a subsequent start with no source update, run `docker compose up -d` at the root, then the Flutter command above. Backend startup still checks/applies pending migrations; follow the backup path whenever installing an update.

## 6. Running POS and CPMS together (one computer or two laptops)

> This same guide is in both READMEs (`qb_pos_inventory_system` and `qb_project_management_system`).

**How the two systems connect.** Each system runs completely on its own computer: its Docker backend plus its Flutter app. Each app only talks to the backend on the same computer (`127.0.0.1`). The only link between them is **CPMS → POS**: CPMS sends material requests to the store, and reads prices, stock, what a project owes, and the status of payment receipts. POS never calls CPMS.

So in a two-laptop setup, **the POS laptop opens the tunnel** and **the CPMS laptop points at it**. It works either way round: POS on Windows with CPMS on the Mac, or the reverse.

| Setup | When | Tunnel? |
|---|---|---|
| **A. One computer** | You run both systems yourself | No |
| **B. Two laptops** (e.g. Windows + Mac) | Each teammate runs one system, e.g. for the adviser demo | Yes, started on the POS laptop |

### Setup A: both systems on one computer

1. Start POS **first**, in `qb_pos_inventory_system`: `docker compose up -d --build`
2. Then start CPMS, in `qb_project_management_system`: `docker compose up -d --build`
3. Check the link, in `qb_project_management_system`:
   ```sh
   docker compose exec backend python manage.py check_pos
   ```
   The last line should be `READY: own-store orders can be sent.`
4. Run both apps (see "Run the apps" below).

No `.env` file and no tunnel are needed. CPMS finds POS at `http://host.docker.internal:8000` and links itself to the POS contractor (Dela Cruz Construction in the demo data).

### Setup B: two laptops (Windows + Mac)

**Once, before demo day, on each laptop (needs a good internet connection; Docker downloads about 1–2 GB):**

| | Windows | Mac (Apple Silicon or Intel) |
|---|---|---|
| Docker | Docker Desktop (WSL 2 backend) | Docker Desktop for Mac |
| Flutter | Flutter SDK + Visual Studio 2022 with **Desktop development with C++** | Flutter SDK + Xcode (open it once and accept the licence) + `brew install cocoapods` |
| Check tools | `flutter doctor -v` | `flutter doctor -v` |

Then clone **your** system's repository and run `docker compose up -d --build` once in it, so everything is downloaded before the demo.

**Step 1: POS laptop.** Start POS, then the tunnel, from the `qb_pos_inventory_system` folder:

```powershell
docker compose up -d
.\scripts\start-tunnel.ps1     # Windows PowerShell
```
```sh
docker compose up -d
./scripts/start-tunnel.sh      # Mac
```

If PowerShell says scripts are disabled, run `Set-ExecutionPolicy -Scope Process Bypass` first, in the same window. The script prints four lines like:

```env
POS_API_BASE_URL=https://<random-name>.trycloudflare.com
POS_API_ALLOW_INSECURE_LOCAL=False
POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key
POS_API_GATEWAY_HEADER_VALUE=<48-character key>
```

Send these four lines to the CPMS laptop, for example in a private chat. The key works like a password: don't post it anywhere public. Only a small gateway is exposed, never the whole POS. It allows only the CPMS sign-in and the `/api/v1/integration/cpms/` routes, and only with that key.

**Step 2: CPMS laptop.** Create the file `qb_project_management_system/django-backend/.env`, paste the four lines, save it, then run this in `qb_project_management_system`:

```sh
docker compose up -d
```

How to create the file:
- **Mac:** `nano django-backend/.env`, paste, then Ctrl+O, Enter, Ctrl+X.
- **Windows:** Notepad → Save as → "All files (\*.\*)" → name it `.env`.

`docker compose up -d` restarts the CPMS backend and its outbox worker with the new settings.

**Step 3: CPMS laptop, check the link:**

```sh
docker compose exec backend python manage.py check_pos
```

`READY` means the material request flow will work. Otherwise it says exactly what's wrong (see Troubleshooting below).

**Step 4: both laptops.** Run your app (see "Run the apps").

**After the demo:**
- POS laptop: `docker compose --profile tunnel stop gateway cloudflared`
- CPMS laptop: delete the four lines from `django-backend/.env` and run `docker compose up -d`. That returns CPMS to one-computer mode.

**Rehearse on one computer:** do Setup B with both systems on the same machine. The tunnel on the POS side, and the four lines in CPMS's `.env`. The traffic then goes out to Cloudflare and back, exactly as between two laptops.

### Run the apps

Each app connects to the backend on its own computer; no settings are needed. From the repository's `flutter` folder:

| | Windows | Mac |
|---|---|---|
| First time | `flutter config --enable-windows-desktop` then `flutter pub get` | `flutter config --enable-macos-desktop` then `flutter pub get` |
| Run | `flutter run -d windows` | `flutter run -d macos` |

Logins: POS `manager`, `cashier`, `stocker`, `admin` (password `demo1234`). CPMS `ramon@example.ph` (owner/PM), `ana@example.ph` (site engineer), `liza@example.ph` (accountant), `maria@example.ph` (admin), `mark@example.ph` (client) (password `password123`).

### Demo script (about 5 minutes)

1. **CPMS, `ana`:** open project **QB-2026-014** → Material requests → new request: Portland cement 40 kg × 5.
2. **CPMS, `ramon`:** open the request → **Own hardware store**. The picker shows the store's live price and stock. Confirm the order. Within about a minute, the order says **Sent to store**, and its "At the store" panel says *Waiting for the store manager to accept*.
3. **POS, `manager`:** **Project requests** → the new request → **Accept**.
4. **POS, `cashier`:** open a shift if needed → **Release materials** → **Find accepted request** → select it → **Release materials** → print the receipt.
5. **CPMS, `ramon`:** within about a minute (or press **Check store now** on the order), the material request shows *Released — picked up from the store · released 5 of 5*. Project → **Financials** → **Owed to the store** shows the charge.
6. **CPMS, `liza`:** on **Owed to the store** → **Submit payment receipt**. Then **POS, `manager`:** **Receivables** → **CPMS receipts** → **Approve**. The CPMS balance goes down, and POS **Payment history** lists it as *CPMS receipt …*.

### Troubleshooting

| What you see | Fix |
|---|---|
| `check_pos`: *could not be reached* | The POS laptop is off, asleep or offline, or its tunnel stopped. Turn off sleep on the POS laptop for the demo, rerun the tunnel script, and copy the new URL. |
| It worked, then stopped after the POS laptop restarted | The tunnel URL changes on every restart. Rerun the script on the POS laptop, update `POS_API_BASE_URL` in CPMS's `.env`, then `docker compose up -d` on the CPMS laptop. The key stays the same. |
| `check_pos`: 403 / *refused* | The key in CPMS's `.env` doesn't match. Copy all four lines again. |
| `check_pos`: *payer … is not a contractor* | Run `docker compose restart backend` on the CPMS laptop; it relinks to the store's contractor on start. |
| `check_pos`: *material codes the store does not sell* | Fix those codes in CPMS **Master lists → Materials**, or use materials that are mapped. |
| School or office Wi-Fi blocks the tunnel | Put the POS laptop (or both laptops) on a phone hotspot. |
| Mac: `docker: command not found` / cannot connect | Open Docker Desktop first and wait until it says it is running. |
| Mac: the app opens but login doesn't stick | Pull the latest code; the CPMS Mac keychain fix is in the commit that added this guide. |
| CPMS order picker says *Store offline* | Same as "could not be reached": CPMS can't reach POS right now. Orders made while offline are sent automatically once it can. |

## 7. Excel catalogue smoke test

Use disposable demo data. Catalogue import intentionally changes prices/names and is not a stock-adjustment feature.

1. Login as `stocker`; open **Products**. Choose a product (for example, seeded **Faucet**) and note its current price and stock quantity.
2. Select **Export to Excel → Save .xlsx**. Verify the native Save dialog and saved file.
3. Open the workbook in Excel. Change one **Price** cell only; keep IDs, headers and the `.xlsx` format.
4. Save and close Excel. Select **Import from Excel** and choose the workbook using the native Open dialog.
5. Check preview shows only the intended change and no errors. Click **Apply import**.
6. Confirm the new price appears and stock quantity is unchanged.
7. Export again and re-import unchanged. Preview should report no changes; applying unchanged rows must not change stock.

**Verified by the owner on Windows:** Faucet price changed from **225 to 1,000**, import succeeded, export/re-import succeeded again, and stock quantity stayed unchanged. This is a user-reported native Windows/Excel smoke test, not an independently observed full regression run. LibreOffice interoperability, physical printing/scanning and exhaustive Windows workflows are not implied. See [QA handoff](docs/sessions/pos-windows-installation-and-excel-acceptance.md).

## Other client targets

From `flutter/`:

```bash
# Linux: needs clang, cmake, ninja-build, pkg-config and libgtk-3-dev.
flutter config --enable-linux-desktop
flutter pub get
flutter run -d linux --dart-define=API_BASE_URL=http://127.0.0.1:8000

# macOS (Xcode + CocoaPods): see section 6 "Run the apps".
flutter config --enable-macos-desktop
flutter run -d macos

# Browser smoke test; does not replace native Windows picker/save verification.
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android emulator defaults to `http://10.0.2.2:8000`. A physical device needs the server's LAN IP, the same trusted network and suitable firewall rules. Do not forward these development ports to the internet. Windows stores tokens using the secure-storage platform backend; Linux uses local preferences per the existing demo-only token-store policy.

## Troubleshooting

- **Docker unavailable:** start Docker Desktop, select Linux containers, then retry `docker version`.
- **Container name/port already used:** check `docker ps`. A WSL-started stack may share Docker Desktop's engine. Do not delete containers/volumes you have not identified. Default ports are API `8000`, database `5435`; changing the API host port also requires updating `API_BASE_URL`.
- **Older Compose rejects optional `env_file`:** update Docker Desktop/Compose v2. The backend `.env` file is optional; stock settings contain the local defaults. Do not assume adding environment values changes settings that do not read them.
- **Windows toolchain missing:** use Visual Studio Installer to add Desktop development with C++, Windows SDK and CMake tools. Re-run `flutter doctor -v`.
- **Plugin symlink support error:** enable Windows Developer Mode, then retry `flutter pub get`.
- **Stale CMake path after moving checkout:** from `flutter/`, run `flutter clean`, `flutter pub get`, then the Windows run command again.
- **Dart SDK too old:** install a Flutter version whose bundled Dart satisfies `flutter/pubspec.yaml`; do not downgrade project dependencies to bypass the requirement.
- **API 404s with doubled `/api/v1/api/v1/`:** set `API_BASE_URL` to the host root only.
- **Login fails:** existing database passwords may differ from fresh-seed credentials. Do not flush the database to recover a password.
- **Spreadsheet access denied:** close the workbook in Excel and choose a writable folder. Keep `.xlsx` extension; do not save as CSV.

## Developer verification

Run backend suites on a **disposable development/test stack**, never alongside another run using the same test database. Django creates/drops its test database; this is not a production health check.

```bash
docker compose exec backend python manage.py check
docker compose exec backend python manage.py makemigrations --check --dry-run
docker compose exec backend python manage.py test --noinput

cd flutter
flutter analyze
flutter test --concurrency=2
```

Golden masters are gitignored local artifacts; fresh clones do not receive them. See [AGENTS.md](AGENTS.md) and [QA-PROFILE.md](docs/testing/QA-PROFILE.md) for test details. All POS evolution phases (including Phase 1c CPMS online payment receipt verification, mid-shift cash drawer movements, and batch expiry alerts) are implemented and tested; see [POS roadmap](planning/pos-evolution/MAP.md).
