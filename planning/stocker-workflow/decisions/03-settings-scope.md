# Decision 03 — Stocker Settings Scope

**Locked:** 2026-10-21  
**Status:** ✅ Locked

## Decision

Static read-only form inside `InventorySkeletonLayout`. Reuse `AdminSettingsForm`
with hardcoded store values. **Remove the "Save settings" button** — a stocker
cannot change store settings, and no backend endpoint exists anyway.

## Rationale

The Settings page has no API backing even for Admin (the Save button is a no-op
on `AdminSettingsPage` too — it uses `AdminMockData` with a silent `() {}`). The
stocker version should be honest: display-only with no Save affordance.

## Deferred

Settings save for any role is tracked in **Fog of War** (known dead button).
