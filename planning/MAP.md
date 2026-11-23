# planning/MAP.md — Planning & Roadmap Index

Entry point for POS planning maps and completed execution plans.
Architecture lives in `docs/SYSTEM_ATLAS.md`; the endpoint contract lives in `ENDPOINTS.md`.

## Active & Recent Plans

1. **[planning/store-ops-round-2-plan.md](store-ops-round-2-plan.md)** — **COMPLETE (2026-11-23).**
   - Phase 1: OR toggle auto-reset after sale/clear, held-cart notes & instant resume removal, POS-wide numeric input formatters/warnings, and Exchange custom replacement quantities.
   - Phase 2: Custom date range filters on Transaction History & Payment History, Requisition Step 2 (`_RequisitionLines`) column spacing redesign, and generic `OR-tagged` VAT labels.
   - Phase 3: Optional supplier payment proof attachment (`0025_supplierpayment_proof_attachment`) with `No proof attached` badge and later `Attach / Update proof` action, Cashier full delivery completion authority + Bodega `For Delivery` handoff, and Stock Manager sidebar cleanup (`Sales` & `Payables` removed; `Supplier returns` under Purchasing).
2. **[planning/store-ops-2026-11/MAP.md](store-ops-2026-11/MAP.md)** — **COMPLETE (2026-11-22).**
   - OR tagging & Attach OR dialog, mutually exclusive line vs. whole-sale discounts, returns & exchanges, held-cart stock reservations & FIFO view, cash drawer denomination counter & custom cash-out categories, daily/weekly/monthly reports with VAT OR split & Excel export, box/pack selling units, and store-wide price list timeline.
3. **[planning/pricing-insights/MAP.md](pricing-insights/MAP.md)** — **COMPLETE (2026-11-21).**
   - Selling-price history, centavo discount allocation, operational profit breakdown, and grouped partial payments.
4. **[planning/pos-evolution/MAP.md](pos-evolution/MAP.md)** — **COMPLETE (2026-11-03 – 2026-11-20).**
   - Phases 1–9, Bodega Checker module, Excel catalogue round-trip, and merged multi-role sidebar.
