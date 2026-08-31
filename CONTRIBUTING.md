# Queen Builders Collaboration Guide

This guide defines how contributors should work with Git, Flutter, Django, and
Docker in this project. Follow it to avoid overwriting another contributor's
work or accidentally deleting local database data.

## 1. Main rule

Do not develop directly on `master`. The `master` branch should contain only
stable, integrated work.

Create a new branch for each feature, fix, or focused task. When the task is
finished, push the branch and open a pull request into `master`.

## 2. Branch names

Use lowercase words separated by hyphens:

```text
<type>/<short-description>
```

Common types:

| Type | Purpose | Example |
| --- | --- | --- |
| `feature/` | New functionality | `feature/user-management` |
| `fix/` | Bug fix | `fix/token-refresh` |
| `ui/` | UI-only work | `ui/admin-dashboard` |
| `refactor/` | Code restructuring | `refactor/auth-service` |
| `docs/` | Documentation | `docs/docker-setup` |
| `chore/` | Maintenance | `chore/update-dependencies` |

Recommended UI branches use one focused screen per branch:

```text
ui/admin-dashboard
ui/admin-user-management
ui/admin-audit-logs
ui/inventory-dashboard
ui/pos-dashboard
ui/sales-dashboard
```

Use `feature/` when the work adds functionality rather than only interface
design. If one contributor owns both Flutter and Django for a complete feature,
use the feature name:

```text
feature/product-management
feature/user-management
feature/sales-checkout
feature/requisition-approval
```

## 3. Starting a task

Make sure existing work is committed before switching branches:

```bash
git status
```

Update `master`, then create the task branch:

```bash
git switch master
git pull origin master
git switch -c feature/example-task
```

Tell the other contributor which module and files you will edit. Avoid editing
the same files simultaneously, especially:

```text
backend_django/config/settings.py
backend_django/config/urls.py
docker-compose.yml
flutter/pubspec.yaml
flutter/lib/routes/routes.dart
```

## 4. Committing work

Review changes before committing:

```bash
git status
git diff
```

Add only files related to the task when practical:

```bash
git add flutter/lib/features/dashboard
git commit -m "ui: add admin dashboard wireframe"
```

Use clear commit prefixes:

```text
feat: connect login to Django
fix: wait for PostgreSQL before migration
ui: add inventory dashboard wireframe
test: cover invalid login
docs: document Docker startup
```

Avoid vague messages such as `changes`, `update`, or `final`.

## 5. Sharing work

Push the feature branch:

```bash
git push -u origin feature/example-task
```

On GitHub, open a pull request from the feature branch into `master`. The other
contributor should review the files and test the change before merging.

After the pull request is merged:

```bash
git switch master
git pull origin master
git branch -d feature/example-task
```

The remote branch can also be deleted after merging.

## 6. Updating a branch

If `master` changes while a feature is being developed:

```bash
git switch master
git pull origin master
git switch feature/example-task
git rebase master
```

If a conflict occurs, coordinate with the contributor who edited the same
module. Do not automatically discard either version. Resolve the files, test
the combined result, then continue:

```bash
git add <resolved-file>
git rebase --continue
```

For a branch that only its author uses, update the remote after a rebase with:

```bash
git push --force-with-lease
```

Never use plain `git push --force` on a shared branch.

## 7. Flutter structure rules

Keep widgets inside the feature that owns them:

```text
flutter/lib/features/<feature>/view/
flutter/lib/features/<feature>/viewmodels/
flutter/lib/features/<feature>/widget/
```

Each widget must have its own Dart file. A `StatefulWidget` and its associated
`State` class may remain together because they represent one component.

Widgets exclusive to one module must begin with the module name:

```text
admin_activity_list.dart
admin_dashboard_content.dart
inventory_stock_table.dart
pos_cart_panel.dart
sales_report_table.dart
```

Shared widgets should use neutral names:

```text
dashboard_shell.dart
mock_metric.dart
mock_section.dart
```

Before committing Flutter work:

```bash
cd flutter
dart format lib
flutter analyze
flutter build macos --debug
```

On Windows, replace the last command with the appropriate Windows build.

## 8. Django structure rules

Keep backend code in the owning application:

```text
backend_django/apps/<module>/models.py
backend_django/apps/<module>/serializers.py
backend_django/apps/<module>/services.py
backend_django/apps/<module>/permissions.py
backend_django/apps/<module>/views.py
backend_django/apps/<module>/urls.py
backend_django/apps/<module>/tests.py
```

Create and commit migrations whenever models change:

```bash
docker compose exec backend python manage.py makemigrations
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py check
```

Do not create conflicting custom user models. Changes to `AUTH_USER_MODEL` must
be agreed on before implementation because changing it after migrations may
require a development database reset.

## 9. Starting the project

Start Docker Desktop first. From the repository root:

```bash
docker compose up -d
docker compose ps
```

If dependencies or the Docker image changed:

```bash
docker compose up -d --build
```

Run Flutter in another terminal:

```bash
cd flutter
flutter run -d macos
```

Stop the containers without deleting data:

```bash
docker compose down
```

Do not run the following during normal development:

```bash
docker compose down -v
```

The `-v` option deletes the PostgreSQL volume, including local users and all
other local application data.

## 10. Secrets and local data

Never commit:

- `.env` files
- SMTP passwords
- Django secret keys
- JWT tokens
- Database dumps containing private data
- Signing certificates or private keys

Database accounts are stored in each contributor's local PostgreSQL volume.
They are not shared through Git. A contributor with a fresh database must create
their own superuser:

```bash
docker compose exec backend python manage.py createsuperuser
```

## 11. Before requesting review

Confirm all of the following:

- The branch contains only the intended task.
- No secrets or generated build files are staged.
- Flutter analysis/build passes for Flutter work.
- Django checks/tests pass for backend work.
- New model migrations are committed.
- Widget files follow the one-widget-per-file rule.
- Module-specific widgets use the module prefix.
- Relevant setup or API documentation is updated.
