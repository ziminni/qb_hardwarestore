# POS evolution Phase 8 — supplier returns, credit notes, supplier cheque clearing: build, gates, review and QA handoff

## Status

**Phase 8 🟡 In Progress — build, review, gates and isolated live QA complete; OWNER CLOSURE STILL PENDING.** Branch `feat/pos-evolution-phase-8`, from Phase 7 `c21a25e`. Decision [20 Supplier returns, credit notes and cheque clearing](../../planning/pos-evolution/decisions/20-supplier-returns-and-cheques.md); canonical plan/evidence [phase-8-plan.md](../../planning/pos-evolution/phase-8-plan.md). **No commit/push, no dev startup/migration/reset.**

## Scope delivered

Goods can go back to a supplier from a chosen PO receipt, minting a numbered credit note that pays down the bill the goods came in on and leaves the remainder as supplier credit a manager applies by hand; supplier cheques now start `ISSUED` and are cleared or bounced once, a bounce restoring the bill. `SupplierReturn` / `SupplierReturnLine` / `SupplierReturnDeduction` and `SupplierCreditNote` are new `inventory` models (append-only like bills); `SupplierPayment` gains `status`/`decided_by`/`decided_at`/`decision_reason`/`credit_note` and `Method.CREDIT`. `StockAdjustment.AdjustmentType.RETURN` is retired as an input (`USE_SUPPLIER_RETURN`); historical rows keep their label. Four migrations: inventory `0012_supplier_cheque_status`, `0013_supplier_returns`, `0014_supplier_credit_notes`, users `0007_supplier_return_audit`. No new route file, VM class or service file — three widgets on existing pages plus two router registrations (33 → 35).

| Task | What it landed | RED evidence |
| --- | --- | --- |
| B1 | Payment `status`/decision fields + `Method.CREDIT`, `clear/` and `bounce/`, once-only decision, `save()` narrowed to the four decision fields while ISSUED | 21 tests, 6F + 19E — cheque created without status, bounce restored nothing, second decision allowed |
| B2 | `SupplierReturn` + lines + deductions, `allocate_from_receipt` (that receipt's batches only), `returnable/` read, RETURN-adjustment retirement, `SUPPLIER_RETURN` audit | ImportError pre-models + RETURN adjustment 201-vs-400; mutation check proved receipt scoping (2 fail variant-wide) |
| B3 | `SupplierCreditNote`, `CN-` numbering via the locked counter, landed-cost value, VAT snapshot both ways, auto CREDIT payment against the source bill | credit > balance absorbed anyway, paid bill still applied, VAT totals off by a cent |
| B4 | Manual `CREDIT` apply under note → bill lock, `?open=true` note list, payables `credited`/`unapplied_credit`/`issued_cheques` | other supplier's note accepted, cap bypassed, summary fields missing |
| F1 | Client data layer: payment status/decision fields, CREDIT decoded-but-unselectable, note/return/returnable models, unknown-status fallback | decode tests on server fixtures (builder-attested; logs not persisted — retained minor) |
| F2 | Return dialog on PO details, receipt-first flow, refusals inline with input kept, double-submit guarded, adjust dialog loses “Supplier Return” | missing API symbols; one pagination fix round (`getAll` beyond page 1) |
| F3 | Payables tabs Bills / Credit notes / Supplier cheques, Apply credit in the pay dialog, manager-only Clear/Bounce, bill details naming `CN-…` | tabs absent, apply-credit ungated, queue read-only for everyone |

## Gates (controller-owned, local + gitignored)

| Gate | Result |
| --- | --- |
| Django full suite | **1219 tests OK** |
| `manage.py check` | clean |
| `makemigrations --check --dry-run` | **No changes detected** (leaves inventory `0014`, users `0007`, pos `0016`) |
| `flutter analyze` | **No issues found!** |
| Flutter ordinary suite | **2142 passed / 241 skipped** |
| Goldens (`RUN_GOLDENS=true`) | **241 passed, ZERO changed captures** — all byte-identical, so nothing to inspect and nothing regenerated |

## Review — APPROVED, no blockers

`temp/p8/review/report.md` traced the money chain (return → note → auto apply → manual apply) with `remaining` as the subject and `applied = min(remaining, balance)`, found **no lock cycle** (receipt → batches(PK) → note → bill; decide payment → bill; `record_supplier_payment` locks the bill only), confirmed the RETURN-adjustment retirement keeps historical labels, confirmed the balance math keeps `unapplied_credit` out of the balance so it can never go negative, and confirmed every Flutter screen shows the server's `detail` inline with the input kept and double-submit guarded. Two wiring additions outside the brief's file lists are documented in the plan (`inventory_service.dart` pagination fix, `purchases_page.dart` as the only construction site of the details dialog). Non-blocking warnings: close-out docs were still to be written, `pos_payment_dialog.dart`'s diff is formatter churn only (reverted before commit), a cosmetic 404 sentence, and the `restored ≤ total` assert as belt-and-braces.

## Isolated live QA — all scenarios PASS, zero confirmed defects

Ran on `buildpro_p1d_qa_{db,backend,web}` (`172.20.0.*`, API `:8001`, web `:8091`); inventory `0012`–`0014` and users `0007` applied to that isolated database only, dev containers stayed stopped, QA made no source edits and ran no suites. Report `temp/p8/qa/report.md`.

Passed: return **2 BAG from receipt A** with **receipt B untouched** (DB read-back: batch #12 75.00 → 25.00, #13 still 125.00; return #1 = 50.00 base units, ₱500.00 note); **₱500** note against a partly paid bill applied **₱320** and left **₱180** as credit; manager applied **₱150 + ₱30** through the UI with the cap message inline (`CN-20261113-0001 has ₱180.00 left.`) and no request sent; cheque **issue → clear** (balance unchanged) and **issue → bounce** (**₱200 restored**); second clear/bounce **409 `CHEQUE_ALREADY_DECIDED`**; role fences (Cashier 403 on return, Stock Manager 403 on apply, read-only tabs for Stock Manager); retired `RETURN` adjustment **400 `USE_SUPPLIER_RETURN`**; a stale-form refusal shown inline without a raw business code; payables reconciled by API + DB read-back (**₱2,400 = ₱980 paid + ₱500 credited + ₱920 balance**, unapplied credit ₱0); return dialog and payables tabs/queue at **1440 / 1100 / 760** with no horizontal overflow.

## Retained minors and limits

- **25 pre-existing RUF012 hits** in `apps/inventory/serializers.py` — HEAD-identical; that file's convention is an inline `# noqa` — plus **2 in migration `0012`**, where Django canonicalises the model names inside `dependencies`/`operations`, so the rule cannot be satisfied in a migration at all. **All dispositioned false-positive**, zero behavioural effect, no refactor shipped.
- The **Django-stub Pyright family** on model/counter code — same dispositioned false-positive family as Phases 6 and 7; a green suite is not a clean diagnostics verdict.
- Cosmetic: a canned 404 sentence in `payables_service.dart` would read slightly off for a non-cheque id (unreachable through the UI — the queue is cheque-filtered server-side).
- F1's RED logs were not persisted (builder-attested); F2 needed one fix round (`getAll` pagination, RED re-witnessed).
- **Not covered, not claimed:** a live 1.3 text-scale run, keyboard-only traversal, printing/PDF, concurrent return/payment or cheque races, browser-side return submission by Store Manager/Admin, a zero-bill return, a VAT-exclusive note in the browser, and the full suites (QA ran none — the gates are the automation evidence).

## Next

Owner closure (Phase 8 stays In Progress until then), then a local commit only when told; owner pushes. Phases 9 → 3 → 2 follow in order.
