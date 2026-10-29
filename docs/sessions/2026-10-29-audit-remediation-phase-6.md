# 2026-10-29 — Audit remediation Phase 6: barcode labels & scanning

Plan: `planning/audit-remediation/phase-6-plan.md` · decisions 11–18 · ledger `.superpowers/sdd/phase-6-plan/progress.md`.
Build trio: expressive-dev (code) · hygiene-reviewer (review) · qa-tester (live API + browser).

## Commits (`81e98a0`..`977f740`)

| Commit | What |
|---|---|
| `81e98a0` | Task 0: `pdf` + `printing`; 50×30 mm Code 128 sticker proven (linux + web builds) |
| `99fac8f` | Unique normalised codes; EAN/UPC check digit; reserved `QB` prefix; `BARCODE_TAKEN` names holder |
| `84276a2` | Every unit auto-gets `QB` + 6-digit id + check digit; backfill migration (15 blank → 0); barcode audit rows |
| `b3ba300` | `GET /variant-uoms/?barcode=` lookup with product/variant active flags |
| `c08da8f` | Blank PATCH on an already-derived code writes no fake audit row |
| `1aea528` | Till loads every catalogue page (was 50); scan matches the unit's own code |
| `68532bc` | Whole units add instantly, measured units open dialog preselected; server fallback on cache miss |
| `6ef53e8` | Sticker PDFs from Products (row + bulk) and after processing a delivery; Print + Save PDF |
| `5d4f6ed` | Product details lists and edits every selling unit's code (inventory/sales/admin role codes) |
| `a3550d9` | Fix: till price, factor, availability from the selling unit (legacy tracking removed from till) |
| `c770790` | Fix: blank scan silent; active sold-out scan says "out of stock", not "archived" |
| `6e96247` | Fix: Receiving label copies cap (200) is stated |
| `977f740` | Fix: details dialog scrolls with visible scrollbar at 1366×768 |

## Evidence

- Backend **497/497** (`docker exec buildpro_backend python manage.py test`), `makemigrations --check` clean.
- Flutter **839/839**, `flutter analyze` clean (controller re-runs).
- Review backend: APPROVED 0C/0I/8 Minor. Review Flutter: CHANGES_REQUESTED 0C/2I/7 Minor → fixed (2 Minors promoted).
- Live API QA B1–B11 pass. Browser E2E E1–E11: 3 fails → fix pass → re-check R1–R7 all pass
  (box of 12 with 3 PC shows 0.25 available and refuses 1; VUOM 17 shows ₱60 / 3.00; blank scan silent with no request;
  sold-out vs archived messages; delivery labels pre-filled; dialog scroll; regression sale TRX-20261029-0004 ₱315 = cart).

## Not verified / deferred

- **Real thermal print** (hardware): user prints once at 100% / actual size.
- Measured-unit scan (m/kg/l): no such unit in dev DB — widget-tested only.
- Deferred Minors (ledger): rapid double-scan can stack two dialogs; blank-code row says "Factory barcode"; role-gate fixture name==displayName; font-load failure inside `layoutPdf`; no direct `wholeUnitCodes` test; sequential catalogue walk; backend 7 hardening Minors; `seed_demo` `KeyError: 'cost'` on half-seeded DB.
- `SYSTEM_ATLAS` not refreshed for Phase 6.

## Dev DB state left by QA

VariantUOM 16 & 17, receipts 18–19, sales TRX-20261029-0001..0004, audit 559–608; cashier shift 18 OPEN. Reseed for a clean demo.
