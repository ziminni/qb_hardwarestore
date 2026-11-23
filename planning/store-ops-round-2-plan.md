# Store Operations Round 2 — Cashier UX, Held Carts, Payables Proof, Deliveries & Role Boundaries

## Destination & Scope

### Destination
Deliver a cohesive, verified round of POS & Store Operations upgrades across the Django backend and Flutter client so that:
1. Cashier checkout, OR toggle reset, held-cart notes & instant resume removal, custom date filters (Transaction History & Payment History), Requisition Step 2 item rows, Exchange custom replacement quantities, and POS-wide numeric input validation all work cleanly without friction.
2. Manager VAT widgets use generic **OR-tagged** wording rather than agency-specific `BIR` labels.
3. Store Payables support optional proof attachments (`proof_image`) on supplier payments with a visible **`No proof attached`** warning badge and a later **`Attach proof`** action.
4. Cashiers can complete all store deliveries (**Start / Deliver / Fail**), while deliveries carrying Bodega-shelved items surface in the Bodega Checker's queue as **For Delivery** loads that Bodega can confirm and dispatch.
5. The Stock Manager (Stocker) sidebar is scoped strictly to stock and purchasing (**Sales** and **Payables** removed; **Returns** moved under **Purchasing** as **Supplier returns**).

### Out of Scope
- Offline-first local SQLite queueing at the till.
- External accounting ERP or bank webhook integrations for supplier payments.
- GPS live-tracking of delivery trucks.

---

## Locked Decisions

1. **Deliveries Completion Authority & Bodega Handoff (`by: me`)**
   - **Choice:** Cashiers can view and transition (**Start / Deliver / Fail**) all store deliveries (both till sales and sales orders) so deliveries never stall when the Store Manager is away. Any delivery whose sale deducted stock from a Bodega shelf surfaces in the Bodega Checker's queue as a **For Delivery** load (distinct from walk-in **Customer Pick-up**), and the Bodega Checker can confirm the load and mark a Bodega delivery dispatched/delivered.
   - **Why:** In daily hardware store operations, the Store Manager is not always at the counter when trucks depart or return, and bulk deliveries frequently load directly from the Bodega.

2. **Store Payables Proof Attachment (`by: me`)**
   - **Choice:** Attaching a proof image/photo (receipt, deposit slip, bank transfer screenshot, or cheque photo) when recording a `SupplierPayment` is **optional** at payment entry. Payments without a file display an amber **`No proof attached`** badge in Payables history with a 1-click **`Attach / View proof`** action so proof can be uploaded later.
   - **Why:** Petty cash or phone-confirmed supplier payments should not be blocked if the photo isn't on the PC yet, while bookkeepers still need a clear visual cue for which payments still need paper proof attached.

3. **Stock Manager (Stocker) Sidebar Tab Set (`by: me`)**
   - **Choice:** Remove **`Sales`** and **`Payables`** from the Stock Manager (`AppAreas.inventory`) sidebar, and move **`Returns`** (supplier returns) under the **Purchasing** section renamed to **`Supplier returns`**.
   - **Why:** The Stock Manager's role is strictly stock and purchasing; customer sales and paying supplier bills belong to the Store Manager and Admin.

4. **Held Carts Resume Lifecycle & Note (`by: delegated`)**
   - **Choice:** Prompt for an optional `note` (`max_length=255`) when holding a transaction; display hold ID, note, timestamp, cashier, customer, item preview, total, and reservation expiry on Held Cart cards; and delete/consume the held cart row as soon as it is resumed into the active till so it disappears immediately from the Held Transactions tab.
   - **Why:** Prevents a cashier from accidentally resuming the same parked basket twice while giving enough context on each card to tell multiple parked customers apart.

5. **POS-Wide Numeric Input Validation (`by: delegated`)**
   - **Choice:** Standardize all numeric fields in the POS flow through shared decimal/integer `TextInputFormatter`s and inline `errorText` / `validator` messages (`lib/core/format/numeric_input.dart`).
   - **Why:** Prevents accidental letters or out-of-range numbers in discount, tender, quantity, cash drawer, and exchange dialogs.

---

## Domain & File Impact

### Django Backend (`backend_django/`)
- **Held Carts (`apps/pos/`):**
  - `apps/pos/models.py`: Add `note = models.CharField(max_length=255, blank=True, default="")` to `HeldCart`.
  - `apps/pos/migrations/0028_heldcart_note.py`: Additive migration for `HeldCart.note`.
  - `apps/pos/serializers.py` & `apps/pos/views.py`: Serialize `note`, `cashier_name`, and item names on `HeldCartSerializer`.
