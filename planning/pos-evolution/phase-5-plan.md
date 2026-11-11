# Phase 5 — Back office: PO by package, supplier payables, delivery, bodega lite

**Status:** [ ] Pending (after [Phase 4](./phase-4-plan.md)). Decision: [18 Panel feedback](./decisions/18-panel-feedback-2026-11.md). Same binding rules and orchestration as Phase 4.

## Goal

Panel comments #11, #7 (with PO discount/VAT), #8, #9-lite.

## Execution checklist

- [ ] **B1 — 🤖 PO by package (backend).** `POItem.variant_uom` (FK VariantUOM of the same variant; migration backfills each line to its variant's base unit), `ordered_qty`/`unit_cost` in that unit; whole-unit rule by that unit. Receiving quantities in the line's unit; batch `qty = received × factor`, landed cost per base = unit cost ÷ factor. Old lines keep meaning (factor 1). Tests `apps.inventory`.
- [ ] **B2 — 🤖 Supplier payables (backend).** PO header `discount_amount`, `vat_inclusive` (default true, rate from store settings) for totals. `Supplier.terms_days` (default 0). Processing a goods receipt creates one `SupplierBill` (received value less its share of PO discount, VAT shown, due date) atomically. `SupplierPayment` (cash/cheque/bank transfer, reference, cheque no./bank/date, partial, ≤ balance, locks, audited) by Store Manager/Admin; Stock Manager read. Endpoints: bills (filter supplier/status/overdue), payments, per-supplier balance. Codes `OVERPAYMENT`, `BILL_PAID`. Tests `apps.inventory` (+ new app if cleaner).
- [ ] **B3 — 🤖 Delivery (backend).** `Delivery` linked to a sale or a sales order: address, contact name/phone, scheduled date, fee, status SCHEDULED → OUT_FOR_DELIVERY → DELIVERED / FAILED (reason). Fee enters the sale/order total as a "Delivery charge" (VAT-inclusive, no stock). Transitions only forward, locked, audited; Store Manager, Admin, Stock Manager. List filter by status/date. Tests `apps.pos`.
- [ ] **B4 — 🤖 Stored at (backend).** `StorageLocation` (name, active; Admin-managed; seeded Store, Bodega) and `Product.stored_at` (default Store). Exposed on products, till catalogue, sale lines, delivery slip data. Tests `apps.inventory`.
- [ ] **F1 — 🤖 PO form and receiving by package** (after B1): unit picker per line, "10 BAG = 250 kg" helper, cost per unit, receiving counts in that unit.
- [ ] **F2 — 🤖 Supplier payables screens** (after B2): Payables page (bills, overdue first, balance per supplier), pay dialog (method, reference, cheque fields, partial), supplier terms on supplier form, PO discount/VAT and totals on PO form/details. Store Manager/Admin pay; Stock Manager read-only.
- [ ] **F3 — 🤖 Delivery UI** (after B3): Deliver toggle in payment dialog and sales order form (address, contact, date, fee); Deliveries page with status actions and failure reason; printable delivery slip (items, stored-at pick-up point, fee).
- [ ] **F4 — 🤖 Stored at UI** (after B4): product form/details field, Admin list of locations, till line badge "Bodega", receipt "Pick up at Bodega".
- [ ] **Task 9 — 🤖 Close.** Whole-change review, full gates, one isolated QA run, docs, owner closure.

## Out of scope

Stock counts per location and transfers; delivery routing/drivers/vehicles; supplier cheque clearing; supplier credit notes/returns to supplier.
