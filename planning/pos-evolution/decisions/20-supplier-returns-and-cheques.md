# Supplier returns, credit notes and supplier cheque clearing

**Status:** Locked 2026-11-12 (by: me — owner answers; defaults marked *delegated*)
**Phase:** 8

## Context

Research (2026-11-12): `StockAdjustment.AdjustmentType.RETURN` ("Return to Supplier") exists but nothing uses it; `allocate_fifo` cannot target a batch; `SupplierBill` is immutable except `balance_amount` and cannot be deleted (`apps/inventory/models.py:684-835`); `SupplierPayment` has no status and lowers the bill balance at issue, even for cheques (`apps/inventory/payables.py:190-237`). Customer cheques already have the PENDING → CLEARED/BOUNCED pattern (`apps/pos/services.py:1072-1143`). Suppliers are records, not users of the system.

## Decisions

1. **Credit note (combined rule):** each supplier return creates a numbered **credit note**. Its value first lowers the unpaid balance of **the bill the goods came in on**. Whatever that bill cannot absorb (already paid, or credit larger than balance) stays as **supplier-level credit**, which a manager applies by hand against any later bill of that supplier. No supplier refund document — the supplier never acts in the system. (by: me — owner chose "1 and 2 since supplier is not a user")
2. **Which stock:** a return picks the **PO receipt** the goods arrived on; stock leaves **that receipt's batches**, valued at their landed cost; quantity is capped at what that receipt brought in and still remains on hand. (by: me)
3. **Supplier cheques:** the bill balance still **drops at issue**, but a cheque payment now starts **Issued**. A Store Manager/Admin marks it **Cleared** or **Bounced** (reason required); a bounce **puts the amount back** on the bill (and back onto supplier credit if it had been applied from credit — *delegated*: credit application is never by cheque, so this cannot arise). Existing supplier cheques are migrated as **Cleared**. (by: me)
4. **Roles:** Stock Manager, Store Manager or Admin **record returns** (reason required, audited). Only Store Manager/Admin **decide supplier cheques** and **apply supplier credit**. (by: me)

## Delegated defaults (owner may override)

- Return quantity is entered in the receipt line's **purchased unit** (e.g. BAG) and converted to base stock, with the whole-unit and two-decimal stock rules that receiving uses.
- Credit value = returned base qty × batch landed cost, rounded once (HALF_UP, 2dp); VAT follows the bill's VAT snapshot (inclusive/exclusive) so the credit mirrors what was billed.
- A credit note is append-only (no edit/delete), like bills and payments; mistakes are corrected by a counter-entry, not an edit.
- Low-stock checks run after a return (stock went out).
- Applying supplier credit is recorded as a payment with method `CREDIT` linked to the credit note, so bill history shows how each peso was settled.
- Bounced supplier cheque: audited `CHEQUE_DECISION`, same as customer cheques; decisions are once-only (`CHEQUE_ALREADY_DECIDED`).

## Consequences

- New models: supplier return (+ lines), credit note, credit application; `SupplierPayment` gains status + decision fields and a `CREDIT` method.
- Payables screens gain Returns/credit-note history, supplier credit balance, "Apply credit" in the pay dialog, and a supplier-cheque queue mirroring the customer cheque queue.
- Supplier balance figures become: bills − payments − applied credit; unapplied credit is shown separately, never as a negative balance.
