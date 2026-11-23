# Store operations round (2026-11-22)

Merged into `master` (`e5dfdab` through `d52cb5d`).

## Phase Progress

| Phase | Scope | Blocking Decisions | Status |
|---|---|---|---|
| 1 | Official receipt (OR / invoice no.) tagging on order slips: at checkout, later via OS search/QR scan, reprint | none (owner answered) | ✅ Done |
| 2 | Discounts: per-product OR whole-sale, never both; whole-sale split by price over lines the cashier leaves ticked; hide product "Allow discounts" toggle | none | ✅ Done |
| 3 | Returns become exchanges: customer pays extra; cheaper swap → store credit / utang reduction; cash refund only when no replacement | none | ✅ Done |
| 4 | Held carts reserve stock with expiry; FIFO batch order shown on stock + sale details | expiry length default (2 h, Admin-editable) | ✅ Done |
| 5 | Cash drawer: denomination count at close, close report by tender, categorised cash-outs (lunch, fuel, supplies, other + custom), store-day open/close | none | ✅ Done |
| 6 | Daily / weekly / monthly reports with breakdowns; VAT report split OR-tagged vs untagged + Excel export | none | ✅ Done |
| 7 | Box / pack units back (flexible decimal factor: box→pcs, bag→kg); supplier orders + exports in the pack unit | none | ✅ Done |
| 8 | Price list: per-product price timeline + store-wide recent changes | none | ✅ Done |

### Phase 1 checkpoint

- Backend done and GREEN: `SalesTransaction.invoice_no` / `invoice_tagged_at` / `invoice_tagged_by` (migration `0024_salestransaction_invoice_no`, unique when non-blank), `services.tag_invoice`, `POST /transactions/attach-invoice/`, `?q=` also matches the invoice no. 16 new tests pass; `ruff` clean.
- Flutter done: sale model, till OR switch + number field, Attach-OR dialog (scanner/camera, 409 shows the number already on the slip, Replace only for manager/admin, reprint through the roll printer), slip prints `OR Invoice No.`, manager sales sheet shows it. 7 new widget/unit tests pass.
- Open: the manager sales sheet's own "Attach OR" action (the dialog is reachable from the till only); VAT report split (Phase 6) not started — the data it needs is now available.

## Owner answers (2026-11-22)

- Box vs piece: bring back as Box/Pack; conversion must stay flexible (box→piece, bag→kilo, any decimal factor).
- Exchange difference: customer pays extra; no cash back for cheaper swaps (store credit / utang). Cash refund only when nothing to swap.
- Held carts: reserve stock with an expiry.
- Drawer: denomination count + split by payment method.
- OR: customer returning days later → find by OS search or QR scan, attach the invoice no., reprint.

## Assistant defaults (not owner rulings, revisable)

- VAT reports count OS slips with an invoice no. as "OR-backed"; others shown in a separate column. Not a BIR filing.
- Whole-sale discount is allocated proportionally to line amounts (existing allocator).
- Cashier, Store Manager, Admin can attach an invoice no.; changing an existing one needs Manager/Admin and is audited.
