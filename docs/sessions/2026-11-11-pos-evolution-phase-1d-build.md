# 2026-11-11 — POS evolution Phase 1d build and verification

**Status:** Phase 1d ✅ Done 2026-11-11, closed by the owner with accepted limits. Not deployed. Dev database intentionally left on Phase 1b (`inventory` 0008 unapplied) by owner choice.

## Scope and ownership

- Branch `feat/pos-evolution-phase-1d` off Phase 1b `1a15920`; planning commit `2b03f85`. Owner pushes.
- Canonical checklist and evidence: [Phase 1d plan](../../planning/pos-evolution/phase-1d-plan.md). Decisions [15](../../planning/pos-evolution/decisions/15-product-packaging-units.md), [16](../../planning/pos-evolution/decisions/16-units-on-existing-products.md), [17](../../planning/pos-evolution/decisions/17-teammate-look-adoption.md).
- Owner gates: Task 8 Add product design approved 2026-11-10; [CPMS contract v0.3](../integration/CPMS-CONTRACT.md) provisionally accepted 2026-11-11.
- Subagent provider ran out of funds mid-phase (HTTP 402); owner authorized direct implementation/review as fallback. Deferred independent reviews of Tasks 10b, 11, 12 ran once funding returned.
- `qb_project_management_system/` not changed.

## Built

- **Units:** `UnitOfMeasure.is_whole` + migration 0008 seeding 12 standard units (RL kept as Roll, no duplicate ROLL). Server owns whole-number rule: `WHOLE_UNIT_QUANTITY` across sale, hold, return, release, quote, sales order, PO, receiving, adjustment and CPMS import. Flutter's hardcoded unit list deleted.
- **Selling units:** real base + extra packaging units with independent prices in Add product and product details; remove never-used extras (`DELETE /variant-uoms/{id}/`), with shared sorted-PK locks so a removal cannot race a new reference. Factor frozen once a unit is on a project request.
- **Fake data removed:** invented inventory tracking (`ProductTrackingViewmodel`) gone; storage location is a device-only hint and says so.
- **Look:** teammate dialog family (AppDialog, SectionHeading) across 12 dialogs; DataPanel title + shown-rows count; category bars and stat tiles; PO progress counts fully received lines; sales document sheet takes numeric totals; header weekday date; sidebar hover, active bar (no motion under reduced motion), hexagon initials; visible 2 px focus outline on gold/text buttons.
- **Seed:** Tile Adhesive sold by KG or BAG (25 kg) stocked through a real PO + Receiving; seed restores standard units after `flush`.

## Verification

| Gate | Result |
| --- | --- |
| Backend full suite | 763 tests OK; migration drift: no changes |
| Flutter analyze | clean |
| Flutter tests | 1545 passed, 241 skipped |
| Goldens | 241 passed |
| Isolated live QA | `temp/p1d/qa/` (local, gitignored): HTTP probes, CPMS fractional-import refusal, cashier/stocker/manager/admin browser flows at 1440/1100/760, keyboard |

## Gotchas found

- Fresh installs got both RL and ROLL until the seed reused the migration's units; `flush` also wiped standard-unit flags. Both fixed RED-first.
- Header date overflowed the cashier till by 95 px at 900×600; date now yields space.
- Golden harness must precache the actual displayed Image providers or the logo goes blank.
- agent-browser on Flutter web: click a button's semantics-box centre (edge hits the barrier); CSS `zoom` is not a text-scale test. Recorded in [QA-PROFILE](../testing/QA-PROFILE.md).
- Host Pyright cannot resolve Django (it lives only in the container); those import errors are false positives.

## Accepted limits (not passed)

- Genuine browser 1.3 text scale (real-font goldens only).
- Concurrent unit removal live (deterministic PostgreSQL tests only).
- Admin overview sale row opens monitoring rather than the sale sheet (pre-existing).
- Dev DB not migrated; isolated QA stack `buildpro_p1d_qa_*` (API 8001, web 8091) still running.

## Next

Phase 1c payment receipts remains in planning with open decisions. Dev migrate/reseed and QA-stack removal need owner approval.
