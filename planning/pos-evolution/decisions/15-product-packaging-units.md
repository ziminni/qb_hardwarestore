# How a product is sold: packaging units replace the old tracking step

**Mode:** grill + research · **Status:** ✅ Locked 2026-11-10 (by: me) · reopens the "no add-unit UI" part of audit-remediation decision 18

## Context (research, 2026-11-10)

- Teammate branch `origin/ui/frontend-progress` (`22ca7e8`) shows Add product step 2 "How is this product tracked?" and step 3 "Pricing & Initial Stock". The same steps existed in our form at merge base `857f333`. They were **mock-only**: method (quantity/weight/length/volume), base unit word list, stock form, package type × size, partial/cut/fractional switches, cost, initial quantity, reorder level and storage location went into an in-memory map keyed by product name and never reached the server.
- Our branch removed them in `da985e6` (2026-10-25, audit-remediation Phase 4) with the locked rule "first stock arrives via purchase order + Receiving; Add product creates catalogue only". Tracking/packaging/location went in the same commit without their own decision.
- Bug at HEAD: `products_details_dialog.dart` still renders that mock "Inventory Tracking" section via `ProductTrackingViewmodel` (registered in `main.dart`), matched by product name. Seed names "Portland Cement" and "PVC Pipe" equal the mock keys, so the demo shows invented data ("By Weight, 4,000 kg, Rack A-01").
- Server today: `ProductVariant.base_uom` plus extra `VariantUOM` rows (own `conversion_factor`, `default_selling_price`, unique `barcode_qr`) are already priced, scanned and FIFO-deducted by the till. `conversion_factor` is 2dp, minimum 0.01, so the base unit must be the smallest counted unit. Client already has `ProductsService.createSellingUnit` and `InventoryViewmodel.setLocationHint` with no screen calling them. Seed creates only BAG, PC, RL units. Whole-vs-fractional quantity is a client-side unit-code list (`flutter/lib/core/units/whole_units.dart`), not a server rule.
- Full findings: local `temp/design-audit/stock-manager.md` (gitignored).

## Decision

- Add product's second step becomes **"How is this product sold?"**: base unit plus optional extra selling units ("Bag = 40 kg at ₱270"), saved as real `VariantUOM` rows through the existing endpoint; each gets its auto QB code (Phase 6).
- **Storage location** returns on the form.
- **Delete** the mock tracking section and `ProductTrackingViewmodel`; nothing invented is shown.
- **Unchanged:** no initial stock or cost on Add product (purchase order + Receiving stays the only way stock arrives).

## Consciously not covered

Stock form, per-product cut/partial switches, tracking individual piece lengths or open-bag leftovers. These need new server fields and till rules; revisit only on request.

## Still open (next decisions)

Adding units to existing products and editing/removing units after creation; where missing units such as kg, m, L come from; whether the whole-number rule should move to the server.
