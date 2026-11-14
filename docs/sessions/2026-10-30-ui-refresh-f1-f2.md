# 2026-10-30 — UI refresh foundation: F1 + F2 built

## Focus

Start the `temp/ui-refresh` build: run foundation cards F1 + F2 with parallel subagents, verify + commit each, and settle the foreman question without breaking the T0 demo.

## What Was Built / Changed

- Verified T0 committed (`6885e03`..`43da13c`; tree clean): responsive AppShell, till redesign, catalogue cache, release token, Manager Approvals/Staff. Routes now 39.
- F1 (`6592f91`): `requisition_token_panel.dart` → `admin_requisition_token_panel.dart`, class → `AdminRequisitionTokenPanel`, imports updated. Pure rename, 3 files.
- F2 (`2eeeb1e`, 50 files): new `lib/core/format/format.dart` (`formatPeso`, `formatDate`, `formatDateTime`, `formatCount`; manual grouping, no new dep per D19). All 34 card files + 3 needed extras converted; zero `toStringAsFixed(2)}'` peso strings remain. Every ₱-pinning test updated to D1 format (e.g. `₱1000.00` → `₱1,000.00`); sub-₱1,000 pins unchanged. Negatives flip to `-₱50.00`.
- Docs (`a3ed34e`): parked CPMS↔POS material-token integration as fog epic `planning/api-integration/decisions/21-cpms-token-integration-model.md` (6 open questions; partly reopens decision 09 on who approves) + MAP fog line. Ledger: `.superpowers/sdd/ui-refresh/progress.md`.
- Gates (fresh, controller): `flutter analyze` → No issues; `flutter test` → 878/878; tree clean.

## Mistakes & Gotchas (Do Not Repeat)

- F1 first commit (`ac19761`) left the class-rename edit unstaged: HEAD defined the OLD class against a new-name caller — a compile break the working-tree suite hid. Amended to `6592f91`; always re-run gates on committed HEAD after amending.
- `git mv` stages the rename but not the content edits — verify all files of a rename are staged before committing.
- `dart format lib test` shows 20 pre-existing unformatted files; do not fold them into card commits (kept for Z1/Z2 sweep). Only format files the card touched.
- Format-shadowing trap: a local `formatDate` shadows the import and recurses (`StackOverflowError`), analyzer stays green — only the full suite catches it (F2 agent hit this).
- `textContaining('₱-')` goes vacuous when negatives flip to `-₱`; rewrite to `-₱`, don't leave green.
- Field decoration (`prefixText: '₱ '`, `Amount (₱)`) and raw-digit text-field initial values are not amounts — never format them.

## Decisions

- Override AGENT-BRIEF "one card per branch": agents build + prove RED/GREEN but do NOT commit or globally format; controller gates once on the combined tree and commits per card (ledgered ruling; single committer, disjoint file sets).
- Foreman stays a backend identity this refresh (feeds the T0 Approvals/token demo; decisions 04/09 already rule it non-POS). Removal = future CPMS-integration epic spanning `qb_project_management_system/` (lift the no-touch boundary first). Refresh handling = L2 cosmetic only.
- Full removal of foreman explicitly rejected (would gut requisitions demo, violates D19, contradicts BuildPro design).

## Wins & Next Step

- Wins: money/date/count now single-format app-wide; token panel named per convention; CPMS target captured without breaking the demo; 878/878 green.
- Next: answer pending question — dispatch **F3 `DataPanel`** (table-wide/cards-narrow, unblocks all table cards) or pause for user's 1440/1100/760 visual look at the new money format first.
