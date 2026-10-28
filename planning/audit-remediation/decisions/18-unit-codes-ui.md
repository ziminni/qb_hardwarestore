# Selling-Unit Codes UI

**Status:** ✅ Locked 2026-10-28 (user chose show + edit codes for every existing unit)
**Mode:** Grill

## Question

The Products UI only creates/patches a variant's factor-1 unit (`products_repository.dart:68,97`). Non-base units (box of 100) exist only via API/admin. How far does Phase 6 go in exposing their codes?

## Decision

**Show and edit the code of every existing selling unit; do not add a "create selling unit" UI.**

- **Product details dialog** lists every selling unit of each variant: unit · conversion factor · code, with "Edit code" for inventory roles (role-code check `inventory`/`sales`/`admin` — Phase 4 lesson, never display names).
- **Edit code dialog:** one field, uses existing `ProductsService.patchSellingUnit` (`PATCH /variant-uoms/{id}/ {barcode_qr}`), then reloads the catalogue. Blank = restore the unit's own `QB` code ([Code assignment](./16-code-assignment.md)). Server codes `BARCODE_TAKEN` / `BARCODE_INVALID` / `BARCODE_RESERVED_PREFIX` map to field errors naming the reason.
- **Product create/edit form** barcode field relabelled "Factory barcode (leave blank to auto-generate)"; edit shows the base unit's current code.
- The variant-level `ProductVariant.barcode` getter (first non-blank) stays only for product **search**; nothing that identifies a unit may use it ([Barcode baseline](./11-barcode-baseline.md) F3).

## Rejected

- **Add-selling-unit UI** — needs conversion-factor/price/validation UX; separate catalog feature (Out of Scope).
- **Base unit only** — box codes reachable only through Django admin.

## Edge cases (RED-first, widget/service tests)

- Details dialog for a 2-unit variant shows both codes.
- Cashier role → no "Edit code" button.
- `BARCODE_TAKEN` → field error, dialog stays open, catalogue unchanged.
- Blank submit → PATCH `''`, reload shows the `QB` code.
