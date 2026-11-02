---
date: 2026-11-02
slug: ui-refresh-wave3b-z1-clock
branch: feature/backend-integration
head: 96137b1
---

# 2026-11-02 — UI refresh: wave 3b close, Z1 copy sweep, clock freeze

## Focus

Close UI-refresh wave 3b (A2 last card + review + browser QA + fix pass FX1-FX9), run Z1 copy sweep, fix date-dependent test failures. Plan: `temp/ui-refresh/TASKS.md`; ledger `.superpowers/sdd/ui-refresh/progress.md`.

## What Was Built / Changed

| Commit | What |
|---|---|
| `5f5a5a2` | Wave 3b merge: A2 user management as summary line + DataPanel (all roles, Staff actions at 760) |
| `77a3225` | Wave-3b fix pass FX1-FX9: hung restore abandons + ignores late answer; UserService getAll; no admin-row actions for manager; staff scrolls at 760 via wheel-forward; Custom range noAnimation; top products by name via catalogue; till reload after sale; fixed-decimal cleanup |
| `2bead88` | Z1 copy sweep: 23 dash strings rewritten per D18, sentence-case Open/Closed badges, formatQuantity/formatPeso in remaining dialogs |
| `96137b1` | Clock freeze: `lib/core/time/app_clock.dart` + `package:clock`, `test/flutter_test_config.dart` pins 2026-10-15 10:00; lib `DateTime.now()` replaced |

Fresh gate (2026-11-02, this session): `flutter analyze` No issues; `flutter test --concurrency=2` exit 0 `+1243 ~224`; golden compare exit 0 `+224`.

## Mistakes & Gotchas (Do Not Repeat)

- WSL restart kills docker + background builders: both buildpro containers were Exited 255, builder record lost. Restart docker first, re-gate before resume.
- agent-browser `mouse wheel` never reaches Flutter web; byte-identical screenshots proved nothing. Use JS WheelEvent dispatch or drag; widget-level scroll proof still needs browser confirm.
- PopupMenu grow animation clips last item mid-animation (Custom range). Fix was `popUpAnimationStyle: noAnimation`, not layout.
- Stock-adjustment fixtures stamped "N hours ago" fail on the 1st of month under a Nov-01 clock while Dec-31 passes. Pin mid-month; boundary proof required for date tests.
- `pkill -f flutter_tester` kills own shell (exit 143). Use `pkill -f "[f]lutter_tester"`.
- Wave-3b golden "drift" was 19 missing PNGs (gitignored goldens dir) + 4 a1 Discounts removals, not fix-pass regressions. Regenerate only owned files.
- Z1 `remarks` separator change hits stored server text: grep readers before touching; `receivingQtyLabel` feeds a controller so stays parseable.

## Decisions

- FX3: System Administrator maps to role code `admin` server-side; admin-row hide covers it.
- Z1: empty values use Not set / No payment / Not linked; Admin Reports tab keeps label Movements (A5-owned).
- All date-defaulting tests run at fixed 2026-10-15 10:00 via `flutter_test_config.dart`.

## Wins & Next Step

- Wins: wave 3b + Z1 committed, full suite + goldens green twice, browser re-check passed (staff scroll, Custom range + picker).
- Next: Z2 whole-app pass (all roles x 1440/1100/760 x text scale 1.3, screenshots, SYSTEM_ATLAS routes 37 to 39). Blocked on user: reseed dev DB, teammate 7 items, adjustments By column, offline till, Movements rename, `git push` (~72 ahead).
