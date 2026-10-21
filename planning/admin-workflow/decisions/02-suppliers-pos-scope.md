# D-02 Suppliers and Purchase Orders Scope

**Status:** Locked 2026-10-22
**Type:** Grill (human-in-the-loop)

## Question

`SuppliersPurchasesViewmodel` holds hardcoded `_suppliers` and `_purchases` lists. `saveSupplier` / `addPurchase` mutate in-memory and show "saved in mock data" snackbars. The backend has `SupplierViewSet` + `PurchaseOrderViewSet` fully wired. What write scope?

## Decision: Read-only live list, no create/edit

Wire `GET /api/v1/suppliers/` and `GET /api/v1/purchase-orders/` to replace hardcoded data. Remove mock snackbars and mock mutators. No create/edit — write scope deferred to Fog. This fixes Stocker Purchasing tabs and Admin view simultaneously.

## Wire contracts (verified)

**SupplierSerializer:**
`id, company_name, contact_person, phone, email, address, is_active, created_at, updated_at`

**PurchaseOrderSerializer:**
`id, supplier (int FK), created_by, created_by_name, order_date, expected_delivery, status (DRAFT/ORDERED/PARTIAL/COMPLETE/CANCELLED), notes, items[], created_at, updated_at`

**POItemSerializer:**
`id, po, variant (int FK), variant_name (from variant.variant_name), ordered_qty, unit_cost, received_qty`

**Permission:** read = `IsAuthenticated` (all roles); write = `IsInventoryRole`.

## Key invariant

`PurchaseOrderSerializer` returns `supplier` as int FK — no `supplier_name` field. Viewmodel resolves display name by matching `supplierId` against the already-loaded suppliers list. No backend change needed.

## Files affected

- `flutter/lib/data/models/supplier.dart` — add `Supplier.fromJson`, `PurchaseOrder.fromJson`, `PurchaseItem.fromJson`
- `flutter/lib/data/services/supplier_service.dart` (NEW)
- `flutter/lib/data/repositories/supplier_repository.dart` (NEW)
- `flutter/lib/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart` — replace hardcoded lists with `load()`, remove `saveSupplier`/`addPurchase`
- `flutter/lib/features/suppliers/views/suppliers_page.dart` — load-on-open, remove mock snackbar, remove/grey Add Supplier button
- `flutter/lib/features/suppliers/views/purchases_page.dart` — load-on-open, remove mock snackbar, remove/grey New PO button

## Cost if wrong

Supplier name shows empty string if supplier not in loaded list (e.g. deleted supplier). Acceptable — shows PO id as fallback.
