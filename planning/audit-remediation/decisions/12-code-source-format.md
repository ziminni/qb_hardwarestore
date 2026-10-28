# Code Source & Format

**Status:** ✅ Locked 2026-10-28 (user chose Hybrid)
**Mode:** Grill

## Question

Where do the codes on a selling unit come from, and what does an internally generated code look like?

## Decision

**Hybrid: manufacturer code first, internal Code 128 for the rest.**

| Source | When | Format | Printed by us? |
|---|---|---|---|
| Manufacturer | Package already carries EAN-13 / UPC-A / EAN-8 | Digits exactly as printed | No |
| Internal | Unbranded goods, repacks, boxes, anything without a code | `QB` + VariantUOM id zero-padded to 6 + `-` + 1 check digit, e.g. `QB000013-0` | Yes — Code 128 label |

### Rules

- **Internal code is derived, not random:** check digit = GS1 mod-10 over the 6 id digits. Unique by construction (ids are unique) and recomputable for audit.
- **`QB` prefix is reserved.** A manual write starting with `QB` is refused `400 BARCODE_RESERVED_PREFIX` unless it equals that unit's own derived code — nobody can hand-type a code that will later collide with a generated one.
- **Manufacturer codes are check-digit validated.** An all-digit value of length 8, 12 or 13 must pass the GS1 mod-10 check, else `400 BARCODE_INVALID` (catches typos when keyed by hand). Other values: printable ASCII, no whitespace, ≤ 100 chars.
- **One code per selling unit.** A box of 100 and a single piece are different units with different codes — scanning either resolves product + unit + conversion factor.
- **Symbology on labels: Code 128** (readable by every 1D laser and 2D imager). EAN labels are never re-printed by us.
- Normalisation and uniqueness per [Barcode baseline](./11-barcode-baseline.md) (trim + upper, case-insensitive partial unique).

### Why

- Branded goods already scan — printing over them is wasted labels and a second code for the same thing.
- Code 128 keeps the cheapest scanners viable and matches the existing keyboard-wedge till input.
- Deriving from the id removes the need for a counter or random-collision retries.

## Rejected

- **Internal only** — labels on every already-coded package; no benefit.
- **QR everywhere** — forces 2D imagers at every till; nothing we encode needs the extra capacity.

## Abuse cases (RED-first)

- Manual `QB000099-0` on unit 13 → `400 BARCODE_RESERVED_PREFIX`.
- `4800016123456` (bad check digit) → `400 BARCODE_INVALID`.
- Code with embedded space / control char → `400 BARCODE_INVALID`.
