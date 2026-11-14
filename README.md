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

For a **fresh disposable demo database only**:

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
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The API URL is the **host root**, without `/api/v1`: client services already add that path. Desktop defaults to `http://127.0.0.1:8000`; the explicit override makes the target clear.

Login using an existing account or fresh-seed credentials above. Single-area accounts retain their own menus. Accounts assigned multiple POS areas land on **Needs you**, with one grouped sidebar and shared destinations shown once. Multiple roles must be assigned to the account; the seed does not automatically make every user multi-role.

Press `q` in the Flutter terminal to stop the app. For normal backend shutdown without deleting data:

```powershell
# Run from repository root.
docker compose stop
```

For a subsequent start with no source update, run `docker compose up -d` at the root, then the Flutter command above. Backend startup still checks/applies pending migrations; follow the backup path whenever installing an update.

## 6. Excel catalogue smoke test

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

Golden masters are gitignored local artifacts; fresh clones do not receive them. See [AGENTS.md](AGENTS.md) and [QA-PROFILE.md](docs/testing/QA-PROFILE.md) for test details. CPMS-dependent payment-receipt approval (Phase 1c) remains on hold; see [POS roadmap](planning/pos-evolution/MAP.md).
