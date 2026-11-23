# 2026-11-23: Store Operations Round 2 & Repository Cleanup

## Focus
Complete Store Operations Round 2 across Django (`backend_django/`) and Flutter (`flutter/`) on `master`, and remove all stale temporary worktrees, merged branches, and obsolete October/early-November planning and session notes.

## What Was Built & Verified
1. **Cashier OR Toggle Auto-Reset:** `PosOfficialReceiptToggle` (`Attach OR?`) in `pos_cart_bar.dart` and `PosTransactionViewmodel` (`submit`, `clear`, `resetSession`) automatically reset `_invoiceNo = null`, `_creditSale = false`, untoggle the switch, and clear the OR input after every completed sale, hold, or cart clear.
2. **Held Transactions Note, Richer Cards & Disappear on Resume:**
   - Holding a transaction prompts for an optional note/identifier (`hold-cart-note-input`).
   - Held Cart cards display `Hold #<id>`, exact date/time, customer, item breakdown (`qty unit productName · subtotal`), reservation expiry badge, and a styled sticky-note box.
   - Resuming a held cart immediately removes it from the Held Transactions tab.
3. **POS-Wide Numeric Input Formatters & Exchange Custom Quantities:**
   - Added shared `decimalInputFormatters()`, `integerInputFormatters()`, and `validateNumericInput()` in `flutter/lib/core/format/numeric_input.dart` and wired them across POS discount, sale quantity, shift opening float, cash-in/cash-out, close shift denomination, return/exchange, and supplier payment dialogs.
   - Added custom replacement quantity input in both the Exchange replacement item picker dialog (`exchange-picker-qty-field`) and Step 3 replacement lines in `pos_returns_page.dart`.
4. **History Custom Date Filters, Requisition Step 2 Layout & Generic OR-Tagged VAT Labels:**
   - Fixed local-timezone comparison (`toLocal()`) and added active range display + `Change dates` / `Clear range` in Transaction History (`sales_transactions_content.dart`).
   - Added `Date` filter chips (`All dates`, `Today`, `This week`, `This month`, `Custom range`) to Payment History (`sales_receivables_content.dart`).
   - Redesigned Requisition Step 2 (`_RequisitionLines` in `material_release_page.dart`) with spaced `Ordered`, `Still to give`, and highlighted `Give now` columns.
   - Replaced `"BIR OR"` labels with generic `"OR-Tagged Only (Official Receipt)"` / `"OR-tagged"` across manager dashboards, reports, and Excel exports.
5. **Store Payables Proof Attachment, Cashier Deliveries Authority & Bodega Handoff, and Stocker Sidebar:**
   - Added `SupplierPayment.proof_attachment` (`0025_supplierpayment_proof_attachment.py`) and `POST /api/v1/supplier-payments/{id}/proof/`, optional file picker in `SupplierPayDialog`, and `No proof attached` warning badge + `Attach / Update proof` action in `SupplierBillDetailsDialog`.
   - Granted Cashiers full store delivery visibility and `Start` / `Delivered` / `Failed` transition authority in `DeliveryViewSet` and `deliveries_page.dart`.
   - Surfaced Bodega-shelved delivery sales in the Bodega Checker's claims queue with `For Delivery · <delivery_no>` badges and delivery address so Bodega can release/load them without double-counting `bodega_stock()`.
   - Removed `Sales` and `Payables` from the Stock Manager (`AppAreas.inventory`) sidebar and moved `Returns` under **Purchasing** as `Supplier returns`.

## Verification
- `flutter analyze`: **0 issues**.
- Django tests (`apps.bodega.tests`, `apps.pos.tests_delivery`, `apps.pos.tests_cash_drawer`): **73/73 passed**.
- Flutter widget & routing tests (`16` suites): **167/167 passed**.
