# Release materials: the cashier picks how much — design (2026-11-27)

Branch `feat/release-cashier-picks`, stacked on `feat/sell-by-measure` (PR #33): both
touch `apps/requisitions/services.py`, and kilo/metre lines need that branch.

## Why

A CPMS project request is released at the store counter, often over several visits.
Today the server decides every amount: each visit gives out the most the shelf can
cover. In real life the foreman may only want 10 of the 30 bags today, or the truck
can't carry more. The owner wants the cashier to choose the amount per line, and the
release screen to be easier to understand.

An end-to-end check on throwaway copies of both systems (15/15) confirmed the link
itself works: a short-stock partial release, a second visit with the same token,
CPMS read-back of released/outstanding, and a CPMS cancel closing the rest.

## Goals

- The cashier sets **Give now** per line, from 0 up to the most that can go out.
- One screen: the waiting requests on the left, the chosen request on the right
  (mockup option B, picked by the owner).
- Each line says in words what was given, what is still owed, and what goes out
  today; a summary says what stays open for the next visit.

## Non-goals

- No change to CPMS code or to the CPMS ↔ POS contract (`docs/integration/CPMS-CONTRACT.md`).
  CPMS only reads back released/outstanding, which keep their meaning.
- No kilo/metre ordering from CPMS (CPMS maps only 2 of 12 materials to store codes).
- No reserving stock between visits, no editing what CPMS asked for.

## Anti-goals

- A cashier must never be able to give out more than is owed or on the shelf.
- Lowering an amount must never close the line: what is not given stays open, and the
  same slip works next visit.
- An old till that sends no amounts must behave exactly as today.

## Approaches considered

1. **Editable Give now in today's three steps** — smallest change, the screen stays familiar.
2. **Queue beside request (picked)** — no step switching; the cashier moves request to
   request quickly at a busy counter. More layout work.
3. **One card per item** — bigger touch targets, long with many lines.

The owner chose editable amounts **and** layout B.

## Backend (decided)

`POST /api/v1/tokens/release/` gains an optional body field:

```json
{"token": "<uuid>", "quantities": [{"item": 6, "qty": "4"}, {"item": 7, "qty": "0"}]}
```

- A line not listed releases its full `releasable` (today's behaviour), so `quantities`
  omitted = no change for old clients.
- Under the existing token→request lock, `_release_plan` is recomputed; each chosen
  `qty` must be `0 <= qty <= releasable` for that line, a whole number for a whole
  unit, at most 2 decimals otherwise. Refusals, all before the first write:
  - `400 RELEASE_QTY_TOO_HIGH` — names the line and its current releasable (stock moved
    since the screen was loaded; the till reloads the request).
  - `400 WHOLE_UNIT_QUANTITY` / `QTY_TOO_PRECISE` — the existing codes and wording.
  - `400 UNKNOWN_RELEASE_LINE` — an item id not on this request, or listed twice.
  - All chosen amounts 0 → the existing `400 NOTHING_TO_RELEASE`, wording adjusted
    ("Nothing was chosen to release…"). Token stays valid.
- Status is decided from what was actually given: every Available line fully given →
  RELEASED and token spent; otherwise PARTIAL. A Not available line is ignored, as today.
- Shared shelf between two lines of one variant: the cap for the second line uses what
  the first line is **actually** taking, not its maximum, so a lowered first line frees
  stock for the second.
- Sale, ledger, FIFO, pick-up shelves, audit row and shift gate are unchanged; they just
  use the chosen quantity.
- `verify-release` / `tokens/verify` keep every field and gain additive ones the screen
  needs (till endpoints only, not the CPMS namespace): `requisition.status`, and per line
  `unit` (selling-unit code), `is_whole`, `unit_price` (2dp string). The screen uses
  `releasable` as the upper limit and `quantity - remaining` as "already given".
- *Builder's call, recorded:* the till caps each stepper at the verify-time
  `releasable`. When two lines share one variant and the cashier lowers the first, the
  second's on-screen cap stays at its verify-time figure (conservative); the server
  would allow more. Rare, and never over-promises.

## Flutter (decided)

`MaterialReleasePage` becomes a two-pane screen on wide windows (≥ 1100 px):

- **Left:** the release queue (today's `_ReleaseQueue`: search, Accepted / Partly
  released pills) with the token scan field under it. Selecting a request or scanning
  opens it on the right; the selected row is highlighted.
- **Right, request open:** a header (request number, project, customer, status pill:
  Accepted / Partly released), then one row per line:
  - item name and "3 of 10 BAG given";
  - a progress bar: grey = already given, blue = Give now;
  - "7 still to give · up to 4 can go out now";
  - a **Give now** stepper (−/+ by 1, typing allowed; whole units whole, measured units
    2 decimals), starting at `releasable`, clamped to `0…releasable`; a "changed from 12.5"
    hint when lowered;
  - a status pill: Enough stock / Short: up to N now / Out of stock / Not available
    (with the store's reason) / Already given.
- **Summary bar** above the button: "Giving today: 4 BAG cement, 5 KG tie wire ·
  ₱1,240.00 on account" (price × qty per line, display only; the server's total is the
  receipt's) and "Still open after this: …". Button: "Release N items"; disabled when
  every amount is 0, with the reason shown.
- **Right, after release:** the receipt panel (today's step 3 content: status, sale
  number, balance due, Print receipt, Next request). The queue on the left refreshes.
- **Narrow windows:** the panes stack (queue, then request), as the current steps do.
- Shift-closed banner, print errors and `RELEASE_QTY_TOO_HIGH` (reload the request and
  say what changed) shown in the right pane.

## Left to the builder

Widget split and names, the exact stepper widget, colours from the existing theme,
whether the summary's peso figure is computed in the viewmodel or the widget.

## Calls I made (owner to check)

- Stacked on `feat/sell-by-measure` rather than master (same files; kilo lines).
- Lines left out of `quantities` release in full, so old tills are unchanged.
- New refusal codes `RELEASE_QTY_TOO_HIGH` and `UNKNOWN_RELEASE_LINE`; everything else
  reuses existing codes.
- Dropped "visit N" from the mockup header: the POS does not count visits per request.
- The peso figure in the summary is an estimate from `unit_price`; the receipt shows the
  server's total.
- Two-pane from 1100 px wide; below that the panes stack.
- `ENDPOINTS.md` gets the new body field and codes; the CPMS contract is untouched.

## Verification

Backend tests for each refusal, partial-by-choice, the shared-shelf rule and the
"no quantities" compatibility path; Flutter widget tests for the stepper limits, the
summary text and the two-pane layout; then the cross-system walk again
(`w_partial.py`), plus a visit where the cashier gives 2 of 4 available, and a
click-through in the rebuilt QA app.
