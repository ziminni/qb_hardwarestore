# Integrity Mechanics

**Status:** Locked 2026-10-24 (Research — technical choices within user decisions). **Phase:** 1.

## Decisions
1. **Sale validation:** dedicated nested input serializers for items/payments: items non-empty; qty > 0; valid active VariantUOM; payment method in enum; amount ≥ 0; ≤ N lines. `full_clean` not relied on.
2. **Idempotency:** optional `Idempotency-Key` header (UUID) on `POST /transactions/`, `/held-carts/{id}/complete/`, release, return. Stored unique on `SalesTransaction.idempotency_key` (nullable). Replay with same key + same user → original response (200); different payload → 409. Flutter generates key per checkout attempt and reuses on retry.
3. **Numbering:** `DocumentCounter(name, date, last)` row locked with `select_for_update` inside the sale transaction; replaces read-latest+1.
4. **Split receipts:** new `GoodsReceiptItem(receipt, po_item, qty)`; processing creates batches from that receipt's lines only; receipt row locked (`select_for_update`) + `processed_at` set to block concurrent reprocess.
5. **Zero-stock positive adjustment:** creates a new batch (unit cost = last known cost or 0 with flag) instead of silently doing nothing.
6. **Release factor-1 UOM:** resolve base-unit VariantUOM or raise 400 `NO_BASE_UOM` before any write.

## Security / RED tests
Empty items, negative qty, bogus method → 400. Same key twice → one transaction. Two concurrent sales → distinct numbers, no 500. Receipts 5 then 2 → stock 7. Concurrent process same receipt → one batch set.
