---
date: 2026-10-15
branch: feature/backend-integration
commits: [664f109, bb8d6a1, 722279f]
scope: planning only — no application source modified
repo: qb_pos_inventory_system
skill: wayfinder (Map Mode)
---

# Session — Integration Map Opened (Wayfinder, Map Mode)

## Focus

The user reviewed `docs/SYSTEM_ATLAS.md` and was overwhelmed: 27 screens on mock data, 8 dead rows, no idea
which feature, role or module to wire first. The job was to analyse the real state, decide the smartest order
of attack, and set up a master Map so integration proceeds one module at a time.

Wayfinder ran in **Map Mode** — too large for a single plan file, and the upstream choices constrain every
downstream module.

## What Was Built / Changed

| Path | What |
| :--- | :--- |
| `planning/api-integration/MAP.md` | Destination, 7 invariants, frontier (6 open), blocked (empty), fog of war, out of scope. |
| `planning/api-integration/decisions/01-first-vertical-slice.md` | **LOCKED** — Cashier journey. |
| `planning/api-integration/decisions/02-product-variant-client-model.md` | Open · Phase 0 · gates Phase 1. |
| `planning/api-integration/decisions/03-pagination-envelope-strategy.md` | Open · Phase 0. |
| `planning/api-integration/decisions/04-role-dashboard-routing.md` | Open · Phase 0, needed again at Phase 5. |
| `planning/api-integration/decisions/05-sales-stack-reconciliation.md` | Open · Phase 6 (released from blocked). |
| `planning/api-integration/decisions/06-checkout-client-contract.md` | Open · Phase 3 (graduated from fog). |
| `planning/api-integration/decisions/07-loading-error-empty-convention.md` | Open · Phase 0 (graduated from fog). |
| `planning/MAP.md` | Index now separates the active map from reference plans. |
| `AGENTS.md` | Active-plan pointer + rewritten next step. |
| `docs/SYSTEM_ATLAS.md`, prior session note | Truth Matrix tally corrected. |

`planning/01-api-integration.md` was **absorbed and deleted** — it covered the same epic, so keeping both
would have been two homes for one fact. 6 stale code references were repointed.

Commits: `664f109` map opened · `bb8d6a1` atlas tally fixed · `722279f` slice locked.

## Mistakes & Gotchas (Do Not Repeat)

### The atlas disagreed with itself, and the HTML was the correct one

`SYSTEM_ATLAS.md` claimed `3 live · 27 mock · 9 dead` (= 39), the HTML KPI said 38 with 8 dead, and the true
count is **38 rows = 3 live · 0 partial · 27 mock · 8 dead**. The whole plan was about to be built on a number
that did not add up. Two independent artifacts of mine disagreed and neither was checked at the time.

### My row counter over-counted, and the over-count hid the real answer

The first count returned 40 rows / 10 dead, because the emoji marker `⚫` also appears in §4's orphan-file
table — not just in the Truth Matrix. Counting by marker across a document catches every table that uses it.
Scope the parse to the intended table.

### A verification grep ran in parallel with the edit it was checking

An `edit` and its verifying `grep` were issued in the **same tool block**, so they executed concurrently: the
grep reported pre-edit state and a successful edit looked like a failure. **Verify your own writes in a
separate, later call.**

### Link checkers do not catch stale code references

A Python checker that parses markdown link targets reported **0 broken links** while 6 backtick references
to a deleted file — `` `planning/01-api-integration.md` `` — sat in 5 files. Filename references in prose are
invisible to link checkers. Grep for the filename separately after any merge or delete.

### Count arithmetic drifted from the list it described

The map's status line said "1 locked · 5 open" while its own frontier list rendered six items. Caught only by
counting the list and comparing. When a summary number describes a list, derive it from the list.

### Filtering `lens_diagnostics` by directory fails

`source=lsp` with a directory path errors (`not a file`); it needs explicit file paths — pass the files, not
the folder.

### FK extraction needs multi-line handling

Matching `models.ForeignKey(X)` on one line missed 34 of 36 relations, because most declarations put the
target on the following line. A naive regex reported a 6-FK schema for a 36-FK database — dangerously
plausible output that would have produced a wrong dependency order in a per-app format.

### The insight that actually unlocked the decision

The dependency chain *looks* like it forces building a stock-receiving UI before POS. **It does not** —
`seed_demo` already supplies products with stock batches, customers, completed sales and an approved
requisition with a minted token. So the order is a product choice, not a forced march. Before accepting a
dependency ordering as forced, check whether seeded demo data already breaks it.

## Decisions

| Decision | Rationale |
| :--- | :--- |
| **Locked: Cashier journey slice** — products → inventory → POS checkout → customers → requisitions → admin | Exercises both hubs, ends every phase with something showable, and `seed_demo` removes the data-creation prerequisite. Beats reference-data-first (nothing demoable for 2-3 sessions), requisition-first (blocked) and admin-first (teaches nothing). |
| **Ordering lens** — prove the pattern on the highest-value read, then walk the dependency chain, one demoable outcome per phase | Governs every later session on the map. |
| Map Mode over Compact Mode | 27 screens, and Phase 0 choices constrain every downstream module. |
| Absorb `01-api-integration.md` into the map | Two files describing one epic violates one-home-per-fact. |
| Six decisions stay open; resolve **one per session** | Keeps the frontier honest and the context window lean. |
| Nothing is Out of Scope by accident | Backend is feature-complete, so this is a client-only epic: no new endpoints, no schema changes. |

## Wins & Next Step

**Verified:** 18 doc files with 0 broken links · 7/7 decision links resolve to real files · 0 orphan decision
files · map self-consistent at **1 locked · 6 open · nothing blocked** · fresh LSP probe reports 0 diagnostics
· working tree clean apart from the deliberately-untracked `flutter/test/`.

**Structural finding worth carrying forward:** the 36 foreign keys form a clean 6-layer DAG, and two entities
carry almost all the weight — **`ProductVariant`** (6 dependents, spanning inventory, POS and requisitions) and
**`Customer`** (3 dependents, spanning POS, collectibles and projects). The 8 dead rows are not 8 problems:
2 are orphaned legacy dashboards and 6 are simply layers not yet reached.

**Next step:** resolve `planning/api-integration/decisions/02-product-variant-client-model.md` in
**domain-model** mode — it gates Phase 1. The question to sketch with the user: does the client model a
`Product` with nested variants, or split `Product` / `ProductVariant` / `InventoryBatch` into three entities?
`product.dart` currently reads 7 fields the backend never sends, and real stock lives on `InventoryBatch`
behind `/api/v1/batches/`, not on the product. Do not start Phase 1 code until the Phase 0 decisions are locked.
