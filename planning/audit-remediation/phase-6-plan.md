# Phase 6 Plan — Barcode Labels & Scanning

**Spec:** [MAP](./MAP.md) row 6. **Branch:** `feature/backend-integration`. **Baseline:** backend 468/468, flutter 771/771 (post chart fix `b5cfc33`), analyze clean.
**Grill (locked 2026-10-28):** hybrid codes (factory EAN else `QB` Code 128) · auto-assign + backfill · cache-first scan with server fallback · instant add for whole units, dialog for measured · USB/BT scanners only · thermal stickers via label-sized PDF, 50×30 mm, no price, Products + Receiving · show/edit codes for every existing unit.
**Research (no grill):** [Barcode baseline](./decisions/11-barcode-baseline.md) — DB uniqueness, normalisation, write authority, audit, and three defects (scan matches variant not unit; dialog preselects wrong unit; till catalogue stops at 50 rows).

## Destination & Scope

Every selling unit carries a unique, scannable code; a scan at the till adds **that exact unit** (box vs piece) from a complete catalogue, finding units created after the till loaded; Stock Managers print 50×30 mm thermal stickers for internal codes from Products or straight after a delivery, and can swap any unit's internal code for its factory EAN.

**Out of scope:** camera scanning (needs HTTPS — returns with `planning/04-cleanup.md`), RFID, raw ZPL/TSPL printer drivers, price on labels, "add selling unit" catalog UI, thermal receipts, discounts/VAT, CPMS.

## Locked Decisions

- [Barcode baseline](./decisions/11-barcode-baseline.md): case-insensitive partial-unique `barcode_qr` (blanks allowed); trim + upper on write and scan; `400 BARCODE_TAKEN` naming the holder; writes stay `IsInventoryRole`; audit records barcode before/after.
- [Code source & format](./decisions/12-code-source-format.md): factory EAN-13/UPC-A/EAN-8 kept (GS1 check digit validated → `BARCODE_INVALID`); otherwise `QB` + 6-digit id + `-` + GS1 mod-10 check, e.g. `QB000013-0`; `QB` prefix reserved (`BARCODE_RESERVED_PREFIX`); labels are Code 128.
- [Code assignment](./decisions/16-code-assignment.md): model-level invariant — no unit is ever blank; save derives the `QB` code; PATCH `''` restores it; data migration backfills existing blanks.
- [Scan resolution](./decisions/13-scan-resolution.md): loaded catalogue (complete, per-unit codes) first; miss → `GET /variant-uoms/?barcode=` → reload → add, or "belongs to archived product", or "no product has code".
- [Scan-to-cart](./decisions/17-scan-to-cart.md): whole units add 1 instantly (re-scan merges); measured units open the dialog with the scanned unit preselected; one shared whole-unit constant.
- [Camera scanning](./decisions/15-camera-scan.md): keyboard-wedge only.
- [Label printing](./decisions/14-label-printing.md): `pdf` + `printing`, one page per 50×30 mm sticker, OS print dialog, code + name + unit (no price), QB units only, copies 1–200, Products row menu + bulk action, Receiving post-process pre-fill.
- [Selling-unit codes UI](./decisions/18-unit-codes-ui.md): details dialog lists every unit's code; inventory roles edit via existing `patchSellingUnit`; no create-unit UI.

## Domain & File Impact

**Backend**

- `apps/inventory/models.py` — `VariantUOM`: `Meta.constraints` `UniqueConstraint(Upper('barcode_qr'), condition=~Q(barcode_qr=''), name='uniq_variantuom_barcode')`; `save()` derives code when blank; module helpers `derived_code(id)` + `gs1_check_digit(digits)`.
- `apps/inventory/migrations/` — (1) schema: add constraint; (2) data: `RunPython` backfill blanks → derived code, reverse no-op. Order: data backfill can run before or after constraint (derived codes are unique), keep constraint first so a pre-existing duplicate fails loudly.
- `apps/inventory/serializers.py` `VariantUOMSerializer.validate_barcode_qr` — normalise; charset/length; EAN check digit; reserved prefix; uniqueness pre-check for a readable `BARCODE_TAKEN` (DB constraint remains the real guard → map `IntegrityError` to the same 400).
- `apps/inventory/views.py` `VariantUOMViewSet` — `get_queryset` honours `?barcode=`; `audit_snapshot/audit_changes` add barcode before/after; `IntegrityError` on the unique constraint → `400 BARCODE_TAKEN` (concurrency).
- Seed command — no change needed (model `save()` assigns codes); assert in test.
- Tests: new `apps/inventory/tests_barcodes.py`.

**Flutter**

