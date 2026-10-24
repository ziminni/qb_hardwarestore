# 2026-10-24 — Audit remediation: Wayfinder MAP + Phase 1 build

## What happened

- Wayfinder opened `planning/audit-remediation/MAP.md` from the 2026-10-23 manuscript/source audit (dossier is local-only under untracked `temp/audit/`). 9 decisions locked by the user (UOM/price authority, data scoping, release shift, admin authority, returns policy, alert resolve, audit depth, credit limit) plus researched integrity mechanics. Barcode/QR is Phase 6, concept in `decisions/10-barcode-concept.md`.
- Phase 1 (money & stock integrity) built from `planning/audit-remediation/phase-1-plan.md` by expressive-dev (deepseek-v4.1-flash), reviewed by hygiene-reviewer (glm-5.3-flash), live-probed by qa-tester (gpt-6-luna).

## Commits

| Commit | Task |
|---|---|
| `3c2349e` | Server-side sale validation (`INVALID_SALE`), server price, `qty × conversion_factor` for sales and returns |
| `8df436a` | Credit limit hard block (`CREDIT_LIMIT_EXCEEDED`); `total_credit_limit` nullable (null = unlimited), migration `pos.0008` |
| `6d0a84a` | `DocumentCounter` locked numbering + `Idempotency-Key` on checkout and held-cart complete, migration `pos.0009` |
| `d7738a3` | `GoodsReceiptItem` lines + `processed_at` lock; split receipts no longer overcount, migration `inventory.0003` |
| `29f7bc2` | Zero-stock positive adjustment reopens newest batch / `NO_BATCH_HISTORY`; release refuses `NO_BASE_UOM` before writes |
| `dea929a` | Flutter: attempt-scoped idempotency key, server receipt lines, new error messages |
| `ae514ee` | Review fix: idempotency hash scoped to endpoint + cart pk; legacy receipt delta tests |

## Gate

Backend 176/176 · `manage.py check` clean · `makemigrations --check` clean · Flutter 552/552 · analyze clean · QA live probes A–I PASS (incl. 10 concurrent checkouts, 5 same-key concurrent → one sale).

## Gotchas

- `makemigrations` inside the container writes root-owned files → `docker exec buildpro_backend chown 1000:1000 <file>` before editing.
- `InventoryBatch.receipt` is non-null, so stock can only be added by reopening an existing batch or a goods receipt.
- Release quantities are already base units — never multiply them by a conversion factor.
- pi-lens LSP keeps flagging `flutter/test/data/services/pos_service_test.dart` with stale errors; `flutter analyze` + `flutter test` are authoritative (14/14).
- QA left demo rows in the dev DB (QA category/brand/`QABOX` UOM, variants 9–13, PO 9, customer `QA Credit Limited`, 18 sales). Harmless; reseed if a clean demo is needed.

## Deferred minors

Listed in `.superpowers/sdd/audit-remediation/progress.md` (`Final: minor (deferred)` lines): release `remaining<=0` KeyError race, seed re-forcing Maria's limit, dead duplicate method check in `process_return`, unused `HeldCartService.complete` key path, pyright pragmas, test helper override, pre-fix hash replays now 409.

## Next

`git push` (assistant shell has no SSH key). Then write `phase-2-plan.md` and BUILD Phase 2 (access control & audit).
