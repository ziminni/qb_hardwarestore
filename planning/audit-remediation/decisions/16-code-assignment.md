# Code Assignment & Backfill

**Status:** ✅ Locked 2026-10-28 (user chose auto + backfill)
**Mode:** Grill

## Question

When does an internal `QB` code get assigned to a selling unit, and how do the 15 existing blank units get theirs?

## Decision

**Invariant: every selling unit always has a code.** A unit saved without a manufacturer code gets its derived `QB` code ([Code source & format](./12-code-source-format.md)) automatically.

### Rules

- **Model-level, not view-level.** `VariantUOM.save()` assigns the derived code when `barcode_qr` is blank after the row has an id (save → derive → `update_fields=['barcode_qr']`, same transaction). Seeds, Django admin, API and tests all obey one rule — no path can leave a blank.
- **Typed EAN wins on create.** A non-blank valid code in the create payload is stored as-is.
- **Replace is a normal PATCH** (inventory role, audited `QB000003-1 -> 4800016123450`).
- **Clearing re-derives.** PATCH `barcode_qr: ''` restores the unit's own `QB` code instead of leaving it blank — a unit can never become unscannable by accident.
- **Backfill = data migration.** `RunPython` assigns derived codes to every blank row; reverse is a no-op. Runs after the uniqueness migration from [Barcode baseline](./11-barcode-baseline.md). Safe on dev (15 blank, 0 dupes) and on any DB because derived codes are unique by id and the `QB` prefix is reserved.
- **No "Generate code" button.** Nothing to generate — every unit already has one. The UI shows the code and lets inventory roles replace it.

### Why

- Scanning works for every unit from day one; no forgotten units.
- Putting the rule on the model means the seed command can't drift from the API.

## Rejected

- **Explicit only** — forgotten units scan as "Product not found".
- **Auto, no backfill** — the 15 old units stay unscannable until someone remembers a bulk button.

## Abuse / edge cases (RED-first)

- Create without code → row has `QB{id:06}-{check}`.
- Create with `4800016123450` (valid) → stored as typed, no QB code.
- PATCH `''` → derived QB code, audit row records the change.
- Migration on a DB with blanks → zero blanks after; re-running is a no-op.
- Seed command → every seeded unit has a code.
