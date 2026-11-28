# Release materials: the cashier picks how much — 2026-11-27

Branch `feat/release-cashier-picks`, stacked on `feat/sell-by-measure` (PR #33), in
the Windows QA clone `DEVELOPMENT_FOLDER/hardware_store_qa`. Design and plan:
`planning/material-release/2026-11-27-cashier-picks-release-design.md` and `-plan.md`.

## Why

CPMS project requests are released at the counter, often over several visits.
Before this branch the server decided every amount (the most the shelf could
cover), so a foreman who wanted 10 of 30 bags today could not be served that way.

## What changed

- **Backend:** `POST /api/v1/tokens/release/` takes an optional
  `quantities: [{item, qty}]`. A listed line gives exactly that amount
  (`0 … releasable`, whole for whole units, 2 decimals otherwise); a line left out
  gives its full releasable, so old tills behave as before. New refusals
  `RELEASE_QTY_TOO_HIGH` (stock moved; names the current limit) and
  `UNKNOWN_RELEASE_LINE` (not on this request, or listed twice); all zeros is
  `NOTHING_TO_RELEASE` ("Nothing was chosen to release…"). Two lines on one
  variant share the shelf by what the first actually takes. Verify answers gain
  `requisition.status` and per line `unit`, `is_whole`, `unit_price`.
  CPMS contract untouched.
- **Flutter:** the release screen is one page: waiting requests and the token
  field on the left, the chosen request on the right (stacked below 1100 px).
  Each line reads "3 of 10 BAG given", a grey/blue bar, "7 still to give · up to
  4 can go out now", a Give now stepper (typing allowed) with "changed from N",
  and a status pill (Enough stock / Short: up to N now / Out of stock / Not
  available + reason / Already given). A summary says what goes today, the
  estimated peso amount on account and what stays open; the button reads
  "Release N items". After the release the receipt takes the right pane.

## Verification

- Backend: new `apps/requisitions/tests_release_choice.py`; full suite on the
  throwaway Postgres (`qbt_db2`): 1,826 tests OK.
- Flutter: `material_release_choice_test.dart` (8) and
  `material_release_two_pane_test.dart` (7) green; `flutter analyze` clean; the
  POS folder has no new failures and 8 previously failing release-page tests pass.
  Full suite: 2,795 pass, 72 fail; none of the failing files touch requisition or
  release code, and the POS-folder list is a subset of the pre-change list.
- Cross-system walk on throwaway CPMS + POS (`w_partial.py`): 23/23, including a
  visit where the cashier gives 2 of 4 — CPMS reads requested 5, released 2,
  outstanding 3, PARTIAL, and the same slip still works.

## Gotchas

- `material_release_page_golden_test.dart` is opt-in (`RUN_GOLDENS`) and writes to
  an absolute WSL path; its PNGs were not regenerated on Windows.
- When nothing at all can go out the screen shows the reason and no button; the
  disabled button with "Set at least one Give now above 0." is for the case where
  stock exists but every amount is 0.
- The till caps each stepper at the verify-time releasable; two lines sharing one
  variant are capped conservatively (the server would allow more).
