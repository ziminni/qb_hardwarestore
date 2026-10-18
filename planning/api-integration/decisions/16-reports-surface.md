# The Reports Surface

**Mode:** grill · **Status:** RESOLVED 2026-10-17 · **Opened:** 2026-10-17
**Phase:** 6 — graduated out of Fog of War ("Reports: three screens over one backend surface"), where it
had sat as a consolidation question since the map opened.

## The question

Three report screens exist — `reports/views/inventory_reports_page.dart`,
`sales/views/sales_reports_page.dart`, `admin/views/reports_page.dart` — over one backend surface. Do
they consolidate, or does each role keep its own?

## The fact that decided it

Read from `backend_django/apps/users/permissions.py`, not from the docs:

```
STAFF_ROLES = [Admin, System Administrator]
IsManagerRole   = Store Manager + Admin + SysAdmin        <- /api/v1/reports/* (ALL FOUR views)
IsInventoryRole = Stock Manager + Store Manager + ...
IsPOSRole       = Cashier + Store Manager + ...
```

Every one of the four `/api/v1/reports/*` views carries `@permission_classes([IsManagerRole])`. So
**Stock Manager and Cashier are refused** — and those are exactly the roles that own the inventory and
sales report screens. Two of the three screens would have returned 403 on every call.

This is why the question was worth a decision rather than a wiring exercise: the obvious task ("wire the
three screens to the four endpoints") is impossible for two of them, and nothing in the UI said so.

## Ruling (user, 2026-10-17)

**One Reports screen, admin/manager-only**, wired to the four `/api/v1/reports/*` endpoints:

- `sales-summary/?from=&to=`
- `inventory-valuation/`
- `stock-movements/?from=&to=`
- `requisition-history/`

`sales/views/sales_reports_page.dart` and `reports/views/inventory_reports_page.dart` are **deleted**,
along with their two routes and their two sidebar entries.

## Why not the alternatives

- *Relax the permissions so all three screens work* would have kept every screen, but it widens who can
  read **cost and valuation data** — `inventory-valuation/` exposes cost prices, and handing those to
  Stock Manager is a business decision made as a side effect of a UI question. It would also be the
  third backend change in Phase 6, none of which were planned when the epic started.
- *Three screens, each on what its role may read* leaves the inventory screen showing **derived** data
  from adjustments and receipts while the real valuation report sits unused behind a permission it
  lacks — a screen that looks like the real thing but is a different number.

## What this costs, stated plainly

- **Two role sidebars lose a Reports entry.** Stock Manager and Cashier will have no reporting at all.
  That is the honest consequence of the server's permission model, not an oversight of this decision —
  but if those roles are *meant* to see reports, this decision is the wrong one and the fix is a
  permission change (option 2), not a UI one.
- **The Atlas hotspot "3 report screens" is resolved by deletion**, not by consolidation: the surviving
  screen is the admin one, and `admin/views/reports_page.dart` (33 lines, currently mock) is the file
  that gets wired.

## Not settled here

Which of the four endpoints the screen shows by default, and whether it offers a date range picker
(`sales-summary` and `stock-movements` take `from`/`to`). That is a UI question for Phase 6.


---

## Amendment — 2026-10-17: four tabs, one report each

The "Not settled here" section above deferred the screen's default view and its date handling. An audit on
2026-10-17 found that note recorded on neither the frontier nor the fog, while both read "EMPTY".

**Ruling (user, 2026-10-17): four tabs — Sales · Valuation · Movements · Requisitions — one report
loaded at a time,** each with its own controls where relevant (`sales-summary` and `stock-movements` take
`from`/`to`; `inventory-valuation` and `requisition-history` do not).

**Why:** only one report loads at a time, so the screen stays fast and each report gets the room its shape
needs — the four endpoints return quite different payloads.

**Cost, stated plainly:** a manager must click through four tabs to see the whole picture, and tab state
plus per-tab loading is more UI to build and test than a single scrolling page. **The recommended option
was the one-page version**; this ruling deliberately chose the tabbed one, and the reason is that the four
payloads are dissimilar enough that one page would need four bespoke sections anyway.
