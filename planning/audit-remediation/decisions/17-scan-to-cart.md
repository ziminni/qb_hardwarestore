# Scan-to-Cart Behaviour

**Status:** ✅ Locked 2026-10-28 (user chose instant for whole units, dialog for measured)
**Mode:** Grill

## Question

Once a scan resolves to an exact selling unit, does the till add it straight to the cart or open the quantity dialog?

## Decision

| Scanned unit | Behaviour |
|---|---|
| Whole unit (`pc`, `piece`, `bag`, `box`, … — the dialog's existing list) | `addLine(item, 1)` immediately; re-scan merges into the same line (existing `addLine` behaviour). |
| Measured unit (`m`, `kg`, `l`, anything not in the whole list) | `PosSaleQuantityDialog` opens with **the scanned unit preselected** and qty focused; Enter confirms. |
| `addLine` refuses (stock, etc.) | Snackbar with the refusal; nothing added. |

### Rules

- **One home for the whole-unit list.** Hoist the `const wholeUnits` set out of `pos_sale_quantity_dialog.dart:87` into one shared constant used by both the dialog validator and the scan path.
- **Dialog takes an initial unit.** `PosSaleQuantityDialog` gains an optional `initial` item; scan passes the resolved one, manual browse keeps today's behaviour. Fixes [Barcode baseline](./11-barcode-baseline.md) F4.
- **Focus returns to the scan field** after every outcome (existing `_restoreScannerFocus`).
- No audio beep (no audio dependency); the cart line updating is the feedback.

### Why

- Fast counter flow for countable goods; no accidental "1 m of wire" sales.

## Rejected

- **Always instant** — measured goods silently get qty 1.
- **Always dialog** — an extra keypress on every item.

## Edge cases (RED-first, widget tests)

- Scan box code twice → one line, qty 2, unit `box`.
- Scan metre code → dialog open, unit `m` preselected.
- Scan whole unit with 0 stock → snackbar, cart unchanged.
- Manual browse (no scan) → dialog behaves as today.
