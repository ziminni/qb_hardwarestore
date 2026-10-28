# Audit Remediation MAP

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Money & stock integrity (backend) — server UOM conversion, server price, sale validation, idempotency, safe numbering, split-receipt delta, zero-stock adjustment, release factor-1 UOM, credit-limit block | ✅ [UOM and price authority](./decisions/01-uom-and-price-authority.md), [Credit limit](./decisions/08-credit-limit.md), [Integrity mechanics](./decisions/09-integrity-mechanics.md) | ✅ Done 2026-10-24 — `3c2349e`..`ae514ee`, backend 176/176, flutter 552/552, hygiene fix-pass + QA live A–I PASS ([plan](./phase-1-plan.md)) |
| 2 | Access control & audit — held-cart/transaction scoping, Admin group authority, self-approval guard, alert resolve role, append-only business audit | ✅ [Data scoping](./decisions/02-data-scoping.md), [Admin authority](./decisions/04-admin-authority.md), [Alert resolve](./decisions/06-alert-resolve.md), [Audit depth](./decisions/07-audit-depth.md) | ✅ Done 2026-10-24 — `cc5b702`..`5c0423d`, backend 333/333, flutter 565/565, hygiene fix-pass (1 Critical + 4 Important) + QA live A–J PASS ([plan](./phase-2-plan.md)) |
| 3 | Cashier — release attaches shift, held-cart close advisory, till Returns tab + debt-first return accounting | ✅ [Release shift](./decisions/03-release-shift.md), [Returns policy](./decisions/05-returns-policy.md) | ✅ Done 2026-10-24 — `2703b7a`..`71ab5fb`, backend 383/383, flutter 694/694, hygiene APPROVED ×2 + API QA A1–A6 PASS + 4 browser E2E rounds (fixed: till payment codes, CORS Idempotency-Key, open-shift dialog, resumed-cart double-sell) ([plan](./phase-3-plan.md)) |
| 4 | Stock Manager — live product CRUD, low-stock on sale/release + dedup, goods-receipt history, persisted supplier toggle | ✅ (no new decision; follows audit findings) | ✅ Done 2026-10-25 — `f4253b9`..`c17fd30`, backend 456/456, flutter 738/738, hygiene ×2 fix-pass + API QA B1–B6 PASS + browser E2E (fixed: Resolve hidden for every role, mouse-unreachable table actions at 1366px, stale Receiving status) ([plan](./phase-4-plan.md)) |
| 5 | Store Manager / Admin — user edit/deactivate UI, overdue filter contract, unlinked-return manager screen, dashboard aggregation limits | ✅ [Returns policy](./decisions/05-returns-policy.md) | ✅ Done 2026-10-26 — `e8443bf`..`a706073`+format, backend 468/468, flutter 769/769, hygiene self-review + API live probes PASS ([plan](./phase-5-plan.md)) |
| 6 | Barcode labels & scanning — unique per-unit codes (factory EAN or auto `QB` Code 128), scan adds the exact selling unit from a complete catalogue with server fallback, 50×30 mm thermal stickers, per-unit code edit | ✅ [Barcode baseline](./decisions/11-barcode-baseline.md), [Code source & format](./decisions/12-code-source-format.md), [Scan resolution](./decisions/13-scan-resolution.md), [Label printing](./decisions/14-label-printing.md), [Camera scanning](./decisions/15-camera-scan.md), [Code assignment](./decisions/16-code-assignment.md), [Scan-to-cart](./decisions/17-scan-to-cart.md), [Selling-unit codes UI](./decisions/18-unit-codes-ui.md) | [ ] Ready to build ([plan](./phase-6-plan.md)) |

## Destination

Every P0/P1 finding in the 2026-10-23 audit (`temp/audit/pos_inventory_system/verification-results.md`, untracked) is fixed with RED-first tests, security enforced at the API boundary in every phase, then role phases close remaining UX gaps, and a final barcode phase makes physical product labels scannable at the POS.

## Notes & Invariants

