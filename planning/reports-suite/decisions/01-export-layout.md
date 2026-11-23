# Management report exports

**Locked (by: me, store owner/project representative choice in planning):** A4 letterhead PDF for reading and printing; Excel workbook for filtering and reconciliation. These are internal management reports, not customer invoices, BIR filings or evidence of accreditation.

## Philippine retail reference
[StoreHub Philippines, “15 StoreHub Features You Need To Use For Your Business,” §1 Real-time reports](https://www.storehub.com/ph/blog/15-storehub-features) describes a BackOffice overview with “today's sales, total transactions, items sold and members.” Borrow the overview-first pattern: on a daily sales report, show the period's invoice total and transaction count before the detailed rows. Do not copy membership metrics or combine unlike selling units. This is a vendor's published dashboard example, not its PDF or workbook specification. The layouts below are our choices.

## PDF: what the manager prints
- A4 portrait; landscape for wide tables. Header: configured store name, address and TIN where available. Omit unavailable identity details; never invent them.
- Report title, period (or “As of” for current stock), applied filters, generated-by and generation time in Philippine time. Label currency PHP (₱).
- Relevant KPI totals first, then detail table. Repeat column headings on continuation pages; footer “Page X of Y”. Distinguish missing cost from zero.

## Excel: what the manager reconciles
- First sheet `Summary`: same report identity, period, filters, units and KPI totals as the PDF. One named sheet per detail table; use numeric money/quantity cells and text for identifiers such as barcodes with leading zeros. Keep user-entered names and notes formula-safe.
- Extend existing builders in `flutter/lib/features/admin/reports_excel_export.dart` (sales, valuation, movements, requisitions and VAT). Do not recalculate totals separately for PDF and Excel or silently export only the visible page.

## Acceptance example (planned, not executed)
For one filtered sales period containing a return, compare the viewer, PDF and workbook: same filter labels, row count and signed invoice total to the centavo. Check a second PDF page for repeated headings and page numbering, and open Excel to verify amounts sum as numbers and a leading-zero barcode survives. An empty result must say “No matching records” rather than look like a failed export.
