# Phase 2 Plan — Access Control & Audit

**Spec:** [MAP](./MAP.md) decisions [Data scoping](./decisions/02-data-scoping.md), [Admin authority](./decisions/04-admin-authority.md), [Alert resolve](./decisions/06-alert-resolve.md), [Audit depth](./decisions/07-audit-depth.md). Extensions found in Phase 2 research are marked **(R)** and ledgered as rulings.
**Branch:** `feature/backend-integration`. **BASE:** `0820875`. **Baseline:** backend 176/176, flutter 552/552.

## Global constraints

- Same harness rules as [Phase 1 plan](./phase-1-plan.md#global-constraints): tests in docker, `content_type='application/json'` for nested writes, RED first (assertion failure, not import error), commit per task with tests, no CPMS, no `temp/`.
- **Role vocabulary** (`apps/users/permissions.py`): Admin + System Administrator = admin; Store Manager = manager; Stock Manager = inventory; Cashier = pos; Site Foreman = foreman. Superuser bypasses role checks (existing `RoleRequired` rule) — keep.
- **Deny by default:** a user with no role group (or only Site Foreman) gets 403 on POS business data. Many existing tests create groupless users (`POSTestBase.cashier1`): add the right group to the fixture; never weaken an assertion. List every fixture change.
- **Hidden ≠ forbidden:** scoping uses queryset filters (a non-owner gets 404, not 403) where the decision says "own"; role denial uses 403.
- Every new refusal is a stable `{code, detail}` 4xx. Never 500.
- Update `ENDPOINTS.md` role matrix rows for every permission you change (one home per fact).

## Task 1 — Admin authority + user-management hardening (decision 04)

**Files:** `apps/users/views.py`, `apps/users/serializers.py`, `apps/users/tests.py` (or new `tests_admin_authority.py`).

1. Replace `IsAdminUser` with `IsAdminRole` on `register_view`, `UserViewSet`, `AuditLogViewSet`. `is_staff` keeps meaning only "may log into Django `/admin`".
2. `UserSerializer`: `is_staff` read-only via API **(R)** — otherwise an admin API call can grant Django-admin access.
3. `UserViewSet` disallows `DELETE` (`http_method_names` without `delete` → 405) **(R)**: accounts are deactivated (`is_active=False`), never deleted, because audit rows will `PROTECT` their user (Task 5).
4. **Last-admin guard:** refuse (400 `LAST_ADMIN`) any change that would leave zero active admins — PATCH `is_active=False`, `assign_role` to a non-admin group, `remove_role` of the admin group. "Active admin" = active superuser or active member of Admin/System Administrator.

**RED tests:** Admin-group user with `is_staff=False` → 200 on `/users/`, `/users/stats/`, `/audit-logs/`, `POST /auth/register/`; `is_staff=True` user without admin group → 403 on all four; cashier → 403; PATCH `is_staff: true` → field unchanged; DELETE user → 405 and row exists; deactivating / demoting the only admin → 400 LAST_ADMIN; with two admins, deactivating one → 200; deactivated user's existing access token → 401 on `/auth/me/`.

## Task 2 — Sales, receivables and held-cart data scoping (decision 02)

**Files:** `apps/users/permissions.py` (role helpers + new permission classes), `apps/pos/views.py`, `apps/pos/serializers.py` (customer), `apps/collectibles/views.py`, tests in new `apps/pos/tests_scoping.py` + `apps/collectibles/tests.py`.

1. Helpers in `permissions.py`: `has_role(user, roles)`; role sets `SALES_READERS = POS ∪ inventory ∪ manager ∪ admin`, `RECEIVABLES_READERS = POS ∪ manager ∪ admin`.
2. `BaseViewSet` (customers, transactions, quotations, sales orders): reads require a `SALES_READERS` role (foreman / groupless → 403); writes stay `IsPOSRole`.
3. `SalesTransactionViewSet.get_queryset`: cashier-only users (pos role and no manager/admin/inventory role) see `cashier=request.user`; manager/admin/inventory see all. Applies to list, detail and `daily_report`. `PaymentViewSet` + `OfficialReceiptViewSet` get the same reader permission and scoping via `transaction__cashier`.
4. `HeldCartViewSet`: **every** method requires `IsPOSRole` (inventory/foreman 403 even on GET). Store-wide among POS roles — decision 05 "any cashier may resume" stands.
5. Customers **(R)**: a non-manager that sends `total_credit_limit` on create/update → 403 `{code:'CREDIT_LIMIT_FORBIDDEN'}` (cashier could otherwise raise their own customer's limit and void Phase 1's block). Customer `DELETE` → `IsManagerRole`; a protected customer → 409 `{code:'CUSTOMER_IN_USE'}`.
6. Receivables **(R)**: `CollectibleLedgerViewSet` becomes read-only (ledgers are written only by `process_sale`/`release_materials`/payments); reads + `aging` require `RECEIVABLES_READERS`. `CollectiblePaymentViewSet`: `http_method_names = ['get','head','options','post']` (no PUT/PATCH/DELETE of money records); reads `RECEIVABLES_READERS`, create `IsPOSRole`. Delete the `is_staff`-based `IsAdminOrReadOnly`.

**RED tests:** cashier A lists `/transactions/` → only own; cashier A GET cashier B's transaction → 404; same for `/payments/`, `/receipts/`, `daily_report` totals; manager + stocker see all; foreman + groupless → 403 on transactions/customers/ledgers/held-carts; inventory GET `/held-carts/` → 403; cashier B can still resume/complete cashier A's held cart; cashier POST customer with `total_credit_limit` → 403 and no row; manager can set it; cashier PATCH/PUT/DELETE `/ledgers/{id}/` → 405/403 and balance unchanged; cashier PATCH/DELETE `/ledger-payments/{id}/` → 405; stocker GET `/ledgers/` → 403.

## Task 3 — Requisition token secrecy + separation of duties

**Files:** `apps/requisitions/views.py`, `apps/requisitions/serializers.py`, `apps/requisitions/services.py`, `apps/requisitions/exceptions.py`, tests in `apps/requisitions/tests.py` (or new `tests_security.py`).

1. **(R) Token secrecy:** the material token is a bearer credential — whoever holds it can release goods on credit. Today `GET /requisitions/` and `GET /tokens/` show every token to any authenticated user, so a cashier can release without being handed the token. Fix:
   - `RequisitionViewSet` reads: manager/admin see all; Site Foreman sees only `requested_by=self`; everyone else 403.
   - `RequisitionSerializer.token`: serialized only for manager/admin or the requesting foreman; otherwise `null`.
   - `MaterialTokenViewSet`: `IsManagerRole`.
   - `RequisitionItemViewSet` reads follow the requisition read rule.
   - `token_verify_view`: `IsPOSRole` (was any authenticated).
2. **Self-approval guard (decision 04 / NFR):** `approve_requisition` raises `SelfApproval` (code `SELF_APPROVAL`) when `approver_id == requisition.requested_by_id`, including superusers → 400. Reject stays allowed.
3. **(R) Immutable after submit:** requisition update/destroy and requisition-item create/update/destroy refused with 400 `{code:'REQUISITION_LOCKED'}` unless the parent is `DRAFT` — otherwise items can be edited after approval and the token releases what nobody approved.

**RED tests:** cashier GET `/requisitions/` and `/tokens/` → 403; stocker → 403; foreman sees own requisitions with token, not another foreman's (404); manager sees all with tokens; cashier `POST /tokens/verify/` still 200 for a valid token; stocker verify → 403; multi-role Foreman+Store Manager user approving own → 400 SELF_APPROVAL, status still SUBMITTED, no token row; PATCH items on an APPROVED requisition → 400 REQUISITION_LOCKED and items unchanged; DRAFT edit → 200.

## Task 4 — Alert resolution (decision 06)

**Files:** `apps/inventory/models.py` (`SystemAlert.resolved_by` FK `SET_NULL` null, `resolved_at`), migration, `apps/inventory/views.py`, `apps/inventory/serializers.py`, tests.

1. `SystemAlertViewSet` → `ReadOnlyModelViewSet` + `resolve` action **(R)**: alerts are system-generated; POST/PUT/PATCH/DELETE on the collection/detail → 405 for everyone.
2. `resolve` permission `IsInventoryRole` (Stock Manager + Store Manager + Admin — the existing class; ruling). Sets `is_resolved`, `resolved_by=request.user`, `resolved_at=now` under `select_for_update`; already resolved → 400 `{code:'ALERT_ALREADY_RESOLVED'}`. Serializer exposes `resolved_by`, `resolved_by_name`, `resolved_at` read-only.

**RED tests:** stocker resolve → 200 with resolver + timestamp; cashier/sales-less/foreman resolve → 403; second resolve → 400; POST `/alerts/` → 405; DELETE `/alerts/{id}/` → 405.

## Task 5 — Append-only business audit (decision 07)

**Files:** `apps/users/models.py` (`AuditLog`), migration (schema + data backfill), `apps/users/services.py` (`log_audit`), `apps/users/admin.py`, every view listed below, tests in new `apps/users/tests_audit.py`.

1. Model: `user` FK → `PROTECT`; new `username_snapshot = CharField(150, blank=True)` filled by `log_audit` from `user.username` (backfill existing rows). New `ActionType`s: `LOGIN_FAILED, RETURN, RELEASE, REQ_APPROVE, REQ_REJECT, ALERT_RESOLVE, SHIFT_OPEN, SHIFT_CLOSE, CART_VOID, ROLE_CHANGE, USER_DEACTIVATE` (≤20 chars).
2. Append-only: `AuditLog.save()` raises `ImmutableAuditLog` if the row already exists; `delete()` raises; a custom QuerySet makes `.update()`/`.delete()` raise. Django admin: `has_add/change/delete_permission` → False.
3. `log_audit(*, user, action_type, description, ip_address=None, username=None)` — `username` overrides the snapshot (failed login with no user). IP from `REMOTE_ADDR` only (never trust `X-Forwarded-For`). **Never** write passwords, JWTs or material-token UUIDs into `description`; reference document numbers instead.
4. Writers, each **inside the same `transaction.atomic()` as the event** (wrap the service call in the view when the service owns its own atomic): sale + held-cart complete (`SALE`), held-cart void (`CART_VOID`), return (`RETURN`), release (`RELEASE`), requisition approve/reject (`REQ_APPROVE`/`REQ_REJECT`), goods-receipt process (`RECEIPT`), stock adjustment (`STOCK_ADJUST`), alert resolve (`ALERT_RESOLVE`), ledger payment (`PAYMENT`), shift open/close (`SHIFT_OPEN`/`SHIFT_CLOSE`), user register (`CREATE`), user PATCH (`UPDATE`, or `USER_DEACTIVATE` when `is_active` flips false), assign/remove role (`ROLE_CHANGE`). Idempotent replays (200) write **no** new row.

**RED tests:** each event writes exactly one row with correct actor, action, snapshot and a description containing the document number; a refused event (e.g. `INSUFFICIENT_STOCK`, `SELF_APPROVAL`, `LAST_ADMIN`) writes none; replayed checkout writes none; `row.save()` on an existing row / `row.delete()` / `AuditLog.objects.update(...)` / `.delete()` raise; admin change/delete permission False; deleting a user with audit rows raises `ProtectedError` at ORM level; release audit description does not contain the token UUID.

## Task 6 — Login lockout + session revocation

**Files:** `config/settings.py` (`rest_framework_simplejwt.token_blacklist` in `INSTALLED_APPS`, explicit `CACHES` LocMem default), `apps/users/views.py` (`login_view`, `logout_view`), `apps/users/serializers.py`, tests in new `apps/users/tests_sessions.py`.

1. **Brute-force lockout:** count failed logins per `(identifier.lower(), REMOTE_ADDR)` in the cache; 5 failures within 15 min → `429 {code:'LOGIN_LOCKED', detail, retry_after}` without checking the password. Success resets the counter. Each failure writes `LOGIN_FAILED` audit (user if the identifier matched, else `username=identifier[:150]`). The response for unknown user and wrong password stays identical.
2. **Revocation:** migrate the blacklist app. `logout_view` accepts `{refresh}`; if it parses and belongs to `request.user`, blacklist it. Always 204 (local logout must succeed). `BLACKLIST_AFTER_ROTATION` now actually works.
3. Prove (and fix with a custom refresh serializer if simplejwt does not already) that a **deactivated** user's refresh token → 401.

Lockout tests must `cache.clear()` in `setUp` so counters cannot leak across tests.

**RED tests:** 5 wrong passwords → 6th attempt (even with the right password) 429 LOGIN_LOCKED; another IP unaffected; success after counter expiry (patch time or clear) → 200 and counter reset; failures write LOGIN_FAILED rows with no password in description; unknown-user and wrong-password bodies identical; logout with refresh → that refresh → 401 on `/auth/refresh/`; reuse of a rotated refresh → 401; logout with another user's refresh → 204 but that token stays valid; deactivated user's refresh → 401.

## Task 7 — Flutter client contract

**Files:** `flutter/lib/core/network/api_client.dart` (expose current refresh token to the auth service), `flutter/lib/data/services/auth_service.dart`, `flutter/lib/data/services/requisition_service.dart`, tests under `flutter/test/`.

1. `AuthService.logout` posts `{'refresh': <token>}` when one is held; failure still logs out locally.
2. Login maps 429 `LOGIN_LOCKED` to a readable lockout message (use server `detail`, mention retry time).
3. Approve maps `SELF_APPROVAL` and `REQUISITION_LOCKED` to readable messages.
4. Any screen whose role newly gets 403 on a list must show the existing permission-denied state, not a crash — verify the cashier history (now own-only, still 200) and the stocker screens (no new 403 expected); add a test only if a gap is found.

**RED tests:** logout sends the refresh token; logout with server down still clears tokens; lockout message; self-approval message. Gate: `flutter analyze` clean + full `flutter test`.

## Phase gate

Backend full suite green, `manage.py check` + `makemigrations --check` clean, migrations applied to dev DB; Flutter full suite + analyze clean; hygiene-reviewer on `0820875..HEAD`; qa-tester live role matrix: every demo role (admin, manager, stocker, cashier, foreman) × every endpoint changed above, plus lockout, logout revocation, token secrecy and audit rows written per event.
