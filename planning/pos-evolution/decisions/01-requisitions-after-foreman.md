# Requisitions after the foreman

**Mode:** grill · **Status:** ✅ Locked 2026-11-03 (by: me — user chose option A)
**Supersedes:** [Requisition UI Ownership](../../api-integration/decisions/09-requisition-ui-ownership.md) on *who approves*, and the POS approve queue in [Approve-queue route gate](../../api-integration/decisions/20-approve-queue-route-gate.md). **Answers** open question 1 of [CPMS ↔ POS material-token integration model](../../api-integration/decisions/21-cpms-token-integration-model.md).

## Decision

The POS keeps a **read-only copy of approved material requests**. Requests are created by the foreman and approved by the project manager **in CPMS**. The POS stores the project, the requested items, the token, and the CPMS requester's **name as plain text**. The cashier still releases materials by scanning the token at the till.

## Why

- The foreman is not a POS user and must not see POS inventory (product owner, 2026-10-30).
- Approval in one system only; the POS keeps the part it is good at: stock out, FIFO, receipt, project payable.

## What this removes from the POS (verified in source 2026-11-03)

- `Site Foreman` group and the `foreman` seed account (`apps/users/management/commands/seed_demo.py:37,45`).
- `Requisition.requested_by` FK to a POS user (`apps/requisitions/models.py:67`, `on_delete=PROTECT`); replaced by a requester-name text field. `approved_by` becomes the CPMS approver's name as text too.
- Foreman-only scoping (`apps/requisitions/views.py:100-108,158,343`), `perform_create` stamping `requested_by` (`:160-164`), `IsForemanOrManager` / `IsForemanOrManagerOrReadOnly` (`apps/users/permissions.py:123,147`).
- POS create / submit / approve / reject actions and the self-approval guard (`apps/requisitions/services.py:55`).
- Approvals screens: admin `/admin/requisitions` and Store Manager `/sales/requisitions` (`features/admin/views/requisitions_page.dart`, its viewmodel, token panel), their sidebar entries and "Requisitions waiting" tiles; `salesTwinOf` loses its requisitions arm.

## What stays

`Project`, `Requisition` (statuses the POS can see: approved, released), `RequisitionItem`, `MaterialToken`, the cashier release flow (`/pos/release`, `release_materials` FIFO + `SalesTransaction(source=REQUISITION)` + receivable), and the unsupported-role screen for any account with no role.

## Open (see MAP)

How approved requests and projects reach the POS, how existing rows migrate, and project-as-customer payables.
