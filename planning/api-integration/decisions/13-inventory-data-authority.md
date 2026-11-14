# Inventory Data Authority for Phase 2

**Mode:** grill · **Status:** LOCKED 2026-10-16 · **Phase:** 2
Supersedes the Phase 2 hand-off row's claim that "None needed". That was written before the Atlas refresh; two
sharply-statable questions live inside Phase 2's own scope.

## The question

Phase 2 is "inventory: stock list, low stock, movements". Two things had to be settled first, because the client
currently **derives** inventory state and **invents** its movement history, while the server has its own opinions
— and its own (empty) tables.

## Findings, all verified against source and the live server (2026-10-16)

**1. The low-stock rule disagrees across the boundary.**

```dart
// client — features/inventory/viewmodels/inventory_viewmodel.dart:208-211
if (stock <= 0) return InventoryStockStatus.outOfStock;
final threshold = variantFor(variantId)?.minStockThreshold ?? 0;
if (stock <= threshold) return InventoryStockStatus.lowStock;   // <=, no >0 guard
```

```python
# backend — apps/inventory/services.py:142-161  _check_low_stock
if total <= 0:                              # OUT_OF_STOCK alert
elif threshold > 0 and total < threshold:   # LOW_STOCK alert  — '<', and a >0 guard
```

A variant sitting **exactly at** its threshold reads `lowStock` client-side and generates **no alert**
server-side. The two authorities can contradict each other on the same row.

**2. The client never calls `/api/v1/adjustments/`.** It inserts `InventoryMovement` objects at five sites in
`inventory_viewmodel.dart` (plus `_seedMovements()` in the constructor). A grep for `adjustments` across
`flutter/lib` returns exactly one hit — a comment. So the movement history shown in the UI is a local fiction
the server has never seen, and the "adjust stock" dialog writes a record that never leaves the device.

**3. Both endpoints are EMPTY, and the seed data cannot fill them.**

```text
GET /api/v1/alerts/       count=0
GET /api/v1/adjustments/  count=0
```

No seed command creates a `SystemAlert` at all, and all 8 seeded variants carry `min_stock_threshold = 20.00`
against ~100 units on hand — nothing is anywhere near low. Reading these endpoints without changing the seed
makes **two screens blank**, which cuts against decision 01's own lens of shipping a demoable outcome per phase.

## Options

### A. Server-authoritative, and seed the missing data — **chosen**

`/alerts/` and `/adjustments/` become the read authority; adjustments POST to the server and the screen re-reads;
`seed_demo` gains a couple of below-threshold variants and a handful of `StockAdjustment` rows so both screens
have real content.

### B. Server records writes, client still displays

POST adjustments so the server accumulates history, but keep the client's derivation and movement log driving the
display. Nothing in the backend is touched. Rejected: it leaves **two** authorities for the same fact and the
drift between them is invisible — the exact defect class decision 11 removed from the product list.

### C. Read the server, accept two empty screens

Most faithful to the literal Destination ("no client-reachable endpoint is left uncalled") but makes the demo
look broken. Rejected on decision 01's "demoable outcome every phase" criterion.

## Resolution — LOCKED 2026-10-16

**Option A.** One authority: the server. The user accepted the one backend change this requires — the
`seed_demo` command, which is **demo data only**: no new endpoint, no model change, no migration, so the map's
"client-side epic only" invariant still holds in substance.

Consequent rules for the Phase 2 build:

1. **The low-stock screen reads `GET /api/v1/alerts/`.** It stops deriving its list.
2. **The stock list's per-row status column must use the SERVER's exact predicate** — `total < threshold` with a
   `threshold > 0` guard — not today's `stock <= threshold`. This is the non-obvious part: wiring the alert list
   while leaving the derived column on `<=` would let the list mark a row `lowStock` while the alert screen
   shows nothing for it, trading one contradiction for a more visible one. Either both agree on `<`, or the
   column is removed.
3. **The client's movement log is deleted.** `_movements`, `_seedMovements()` and the five inline
   `InventoryMovement` insertions go; the movements screen reads `GET /api/v1/adjustments/`, and the adjust
   dialog POSTs to `/api/v1/adjustments/` then re-reads. A movement that exists only on the device is not a
   movement record.
4. **`seed_demo` gains:** 2 variants taken below their threshold (so `/alerts/` is non-empty and the low-stock
   screen has rows) and ~5 `StockAdjustment` rows across types (so `/adjustments/` has a history, including at
   least one of each adjustment type the UI filters on).
5. **`parsePaged` unwraps both new envelopes** (decision 03) — no hand-rolled `data['results']`, and alerts are
   a list endpoint so the same strictness applies.

## Accepted cost, stated plainly

- The demo now depends on a **backend seed change**, which is the first non-client edit in this map. If
  `seed_demo` is not re-run, both screens render their empty states — correct behaviour, but not demoable.
- The low-stock screen's contents become whatever the server has **alerted**, not everything currently below
  threshold. A variant that drops below threshold without going through an adjusted path (a direct batch edit,
  say) will not appear until an alert is generated. This is the price of one authority, and it is the honest
  behaviour: an alert is an event, not a live view.
- `statusForVariant` gains a `threshold > 0` guard and changes `<=` to `<`, which flips the status of any variant
  sitting exactly on its threshold from `lowStock` to `inStock`. No seeded variant is in that state today, so the
  visible change is zero — but the rule is now the server's.
