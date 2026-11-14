# Panel feedback after the presentation (12 comments)

**Mode:** grill · **Status:** ✅ Locked 2026-11-11 (by: me; small defaults by: delegated, marked ⚙)

## Context (research 2026-11-11, two read-only code audits)

| # | Comment | Found in code |
|---|---|---|
| 1 | VAT, discount (till and PO) | `SalesTransaction.vatable_sales/vat_amount/discount_amount` exist but checkout writes VAT 0 and hard-zeroes discount (`apps/pos/services.py`); no till input; D12 removed Discounts from reports. PO has neither. |
| 2 | Pagination | DRF 50/page; app walks all pages (`getAll`) and lazy-scrolls; no page controls. |
| 3 | Low stock warning | **Exists**: `min_stock_threshold` (editable in product form, shown on details), `SystemAlert` LOW/OUT, Low stock page, restock panel, notifications, resolve. |
| 4 | UX flow per role | Prose only (README, atlas). |
| 5 | Barcode masterlist | 50×30 label printing only; no list export; `pdf`/`printing` already installed. |
| 6 | Multiple payments, cheque | Server checkout already takes `payments[]`; till sends one. Methods CASH/CARD/GCASH/BANK_TRANSFER; no cheque. |
| 7 | Store's own payables | Missing. Supplier has contact fields; PO statuses only. |
| 8 | Delivery + charge | Missing for customers. Sales order statuses CONFIRMED/PROCESSING/READY/COMPLETED. |
| 9 | Bodega/warehouse | No location model; shelf location is a device-only hint. |
| 10 | Multiple roles per account | Server role checks accept any group; API reports first group; app enters one area. |
| 11 | PO bulk vs piece | `POItem` and receiving are base-unit only. |
| 12 | Sales feature | Exists: Store Manager area = transactions, quotations, sales orders, receivables, reports. No group named "Sales". |

## Decision

All twelve are answered before testing, in two major phases (one whole-change review + one QA run each, owner's request to save time):

**Phase 4, front counter:** #2, #4, #5, #10 lite, #1 (till part), #6. #3 and #12 need no build: demo and answer.
**Phase 5, back office:** #11, #7 (with PO discount/VAT, #1 PO part), #8, #9 lite.

Owner rulings:
- **VAT:** shelf prices include 12% VAT. Receipt, sale detail and reports show Vatable sales = net ÷ 1.12 and VAT = net − vatable, computed on the server after discount. An Admin setting turns VAT off (receipt says "Non-VAT") and holds the rate.
- **Discount:** whole-sale discount, ₱ or %, reason required, applied by the cashier up to a cap the **Admin sets** in store settings (⚙ default 10%). Above the cap a Store Manager/Admin approves on the spot with their password. Audited. Discounts row returns to reports (supersedes D12).
- **Returns of a discounted sale refund net:** each line's refund is its share of what was actually paid (discount spread proportionally), so a refund never exceeds payment.
- **Split payment:** one sale may take several tenders (cash + GCash + cheque …), remainder to utang as today for named customers.
- **Cheque is pending until cleared:** cheque no., bank, cheque date recorded. The amount stays owed (named customer only; walk-in cannot pay by cheque) until a Store Manager/Admin marks it **Cleared** (applied as payment) or **Bounced** (stays owed, reason). Applies at the till and to utang payments.
- **Multi-role lite:** an account may hold several roles. After login a user with more than one picks an area; the header switches area any time. Admin assigns roles (existing last-admin / manager-cannot-grant-admin guards stay). The full merged sidebar remains Phase 2.
- **Supplier payables:** processing a delivery creates a **supplier bill** (received qty × cost, less its share of PO discount; VAT shown), due = receipt date + supplier terms days (⚙ default 0 = on receipt). Store Manager/Admin record payments (cash, cheque, bank transfer; partial OK); Stock Manager views. Balance and overdue per supplier. Supplier cheques are recorded as paid when issued (⚙; clearing tracking is for customer cheques only).
- **PO by package:** a PO line names a selling unit ("10 BAG at ₱250/bag"); receiving counts in that unit; stock enters in base units (qty × factor), landed cost per base unit = unit cost ÷ factor.
- **Delivery:** a till sale or sales order can be marked Deliver: address, contact name/phone, date, fee. The fee is a "Delivery charge" line on the receipt (VAT-inclusive, no stock). Deliveries page: Scheduled → Out for delivery → Delivered, or Failed with reason; Store Manager, Admin and Stock Manager update. A printable delivery slip lists items and where each is picked up.
- **Bodega lite:** server-side "Stored at" per product from a short Admin-managed list (⚙ seeded **Store**, **Bodega**). Shown on product details, at the till line, on receipts ("Pick up at Bodega") and on delivery slips. No per-location stock counts or transfers (full version stays future). The device-only shelf hint stays as is.

Delegated defaults (⚙): pager 25 rows per page on every shared table; barcode masterlist (PDF with scannable barcodes + CSV) for Stock Manager, Store Manager and Admin, filterable by category and active; role flow diagrams in `docs/ROLE-FLOWS.md`; PO discount/VAT live on the PO header and affect bills, not batch landed cost.

## Consequences

- Store settings become a real server model (VAT on/rate, discount cap); the static Admin Settings page becomes editable (was Partial in the atlas).
- CPMS contract unaffected: CPMS never reads sales, VAT, discounts or supplier data; release sales gain a VAT breakdown only.
- Phase 1c (payment receipts) stays pending; its open decision is unchanged.
