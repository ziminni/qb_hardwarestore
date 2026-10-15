# Role to Dashboard Routing for All Six Roles

**Mode:** grill · **Status:** OPEN · **Opened:** 2026-10-15

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

## Resolution

_Unresolved — awaiting the routing decision._
