# 2026-11-08 — POS evolution Phase 1b build and verification

**Status:** Phase 1b ✅ Done 2026-11-08 with explicit owner-accepted QA limits. Tasks 0–10, reviews, final automated gates and core isolated live QA are complete. Unverified checks below remain unverified; this is not deployment or commit authorization.

## Scope and ownership

- Branch: `feat/pos-evolution-phase-1b`, based on Phase 1 completion `fa0f342`. Changes remain uncommitted; no commit/push was authorized for this execution.
- Canonical checklist: [Phase 1b plan](../../planning/pos-evolution/phase-1b-plan.md#execution-checklist). Roadmap: [POS evolution MAP](../../planning/pos-evolution/MAP.md).
- Owner waived prediction prompts and required subagents. At most two builders; backend work sequential; Flutter test concurrency 2.
- Owner explicitly delegated the originally joint-owned completion predicate. Owner requested the v0.2 contract diff, then explicitly chose **Approve and continue** on 2026-11-08. The contract is provisionally accepted; this does not approve existing dev DB writes or Phase 1c execution.
- `qb_project_management_system/` was not changed. No dev DB migration, flush or reseed was performed.

## Built and task-verified

- History-preserving `requisitions.0003_store_review`: APPROVED → ACCEPTED, nullable line intent/reasons, request decline reason and nullable released-value accumulator. Historical released quantities imply an unknown money baseline; quantities, credentials, sales, ledgers, payments and audit history are preserved.
- Imports land WAITING. Store Manager/Admin accept every line explicitly (at least one Available) or decline the whole request with a reason. Acceptance reserves no stock and creates no debt. Generic writes and retired approval actions stay unavailable.
- Accept, Decline, Close and Release share token-then-request locks and repeat state checks under lock. WAITING/DECLINED scanner refusals explain the state before generic spent-token errors.
- False lines never consume shared stock or keep a token open. PARTIAL retains the token; RELEASED means all eligible lines are complete, even if a declined line retains numeric outstanding quantity.
- Releases accumulate the persisted two-decimal sale total atomically. Unknown historical totals remain null after later releases. Expected amount is a live non-debt budget: known released value plus current-priced outstanding Available quantities, rounded once; payments affect payables, not that estimate.
- Staff and CPMS read the same budget helper. Read-back preserves true shortfalls and includes store decisions/reasons, without exposing per-unit prices, stock, tokens or internal released totals.
- Shared Requests from projects queue, two role shells/routes, appended sidebar indices and server-total badge. Review recovery handles unreadable success, uncertain outcomes and conflicts before re-enabling actions. List generations guard stale rows/counts/errors and spinner completion; notifications are disposal-safe.
- Till summaries/receipts exclude declined lines from open counts and show store reasons. Reports retain the separate CPMS approver. Seed exercises ACCEPTED/FULL, RELEASED, PARTIAL, WAITING and DECLINED through real services and is repeat-safe.

## Reviews and automated verification

Every implementation task received source review and controller verification; per-task RED/GREEN evidence is in the plan. Final whole-change source review returned **APPROVED, zero Important/Critical findings**. Minor action-response per-line relation queries were noted, not changed.

Latest final controller reruns (logs `temp/p1b-qa/controller/final-*`; all six gates exit 0):

| Command | Actual result |
|---|---|
| `docker exec buildpro_backend python manage.py test --noinput` | 699 tests, OK, exit 0; disposable Django test database only |
| `... manage.py check` | No issues, exit 0 |
| `... manage.py makemigrations --check --dry-run` | No changes detected, exit 0 |
| `flutter analyze` | No issues, exit 0 |
| `flutter test --concurrency=2` | 1408 passed / 225 skipped, exit 0 (1409 after the 2026-11-09 Review fix) |
| `flutter test --tags golden --dart-define=RUN_GOLDENS=true --concurrency=2` | 225 passed, exit 0 after the test-only fixture fix |
| QA web build with `API_BASE_URL=http://127.0.0.1:8001` | Exit 0; static output `/tmp/qb-p1b-qa-web` |

### Golden investigation

Initial full run failed only login 1440: exactly 48 pixels, the blinking username caret. Focused rerun passed unchanged. First fixture pass pinned calm-state carets but found error-760's off-phase master and a separate late JPEG decode (missing logo). Final test-only pass pins/restores the deterministic cursor for every snapshot and awaits actual `Image` providers through `precacheImage` inside `tester.runAsync`, replacing a guessed 300ms delay.

Only error-760's master was authorized to change. RED without update proved 48 white→gold caret pixels; the controller independently decoded both PNGs and confirmed exactly 48 changes at x275–276/y480–503, with all other pixels and the other three masters byte-identical. Focused four-test file passed three times; controller then passed all 225 goldens and ordinary/analyzer gates. No production UI/auth/SDK/theme change, skipped test or relaxed comparator. Backups and hashes: `/tmp/p1b-testonly/`.

Scoped fixture/atlas review returned APPROVED, no blocking findings. Both atlas artifacts now agree: 40 routes; 19 VM classes/20 files; 17 actual ApiClient-importing service files/22; 35 direct app models plus custom User = 36; matrix 36 Live/1 Partial/0 Mock/3 Dead across 40 rows. Controller asserted source counts, matrix parity, JavaScript syntax and 34 local documentation links. Atlas HTML was not browser/DOM-tested.

## Isolated live QA

Owner approved disposable QA, not writes to the existing dev DB. Isolation was checked before migration/seed:

- Network `buildpro_p1b_qa_net`, disconnected from the dev Compose network.
- PostgreSQL container `buildpro_p1b_qa_db`, separate volume `buildpro_p1b_qa_pgdata`; zero public tables before migration.
- QA backend DNS `db` resolved to its isolated PostgreSQL IP, different from `buildpro_db`; backend is attached only to the QA network. Current backend source is mounted read-only.
- API container `buildpro_p1b_qa_backend`: `http://127.0.0.1:8001`; static web container `buildpro_p1b_qa_web`: `http://127.0.0.1:8091`.
- Disposable migration and seed exited 0: 5 users, 8 batches, 7 transactions, 3 open utang ledgers. Both HTTP endpoints became healthy. One initial static-server connection reset disappeared after readiness; no application change was needed.
- Evidence: `temp/p1b-qa/setup.txt`, `migrate.log`, `seed.log`; dynamic tokens remain in local seed output, not this note.
- Independent report: local `temp/p1b-qa/report.md`. Core browser/API flows PASS, no Critical/Important defect found in tested scope. Seven final probes recorded 14+28+21+56+17+15+10 passing assertions; baseline probe made 20 calls. Controller parsed final JSONL/status summaries, found no HTTP 5xx, compiled probe helpers and visually confirmed both reported label issues.
- Browser scale 1.0 passed at 1440/1100/760 for queue/dialog/till, including keyboard focus, long reasons, list/dialog scrolling, >50-row search/badge updates, mixed review/release, full and restock/rescan, refusals and role routing. Money/history/price/payment checks passed through live APIs; a barrier-synchronized two-reviewer race had one winner/one 409 and one audit decision.
- QA changed stock/prices, created sales/debt/payment rows, consumed seeded tokens and added queue rows. Preserved QA data is **not pristine seed data**; rerunning the idempotent seed will not reset it. Existing dev data remains unchanged. Containers/volumes/evidence remain intact; no automatic cleanup. Local seed/private-fixture artifacts contain bearer credentials: keep `temp/p1b-qa/` untracked and never include it in a commit.

## Owner-accepted limits and handoff

After the QA report and controller evidence review, the owner selected **“Close with limits (Recommended)”** on 2026-11-08. This explicitly accepts the following gaps/cosmetic issues rather than marking their checks passed:

- Genuine browser 1.3× text scaling was blocked by harness capability. No zoom/device-scale substitution was counted. Queue/dialog have actual `MediaQuery` 1.3 widget coverage; till 1.3 remains unverified.
- No live timeout/unknown-outcome injection or simultaneous Close-vs-Review race. Sequential stale-after-close and concurrent two-reviewer checks passed; automated coverage does not replace the missing live probes.
- Sidebar destination "Requests from projects" truncates to "Requests from p…" in both Admin and Store Manager sidebars at 1440 (`temp/p1b-qa/screenshots/queue-1440.png`). Minor, accepted, unfixed: fitting it needs a shorter label (owner wording call).
- **Fixed 2026-11-09:** "Review" split mid-word at 1100. Action column now has weight 2 (`project_requests_content.dart`); new real-font test in `project_requests_page_test.dart` failed first (needed 50 px, had 38 px), then passed. The queue golden's guessed logo-size preload was replaced by precaching the images actually on screen, removing a parallel-load flake. Regenerated `p1-requests-1440` and `p1-read-only-1100` and inspected them. Reruns: analyze clean, Flutter 1409 passed/225 skipped, goldens 225 passed twice (all exit 0); backend unchanged.
- Atlas HTML was not browser/DOM-tested; native desktop pixels and real paper printing remain unchecked.

Plan Task 10 and MAP Phase 1b are closed on this basis. Work remains uncommitted; no push, dev DB migration/reset, QA cleanup or CPMS change was authorized. Next on request: plan Phase 1c receipt storage/allocation; do not start its implementation.

## 2026-11-09 follow-up: dev reseed, QA teardown, sidebar rename

- Dev DB (`buildpro_db`, :8000) reached Phase 1b when a backend restart applied 0003 (entrypoint migrates on every start). Owner approved the wipe: `migrate` (no-op) + `flush --noinput` + `seed_demo` exit 0; R1001–R1005 match the README table, five logins and health 200. Tokens live only in gitignored `temp/dev-reseed/seed.log`.
- Isolated QA stack (`buildpro_p1b_qa_*`, :8001/:8091) removed with owner approval; evidence stays in `temp/p1b-qa/`.
- Owner renamed the sidebar label to "Project requests" (page title unchanged) to fix the 1440 truncation. RED-first width test, 17 label-only golden regenerations, reviewer APPROVED; gates 1410 passed / 225 goldens / analyze clean. Dev e2e PASS with no defects (`temp/dev-e2e/report.md`), then dev reseeded again so the demo data is clean.
- Gotcha: regenerating a drawer golden alone with `--plain-name` dropped the logo; regenerate the whole file, then confirm only intended PNGs changed.
- Branch pushed at `bcf2efd` (includes `clock ^1.1.2` for older Windows Flutter SDKs). Phase 1c still blocked on "Receipt storage and allocation"; wayfinder first.
