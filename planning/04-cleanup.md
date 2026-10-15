# 04 — Cleanup: Dead Files, Duplicates, Stale Branches, Config Debt

**Priority: P2.** None of this blocks the demo. All of it makes the next person's work harder, and some of
it actively misleads (three report screens, two sales stacks, a broken test file).

## Dead and orphaned files

| Path | Why it is dead |
| :--- | :--- |
| `flutter/lib/features/dashboard/views/pos_dashboard.dart` | Referenced by no other Dart file. `routes.dart` builds `features/pos/views/pos_transaction_page.dart` for the POS dashboard route. |
| `flutter/lib/features/dashboard/views/sales_dashboard.dart` | Same — superseded by `features/sales/views/sales_dashboard_page.dart`. |
| `flutter/lib/features/dashboard/viewmodels/dashboard_mock_data.dart` | Becomes fully dead once the two orphans above go. |
| `flutter/test/widget_test.dart` | Flutter's default counter template. Calls `const MyApp()` with no argument, but `MyApp` requires an `auth` argument, so it does not compile. It is untracked and is the **one known error** in `flutter analyze`. |

`widget_test.dart` is the one item here that is actively harmful: it is the only thing standing between
this repo and a clean `flutter analyze`. Either rewrite it against the real `MyApp(auth: ...)` signature or
delete it — leaving a non-compiling test in the tree invites someone to commit it.

## Duplicates to reconcile

| Duplicate | Verdict |
| :--- | :--- |
| `sales/viewmodels/sales_module_viewmodel.dart` (129 lines) vs `sales/viewmodels/inventory_sales_viewmodel.dart` | **Two parallel sales stacks with no shared model.** `data/models/sales_module.dart` and `data/models/sales.dart` describe overlapping concepts. Pick one before wiring the API, or `planning/api-integration/MAP.md` will wire both. |
| `reports/views/inventory_reports_page.dart` + `sales/views/sales_reports_page.dart` + `admin/views/reports_page.dart` | Three screens over one backend surface (`/api/v1/reports/*`). Consolidate to one parameterised screen. |
| `core/layout/sales_skeleton_layout.dart` (190 lines) vs `core/layout/inventory_skeleton_layout.dart` (201 lines) | Near-clones; the diff is mostly nav labels. Collapse to one parameterised layout. |
| `flutter/README.md` | The generated 3-line stub (`# client` / "A new Flutter project."). Wrong name, no content. The real setup doc is the root `README.md`. |
| `.gitignore` lines 4–7 and 16–20 | Legacy `client/` and `server/` paths from before the `flutter/` / `backend_django/` rename. Harmless but misleading; the correct entries already exist below them. |

**Naming inconsistency:** `features/dashboard/widget/` and `features/auth/widget/` are singular, while the
other eight features use `widgets/`. Cheap to fix now, annoying later.

## Branch consolidation

The three UI branches are **not three parallel efforts**. Earlier merge simulation showed `ui/frontend-progress`
already **contains** `ui/inventory-management` and `ui/pos-transaction-simulator` as ancestors, with zero
unique commits of their own — and `master` is an ancestor too, so it can fast-forward.

| Branch | State |
| :--- | :--- |
| `ui/frontend-progress` | Superset; the integration branch. |
| `ui/inventory-management` | Strict ancestor — no unique commits. |
| `ui/pos-transaction-simulator` | Strict ancestor — no unique commits. |
| `feature/backend-integration` | Current work; ahead of master, **unpushed**. |

Before deleting the two ancestor branches, **re-verify** rather than trusting this table:

```bash
git merge-base --is-ancestor origin/ui/inventory-management origin/ui/frontend-progress && echo "ancestor"
git merge-base --is-ancestor origin/ui/pos-transaction-simulator origin/ui/frontend-progress && echo "ancestor"
```

Also note `feature/backend-integration` carries the port fix and the Linux desktop work, so a plain
fast-forward of `master` does **not** include them.

## Config debt

| Item | Detail |
| :--- | :--- |
| Secrets in source | `SECRET_KEY` and DB credentials live in `settings.py`. Move to env via `django-environ`. |
| Single settings module | Split into `base` / `dev` / `prod` / `test`. |
| `ALLOWED_HOSTS = ['*']`, `CORS_ALLOW_ALL_ORIGINS = True` | Dev-only; must not reach production. |
| Migrations run at container start | Committed migrations exist, so auto-`makemigrations` on boot can be dropped. |

Already fixed — do not re-do: the tracked `__pycache__` `.pyc` files were removed from the index, and
`.gitignore` covers `backend_django/**/__pycache__/` and `backend_django/**/*.pyc`.

## Acceptance

- `flutter analyze` reports zero errors.
- One sales stack, one reports screen, one skeleton layout.
- No file in the tree is unreferenced.
