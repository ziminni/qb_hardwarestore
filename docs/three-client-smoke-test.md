# BuildPro demo: POS, CPMS, and Bodega Android

Use a disposable demo database or an existing **demo** installation. Do not place test sales, seed Bodega examples, or restore backup files in a real store database. For an existing installation, back up before starting the updated backend: [POS backup instructions](../README.md#2-existing-database-back-up-before-starting-updated-backend) and [CPMS setup](https://github.com/ziminni/qb_projectmanagement/blob/main/README.md). Never use `docker compose down -v` to apply an update.

## 1. Start POS and CPMS on one computer

Stop running Flutter apps before updating. In the POS clone, test the published PR branch until it merges; after merge, use `master`. Keep any local edits before switching. In the CPMS clone, use `main`. Start Docker Desktop. Run each command from its **own repository root**, POS first:

```sh
# POS root
 docker compose up -d --build backend
# CPMS root (starts both the API and the outbox worker)
 docker compose up -d --build
 docker compose exec backend python manage.py check_pos
```

POS health: `http://127.0.0.1:8000/api/health/`. CPMS Flutter defaults to `http://127.0.0.1:8001/api/v1`. `check_pos` should end in `READY` after validating sign-in, the demo contractor, and mapped materials. This is a connectivity check, not a completed order. If this machine previously used a tunnel, remove the old `POS_API_*` tunnel overrides from CPMS's `django-backend/.env` and restart CPMS before trying the same-PC setup.

From **each repo's `flutter/` folder**, in separate terminals:

| Windows PowerShell | macOS Terminal |
|---|---|
| `flutter pub get` then `flutter run -d windows` | `flutter pub get` then `flutter run -d macos` |

Check `flutter doctor -v` first. Windows needs Visual Studio Desktop development with C++; Mac needs Xcode and CocoaPods. Use host Flutter, not WSL Flutter, for native Windows builds. Stop and relaunch the native client after pulling; rebuilding Docker alone does not update the UI.

## 2. POS desktop smoke test

Fresh seed users: `cashier`, `manager`, `stocker`, and `admin`; demo password `demo1234`. Existing accounts keep their passwords.

1. As **Admin**, set a small GCash fee in **Settings → Payment method fees** on the demo database. As **Cashier**, open a shift and add a stocked item. **Proceed to payment** should open one checkout panel, not a Next/Review wizard. Choose GCash, check the fee and total, and submit once. Card remains hidden. As **Manager**, confirm the saved transaction and separate payment fee in reports.
2. Ring a second sale using goods stocked at **Bodega**, and turn on **Delivery** at checkout. As **Manager**, open **Sales → Deliveries → View loading details** and verify the allocated Store/Bodega quantities. Mark **Start** when the truck would leave, then **Delivered**. This sale must not appear in the Checker pickup queue. Bodega Stock should show scheduled quantities as **Awaiting dispatch** until departure; a failure does not automatically restock.

## 3. CPMS desktop and bridge smoke test

Fresh demo accounts: `ana@example.ph` (site engineer), `ramon@example.ph` (owner/PM), `liza@example.ph` (accountant), `maria@example.ph` (admin), and `mark@example.ph` (client); password `password123`.

1. As Ana, file a material request for an assigned ongoing demo project. As Ramon, create an **own-store** order from it using a mapped item with available POS stock. Wait for sync; if it stays pending or fails, rerun `check_pos` and inspect the CPMS worker logs with `docker compose logs --tail=80` from the CPMS root.
2. As POS **Manager**, accept the request in **Project requests**. As POS **Cashier** with an open shift, find it under **Release materials** by request number or project, confirm the quantity, then release it once. Printing is optional for this test.
3. Back in CPMS, check the order's store status and **Financials → Owed to the store**. Check that the amount matches the POS release. Store release is not the same as site delivery; confirm receipt separately if needed.

For two laptops, use the [free Quick Tunnel instructions](../README.md#setup-b-two-laptops-windows--mac). Only CPMS uses the keyed tunnel URL; the phone connects directly to the POS backend on the trusted LAN or over USB. A restarted Quick Tunnel needs its new URL in CPMS. Permanent hostname and hosting choice are not required for this rehearsal.

## 4. Bodega Checker on Android (no printer required)

This is the POS Android app signed into the **Bodega Checker** role, not a separate CPMS app. On a disposable POS database, `docker compose exec backend python manage.py seed_bodega_demo` adds Bodega examples. Use `checker` / `demo1234` on the fresh demo seed.

1. From POS `flutter/`, with the Android SDK installed, run `flutter pub get` and `flutter build apk --release`. Install `build/app/outputs/flutter-apk/app-release.apk` on the phone. If you already have a current test APK, use that instead.
2. On the phone, tap **Server** before login. With LAN access, enter the **computer running POS**'s LAN IP and port, for example `192.168.1.10:8000`. Both devices must be on a trusted network that lets them reach each other. Do not expose raw POS port `8000` publicly. Alternatively, connect an authorized USB-debugging phone and run `adb reverse tcp:8000 tcp:8000` on the POS computer, then use `127.0.0.1:8000` in the app. Replace both port numbers if the backend uses another host port.
3. Ring a **pickup** sale using Bodega stock (leave Delivery off), then open **Customer pickups** as Checker. Scan the receipt QR from a PDF displayed on another screen, or type the real `OR-…` number from that same backend. Confirm pickup and check that remaining quantity decreases once. An OR from another database will not work. Check **Supplier arrivals** separately using a Stock Manager receipt sent to Bodega.

Leave SMS disabled for this demo. The modem/SIM is a separate hardware test. USB debugging may be turned off when finished. Native Mac launch, physical receipt printing, and a full order through the Quick Tunnel are separate acceptance checks.
