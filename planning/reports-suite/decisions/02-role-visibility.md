# Role visibility per report

**Locked (by: me, 2026-11-23):**
- **Admin & Store Manager (`IsManagerRole`):** Full access to all Sales, VAT, Requisition, and Inventory reports + KPIs + PDF/Excel exports.
- **Stock Manager (`IsInventoryRole` — Admin, Store Manager, Stock Manager):** Access to the Inventory reports catalogue (Current stock & valuation, Stock movement, GRN, STN, FIFO/batch age, Expiry, Shrinkage, Stock adjustments, Reorder, Dead stock, Fast/Slow movers, Cycle count) + PDF/Excel exports. No access to Sales, VAT, Profit/Margin, or Cashier performance reports (`403 Forbidden`).
- **Cashier:** Keeps existing Shift X/Z-reading in the till; no Reports suite tab.

## Backend & UI impact
- Inventory report endpoints under `/api/v1/reports/` use `@permission_classes([IsInventoryRole])`; Sales and VAT report endpoints remain `@permission_classes([IsManagerRole])`.
- In Flutter, `InventoryReportsPage` renders the shared Reports catalogue filtered to the Inventory section (`Sales` section hidden for Stock Manager-only accounts; merged multi-role accounts see sections matching their active/held roles).