- **Security is per-phase, not a phase.** Every task spec lists abuse cases and each must have a RED-first test: wrong role → 403, non-owner → 404/403, forged price ignored, negative/empty payload → 400, replay → no duplicate, concurrent request → no double effect.
- **Server is the trust boundary.** Flutter checks are UX only; never rely on them for integrity.
- **Proof rule (AGENTS.md):** a test counts only after it fails without the fix; claims need command output.
- **Backend test harness:** `POSTestBase` extends Django `TestCase` → use `content_type='application/json'` for nested writes.
- **Key files:** `apps/pos/services.py` (`process_sale`, `generate_transaction_no` :24, `generate_or_number` :33, `process_return` :797), `apps/requisitions/services.py` (`approve_requisition` :40, `release_materials` :133), `apps/inventory/services.py` (`process_goods_receipt` :20, `apply_stock_adjustment` :110, `_check_low_stock` :146), `apps/users/views.py` (`IsAdminRole` on register/users/audit since Phase 2), `apps/inventory/views.py` (`SystemAlertViewSet` :251).
- **Barcode state:** see [Barcode baseline](./decisions/11-barcode-baseline.md) — field exists (`models.py:144`), all 15 dev units blank; till scan is keyboard-wedge → `findByBarcode`, but resolves the variant not the unit, preselects the wrong unit, and the till catalogue stops at 50 rows (fixed in Phase 6 Tasks 4–5).
- **CPMS untouched.** POS-local requisition/token models only.
- **Agents:** expressive-dev (`deepseek-v4.1-flash`) codes; hygiene-reviewer (`glm-5.3-flash`) reviews every diff; qa-tester (`gpt-6-luna`) live-probes each phase. Use bare model IDs (opencode-go default provider).

## Decisions So Far

- [UOM and price authority](./decisions/01-uom-and-price-authority.md): server multiplies selling qty × `conversion_factor` before FIFO; server records `default_selling_price`, client price ignored.
- [Data scoping](./decisions/02-data-scoping.md): cashier sees own transactions; any POS-role cashier may list/resume held carts; non-POS roles denied held carts; manager/admin see all.
- [Release shift](./decisions/03-release-shift.md): material release requires OPEN shift and attaches it; counts in Z gross, not cash drawer.
- [Admin authority](./decisions/04-admin-authority.md): Admin group is the single authority; `IsAdminUser` → `IsAdminRole`; `is_staff` only for Django `/admin`.
- [Returns policy](./decisions/05-returns-policy.md): cashier returns from a new till Returns tab, open shift, linked sale required + qty cap; unlinked only Store Manager with reason; return value reduces open debt first, cash refunds only excess.
- [Alert resolve](./decisions/06-alert-resolve.md): Stock Manager + Admin resolve; resolver recorded.
- [Audit depth](./decisions/07-audit-depth.md): app-level append-only audit written in-transaction for business events; no update/delete; user FK PROTECT + username snapshot.
- [Credit limit](./decisions/08-credit-limit.md): server hard block `CREDIT_LIMIT_EXCEEDED`; nullable limit, null = unlimited, existing 0 migrated to null.
- [Integrity mechanics](./decisions/09-integrity-mechanics.md): `Idempotency-Key` header stored unique on transaction; locked counter for numbers; receipt-line deltas; zero-stock adjustment creates batch.
- [Barcode baseline](./decisions/11-barcode-baseline.md): case-insensitive partial-unique `barcode_qr` (blanks allowed), trim+upper on write and scan, `400 BARCODE_TAKEN`, inventory-role writes, barcode before/after audited; scan-unit, dialog-preselect and 50-row catalogue truncation are build defects.
- [Code source & format](./decisions/12-code-source-format.md): factory EAN/UPC kept (GS1 check validated); else `QB` + 6-digit id + `-` + GS1 check (`QB000013-0`); `QB` prefix reserved; labels Code 128.
- [Scan resolution](./decisions/13-scan-resolution.md): complete loaded catalogue first, miss → `GET /variant-uoms/?barcode=` → reload; archived and not-found named separately.
- [Label printing](./decisions/14-label-printing.md): barcode stickers (not RFID) on a driver-installed thermal printer via client `pdf`+`printing`, one 50×30 mm page per sticker, no price, QB units only, Products + post-Receiving entry.
- [Camera scanning](./decisions/15-camera-scan.md): USB/Bluetooth keyboard-wedge only; camera waits for HTTPS.
- [Code assignment](./decisions/16-code-assignment.md): model-level invariant — no unit ever blank; save derives `QB`, PATCH `''` restores it, data migration backfills.
- [Scan-to-cart](./decisions/17-scan-to-cart.md): whole units add 1 instantly (re-scan merges); measured units open the dialog with the scanned unit preselected.
- [Selling-unit codes UI](./decisions/18-unit-codes-ui.md): details dialog shows and edits every existing unit's code; no create-unit UI.

## Active Frontier

_(empty — Phase 6 fully grilled 2026-10-28; build per [plan](./phase-6-plan.md))_

## Blocked

_(none)_

## Fog of War

_(empty)_

## Out of Scope

- CPMS repo and real POS↔CPMS API exchange.
- Production hardening of secrets/HTTPS (stays in `planning/04-cleanup.md`).
- Payment gateway / split-tender UI.
- Discounts/VAT (sale service hard-zeros them) — needs its own product decision.
- Thermal **receipt** printing (Phase 6's `printing` dependency can be reused later).
- Camera scanning (with production HTTPS), RFID tags, raw ZPL/TSPL drivers, prices on labels, "add selling unit" catalog UI.
