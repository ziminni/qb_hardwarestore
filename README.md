# BuildPro — POS & Inventory System

Hardware-store point of sale, inventory, receivables, analytics, and remote Bodega warehouse system for **Queen Builders**. Built with **Flutter** (Windows, macOS, Linux, Android/iOS Bodega) and **Django 5.2 LTS + DRF + PostgreSQL**.

Construction Project Management (**CPMS**) lives in a separate repository; normal store operations work even when CPMS is offline.

---

## Documentation Hub

| Guide | What's Inside |
|---|---|
| **[Setup & Daily Operations](docs/SETUP.md)** | Prerequisites, first install, safe DB updates, Cloudflare Named Tunnel (permanent URL + zero-click auto-start on reboot), CPMS linking, and troubleshooting. |
| **[Bodega Mobile App](docs/MOBILE-BODEGA.md)** | Building the Android APK (`flutter build apk --release`), pre-baking tunnel URL/key, connecting remotely over mobile data or local Wi-Fi, offline outbox sync, and SMS fallback. |
| **[Production Deployment](docs/production-setup.md)** | Real store go-live (`DJANGO_DEBUG=false`, `gunicorn`, strong secrets, real accounts, private backups, USB SMS modem bridge). |
| **[Three-Client Smoke Test](docs/three-client-smoke-test.md)** | End-to-end verification walkthrough across POS Desktop + CPMS + Bodega Android. |
| **[System Architecture (Atlas)](docs/SYSTEM_ATLAS.md)** | Full module overview, role workflows ([ROLE-FLOWS.md](docs/ROLE-FLOWS.md)), and data model. |
| **[API Reference](ENDPOINTS.md)** | REST API routes, payloads, and role permissions. |
| **[Backup & Restore Safety](docs/backup-restore-safety.md)** | Private backup storage (`backend_django/private/backups/`) and verified true-replace restore. |

---

## Quick Start (Windows PowerShell / macOS)

### 1. Start POS Backend + Named Tunnel
```powershell
# Windows PowerShell (one-time named tunnel setup; starts db, backend, gateway & cloudflared):
.\scripts\start-tunnel.ps1 -Token "<your-cloudflare-tunnel-token>" -Hostname "pos-api.yourdomain.com"
```
```sh
# macOS / Linux:
./scripts/start-tunnel.sh --token "<your-cloudflare-tunnel-token>" --hostname "pos-api.yourdomain.com"
```
*(No tunnel needed? Just run `docker compose up -d --build backend`.)*

Because all Compose services use `restart: unless-stopped`, **after any reboot just open Docker Desktop** — everything restarts and reconnects automatically.

### 2. Run the Desktop Client
```powershell
cd flutter
flutter pub get
flutter run -d windows   # or: flutter run -d macos
```

### 3. Build the Bodega Android APK
```powershell
cd flutter
flutter build apk --release
# Output: flutter\build\app\outputs\flutter-apk\app-release.apk
```
See [docs/MOBILE-BODEGA.md](docs/MOBILE-BODEGA.md) for pre-baking your tunnel URL & gateway key into the APK.

---

## Key Capabilities
- **POS Till & Shifts:** Barcode/QR scan, packaging UOMs, per-line & cart centavo discounts with shift/sale approval limits, never-discounted items, utang credit markup, payment-method fees (GCash/Card/Bank), mid-shift cash drawer movements, Z-reading with explicit drawer carry, and ESC/POS thermal receipt printing.
- **Inventory & Purchasing:** FIFO batch costing, landed cost snapshots (`pos.0022`), Store & Bodega locations, stock transfers, supplier POs/payables/cheques/returns/credit notes, Excel `.xlsx` catalogue round-trip, and per-unit selling-price history.
- **Analytics & Reports:** Operational Profit Breakdown (Shelf/Utang Price → Discounts → VAT → FIFO COGS → Gross Profit, Margin % & Markup % with legacy cost-coverage indicators) and visual charts across Sales, Valuation, Stock Movements, and Requisitions.
- **Bodega Warehouse & CPMS Integration:** Remote Bodega mobile app over Cloudflare Named Tunnel (with offline snapshot cache & idempotent outbox sync), offline SMS modem fallback, and CPMS material request / payment receipt workflow.

---

## Developer Verification

Run tests on a disposable database (never against a live store database):
```bash
docker compose exec backend python manage.py check
docker compose exec backend python manage.py makemigrations --check --dry-run
docker compose exec backend python manage.py test --noinput

cd flutter
flutter analyze
flutter test --concurrency=2
```
