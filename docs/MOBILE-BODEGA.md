# BuildPro POS — Bodega Mobile App Guide (Android & iOS)

The mobile app (`BuildPro POS`) is used by the **Bodega Checker** to scan customer Official Receipt QR codes, release warehouse pick-ups, check supplier deliveries with photo proof, and work through temporary Wi-Fi drops.

---

## 1. Building the Android Release APK (Windows PowerShell)

Make sure the Flutter SDK and Android SDK are installed (`flutter doctor -v` shows Android toolchain ready), then run from `qb_pos_inventory_system\flutter`:

### Standard APK (Configure Server on the Phone)
```powershell
cd flutter
flutter pub get
flutter build apk --release
```
Output APK:
```text
flutter\build\app\outputs\flutter-apk\app-release.apk
```
Copy `app-release.apk` to the Android phone and install it (allow installing from unknown sources if prompted).

### Pre-Configured APK (Zero Setup on the Phone — Recommended for Remote Bodega)
You can bake your permanent Cloudflare Named Tunnel URL and gateway key directly into the APK so the Bodega Checker doesn't have to type them:
```powershell
cd flutter
flutter pub get
flutter build apk --release `
  --dart-define=API_BASE_URL=https://pos-api.yourdomain.com `
  --dart-define=API_GATEWAY_KEY=<your-48-char-QB_GATEWAY_KEY>
```
*(You can still override the address or key anytime on the phone via **Server: …**.)*

---

## 2. Connecting the Phone to POS

### Option A — Remote / Faraway Bodega (Online via Cloudflare Named Tunnel)
Works over **mobile data or any Wi-Fi** (no need to be on the store's LAN):
1. Ensure the POS tunnel is running (`.\scripts\start-tunnel.ps1` on Windows or `./scripts/start-tunnel.sh` on macOS — see [docs/SETUP.md](SETUP.md#5-cloudflare-named-tunnel-permanent-url-for-cpms--remote-bodega)).
2. On the phone's login screen (or **Profile → Server address**), tap **Server: …** and enter:
   - **Server URL or LAN IP:** `https://pos-api.yourdomain.com`
   - **Gateway key (for online tunnel):** your `QB_GATEWAY_KEY` from `tunnel/gateway.env`
3. Tap **Save**, then sign in as the **Bodega Checker** (`checker` / `demo1234` on a fresh demo seed, or the real store account).

> **Security:** The tunnel gateway (`tunnel/nginx.conf.template`) only exposes `/api/v1/bodega/`, Bodega session endpoints, delivery/avatar images, and CPMS integration routes — all gated by `X-QB-Gateway-Key` plus Django JWT & role checks. Admin, POS till, reports, and backups stay blocked (`404`).

### Option B — Same Store Wi-Fi (Local LAN)
1. Connect the phone to the same Wi-Fi network as the store PC running POS.
2. Tap **Server: …** on the login screen and enter:
   - **Server URL or LAN IP:** `http://<store-pc-lan-ip>:8000` (e.g. `192.168.1.10:8000`)
   - **Gateway key:** leave blank
3. Tap **Save** and sign in.

---

## 3. Offline Resilience

- **Temporary signal drops (built into the mobile app):** The app caches active pick-ups locally and queues releases in a persistent outbox (`Idempotency-Key` protected). When connectivity returns, queued releases replay automatically (or via **Sync now**) without double-releasing. See [docs/offline-sync-design.md](offline-sync-design.md).
- **No internet / no mobile data at all (SMS fallback):** Connect a USB GSM modem to the store PC and run `scripts/sms_bridge/sms_bridge.py`. The checker receives pickup SMS alerts with a one-time code and replies `DONE <OR> <OTP>` to release stock. See [docs/production-setup.md](production-setup.md).

---

## 4. iOS Notes
- Camera, photo library, and local-network permissions are configured in `flutter/ios/Runner/Info.plist`.
- Build on macOS with Xcode (`cd flutter && flutter build ios --release`).
