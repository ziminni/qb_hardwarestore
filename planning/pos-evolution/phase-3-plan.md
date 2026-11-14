# Phase 3 — Excel catalogue round-trip

**Status:** [ ] Planned 2026-11-12, not authorized. Builds after Phase 9 (order 6 → 7 → 8 → 9 → **3** → 2). Decision: [23 Excel catalogue round-trip](./decisions/23-excel-catalogue-round-trip.md). Same binding rules as [Phase 4](./phase-4-plan.md#rules-that-bind-every-task). Source references below were checked against `864a667` + working tree on 2026-11-12; re-verify at phase start (Phases 6–9 will have moved lines, and Phase 9 makes `Product.stored_at` the stock "home").

## Goal

Stock Manager, Store Manager and Admin export the catalogue (products, variants, selling units, prices, barcodes) to `.xlsx`, edit it in Excel, and re-import it: preview first, apply only with zero row errors, all-or-nothing, never touching stock.

## Rules that bind every task

- Server is the trust boundary: every rule lives in Django; the Flutter parser only shapes rows. One set of rules: the import calls the existing serializers, not copies of them.
- RED first, with output. Backend lane sequential; at most two Flutter lanes on disjoint files. Migrations on the Django test DB only; **no dev DB start/migrate/reset** (`buildpro_backend` entrypoint migrates).
- Copy: sentence case, no em dashes; every row error says the row, the column and what to type instead.

## Source facts this plan relies on

- No xlsx package today: `flutter/pubspec.yaml:19` has only `file_selector: ^1.1.0`; `pdf`/`printing` at `:21-22`.
- Save path to reuse: `BarcodeListFileExporter.saveCsv` (`flutter/lib/features/labels/barcode_list_dialog.dart:48-56`, `getSaveLocation` + `XFile.fromData(...).saveTo`). Open path to reuse: `ImageFileService` `openFile(acceptedTypeGroups:)` (`flutter/lib/data/services/image_file_service.dart:6,17`).
- Formula escaping: private `_textField` (`flutter/lib/features/labels/barcode_list_csv.dart:70-71`, leading `'` for `= + - @ TAB CR`).
- Products page button row and role gate: `products_page.dart:333-345`, `canExportBarcodeList` (`barcode_list_dialog.dart:18-19`, codes `inventory/sales/admin`). Page routed at `routes.dart:471` (inventory shell).
- Serializers: `ProductSerializer` (`backend_django/apps/inventory/serializers.py:503`, active-location rule `:532`), `ProductVariantSerializer` (`:436`, `FROZEN_AFTER_CREATION` `:480`, thresholds `:482`), `VariantUOMSerializer` (`:212`, `FROZEN_ONCE_SOLD` `:261`, `validate_barcode_qr` `:306`, one base unit `:368`), `selling_unit_freeze_reason` (`:175`), `unit_in_use` (`:124`).
- Barcode race: `_refuse_lost_barcode_race` (`apps/inventory/views.py:100`) on `uniq_variantuom_barcode` (`models.py:303`). Audited writes: `_AuditedCatalogViewSet` (`views.py:210`), `VariantUOMViewSet.audit_changes` (`views.py:419`), `audit_request` (`apps/users/services.py:35`), `AuditLog.ActionType` (`apps/users/models.py:145`, CREATE/UPDATE `:149-150`).
- Roles: `IsInventoryRole` (`apps/users/permissions.py:180`). Refusal base: `CatalogWriteRefused` (`apps/inventory/exceptions.py:8`).
- Model shape: `Product.category`/`brand` required (`models.py:209-212`), `stored_at` (`:222`), `is_active` (`:228`); `ProductVariant.variant_name`/`base_uom`/`min_stock_threshold`/`is_active` (`:248-261`); `VariantUOM` has **no** `is_active` (`:274-287`). Latest migrations: users `0005_delivery_audit`, inventory `0011_*` (Phase 6–9 will add more).

## Rulings (2026-11-12)

1. **Brand column added** (by: me): matched by name like Category, must exist, listed on the Lists sheet; existing rows may change brand.
2. **Active stays product-level** (by: delegated): maps to product `is_active` (selling units have no active flag; variant `is_active` not exposed). Rows of one product disagreeing on Active, Category, Product name, Stored at or Brand are row errors.

## Package choice (S0 confirms)

- **Primary: `excel`** (pub.dev, MIT, pure Dart): `Excel.decodeBytes` reads, `Excel.createExcel()` + `encode()` gives bytes we hand to the existing `XFile` save path (not its own `save()` download), `TextCellValue` keeps barcodes/IDs as text.
- **Fallback: `excel_community`** (MIT fork of `excel`, same API, states web + desktop). Rejected: `syncfusion_flutter_xlsio` (write-only, commercial licence).

## Execution file scope

- **S0 spike:** throwaway scratch under `temp/p3/spike/` (gitignored), plus `flutter/pubspec.yaml`/`pubspec.lock` only once a package is chosen.
- **B1/B2 backend:** new `backend_django/apps/inventory/catalogue_import.py` (service), `views.py` (one `CatalogueImportViewSet` or two `APIView`s), `urls.py`, `exceptions.py`, new `tests_catalogue_import.py`; `apps/users/models.py` + one choices-only migration for the summary action; `ENDPOINTS.md`.
- **F1 export:** new `flutter/lib/features/catalogue_io/` (`catalogue_sheet.dart` columns/row mapping, `catalogue_xlsx.dart` writer, `catalogue_io_dialog.dart` exporter interface like `BarcodeListExporter`); shared escape helper extracted from `barcode_list_csv.dart` (CSV behaviour unchanged, its tests pin it); `products_page.dart` (owns both buttons); tests under `flutter/test/features/catalogue_io/`.
- **F2 import (after B1 wire and F1):** `catalogue_io/` reader, `catalogue_import_service.dart`, viewmodel, preview dialog; tests. No edit to `products_page.dart` beyond enabling the Import button F1 placed.

## Execution checklist

- [x] **S0 — 🤖 Package spike — DONE 2026-11-14: `excel` REJECTED (every version caps `xml <7.0.0`; `pdf ^3.13.1` needs `xml ^7.0.1` — unresolvable); fallback `excel_community ^2.6.2` CHOSEN (shares `xml 7.0.1` + `archive 4.5.2` with pdf/printing; import `package:excel_community/excel_community.dart`; `Excel.encode()` → `List<int>?`). Proven in a throwaway worktree at `3791279`: pub get OK, `flutter build web` + `flutter build linux` OK via a probe entrypoint, round-trip test RED→GREEN (`0012345678905` stays text, `=SUM(A1)` stays a literal). Unverified: web `openFile`+`readAsBytes` (needs a browser gesture), LibreOffice re-save, wasm. F1 adds the pubspec line (expect lock churn: `excel_community` + `equatable`). Evidence `temp/p3/spike/report.md`.** Original brief: Add `excel`; `flutter pub get` resolves beside `pdf`/`printing` (shared `archive`/`xml`); `flutter build web` and `flutter build linux` succeed; unit test round-trips `TextCellValue('0012345678905')` and a `'=SUM(A1)` name through encode → `decodeBytes` unchanged; `openFile` + `readAsBytes` works on web. Record the choice, versions and evidence here. Fallback to `excel_community` on any failure; both fail → stop and ask.
- [ ] **B1 — 🤝 Preview (backend validation).** `POST /api/v1/catalogue-import/preview/` `{rows:[...]}` (IsInventoryRole). RED tests first. Per row: >2,000 rows → `CATALOGUE_IMPORT_TOO_LARGE` (whole request); IDs that don't exist, or a Variant ID not under its Product ID, or a Unit ID not under its Variant ID → row error; Category/Stored at/Brand/Unit code matched case-insensitive by name/code and must exist (inactive Stored at refused by `ProductSerializer.validate`); ID rows run the existing serializers with `partial=True` (barcode normalisation/GS1/uniqueness, freeze via `selling_unit_freeze_reason`, thresholds ≥ 0); blank-ID rows grouped into new products/variants by name and validated as creates; exactly one Units-per-base = 1 row per variant (base unit = `base_uom`); duplicate barcodes inside the file → row error. Returns `{creates, changes:[{row, field, before, after}], unchanged, errors:[{row, column, code, message}], fingerprint}`. Fingerprint = hash of `(model, pk, updated_at)` of every referenced row plus the normalised payload. Zero writes, asserted by query/row counts. Stock and batches untouched in every test.
- [ ] **B2 — 🤝 Apply (backend transaction).** `POST .../apply/` with the same rows + `fingerprint`. One `transaction.atomic`: `select_for_update` on referenced products/variants/units in PK order, re-run B1 validation, recompute fingerprint; mismatch → 409 `CATALOGUE_PREVIEW_STALE` ("Run the preview again"); any row error → 400 with the error list, nothing written. Writes through the serializers; per changed record one CREATE/UPDATE audit row (reuse `VariantUOMViewSet.audit_changes` wording for price/barcode) plus one summary row (new `CATALOGUE_IMPORT` action, choices-only users migration). `IntegrityError` on `uniq_variantuom_barcode` caught **outside** the atomic block via `_refuse_lost_barcode_race` → whole import refused, nothing saved. Tests: happy path, partial failure leaves zero writes and zero audit rows, stale preview, concurrent barcode race, in-use unit factor change refused but price change allowed, stock totals identical before/after, role matrix (Cashier 403). `ENDPOINTS.md` updated. Full backend + check + drift.
- [ ] **F1 — 🤖 Export (after S0).** "Export to Excel" button beside "Barcode list" for `inventory/sales/admin`. Sheet 1 one row per selling unit in decision 23's column order plus a Brand column (owner ruling 2026-11-12); IDs, barcodes, unit codes written as text; prices/factors/thresholds as numbers; text cells escaped by the shared helper; sheet "Lists" with active categories, unit codes, active locations (and brands). Data from existing catalogue/product services; save via the `getSaveLocation` + `XFile.saveTo` path. Tests: row mapping, leading-zero barcode text, escaped names, header order pinned, cancelled save is silent.
- [ ] **F2 — 🤖 Import + preview (after B1 wire, F1).** "Import from Excel": `openFile` (`.xlsx` type group) → parse sheet 1 by header names (missing/renamed header → one clear refusal); cells to strings, Excel numbers normalised (`12.0` → `12`), the export's leading `'` stripped only before `= + - @ TAB CR`; >2,000 rows refused before upload. Preview dialog (`AppDialog` family, `DataPanel` for errors): counts for creates/changes/unchanged, error table row/column/message, change list before → after; Apply disabled while errors > 0; 409 stale shows "Run the preview again"; unknown codes show server detail; success refreshes the products list. Tests: exported file re-imported unchanged = all rows "unchanged" (round-trip), parser edge cases, dialog states, double-apply guarded.
- [ ] **Task close — 🤖** Whole-change review (`hygiene-reviewer`); full gates (backend tests + check + drift on the isolated QA container, Flutter analyze/test `--concurrency=2`, goldens: only intended products-page captures change, inspected); isolated QA on the disposable stack (`docs/testing/QA-PROFILE.md`, re-verify `172.20.0.*` network first): export a seeded catalogue, open in LibreOffice, edit price/barcode/name, add a product, re-import, preview, apply; a bad row blocks apply; stale preview refused; stock unchanged by read-back. Docs: `ENDPOINTS.md`, `docs/SYSTEM_ATLAS.md` + `docs/system-atlas.html`, MAP status. Owner closure.

## Orchestration

S0 first. Backend B1 → B2 sequential. Flutter lane A: F1 after S0; lane B: F2 after B1 wire + F1. Controller runs full suites/goldens; focused tests per builder.

## Out of scope

Stock counts or adjustments through the file; deletes (archive via Active = no); CSV import; images/descriptions; supplier or price-history sheets; creating categories, units, brands or locations from the file; server-side file handling.
