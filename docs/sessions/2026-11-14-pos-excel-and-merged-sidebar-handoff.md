# POS Excel and merged-sidebar PR handoff

## Scope

Branch: `feat/pos-evolution-phase-3`, based on Phase 9 commit `22836ed`.
Includes Phase 3 Excel catalogue export/import with preview and atomic Apply, and Phase 2 destination registry, union-area routing, merged sidebar and combined dashboard.
CPMS repository is not part of this change.

## Verification

Previously recorded controller gates: 1,365 backend tests; system check and migration drift clean; Phase 3 Flutter 2,329 tests and 241 goldens; Phase 2 Flutter 936 tests and 250 goldens (241 existing unchanged, nine new). Independent lane reviews and Phase 2 whole-change review approved.

Fresh precommit checks: Flutter analyze clean, 165 focused catalogue/navigation/routing/dashboard tests passed, git diff whitespace check clean after removing one trailing space.

Browser QA against disposable PostgreSQL: merged manager/stock account logged into combined dashboard; actual XLSX download re-imported through real browser file input/parser; preview reported one unchanged row; Apply reported nothing to change. Populated batch stock remained 7.00 with identical before/after snapshot hash. Native chooser was suppressed for automation, so this does not prove native chooser behavior.

Standalone 2,000-row writer/parser probe passed, preserving every ID/barcode/price: 149,876 bytes, 282 ms write and 5,103 ms parse in Flutter test VM. Not browser, Windows or backend end-to-end timing.

Detailed logs/screenshots remain local under ecosystem `temp/p2/` and `temp/p3/`; these are not portable tracked PR artifacts.

## Open verification and accepted boundaries

- Native Windows picker/save and Microsoft Excel/LibreOffice edit/resave remain unverified. Phase 3 and final owner closure remain open; committing does not close these gates.
- Browser changed-row/create/error/stale UI paths were not repeated in the final browser run; server/parser acceptance and regression tests cover those cases separately.
- Golden masters remain gitignored local artifacts; fresh checkouts do not receive them in this commit.
- Phase 1c CPMS payment-receipt approval remains intentionally on hold.
- No development database mutation, push or master merge performed for this handoff.
