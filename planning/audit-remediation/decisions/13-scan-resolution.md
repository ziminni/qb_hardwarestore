# Scan Resolution

**Status:** ✅ Locked 2026-10-28 (user chose cache first, server fallback)
**Mode:** Grill

## Question

When the cashier scans, does the till resolve the code from its loaded catalogue, from a server lookup, or both?

## Decision

**Loaded catalogue first; server fallback on a miss.**

```text
scan → normalise (trim + upper)
     → match a till line by ITS OWN VariantUOM code (not the variant's)  ── hit → add that exact unit
     → miss → GET /api/v1/variant-uoms/?barcode=<code>
              → [] → "No product has code <code>"
              → [row] → reload catalogue
                        → now present → add that exact unit
                        → still absent (variant/product archived) → "<code> belongs to <product>, which is archived"
```

### Rules

- **Prerequisite defects fixed regardless** ([Barcode baseline](./11-barcode-baseline.md)): F3 each `PosCatalogItem.barcode` = its own `uom.barcodeQr`; F5 `fetchCatalogue` uses `getAll` for products and batches.
- **Endpoint:** `VariantUOMViewSet.get_queryset` honours `?barcode=` as an exact match on the normalised value (`Upper(barcode_qr) == upper(trim(param))`). Read stays `IsAuthenticated` (cashiers already read the catalogue). No new route, no new permission.
- **Server stays authoritative.** The lookup only finds the unit; price and stock are re-validated in `process_sale` exactly as today.
- **One fallback per scan.** No retry loop; a failed lookup request shows the network error message, not "not found".
- **Archived ≠ not found.** The fallback response carries enough (variant/product names) to say *why* it can't be sold.

### Why

- Cache hit is instant at the till — the common case.
- Fallback removes the "added a product, till can't see it until refresh" trap without paying a round trip on every scan.

## Rejected

- **Cache only** — new units unscannable until refresh.
- **Server every scan** — latency on every beep.

## Abuse / edge cases (RED-first)

- `?barcode= qb000013-4 ` (padded, lower) → finds `QB000013-0`.
- `?barcode=` unknown → `200 []`.
- Unauthenticated `?barcode=` → 401.
- Scanning a box code adds the box unit with its conversion factor, not the piece unit (widget test).
- Product #51 / batch #51 present in catalogue (service test with 2-page stub).
