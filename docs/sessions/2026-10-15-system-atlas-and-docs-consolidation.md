---
date: 2026-10-15
branch: feature/backend-integration
commits: [d18bfb6, 9aecbe4]
scope: documentation only — no application source was modified
repo: qb_pos_inventory_system
---

# Session — System Atlas & Documentation Consolidation

## Focus

Two related deliverables on the **POS/inventory** repo (CPMS deliberately untouched):

1. Reverse-engineer the repo into `docs/SYSTEM_ATLAS.md` + `docs/system-atlas.html` — every claim verified
   against source rather than the existing markdown.
2. Audit the root-level `.md` files against the codebase and consolidate them under the ICM rule
   **one home per fact**.

## What Was Built / Changed

### Deliverable 1 — system atlas (`d18bfb6`)

| File | Content |
| :--- | :--- |
| `docs/SYSTEM_ATLAS.md` (209 L) | Architecture flowchart, 27-entity erDiagram, Truth Matrix, vibe-debt hotspots, ranked study path. |
| `docs/system-atlas.html` (579 L) | Self-contained cockpit: Tailwind + Mermaid v10 CDNs, 5 tabs, filterable matrix, localStorage study checkboxes. |

Truth Matrix result: **3 live · 27 mock · 9 dead.** Only `auth` (5 routes) and `api/health/` are called by
the Flutter client; all 24 router routes + 4 report paths are uncalled.

### Deliverable 2 — docs consolidation (`9aecbe4`)

Created `README.md` (206 L), rewrote `AGENTS.md` (32 L), created `planning/` (5 files, 344 L), corrected
`ENDPOINTS.md`, made `CONTRIBUTING.md` platform-neutral. Deleted 6 files / 709 lines:
`PHASE_1.md`, `PHASE_2.md`, `PHASE_3.md`, `TEAM_UPDATE.md`, `API_CONNECTION_SETUP.md`, `flutter/README.md`.

Facts recovered from the deleted files and re-homed:

| Fact | New home |
| :--- | :--- |
| Correct credentials (`demo1234`), `seed_demo`, ports, base-URL table, `--dart-define`, Android cleartext | `README.md` |
| Unbuilt work, decisions, roadmap | `planning/` |
| Six canonical role names (from `apps/users/permissions.py`) | `ENDPOINTS.md` §3.2 |

## Mistakes & Gotchas (Do Not Repeat)

### Mermaid renders an error SVG into a hidden container

`mermaid.run({querySelector: '.mermaid'})` renders **every** diagram in the document. A diagram inside a
`display:none` tab panel fails and is replaced by a "Syntax error in text" SVG — silently, with no console
error and valid SVGs present in the DOM.

Fix: render only the active panel's nodes, so hidden panels render on first activation:

```js
const panel = document.querySelector('[data-panel]:not(.hidden)');
await mermaid.run({ nodes: [...panel.querySelectorAll('pre.mermaid')] });
```

### `<br/>` inside `<pre class="mermaid">` is a real tag

The browser parses it as an element, so it vanishes from `textContent` and corrupts the node label. Use
single-line labels instead. Escape `>` as `&gt;` in diagram source — the browser decodes it back correctly.

### A blanket `sed` silently produced malformed JS

Replacing `document.getElementById(` with `document.querySelector('#` turned `getElementById('c-' + k)`
into `querySelector('#'c-' + k)` — the original opening quote was still there. Caught only by diffing
against the backup. **Always verify after a mechanical multi-file rewrite**, and syntax-check the result
(`node --check` on the extracted script).

### Lint warnings can be stale cache

The cached `Marksman: link to non-existent document` warnings persisted after the target files were
created. A fresh probe (`lens_diagnostics source=lsp mode=full`) reported **0 diagnostics**. Do not treat a
cached finding as current — re-probe before "fixing" a non-issue.

### Static checks passed while the page was visually broken

JS syntax check clean, lint clean, both SVG elements present — and Tab 2 still showed an error. Only a
**screenshot** revealed it. For visual deliverables, render and look; DOM/syntax assertions are not enough.

### `ENDPOINTS.md` contained two false claims

| Claim | Reality |
| :--- | :--- |
| "Pagination: **None for now** — list endpoints return full arrays" | `settings.py:167-168` sets `PageNumberPagination`, `PAGE_SIZE = 50`. Every list returns `{count, next, previous, results}`. |
| "`tests.py` are still empty stubs across all apps" | **546 lines** of real tests across 5 apps. |

