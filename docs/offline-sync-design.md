# Bodega Mobile Offline-Sync Design (Store + Remote Warehouse)

## 1. Problem & Current Architecture

Today, the store runs two warehouse paths when the Bodega is away from the counter:

1. **Online mobile app (`BuildPro POS` APK on Android / iOS):** The Bodega Checker connects to the store server over Wi-Fi (`Server: <ip>:8000` on the login screen), scans the customer's Official Receipt QR code, views the remaining pick-up lines, and records full or partial releases and delivery-check photos.
2. **Offline SMS bridge (`apps/sms` + `scripts/sms_bridge/sms_bridge.py`):** When the warehouse has no Wi-Fi or mobile data, the store PC texts the checker's registered phone (`QB PICKUP <OR>: <items>. Code <OTP>. Reply: DONE <OR> <OTP>`) and the checker replies by regular SMS to release the full claim.

When the checker carries the **mobile app** into a dead zone (no Wi-Fi at the back of the warehouse), the app currently requires a live HTTP connection for every scan and release.

---

## 2. Offline-Sync Mobile Design (Next Evolution)

To let the mobile app work during temporary Wi-Fi drops and sync automatically when the checker walks back into Wi-Fi range:

### A. Local Snapshot Cache (Read Path)
- **What is cached on the phone:**
  - While online, `BodegaViewmodel` stores the active pick-ups list (`GET /api/v1/bodega/pickups/`) and pending supplier delivery checks (`GET /api/v1/bodega/delivery-checks/`) in a local SQLite / shared-preferences store keyed by server base URL and user ID, with a `last_synced_at` timestamp.
- **QR scan while offline:**
  - Scanning a receipt QR code (`OR-YYYYMMDD-NNNN`) looks up the cached pick-up snapshot locally when the server is unreachable, showing an explicit banner: **`Offline snapshot from <time> — quantities may have changed at the counter`**.

### B. Outbox Queue with Idempotency Keys (Write Path)
- **Queued actions:**
  - When the checker taps **Release** while offline, the app writes a `PendingBodegaAction` to a persistent local outbox queue:
    - `client_action_id` (UUID v4 — sent as `Idempotency-Key`)
    - `sale_id` / `or_number`
    - `lines`: `[{variant_id, location_id, qty}]`
    - `received_by`, `notes`, `queued_at`
- **Replay on reconnect:**
  - When network connectivity returns (or the checker taps **Sync now**), the app replays queued actions in FIFO order to `POST /api/v1/bodega/pickups/<sale_id>/release/` with `Idempotency-Key: <client_action_id>`.

### C. Conflict Rules (Server Remains the Authority)
- **Idempotent replay:** If the phone sent a release, lost Wi-Fi before reading the 201 response, and retries, the server returns the original release without double-deducting.
- **Already released (via counter, another checker, or SMS):** If the claim was already released by SMS (`DONE <OR> <OTP>`) or voided/returned at the counter while the phone was offline, the server returns `400 BODEGA_OVER_RELEASE` / `SALE_RETURNED`. The phone marks the queued item as **Needs review** with the server's message instead of silently dropping it.
- **Session expiry:** If the access JWT expired while offline, the sync worker refreshes the token first; if the refresh token also expired, the queued actions stay encrypted on disk until the checker signs back in.
