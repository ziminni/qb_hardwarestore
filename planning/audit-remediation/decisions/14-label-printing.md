# Label Printing

**Status:** ✅ Locked 2026-10-28 (user chose thermal barcode stickers via label-sized PDF, 50×30 mm, no price, Products + Receiving entry points)
**Mode:** Grill + prototype

## Question

How does a Stock Manager get a physical `QB` label onto a product — what renders it, what's on it, where is the button?

## Clarified

- **Barcode stickers, not RFID.** User confirmed printed Code 128 stickers scanned by USB/Bluetooth barcode scanners. RFID (radio tags, per-item IDs, bulk reads) would be a different system → Out of Scope.
- **Printer:** thermal label printer installed as a normal OS printer (driver), e.g. Xprinter / TSC / Zebra.

## Decision

| Aspect | Locked |
|---|---|
| Render | Client-side PDF via `pdf` + `printing` (pure Dart, Code 128 built in). **One PDF page = one sticker.** Opens the OS print dialog; user picks the thermal printer. |
| Size | **50 × 30 mm** page, minimal margins. Single constant (`shortcut: one roll size; add a size picker if the store switches rolls`). |
| Content | Code 128 bars · human-readable code (`QB000013-0`) · product + variant name (ellipsis) · selling unit. **No price** (server price is authority; printed prices go stale). |
| Which units | Only units whose code starts with `QB`. Manufacturer EAN units are listed as "has factory barcode — skipped". |
| Copies | Per unit, integer 1–200 (validated; prevents a 10 000-page accident). |
| Who | Inventory roles' screens (Stock Manager, Store Manager, Admin). Printing writes nothing to the server, so it needs no server permission and no audit row (codes are public, static identifiers). |
| Entry 1 — Products | Row menu "Print labels" (that variant's QB units) + multi-select toolbar action. Picker lists **every selling unit** of the chosen variants (read from loaded `sellingUoms`, including non-base units). |
| Entry 2 — Receiving | After "Process into stock" succeeds: "Print labels for this delivery". Pre-fills each delivered variant's **base unit** with copies = qty received **when the base unit is whole** (shared whole-unit list from [Scan-to-cart](./17-scan-to-cart.md)); measured base units (m, kg) default to 1; non-base units default 0. All editable. |
| Preview | `printing`'s preview (`PdfPreview` / `layoutPdf`) — testable in dev with no printer. |

### Platform note

`printing` targets web, Linux, Windows, Android. **Build-start spike:** add both packages, render one sticker, open the dialog on Linux desktop and web; if Linux GTK printing fails, fall back to `Printing.sharePdf`/save-to-file via existing `file_selector`. Verify before writing UI.

### Why

- Works with any driver-installed thermal printer; no printer-language lock-in; works from the web build; testable without hardware.
- No price on label → no reprint on price edits, no shelf/till mismatch.

## Rejected

- **A4 sticker sheets** — superseded by user's thermal-printer plan.
- **Raw ZPL/TSPL** — one printer family, not reachable from web, untestable in dev.
- **Server PDF (reportlab)** — extra download/open step per print; no benefit over client render.

## Edge / abuse cases (RED-first)

- Copies 0, 201, `abc` → field error, nothing generated.
- EAN unit selected → skipped with reason, not printed.
- PDF page count = sum of copies; each page's barcode payload = that unit's code (unit test on the document builder, decoding the bar payload from the widget tree, not the pixels).
- Long product name → ellipsis, code text never truncated.
