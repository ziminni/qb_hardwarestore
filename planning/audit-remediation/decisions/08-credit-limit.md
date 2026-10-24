# Credit Limit

**Status:** Locked 2026-10-24 (Grill + Research). **Phase:** 1.

## Decision
- `process_sale()` rejects named-customer shortfall when `outstanding OPEN/PARTIAL balance + new shortfall > total_credit_limit` → 400 `CREDIT_LIMIT_EXCEEDED`.
- **Research:** field is `DecimalField(default=0)` non-null (`apps/pos/models.py:27`) and no seed sets it, so every customer is 0. Hard-blocking 0 would break existing credit. Make it **nullable: null = unlimited, 0 = no credit allowed**; data migration converts existing 0 → null; seed gives Maria Santos an explicit limit.

## Security / RED tests
- Limit 500, balance 400, shortfall 200 → 400, nothing written. Null limit → allowed. Limit 0 → any shortfall rejected. Walk-in rule unchanged.
