---
date: 2026-10-20
branch: feature/backend-integration (pushed, in sync with origin)
status: Phases 0-6 built, QA pass done, no build phase remains
---

# 2026-10-20 — Atlas refresh to 100% live, branch pushed, full API QA pass

## Focus

Three things, in order: (1) incremental refresh of `docs/SYSTEM_ATLAS.md` + `docs/system-atlas.html` so the
Truth Matrix reflects Phases 0–6 and the dashboard mock-purge; (2) hand off for manual testing once the user
pushed the branch; (3) run the `qa-tester` protocol over every live workflow and edge case.

## What Was Built / Changed

- **Atlas refreshed from source** (`5b5991a`) — no app code touched. Truth Matrix went 10 live → **23 live ·
  2 partial · 5 mock · 7 dead/deleted** (37 rows). Backend counts corrected 25 → **31 models** (added
  `Quotation`, `QuotationItem`, `SalesOrder`, `SalesOrderItem`, `SalesItemDeduction`), 39 backend routes,
  26 client-called paths, 28 `GoRoute`s, 17 viewmodels, 28 screens. erDiagram gained the quotation/order/
  deduction edges; all six backend service flows now marked as having observed client consumers. `MD` 249
  lines (under the 250 budget); `HTML` KPIs, model map, truth matrix, debt cards and study path (8 → 11
  items) all re-derived.
- **Branch pushed by the user**; local `feature/backend-integration` is in sync with `origin/`, tree clean.
- **QA pass executed inline** under `qa-tester.md` (see Mistakes for why inline): auth matrix × 5 roles,
  catalogue/batches/alerts/categories, synthetic adjustment + reversal, exact sale, both underpay paths,
  insufficient stock, linked return + return-of-return + over-draw, quotation → sales order, PO/receipt
  guards, requisition approve + token verify, all four reports with role gates, users list/stats/register
  validation, ledgers + aging.

## Mistakes & Gotchas (Do Not Repeat)

- **The `qa-tester` subagent cannot start on this account.** Two launches (default model, then
  `opencode/glm-5.3-flash`) both died with HTTP 402: the request asked for ~926k max tokens while the
  OpenRouter balance covered ~31k. Zero tool uses — nothing was tested, nothing touched. Fallback that
  worked: run the `qa-tester.md` protocol inline (same mission, finding format, evidence labels).
- **`docs/system-atlas.html` had a pre-existing missing comma** after the `s8` study entry — it broke the
  entire `<script>` block, so every tab was dead. Caught only by extracting the script and running
  `node --check`. Do that after any edit to that file; a green-looking page can be inert.
- **Three atlas rows claimed endpoints the client never calls.** Suppliers, purchases and categories listed
  `GET /suppliers/` etc. because the backend serves them; verification showed
  `suppliers_purchases_viewmodel` imports no service and the category path appears nowhere in `lib/`.
  Corrected to "endpoint exists, uncalled". A backend route existing is not evidence of a client caller.
- **`GET /products/` has no `name` key** — it is `base_name`, with variants nested. A probe assumed `name`
  and raised `KeyError`; read the envelope before scripting against it.
- **Wrong password returns 400, not 401** (`{"non_field_errors":["Invalid username or password."]}`) — DRF
  serializer behavior. Not a defect, but don't assert 401 in a test.
- **Goods-receipt validation order**: a receipt against a COMPLETE PO returns
  `"PO 1 is COMPLETE and cannot receive more."` *before* any per-item checks, so item-level errors
  (unknown `po_item`, over-qty cap) are unreachable while every seeded PO is COMPLETE.
- **`flutter test` / `flutter analyze` must run from `flutter/`**, and `manage.py test` must run inside the
  container (`docker compose exec -T backend`) — direct host runs fail on DB/host resolution.

## Decisions

- QA writes stayed synthetic and labelled: one adjustment (+0.50) with an exact reversal, sales to Maria
  Santos, and a quotation/order pair. Nothing was flushed or reset; the human still tests on real data.
- **The irreversible release flow was NOT executed** — it FIFO-deducts stock, writes a sale and always
  leaves a receivable. Req 2 was approved and its token left staged so the first manual click is
  meaningful. Over-receipt/process-guard and partial-payment paths were deliberately left to the backend
  suite (green) rather than mutating seeded ledgers.
- Atlas is generated from source each time; docs claims are never trusted as evidence.

## Wins & Next Step

- Wins: atlas now tells the truth (23 live / 5 mock / 7 dead) with a working cockpit; branch is pushed and in
  sync; every live workflow was probed API-live and **all refusal paths returned the specified code +
  message**; suites green in the same session — backend **89/89**, flutter **395/395**, analyze clean, tree
  clean.
- Demo data after QA (honest, labelled): 10 transactions (TRX-0008/0009 sales, TRX-0010 return),
  4 ledgers (Maria 4900 OPEN, Dela Cruz 472 OPEN, two PAID), 1 quotation (QT-0001 DRAFT), 1 sales order
  (SO-0001 CONFIRMED), adjustments 6+7 netting to zero, requisition 2 APPROVED with token
  `132933b4-d825-4c94-beb6-bd1a4660f3f1`.
- Next: manual UI testing of the pushed build (`flutter run -d web-server --web-port 8080` against
  `http://127.0.0.1:8000`, users `admin`/`manager`/`cashier`/`stocker`, password `demo1234`), starting with
  the staged material release. Then wayfinder for the next scope decision (account edits via `assign_role`,
  paged staff list, or the CPMS repo) — no build phase remains on this map.
