# 2026-10-31 — UI refresh: foundation F3/F4 + screen wave 1

## Focus

Finish the UI-refresh foundation (shared components, grouped sidebar), review it, then build the table-heavy screens (wave 1) in parallel worktrees. Plan: `temp/ui-refresh/TASKS.md`; ledger `.superpowers/sdd/ui-refresh/progress.md`.

## What Was Built / Changed

| Commit | What |
|---|---|
| `6ba7195` | F3 shared components: AppPanel, StatusBadge, DataPanel (table at >= 720 px of its own width, cards below), MetricTile, MetricGrid, EmptyState, ErrorBanner, FilterBar; TextButton theme font fix |
| `3a58d65` | F4 grouped sidebar for all roles: groups without reordering, gold active bar, remembered collapse, brand subtitle, live markers (held carts, requisitions awaiting approval, open low-stock alerts) |
| `9d6c565` | Foundation review fixes: theme fills titleLarge/headlineSmall (Cinzel) and titleMedium/Small (Open Sans); FilterBar controller swaps; DataPanel lazy rows in bounded slots |
| `9b085fe` `dcbcd44` `5306124` | Wave 1: S1 one shared transactions content (3 role pages); K2 products on shared panels (4 views kept); K4 stock book, Adjust reachable at 1100, "Shelf note (this computer)" |
| `5b8a98a` | DataPanelColumn `flex` |
| `d5550b3` | Wave-1 review fixes: manager payment caption + Today/This week/This month chips, stock retry keeps rows, lazy transaction lists (shells expose `scrollable`), column weights, FilterBar second chip group |

Gate after `d5550b3` (controller run): `flutter analyze` clean, `flutter test` 1004 passed / 40 opt-in goldens skipped.

## Mistakes & Gotchas (Do Not Repeat)

- Agent transcripts in `/tmp/pi-subagents-*` are lost on a session reset: verify a card from its commit message, diff and your own gate run; copy key report lines into the ledger as soon as a card lands.
- The Agent tool's `isolation: worktree` fails here (agent cwd `qb_ecosystem/` is not a git repo). Create worktrees manually under `.superpowers/worktrees/<card>` (gitignored) on `ui/<card>` branches and pass the path in the prompt; `temp/` is untracked so plans are read by absolute path.
- Role shells wrap pages in a scroll view, so DataPanel only goes lazy when the page passes `scrollable: false` and puts the panel in `Expanded`.
- Never pass `isLoading: true` to DataPanel when rows exist (it swaps rows for a spinner).
- `git mv` stages the rename but not later content edits; check `git diff --cached` before committing a rename.
- Bundled Open Sans / Cinzel have no U+20B1 (₱); money renders via system/web font fallback only (open user question: offline web till?).
- pi-lens repeatedly reported `empty_state.dart` missing: stale snapshot (LSP root is `qb_ecosystem/`, no pubspec); `flutter analyze` is the truth.

## Decisions

- Screen cards: one card per worktree/branch, agent commits on its branch, controller re-gates and merges `--no-ff`.
- Visual check = opt-in golden PNGs with real fonts (`RUN_GOLDENS`), written to `.superpowers/sdd/ui-refresh/goldens/`, viewed by the controller; browser capture remains unreliable.
- Foreman stays a backend identity; CPMS integration parked as fog (`planning/api-integration/decisions/21-cpms-token-integration-model.md`).
- Heading rule: >= 18 px Cinzel, <= 16 px Open Sans (page titles now Cinzel; user to glance at a real screen).

## Wins & Next Step

- Wins: tables fill the width and become cards on narrow windows; one money/date format; consistent sidebar across roles; 1004 tests green.
- Next: wave 2 in flight (S2 receivables, K5 stock adjustments, K6 low stock, K7 purchasing, K9 returns, A6 audit/settings) from `d5550b3`: verify each branch, merge, review, fix pass; then wave 3 (cashier C*, manager M*, K1/K3/K8/K10, A1-A5, L1/L2), then Z1 copy sweep and Z2 whole-app pass.