- **Payables Proof Attachment (`apps/inventory/`):**
  - `apps/inventory/models.py`: Add `proof_image = models.ImageField(upload_to="supplier_payments/%Y/%m/", null=True, blank=True)` to `SupplierPayment` and allow a targeted proof-only attachment method `attach_proof()` on the append-only model.
  - `apps/inventory/migrations/0024_supplierpayment_proof_image.py`: Additive migration for `SupplierPayment.proof_image`.
  - `apps/inventory/serializers.py` & `apps/inventory/views.py`: Accept optional `proof_image` on `POST /api/v1/supplier-bills/{id}/payments/` (multipart or JSON) and add `POST /api/v1/supplier-payments/{id}/proof/` (`MultiPartParser`) to attach proof to an existing payment; expose `proof_image_url` and `has_proof` on payment responses.
- **Deliveries & Bodega Handoff (`apps/pos/` & `apps/bodega/`):**
  - `apps/pos/permissions.py` & `apps/pos/views.py` (`DeliveryViewSet`): Allow `IsPOSRole` (Cashier, Store Manager, Stock Manager, Admin) and `IsBodegaRole` to list deliveries and run `start`, `deliver`, and `fail` transitions without restricting Cashiers to `own_scope_field` or `start`-only.
  - `apps/bodega/services.py` & `apps/bodega/views.py`: Include Bodega deductions from delivery-backed sales in `BodegaClaimListView` with `fulfillment_type: "DELIVERY" | "PICKUP"`, `delivery_id`, `delivery_no`, and `delivery_status` so Bodega Checkers see **For Delivery** vs. **Customer Pick-up** and can confirm load & dispatch.

### Flutter Client (`flutter/`)
- **Shared Numeric Validation:**
  - `lib/core/format/numeric_input.dart` & `lib/core/format/money_input.dart`
- **Cashier Till, Held Carts, Requisition & Returns:**
  - `lib/features/pos/widgets/pos_cart_bar.dart` (`PosOfficialReceiptToggle` auto-reset when `invoiceNo` clears)
  - `lib/features/pos/views/pos_transaction_page.dart`, `lib/features/pos/views/pos_held_transactions_page.dart`, `lib/features/pos/widgets/pos_held_cart_card.dart`, `lib/features/pos/viewmodels/held_cart_viewmodel.dart`, `lib/data/models/held_cart.dart`
  - `lib/features/pos/views/material_release_page.dart` (`_RequisitionLines` table/card spacing redesign)
  - `lib/features/pos/views/pos_returns_page.dart` (custom quantity input in Exchange replacement picker and replacement lines)
  - `lib/features/pos/widgets/pos_payment_dialog.dart`, `pos_line_discount_dialog.dart`, `pos_sale_quantity_dialog.dart`, `pos_shift_cash_movement_dialog.dart`, `pos_shift_close_dialog.dart`, `pos_opening_float_form.dart`, `pos_returns_line_row.dart`
- **Transaction History, Payment History & Manager VAT Labels:**
  - `lib/features/sales/widgets/sales_transactions_content.dart` (fix custom date range filtering & chip label state)
  - `lib/features/sales/widgets/sales_receivables_content.dart` (add custom date range filter to Payment History + numeric validation on Record Payment)
  - `lib/features/sales/views/sales_dashboard_page.dart`, `lib/features/admin/views/reports_page.dart`, `lib/features/admin/views/admin_dashboard_page.dart` (generic `OR-tagged` wording)
- **Payables, Deliveries, Bodega & Stocker Navigation:**
  - `lib/features/payables/views/payables_page.dart`, `lib/data/models/payable.dart`, `lib/data/services/payables_service.dart`
  - `lib/features/deliveries/views/deliveries_page.dart`, `lib/features/bodega/views/bodega_pages.dart`
  - `lib/core/navigation/app_destinations.dart` & navigation tests (`test/core/navigation/app_destinations_test.dart`, `test/routes/sidebar_index_consistency_test.dart`, `test/shared/sidebar_pattern_test.dart`)

---

## Phased Execution Checklist

