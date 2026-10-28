# Camera Scanning

**Status:** ✅ Locked 2026-10-28 (user chose keyboard-wedge only)
**Mode:** Grill

## Question

Does Phase 6 support scanning with a phone/webcam camera, or only USB/Bluetooth keyboard-wedge scanners?

## Decision

**Keyboard-wedge (USB/Bluetooth) scanners only.** The existing till scan field (`pos_product_browser.dart`, `_handleScan`) is the only input path. Camera scanning moves to **Out of Scope** and returns together with production HTTPS (`planning/04-cleanup.md`).

### Why

- Works today with zero dependencies on every target (web, Linux, Windows, Android with a BT scanner).
- Browser camera access requires HTTPS; adding it pulls production hardening into this phase.

## Rejected

- **Android-only camera** — new dependency + permission flow + an Android test path nobody runs.
- **Camera everywhere** — requires HTTPS on web.
