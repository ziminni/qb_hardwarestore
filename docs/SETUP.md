# BuildPro POS — Setup & Operations Guide (Windows & macOS)

This guide covers **first-time installation, safe updates, daily startup, Cloudflare Named Tunnel (permanent URL), CPMS linking, and troubleshooting**.

- Building or connecting the **Bodega Android phone app**? See [docs/MOBILE-BODEGA.md](MOBILE-BODEGA.md).
- Deploying to a **real live hardware store**? See [docs/production-setup.md](production-setup.md).
- Testing **POS + CPMS + Bodega Android** together? See [docs/three-client-smoke-test.md](three-client-smoke-test.md).

---

## 1. Prerequisites

| Component | Windows | macOS |
|---|---|---|
| Docker | Docker Desktop (Linux containers / WSL 2 backend) | Docker Desktop for Mac |
| Flutter | Flutter SDK (Dart `>=3.11`) + Visual Studio 2022 (**Desktop development with C++**, Windows SDK, CMake) | Flutter SDK (Dart `>=3.11`) + Xcode (opened once) + `brew install cocoapods` |
| Git | Git for Windows | Xcode CLT / Homebrew Git |

> Use **Windows PowerShell** (not WSL) to build and run the native Windows desktop/Android apps. Do not run a second copy of the same Compose stack from WSL at the same time as Windows Docker Desktop — ports `8000` and `5435` will clash.

Verify tools:
```powershell
git --version
docker version
docker compose version
flutter --version
flutter doctor -v
```

---

## 2. First-Time Installation

```powershell
git clone https://github.com/ziminni/qb_hardwarestore.git qb_pos_inventory_system
cd qb_pos_inventory_system
git switch master
git pull --ff-only origin master
```

Build and start the backend + PostgreSQL:
```powershell
docker compose up -d --build backend
docker compose ps
```

| Container | Purpose | Host Port |
|---|---|---|
| `buildpro_backend` | Django REST API | `8000` |
| `buildpro_db` | PostgreSQL 15 | `5435` (container `5432`) |

Verify health:
```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/health/
# Expected: status: ok, service: BuildPro API
```

---

## 3. Demo Accounts (Fresh Seed Only)

On a brand-new empty database, `docker compose up -d` runs `migrate` and `seed_demo --if-empty`. Existing databases are never overwritten.

| Username | Role | Password (fresh seed) |
|---|---|---|
| `admin` | System Administrator | `demo1234` |
| `manager` | Store Manager | `demo1234` |
| `stocker` | Stock Manager | `demo1234` |
| `cashier` | Cashier | `demo1234` |
| `checker` | Bodega Checker | `demo1234` |
| `cpms_service` | CPMS integration account (no POS UI) | `demo1234` |

Django Admin: `http://127.0.0.1:8000/admin/`

---

## 4. Run the Desktop App

From `flutter/`:

| | Windows PowerShell | macOS |
|---|---|---|
| First time | `flutter config --enable-windows-desktop` then `flutter pub get` | `flutter config --enable-macos-desktop` then `flutter pub get` |
| Run | `flutter run -d windows` | `flutter run -d macos` |
| Release build | `flutter build windows --release` | `flutter build macos --release` |

---

## 5. Cloudflare Named Tunnel (Permanent URL for CPMS & Remote Bodega)

Use a **Cloudflare Named Tunnel** so your URL (e.g. `https://pos-api.yourdomain.com`) never changes across restarts and reconnects automatically after a reboot.

> You do **not** need to install `cloudflared` on Windows or macOS — Docker runs `cloudflare/cloudflared:latest` automatically.

### One-Time Setup on the POS Computer
1. In **Cloudflare Zero Trust → Networks → Tunnels**, create a tunnel and copy its **token**.
2. Add a **Public Hostname** on that tunnel:
   - **Subdomain + Domain:** e.g. `pos-api.yourdomain.com`
   - **Service Type:** `HTTP`
   - **URL:** `gateway:8080` *(not `localhost:8000` — `gateway` enforces `X-QB-Gateway-Key` and blocks non-CPMS / non-Bodega routes)*
