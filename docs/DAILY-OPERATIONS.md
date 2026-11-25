# BuildPro Ecosystem — Daily Operations & Update Guide

> **Windows Docker presentation (no Contabo):** See `docs/PRESENTATION-SETUP.md` in the CPMS checkout. The Contabo instructions below are for the retired VPS deployment.

Complete runbook for running and updating the 3-device **BuildPro** ecosystem (**Windows POS & Inventory** + **USB SIM800C SMS Bridge** + **Contabo VPS CPMS** + **Android Bodega Mobile**):

1. [Live Architecture & Endpoints](#live-architecture--endpoints)
2. [Part 1 — Starting From Complete Shutdown](#part-1--starting-from-complete-shutdown)
3. [Part 2 — Updating After Pushing Code Changes](#part-2--updating-after-pushing-code-changes)
4. [Part 3 — Offline Dual-SIM SMS Demo Checklist](#part-3--offline-dual-sim-sms-demo-checklist)

---

## Live Architecture & Endpoints

| System | Host | Public HTTPS URL | Branch |
|---|---|---|---|
| **POS & Inventory** | Store Windows PC (Docker + Cloudflare Named Tunnel) | `https://pos-api.posinventory.space` | `master` |
| **CPMS** | Contabo Windows Server VPS (24/7 native Windows + Cloudflare Named Tunnel) | `https://cpms-api.posinventory.space` | `main` |
| **Bodega Mobile** | Android Phone (Pre-baked APK + Dual-SIM Offline SMS) | Connects to `https://pos-api.posinventory.space` | `master` |
| **USB SMS Bridge** | Store Windows PC (`LC SIM800C V3`, `COM5`, `9600` baud) | Local `http://127.0.0.1:8000` | `master` |

---

## Part 1 — Starting From Complete Shutdown

### 1. Windows Laptop (POS & Inventory Server + Desktop App)
1. **Open Docker Desktop** and wait until it is running (green status).
   - Containers (`buildpro_db`, `buildpro_backend`, `buildpro_tunnel_gateway`, `buildpro_tunnel`) have `restart: unless-stopped` and start automatically.
2. Open **PowerShell** inside the POS repo (`hardware_store` / `qb_pos_inventory_system`) and pull latest `master`:
   ```powershell
   git checkout master; git pull origin master
   ```
   *(If `backend_django/` changed since your last run, also run `docker compose build backend`.)*
3. **Choose your database mode:**
   - **Keep existing data (normal daily start):**
     ```powershell
     curl.exe -s https://pos-api.posinventory.space/api/health/
     ```
     *(Expected: `{"status":"ok"}`. If not, run `.\scripts\start-tunnel.ps1`.)*
   - **Fresh Empty reset** *(only the 6 accounts, `Store`/`Bodega` with `is_bodega=True`, 12 standard UOMs, `Walk-in Customer`, and `BuildRight Construction` contractor — zero products/sales/POs)*:
     ```powershell
     .\scripts\reset-fresh-empty.ps1 -ConfirmReset
     ```
   - **Basic Seeded Demo reset** *(accounts + sample hardware products, stock, suppliers & contractor)*:
     ```powershell
     .\scripts\reset-seeded-demo.ps1 -ConfirmReset
     ```
4. **Launch the POS Desktop App:**
   ```powershell
   cd flutter
   flutter pub get
   flutter run -d windows
   ```
   *(Fresh/demo accounts — password `demo1234`: `admin`, `manager`, `stocker`, `cashier`, `checker`.)*

---

### 2. USB SIM800C SMS Module (2nd PowerShell on Windows Laptop)
1. Plug in your **LC SIM800C V3** USB modem (SIM card with load; COM port usually `COM5`).
2. Start the bridge:
   ```powershell
   cd hardware_store\scripts\sms_bridge
   python sms_bridge.py --api http://127.0.0.1:8000 --key <YOUR_SMS_GATEWAY_KEY> --driver at --port COM5 --baud 9600
   ```
   *(Wait until it logs **`modem ready`**.)*
3. **Register the Bodega Checker's phone** *(required once after any DB reset)*:
   - In POS Desktop, sign in as **`admin`** or **`manager`** → **Settings → SMS & Bodega phones** → add the phone's SIM number (e.g. `0917...`) → toggle **Active** ON.

---

### 3. Contabo Windows VPS (CPMS Server — Runs 24/7)
- **Normal daily start (keeping existing data):** Do **nothing** — `PostgreSQL 15`, `BuildPro_CPMS_API`, `BuildPro_CPMS_Outbox`, `cloudflared`, and `CPMS_AutoDeploy` run 24/7 even with RDP closed.
- **Only if you reset POS in Step 1** and want CPMS wiped to match, RDP into the Contabo VPS, open **PowerShell (Administrator)**, and run **one**:
  - **Fresh Empty CPMS** *(Company profile, System Admin `maria@example.ph`, and Own Hardware Store linked to POS)*:
    ```powershell
    cd C:\cpms; git pull; .\scripts\reset-fresh-empty-vps.ps1
    ```
  - **Basic Seeded Demo CPMS** *(Company, 6 accounts, master lists, 4 projects, workers, and Own Hardware Store linked to POS)*:
    ```powershell
    cd C:\cpms; git pull; .\scripts\reset-seeded-demo-vps.ps1
    ```
  - Close RDP once `check_pos` prints **`READY`**. *(Always run the POS reset before the CPMS VPS reset so CPMS auto-links cleanly to the new POS contractor payer.)*

---

### 4. Teammate's Mac / Dev Laptop (CPMS Flutter App — No Docker Needed)
Open **Terminal** inside `qb_project_management_system`:
```bash
git checkout main
git pull origin main
cd flutter
flutter pub get
flutter run --dart-define=API_BASE_URL=https://cpms-api.posinventory.space/api/v1
```
- **User accounts & Forgot Password (zero-email in-app mode):**
  - When Admin creates a user or resets a password, CPMS displays the **Email + Temporary Password** card with a **Copy** button; the user sets their own password on first sign-in.
  - When a user clicks **Forgot password**, the 6-digit reset code (valid 15 min) appears in the System Administrator's **Notifications** bell.
  - *(Optional: to enable free Gmail delivery over HTTPS port 443 without third-party signup, deploy a 4-line Google Apps Script Web App on your Gmail and set `EMAIL_WEBHOOK_URL` in `C:\cpms\django-backend\.env`.)*

---

### 5. Android Phone (Bodega Mobile App — Dual-SIM Offline SMS)
- **Normal days (no reset, no mobile code change):** Just open **BuildPro POS** on the phone.
- **After any POS database reset:** On the phone open **Settings → Apps → BuildPro POS → Storage → Clear storage**, then sign in as **`checker` / `demo1234`** (allow SMS + Phone permissions so the Dual-SIM picker works).
- **First time or after mobile code changes:** Build the pre-baked APK from the POS repo `flutter` folder on Windows:
  ```powershell
  flutter build apk --release --dart-define=API_BASE_URL=https://pos-api.posinventory.space --dart-define=API_GATEWAY_KEY=<your-48-char-QB_GATEWAY_KEY> --dart-define=STORE_SMS_NUMBER=+639XXXXXXXXX
  ```
  Copy & install `flutter\build\app\outputs\flutter-apk\app-release.apk` onto the phone.

---

## Part 2 — Updating After Pushing Code Changes

### A. When POS (`qb_hardwarestore` / `master`) Changes Are Pushed
On your **Windows POS PC** (PowerShell inside `hardware_store`):
1. Pull latest `master`:
   ```powershell
   git checkout master; git pull origin master
   ```
2. **If `backend_django/` changed** (models, serializers, views, migrations, requirements):
   ```powershell
   docker compose up -d --build backend
   ```
   *(Preserves your existing PostgreSQL database and uploaded photos.)*
3. **If `flutter/` desktop UI changed:**
   ```powershell
   cd flutter; flutter pub get; flutter run -d windows
   ```
4. **If `flutter/` Bodega mobile UI changed:**
   Rebuild and reinstall the APK using Step 5 above.

### B. When CPMS (`qb_projectmanagement` / `main`) Changes Are Pushed
1. **Contabo VPS Server (Automatic):**
   - `CPMS_AutoDeploy` checks `origin/main` every **2 minutes**.
   - **Flutter UI-only push (`flutter/`):** Pulled silently with zero API downtime.
   - **Backend push (`django-backend/`):** Automatically installs new `requirements.txt` packages, runs `migrate --noinput` + `collectstatic --noinput`, restarts `BuildPro_CPMS_API` & `BuildPro_CPMS_Outbox`, and logs to `C:\cpms\deploy.log`.
   - *(Force immediately on VPS: `powershell -NoProfile -Ep Bypass -File C:\cpms\auto-deploy.ps1`.)*
2. **Mac / Windows CPMS Flutter App:**
   ```bash
   git checkout main && git pull origin main
   cd flutter && flutter pub get
   flutter run --dart-define=API_BASE_URL=https://cpms-api.posinventory.space/api/v1
   ```

---

## Part 3 — Offline Dual-SIM SMS Demo Checklist
1. **POS Desktop (`cashier`):** Open Shift → sell a **`Bodega`** item → Checkout → open **Transaction History** (shows **`Awaiting Bodega`**).
2. **Android Phone (`checker`):** Pull to refresh **Pick-ups** while online (caches the claim & 4-digit `sms_code`).
3. **Turn OFF Wi-Fi & Mobile Data** on the phone.
4. Tap the pick-up → tap **Release** → choose the SIM with load in **"Choose SIM for offline SMS"**.
5. Watch `sms_bridge.py` log `PROCESSED OK BR-... released`, and watch POS Desktop **Transaction History** auto-update to **`Bodega: Accomplished`** within 10 seconds.

---

### Quick Health Verification (From Any Browser or Terminal)
- **POS:** `https://pos-api.posinventory.space/api/health/` → `{"status":"ok"}`
- **CPMS:** `https://cpms-api.posinventory.space/api/health/` → `{"status":"ok","service":"BuildPro CPMS","system":"cpms"}`
