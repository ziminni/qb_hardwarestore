# Role to Dashboard Routing for All Six Roles

**Mode:** grill · **Status:** LOCKED 2026-10-15 · **Opened:** 2026-10-15

## The question

Should the client map all six backend roles to a dashboard, and what does each unmapped role see?

## Why it matters

The `foreman` account authenticates successfully (HTTP 200, valid JWT) and is then bounced straight back to
`/login`, because `dashboardForRole()` has no case for the role the backend actually sends.

| Layer | Behaviour |
| :--- | :--- |
| `apps/users/permissions.py:19` | Defines the role `Site Foreman`. |
| `apps/users/serializers.py:39-41` | The role to segment map omits it, so the fallback emits `site_foreman`. |
| `flutter/lib/routes/routes.dart:68` | `dashboardForRole()` matches only `admin`, `inventory`, `pos`, `sales`; everything else returns `null`. |
| `flutter/lib/routes/routes.dart:120` | `if (dashboard == null) return isLogin ? null : login;` |

The Flutter tree contains **zero** references to `foreman`. Backend permissions are correct — this is purely a
client routing gap. It blocks the requisition and token-release flow, since that flow begins with a foreman
creating a requisition.

## Options

### A. Map `site_foreman` to a new foreman dashboard

Most correct: a foreman sees projects and requisitions, which is what the role is for. Requires building that
dashboard, which is currently in the Fog of War.

- **Cost:** new screens before any existing screen is wired.
- **Risk:** scope grows before the first win.

### B. Map `site_foreman` to an existing dashboard for now

Unblocks testing immediately and can be revisited. Cheapest path to a working requisition demo.

- **Cost:** a foreman briefly sees screens that are not theirs.
- **Risk:** a temporary mapping becomes permanent by accident.

### C. Treat the role as unsupported and surface a clear message

Route unmapped roles to an explicit "no dashboard for your role yet" screen instead of silently looping.

- **Cost:** does not unlock the requisition flow.
- **Risk:** none technically, but it leaves the gap open.

## Recommendation

**Option B now, then A when the requisition screens are built** — it unblocks the P1 differentiator with a
one-line change, and the honest interim state is documented rather than hidden. Option C is worth doing
regardless, because a silent redirect loop is a bad failure mode for any future role.

This decision should also cover the general rule: every role in `permissions.py` must resolve to *something*,
so the same bug cannot reappear when a seventh role is added.

## Resolution — LOCKED 2026-10-15

**A Site Foreman is not a POS user. `site_foreman` gets no POS dashboard, and unmapped roles get an explicit
screen instead of a silent redirect loop.**

Clarified by the product owner during this session: the foreman is a **CPMS-side identity** that requests
material from the store. POS models the role only because `Requisition.requested_by` needs an actor
(`apps/users/permissions.py:19`, plus the `foreman` account `seed_demo` creates). It is not a role that logs
into the POS client.

So the resolution is deliberately **not** "give it a dashboard":

- `dashboardForRole()` keeps returning `null` for `site_foreman`, now **by intent** rather than by omission.
- The null branch changes: `if (dashboard == null) return isLogin ? null : login;` becomes an explicit
  unsupported-role screen, so an unmapped or role-less account is told *why* instead of looping.
- No foreman dashboard is built in POS. The Fog of War entry for requisition screens is re-scoped by
  [Requisition UI Ownership](./09-requisition-ui-ownership.md).

Why not the other options:

- **Build a foreman dashboard** — builds POS screens for a role that does not exist in POS, duplicating screens
  that belong to CPMS.
- **Temporary mapping to an existing dashboard** — would show a foreman POS screens that are not theirs and
  leaves a misleading mapping to unlearn. With the role's true ownership now known, honesty is cheaper.

### Knock-on corrections

| Item | Correction |
| :--- | :--- |
| `README.md` demo-account table | Must state that `foreman` has **no POS UI role** — it exists for API and CPMS use, not for logging into this client. |
| Phase 5 scope | Creating and submitting requisitions is CPMS-side. POS owns approval and material release. Re-scoped in [Requisition UI Ownership](./09-requisition-ui-ownership.md). |
| General rule | Every role in `permissions.py` must resolve to *something* — a dashboard or the explicit unsupported screen. No silent loops, ever. |
