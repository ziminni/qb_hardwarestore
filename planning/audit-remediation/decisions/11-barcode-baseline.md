# Barcode Baseline — Findings, Uniqueness, Write Authority

**Status:** ✅ Locked 2026-10-28 (research — verified in source and dev DB, no human choice needed)
**Mode:** Research

## Verified findings

| # | Finding | Evidence |
|---|---|---|
| F1 | `VariantUOM.barcode_qr` exists: `CharField(max_length=100, blank=True, default='', db_index=True)`, **not unique**. | `backend_django/apps/inventory/models.py:144` |
| F2 | Dev DB: 15 selling units, **15 blank, 0 duplicates**. Nothing to de-duplicate. | `docker exec buildpro_backend python manage.py shell` 2026-10-28 |
| F3 | **Scan resolves the variant, not the selling unit.** Every till catalogue line takes `barcode: record.variant.barcode` — the *first* non-blank code across the variant's units (`flutter/lib/data/models/product.dart:43`) — instead of its own `uom.barcodeQr`. A box label and a piece label cannot be told apart. | `flutter/lib/features/pos/viewmodels/pos_transaction_viewmodel.dart:402` |
| F4 | **Scan dialog ignores the scanned unit.** `PosSaleQuantityDialog` always preselects `widget.options.first`. | `flutter/lib/features/pos/widgets/pos_sale_quantity_dialog.dart:27` |
| F5 | **Till catalogue truncates at 50 rows.** `fetchCatalogue` calls `getList` (one page, `PAGE_SIZE` 50) for both products and batches, not `getAll`. Product #51+ is unsearchable and unscannable; batch #51+ understates stock. Invisible in dev (9 products / 17 batches). | `flutter/lib/data/services/products_service.dart:69-70`, `api_client.dart:215`, `config/settings.py:177` |
| F6 | Selling-unit writes are already `IsInventoryRole` (Stock Manager / Store Manager / Admin) and audited in-transaction, but the audit diff records **price only** — a barcode change leaves a row saying "Selling unit … updated" with no before/after. | `apps/inventory/views.py:236-250`, `apps/users/permissions.py:105` |
| F7 | Client-side duplicate check exists in the product form (`products_form_dialog.dart:227-239`) but only against loaded rows — UX hint, not integrity. | — |
| F8 | No barcode / PDF / printing / camera package in `pubspec.yaml`. Targets present: web, linux, windows, android. Django 5.2.18 (supports conditional expression `UniqueConstraint` on PostgreSQL). | `flutter/pubspec.yaml` |

## Locked

1. **Uniqueness at the DB.** `UniqueConstraint(Upper('barcode_qr'), condition=~Q(barcode_qr=''), name='uniq_variantuom_barcode')`. Blanks stay allowed and unlimited. Migration is safe (F2: zero duplicates).
2. **Normalise on write.** Serializer trims whitespace and upper-cases before save; a clash returns `400 BARCODE_TAKEN` naming the holder (product · variant · unit) — inventory roles may already read every catalog row, so naming it leaks nothing.
3. **Scan normalises the same way** (trim + upper) so stored and scanned values compare equal.
4. **Write authority unchanged:** `IsInventoryRole`; cashiers never assign codes.
5. **Audit the code:** extend `VariantUOMViewSet.audit_snapshot/audit_changes` with `barcode '' -> 'QB…'`.
6. **F3, F4, F5 are defects, not decisions** — they are Phase 6 build tasks regardless of how the frontier resolves.

## Abuse cases (RED-first tests)

- Duplicate code, different case / padded whitespace → `400 BARCODE_TAKEN`, nothing saved.
- Cashier PATCH `barcode_qr` → 403.
- Concurrent assignment of the same code to two units → exactly one 2xx (DB constraint, not check-then-act).
- Barcode change → one audit row with before/after.