The pagination one is integration-breaking: following it produces a type error on every list screen.
This doc is designated the canonical API contract, so errors here are the most expensive kind.

### `foreman` authenticates but cannot reach a dashboard

| Layer | Behaviour |
| :--- | :--- |
| `apps/users/permissions.py:19` | defines role `Site Foreman` |
| `apps/users/serializers.py:39-41` | role→segment map omits it; fallback yields `site_foreman` |
| `flutter/lib/routes/routes.dart:68` | `dashboardForRole()` matches only `admin`/`inventory`/`pos`/`sales` → `null` |
| `flutter/lib/routes/routes.dart:120` | `if (dashboard == null) return isLogin ? null : login;` |

Result: HTTP 200, valid JWT, then bounced straight back to `/login`. The Flutter tree has **zero**
`foreman` references. Backend permissions are correct — this is a client routing gap.

### `git commit <path>` does not pick up untracked files

The atlas files were untracked, and `git rm` had already staged 6 deletions that would have been swept into
the atlas commit. Resolve by `git reset` (unstage), staging and committing per path explicitly.

### Other traps hit

- `git rev-list master..HEAD` fails — there is **no local `master`**; locally it is `main` while the remote
  default is `master`, and `CONTRIBUTING.md` says `master`. Naming is split across the two.
- Schema reality: `ProductSerializer` sends only `id, category, category_name, brand, brand_name, base_name,
  description, image_url, is_active, variants, created_at, updated_at`. `flutter/lib/data/models/product.dart`
  reads `sku`, `cost_price`, `selling_price`, `current_stock`, `reorder_level`, `qr_identifier`,
  `storage_location` — **none exist**. By contrast `data/models/inventory.dart` matches
  `StockAdjustmentSerializer` exactly, so it is correct but misleadingly named.
- Markdown lint rules that fired on freshly written docs: MD040 (fenced block needs a language), MD060
  (padded `| --- |` separator rows), MD036 (use real headings, not bold pseudo-headings), MD028 (two
  adjacent blockquotes — merge with a `>` separator line).

## Decisions

| Decision | Rationale |
| :--- | :--- |
| Delete all 5 obsolete root docs + the generated `flutter/README.md` stub | Every unique fact was re-homed first; nothing referenced them; all carried the wrong password (`admin123`). |
| Doc homes are now single-purpose | `README.md` = setup; `AGENTS.md` = routing; `docs/SYSTEM_ATLAS.md` = architecture/truth matrix; `ENDPOINTS.md` = API contract; `CONTRIBUTING.md` = process; `planning/` = unbuilt work; `docs/sessions/` = history. |
| `CONTRIBUTING.md` stays **platform-neutral**, not Linux-only | The team spans macOS (a teammate), native Windows, and WSL/Linux. Listing macOS-only commands was the bug; replacing them with Linux-only would repeat it. |
| `planning/` holds unbuilt work, not `docs/` | Keeps roadmap separable from architecture, and matches what `AGENTS.md` already pointed at. |
| Split into two commits (atlas, then consolidation) | The atlas is a finished standalone deliverable; the consolidation is a separate decision with its own rationale. |
| POS DB host port stays `5435` in the shared `docker-compose.yml` | Only a mapping's left-hand host port can conflict; this avoids a host-installed Postgres on `5432`/`5433`. |

## Wins & Next Step

**Verified working:** the atlas renders correctly in a real browser (2 Mermaid diagrams, 27 entities; matrix
38 rows; filters 27 mock / 8 dead; search 12 hits for "sales" with a working empty state; study checkboxes
with `localStorage` persistence). All doc links resolve (0 broken across 9 files); fresh LSP probe reports 0
diagnostics. Backend stack healthy on 8000 (API) / 5435 (DB), 5 seeded accounts verified live.

**Next step — do not start by writing API calls.** Three prerequisites come first:

1. Fix `flutter/lib/data/models/product.dart` — it reads 7 fields the backend never sends.
2. Register `ProductsViewmodel` and `PosTransactionViewmodel` in `flutter/lib/main.dart` (only 6 of 8
   viewmodels are wired, so they are currently unreachable).
3. Handle the paginated envelope (`response.data['results']`, not `response.data`).

Only then wire `products` → `inventory` → the rest, per `planning/api-integration/MAP.md`. A recovered
earlier implementation of exactly this (`pos_service.dart` calling `/products/` and `/batches/`) is
salvageable from commit `22c7c26` — see `planning/02-lost-work-recovery.md`.