- `pubspec.yaml` — add `pdf`, `printing` (Task 0 spike decides go/fallback).
- `lib/data/services/products_service.dart` — `fetchCatalogue` → `getAll` for products + batches (F5); new `lookupByBarcode(code)` → `List<VariantUom>` via `?barcode=`.
- `lib/data/models/variant_uom.dart` — expose code helpers: `isInternalCode` (`QB` prefix); normalise helper shared with scan (`trim().toUpperCase()`).
- `lib/features/pos/viewmodels/pos_transaction_viewmodel.dart` — `PosCatalogItem.barcode = uom.barcodeQr` (F3); `findByBarcode` normalises; new `resolveScan(code)` returning hit / archived / not-found / network-error with server fallback + catalogue reload.
- `lib/features/pos/widgets/pos_sale_quantity_dialog.dart` — optional `initial` item (F4); whole-unit set moved to a shared const (e.g. `lib/core/units/whole_units.dart`).
- `lib/features/pos/views/pos_transaction_page.dart` `_handleScan` — branch: whole → `addLine(item, 1)`; measured → dialog with `initial`; outcomes → snackbar; focus restore unchanged.
- `lib/features/products/widgets/products_details_dialog.dart` — per-unit code list + "Edit code" (role-code gated).
- New `lib/features/products/widgets/edit_unit_code_dialog.dart` — PATCH via `ProductsService.patchSellingUnit`, server-code field errors, reload.
- `lib/features/products/widgets/products_form_dialog.dart` — relabel field; keep client duplicate hint (UX only).
- New `lib/features/labels/label_document.dart` — pure `Future<Uint8List> buildLabelPdf(List<LabelRequest>)` (one page per copy, 50×30 mm).
- New `lib/features/labels/label_print_dialog.dart` — unit rows (QB units printable; EAN rows "factory barcode — skipped"), copies field 1–200, Preview/Print via `printing`.
- `lib/features/products/views/products_page.dart` + `products_table.dart` (row menu "Print labels") + `products_bulk_actions.dart` (bulk "Print labels").
- `lib/features/inventory/views/inventory_receiving_page.dart` — after successful `processReceipt`, "Print labels for this delivery" from `ReceivingViewmodel._lastBatches` (base whole unit → copies = received qty; measured base → 1; non-base → 0).

**Contract / docs** — `ENDPOINTS.md` (`?barcode=`, error codes, auto-assign rule), `docs/SYSTEM_ATLAS.md` + `system-atlas.html`, session note.

## Phased Execution Checklist

- [ ] **Task 0 — Printing spike (gate for Task 6).** Add `pdf` + `printing`; render one 50×30 mm Code 128 sticker; open preview/print on **Linux desktop** and **web**. Record result in the session note. If Linux GTK print fails: fall back to save-PDF via existing `file_selector` on desktop (`shortcut:` comment). Revert nothing — the deps stay if it works.
- [ ] **Task 1 — Backend code integrity (RED first).** Constraint + migration; serializer normalise/charset/EAN check/reserved prefix/`BARCODE_TAKEN`; `IntegrityError` → 400. Tests: duplicate different case/whitespace → 400; bad EAN → 400; manual `QB…` not own → 400; own derived code accepted; cashier PATCH → 403; two concurrent PATCHes same code → exactly one 2xx (`TransactionTestCase` + threads, as Phase 1 idempotency tests). **Known-answer vectors (computed 2026-10-28, GS1 mod-10):** id 3 → `QB000003-1`, id 12 → `QB000012-3`, id 13 → `QB000013-0`, id 16 → `QB000016-1`; EAN `4800016123450` valid, `4800016123456` invalid.
- [ ] **Task 2 — Backend auto-assign + backfill + audit (RED first).** `save()` derive; PATCH `''` re-derives; data migration (test via `MigrationExecutor` or direct helper test + `makemigrations --check`); seed leaves zero blanks; audit row `barcode 'QB000003-1' -> '4800016123450'`.
- [ ] **Task 3 — Backend lookup (RED first).** `?barcode=` exact normalised match, `200 []` on unknown, 401 unauthenticated, cashier allowed, returns archived variants too (client decides message).
- [ ] **Task 4 — Flutter catalogue + per-unit identity (RED first).** `getAll` for products + batches (2-page stub test proves item #51); `PosCatalogItem.barcode` per unit; scan of box code resolves box unit (fails today).
- [ ] **Task 5 — Flutter till scan flow (RED first).** `resolveScan` with server fallback + reload; archived / not-found / network-error messages; whole unit instant add + merge on re-scan; measured unit opens dialog with scanned unit preselected; shared whole-unit const; manual browse unchanged.
- [ ] **Task 6 — Flutter labels (after Task 0).** `buildLabelPdf` unit test (page count = Σ copies; each page's payload = its unit code; long names ellipsised; EAN units excluded); `LabelPrintDialog` (copies validation 1–200, skipped EAN rows); Products row menu + bulk action; Receiving post-process pre-fill.
- [ ] **Task 7 — Flutter unit codes UI.** Details dialog lists all units' codes; Edit code dialog with server-error mapping + blank-restores-QB; cashier sees no Edit; form relabel.
- [ ] **Gate.** `docker exec buildpro_backend python manage.py test --noinput` + `check` + `makemigrations --check`; `flutter analyze` + full `flutter test`; hygiene-reviewer (backend, flutter); qa-tester API probes (uniqueness/case, EAN check, reserved prefix, auto-assign on create, PATCH blank, `?barcode=`, cashier 403, backfill leaves zero blanks) + browser E2E (type a `QB` code + Enter in the till scan field ⇒ exact unit added; scan twice merges; metre unit opens dialog; code created after load found via fallback; Products → Print labels preview shows N stickers; Receiving → Print labels pre-filled; edit a unit code to a valid EAN and scan it).
- [ ] **Close.** MAP row 6 ✅, `ENDPOINTS.md`, atlas pair, session note, AGENTS pointer. Audit-remediation map complete.

## Risks

- **`printing` on Linux desktop** depends on GTK print support — Task 0 exists to find out before UI work.
- **Real thermal printer untested in dev** — PDF preview proves layout; first physical print is a user acceptance step (driver scaling must be "actual size / 100 %").
- **Backfill on a non-dev DB with a hand-typed `QB…` code** — the constraint migration fails loudly rather than silently re-coding; resolve by clearing that code first.
