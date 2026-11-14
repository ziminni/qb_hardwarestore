# Approve Queue Route Gate

**Mode:** grill · **Status:** RESOLVED 2026-10-18 · **Opened:** 2026-10-18
**Phase:** 6C wiring (the queue screen exists; only its gate is wrong).

## The question

The approve/reject queue lives at `/admin/requisitions`, and the client fence
bounces every non-`admin` role off `/admin/*`. The seeded approver `manager` is a
pure Store Manager (client role `sales`, not superuser) — so the account that
`seed_demo` itself uses to approve requisitions is redirected to the sales
dashboard and can never open the queue. Should the fence open for them?

## Facts, verified in code on 2026-10-18

- Fence: `routes.dart` `redirectFor` — `location.startsWith('/admin/') &&
  role != 'admin'` returns the role dashboard, with one exemption already:
  `/admin/reports` for role `sales` ([Receivables Record Payment](./19-receivables-record-payment.md)
  fix pass, finding 4).
- Queue route: `adminRequisitions = '/admin/requisitions'` (`routes.dart:46`).
- Role mapping (`apps/users/serializers.py:39-41`): Store Manager → `sales`;
  Admin/System Administrator → `admin` (superusers always `admin`).
- Seeded `manager` is group Store Manager, not superuser
  (`seed_demo.py:39`); the same seed has them approving requisitions (lines 307, 314).
- Server side already admits Store Manager: requisition approve/reject views are
  `IsManagerRole` (Store Manager + Admin), the same permission class as `/reports/*`.

## Ruling (user, 2026-10-18): exempt the queue, mirroring reports.

Admit role `sales` to `/admin/requisitions` only, in the same `redirectFor`
branch as the reports exemption. Rejected: moving the queue out of `/admin/*`
(cleaner fence, but route + nav + skeleton + test churn for one screen), and
leaving admin-only (no change, but the seeded approver stays locked out of the
demo's own approval flow).

## Cost, stated plainly

Per-screen holes accumulate in the fence: reports, now requisitions. If a third
screen needs the same treatment, the exemptions should graduate into a named
manager-allowed set instead of a third `if` — that promotion is deliberately not
done here.

## Build contract (for executing-plans)

- `routes.dart`: extend the exemption to `adminRequisitions` for `sales`; keep
  Cashier (`pos`) and Stock Manager (`inventory`) bouncing everywhere under `/admin/`.
- Routing test RED→GREEN: Store Manager stays on `/admin/requisitions`;
  Store Manager still bounces off `/admin/users`; Cashier still bounces off
  `/admin/requisitions`. No backend, model, or migration change.
