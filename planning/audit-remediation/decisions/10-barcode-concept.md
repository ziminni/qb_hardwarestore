# Barcode / QR Concept (Fog — grill at Phase 6 start)

**Status:** Concept background. Split 2026-10-28 into [Barcode baseline](./11-barcode-baseline.md) (locked), [Code source & format](./12-code-source-format.md), [Scan resolution](./13-scan-resolution.md), [Label printing](./14-label-printing.md), [Camera scanning](./15-camera-scan.md).

## How it works
- **Identity lives on the selling unit:** `VariantUOM.barcode_qr`. "Nail / pc" and "Nail / box of 100" carry different codes, so one scan = product + unit + conversion factor (Phase 1 makes the server convert).
- **Daily flow:** receive stock → assign/generate code → print label → stick on item/shelf → cashier scans → lookup VariantUOM → cart line → server re-prices and re-checks stock at checkout.
- **Scanner types:** USB/Bluetooth *keyboard-wedge* scanners "type" the code + Enter (till already supports this). Camera scanning (phone/webcam) needs a package and HTTPS on web.
- **Symbologies:** EAN-13/UPC = manufacturer codes (reuse when present). Code 128 = compact internal labels for unbranded goods (lumber, cut wire, repacks). QR = 2D, phone-friendly, more data, slower on 1D laser scanners.

## Security concepts
- A product barcode is a **public, static identifier**, never authority: price/stock always come from the server.
- Must be **unique** across VariantUOMs (DB constraint) — duplicates make scans ambiguous.
- Differs from the requisition **token QR**: secret, random UUID, one-time, server-verified, burned on use.
- Label print/assign actions are inventory-role only and audited.

## Open questions (Phase 6 grill)
Symbology default; internal code format (e.g. `QB` + zero-padded id + check digit); handling existing blanks/duplicates; server lookup endpoint `GET /variant-uoms/?barcode=` vs client cache; label printing path (browser PDF sheet vs thermal label printer); camera scan support.
