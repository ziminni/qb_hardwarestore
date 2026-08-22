# Sprint 1 — Foundation: Authentication & Product Catalog

**Date:** August 2026  
**Status:** ✅ Complete  
**Commits:** `17951a7` → `411ffd0` → `7d880ae`

---

## What was built

### 1. Custom User Model (email-based auth)
- **`apps/users/models.py`** — `User` extends `AbstractBaseUser` + `PermissionsMixin`.
  `USERNAME_FIELD = 'email'` (no username). `AuditLog` with action-type choices.
- RBAC uses Django's **built-in `Group`** and **`Permission`** (auth_group / auth_permission),
  avoiding custom tables while still satisfying the ERD's intent.

### 2. JWT Authentication
- **`POST /api/v1/auth/register/`** — create account (public).
- **`POST /api/v1/auth/login/`** — returns `{ access, refresh, user }`. Login is
  audited in `AuditLog`. `last_login` updated.
- JWT config: 8h access token (POS shift length), 7d refresh, rotation + blacklist.

### 3. RBAC Permissions
- **`apps/users/permissions.py`** — `HasRole(role_name)` factory.
  Constants: `Admin`, `Cashier`, `Stock Manager`, `Store Manager`,
  `Site Foreman`, `System Administrator`.
- `UserViewSet` endpoints for role management:
  - `POST /api/v1/users/{id}/assign_role/`
  - `POST /api/v1/users/{id}/remove_role/`

### 4. Audit Trail
- `AuditLog` model — immutable log of LOGIN/LOGOUT/CREATE/UPDATE/DELETE/SALE/etc.
- Read-only `AuditLogViewSet` (`GET /api/v1/audit-logs/`) — admin only.

### 5. Product Catalog (Inventory App)
- **Models:** `Category`, `Brand`, `UnitOfMeasure`, `Product`, `ProductVariant`,
  `VariantUOM`.
- `ProductVariant` has a `base_uom` (smallest divisible unit — stock is tracked here).
  `VariantUOM` defines alternative selling units (box, bundle) with a
  `conversion_factor` and `default_selling_price`. One variant can have multiple
  selling UOMs (e.g., pcs + box + carton).
- DRF `ModelViewSet`s with `select_related` / `prefetch_related` for N+1
  prevention. Write operations require `IsAdminUser`; read requires
  `IsAuthenticated`.
- Django Admin with inline variants.

### 6. Config / Wiring
- `AUTH_USER_MODEL = 'apps_users.User'` — set **before first migration** (done).
- `djangorestframework-simplejwt` added to requirements.
- `REST_FRAMEWORK` — JWT auth default, pagination (50/page).
- `SIMPLE_JWT` — 8h/7d, rotation, blacklist.
- `TIME_ZONE = 'Asia/Manila'`.
- URL namespace: `/api/v1/` with separate `apps/users/urls.py` and
  `apps/inventory/urls.py`.

---

## API Endpoints (Sprint 1)

| Method | URL | Auth | Description |
|--------|-----|------|-------------|
| `POST` | `/api/v1/auth/register/` | Public | Create user |
| `POST` | `/api/v1/auth/login/` | Public | Get JWT pair |
| `GET` | `/api/v1/users/` | Admin | List users |
| `POST` | `/api/v1/users/` | Admin | Create user |
| `GET/PUT/PATCH/DELETE` | `/api/v1/users/{id}/` | Admin | User CRUD |
| `POST` | `/api/v1/users/{id}/assign_role/` | Admin | Add to group |
| `POST` | `/api/v1/users/{id}/remove_role/` | Admin | Remove from group |
| `GET` | `/api/v1/audit-logs/` | Admin | Audit trail |
| `GET/POST` | `/api/v1/categories/` | Auth/Admin | Category CRUD |
| `GET/POST` | `/api/v1/brands/` | Auth/Admin | Brand CRUD |
| `GET/POST` | `/api/v1/uoms/` | Auth/Admin | UOM CRUD |
| `GET/POST` | `/api/v1/products/` | Auth/Admin | Product CRUD (nested variants) |
| `GET/POST` | `/api/v1/variants/` | Auth/Admin | Variant CRUD |
| `GET/POST` | `/api/v1/variant-uoms/` | Auth/Admin | VariantUOM CRUD |

---

## How to test (Docker required)

```bash
# 1. Rebuild (simplejwt is a new dependency)
docker compose up -d --build

# 2. Create superuser
docker compose exec backend python manage.py createsuperuser
# email: admin@buildpro.com  password: admin123

# 3. Create roles
docker compose exec backend python manage.py shell -c "
from django.contrib.auth.models import Group
for name in ['Admin','Cashier','Stock Manager','Store Manager','Site Foreman','System Administrator']:
    Group.objects.get_or_create(name=name)
print('Done')
"

# 4. Test login
curl -X POST http://127.0.0.1:8000/api/v1/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@buildpro.com","password":"admin123"}'

# 5. Use the access token from step 4 to hit a protected endpoint
curl http://127.0.0.1:8000/api/v1/products/ \
  -H "Authorization: Bearer <access_token>"
```

---

## Next: Sprint 2 (Supplier, Purchasing, POS)
See the plan document for the full roadmap. Sprint 2 adds:
- `Supplier`, `PurchaseOrder`, `POItem`, `GoodsReceipt`, `InventoryBatch`,
  `StockAdjustment`, `SystemAlert`
- POS: `Customer`, `SalesTransaction`, `SalesItem`, `Payment`, `OfficialReceipt`
- FIFO batch allocation service
- Low-stock alert generation