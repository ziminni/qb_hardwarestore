# Excel catalogue round-trip

**Status:** Locked 2026-11-12 (by: me — owner answers; defaults marked *delegated*)
**Phase:** 3

## Context

Research (2026-11-12): no Excel/CSV package in Flutter or backend; the server produces no files. The barcode-list CSV export (`flutter/lib/features/labels/`) already saves on web and desktop through `file_selector` with formula-injection escaping. Catalogue writes are per-row ModelViewSets with rich validation (barcode normalisation/GS1/uniqueness and race mapping, one base unit, in-use freeze of unit/factor, active storage location, audited writes in `_AuditedCatalogViewSet`). There is no bulk endpoint.

## Decisions

1. **Format:** real **.xlsx**, read and written in the Flutter app with one added package; the server stays file-free and receives parsed rows as JSON. (by: me)
2. **Power:** rows **with a system ID update** that product/variant/selling unit (name, category, price, barcode, low-stock threshold, stored at, active); rows **without an ID create** new products and selling units. Units already sold, ordered or requested keep their unit and size (price/barcode still editable). **Never touches stock.** (by: me)
3. **Bad rows:** upload shows a **preview** (creates, changes, unchanged, and every row error). **Apply is allowed only with zero errors** and saves everything in **one transaction**. (by: me)

## Delegated defaults (owner may override)

- **One sheet, one row per selling unit**, columns: Product ID, Variant ID, Unit ID, Category, Product name, Variant, Unit code, Units per base, Price, Barcode, Low-stock threshold, Stored at, Active. A product's base unit is the row with Units per base = 1. A second "Lists" sheet carries the valid categories, unit codes and locations.
- **Server-side validation:** a new `POST /api/v1/catalogue-import/preview/` and `/apply/` (Stock Manager, Store Manager, Admin) reuse the existing serializers row by row, so there is one set of rules. Apply re-validates under locks; if anything changed since the preview, it refuses and asks for a new preview.
- **Audit:** one audit row per changed record plus one summary row for the import.
- **Limits:** up to 2,000 rows per file; IDs that don't exist or belong to another product are row errors; categories and storage locations are matched by name, case-insensitive, and must already exist.
- **Export** escapes formula-like text like the barcode CSV, and stores barcodes as text so Excel keeps leading zeros.

## Consequences

- One new Flutter dependency (xlsx read/write), chosen at build time for web + desktop support.
- No deletes through import; archiving is `Active = no`.

## Follow-up rulings (2026-11-12)

- **Brand column added** (by: me): new products need a brand (`Product.brand` is required); the sheet gains a Brand column matched by name like Category, and existing rows may change brand.
- **Active stays product-level** (by: delegated, owner said "decide what is best"): `Active = no` archives the whole product, as the form does. No per-unit archiving: it would touch every unit picker (till, orders, PO, CPMS list) for little gain, and never-used units can already be removed.