### Phase 1 — Cashier Till, Held Carts Note/Resume & POS Numeric Validation
- [x] 🤖 **1.1 OR Toggle Auto-Reset:** Sync `PosOfficialReceiptToggle` in `pos_cart_bar.dart` with `PosTransactionViewmodel.invoiceNo` so completing or clearing a transaction resets the `Attach OR?` switch to off and clears the text controller.
- [x] 🤝 **1.2 Held Cart Note & Immediate Disappear on Resume:** Prompt for an optional note when clicking **Hold transaction**, enrich `PosHeldCartCard` (hold `#`, note, timestamp, cashier, customer, item preview, total, reservation expiry), and remove the held cart on resume so it disappears from the Held tab immediately.
- [x] 🤖 **1.3 POS-Wide Numeric Input Formatters & Warnings:** Create `lib/core/format/numeric_input.dart` and wire numeric formatters + inline validation warnings across `pos_payment_dialog.dart`, `pos_line_discount_dialog.dart`, `pos_sale_quantity_dialog.dart`, `pos_shift_cash_movement_dialog.dart`, `pos_shift_close_dialog.dart`, `pos_opening_float_form.dart`, and `pos_returns_line_row.dart`.
- [x] 🧑 **1.4 Exchange Custom Replacement Quantity:** Add direct numeric quantity input (with validation) in the Exchange replacement item picker dialog and on each replacement line in `pos_returns_page.dart`.
- [x] 🤖 **1.5 Verify Phase 1:** Run Django held-cart tests, `flutter analyze`, and targeted POS widget tests (`pos_held_*`, `pos_exchange_test.dart`, `pos_discount_mode_test.dart`, `pos_cash_drawer_test.dart`).

### Phase 2 — Custom Date Filters, Requisition Step 2 Layout & Generic OR-Tagged VAT Labels
- [x] 🤝 **2.1 Fix Transaction History Custom Date Range:** Fix custom date range chip selection, local-date comparison, and active range display in `sales_transactions_content.dart` so selecting a custom range reliably filters and shows the chosen dates on the chip.
- [x] 🤖 **2.2 Add Custom Date Filter to Payment History:** Add `Date` filter chips (`All dates`, `Today`, `This week`, `This month`, `Custom range`) to the Payment History tab in `sales_receivables_content.dart`.
- [x] 🤖 **2.3 Redesign Requisition Step 2 Item Rows:** Rebuild `_RequisitionLines` in `material_release_page.dart` with clear column headers, distinct spacing/pills for `Ordered`, `Still to give`, and `Give now`, and responsive wrapping on narrow widths.
- [x] 🧑 **2.4 Generic OR-Tagged VAT Wording:** Replace remaining user-visible `"BIR OR"` labels in `sales_dashboard_page.dart`, `reports_page.dart`, `admin_dashboard_page.dart`, and `reports_excel_export.dart` with generic `"OR-tagged"` / `"Official Receipt (OR)"` wording.
- [x] 🤖 **2.5 Verify Phase 2:** Run `flutter analyze` and targeted tests (`sales_transactions_content`, `sales_receivables`, `material_release`, `vat_period_reports_test.dart`, `reports_excel_export_test.dart`).

### Phase 3 — Payables Proof Attachment, Deliveries & Bodega Handoff, and Stocker Sidebar Cleanup
- [x] 🤝 **3.1 Store Payables Proof Attachment:** Add `SupplierPayment.proof_attachment` (`0025_supplierpayment_proof_attachment.py`) and `POST /api/v1/supplier-payments/{id}/proof/`, add optional proof file/photo picker to the Record Payment dialog in `supplier_pay_dialog.dart`, and render the **`No proof attached`** warning badge + **`Attach / Update proof`** action on payment rows.
- [x] 🤖 **3.2 Cashier Deliveries Authority & Bodega Handoff:** Allow Cashiers to view and **Start / Deliver / Fail** all deliveries in `DeliveryViewSet` and `deliveries_page.dart`; surface Bodega-sourced delivery loads in `BodegaClaimListView` and the Bodega Checker UI with a **`For Delivery`** badge and dispatch action.
- [x] 🧑 **3.3 Stock Manager Sidebar Cleanup:** Remove `Sales` and `Payables` from `AppAreas.inventory` in `app_destinations.dart`, move `Returns` under `Purchasing` as `Supplier returns`, update `selectedNavigationIndex` on affected inventory pages, and update navigation tests.
- [x] 🤖 **3.4 Verify Phase 3:** Run Django tests (`apps.inventory`, `apps.pos`, `apps.bodega`), `flutter analyze`, and Flutter tests (`payables`, `deliveries`, `bodega`, `app_destinations_test.dart`, `sidebar_index_consistency_test.dart`).