3. Run the one-line setup command once from `qb_pos_inventory_system`:
   ```powershell
   # Windows PowerShell
   .\scripts\start-tunnel.ps1 -Token "<your-cloudflare-tunnel-token>" -Hostname "pos-api.yourdomain.com"
   ```
   ```sh
   # macOS / Linux
   ./scripts/start-tunnel.sh --token "<your-cloudflare-tunnel-token>" --hostname "pos-api.yourdomain.com"
   ```
   This saves `tunnel/gateway.env` (gitignored), starts `db`, `backend`, `gateway`, and `cloudflared`, and prints the 4 lines for CPMS.

### Zero-Click Auto-Start After Reboot
`db`, `backend`, `gateway`, and `cloudflared` all use `restart: unless-stopped`. Enable **"Start Docker Desktop when you sign in"** in Docker Desktop Settings — after any reboot, everything starts and reconnects automatically with zero commands.

### Stop / Bring Everything Down Safely
```powershell
# Stop only the tunnel:
docker compose --profile tunnel stop gateway cloudflared

# Stop all containers (including tunnel, KEEPING database data):
docker compose --profile tunnel down
```
> **Never** run `docker compose down -v` or `python manage.py flush` on a database you want to keep.

---

## 6. Connect CPMS (Same PC or Another Computer)

1. Put the 4 lines printed by `start-tunnel` into `qb_project_management_system/django-backend/.env`:
   ```env
   POS_API_BASE_URL=https://pos-api.yourdomain.com
   POS_API_ALLOW_INSECURE_LOCAL=False
   POS_API_GATEWAY_HEADER_NAME=X-QB-Gateway-Key
   POS_API_GATEWAY_HEADER_VALUE=<48-character-key-from-start-tunnel>
   ```
2. Start CPMS and verify the connection:
   ```bash
   docker compose up -d
   docker compose exec backend python manage.py check_pos
   ```
   Expect **`READY`**.

---

## 7. Updating an Existing Installation Safely

1. **Back up PostgreSQL first (Windows PowerShell):**
   ```powershell
   $backupDir = Join-Path $env:USERPROFILE "BuildProBackups"
   New-Item -ItemType Directory -Force $backupDir
   $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
   docker compose exec -T db pg_dump -U admin -d buildpro_pos -Fc -f /tmp/pre-update.dump
   docker cp buildpro_db:/tmp/pre-update.dump (Join-Path $backupDir "pos-$stamp.dump")
   ```
2. **Pull & rebuild backend** (migrations apply automatically on startup):
   ```powershell
   docker compose stop backend
   git pull --ff-only origin master
   docker compose up -d --build backend
   ```
   *(If you run Django locally outside Docker with `manage.py runserver`, run `python manage.py migrate` manually before starting the server.)*

---

## 8. Troubleshooting

| Issue | Fix |
|---|---|
| *Store settings / Product catalogue could not be loaded* after pulling | Database migrations haven't been applied yet. Run `docker compose up -d --build backend` (or `python manage.py migrate` if running locally). |
| `docker compose down` says *Network ... Resource is still in use* | Tunnel containers are still attached. Run `docker compose --profile tunnel down`. |
| `port 8000` or `5435` already in use | Another stack (e.g. WSL vs Windows Docker Desktop, or local `runserver`) is already running. Stop the duplicate before starting. |
| `check_pos` returns `403` | `POS_API_GATEWAY_HEADER_VALUE` in CPMS `.env` doesn't match `QB_GATEWAY_KEY` in POS `tunnel/gateway.env`. |
| `flutter run` fails on Windows with symlink error | Enable **Windows Developer Mode**, then run `flutter pub get`. |
| `flutter` CMake error after moving folder | Run `flutter clean && flutter pub get` inside `flutter/`. |
