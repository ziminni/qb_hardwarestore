# pyright: reportMissingImports=false
#
# Same false-positive class documented in apps/users/models.py: this checker runs with a
# working directory outside the repo, so it resolves neither pyrightconfig.json nor
# django-stubs.
"""Role-based permissions backed by Django Group membership.

Role names MUST match the auth Groups referenced by
apps.users.serializers.UserSerializer.get_role() and the seeded roles.

Usage in ViewSets:
    permission_classes = [IsAdminRole]
    # or in get_permissions():
    return [IsInventoryRole()]
"""

from rest_framework.permissions import SAFE_METHODS, BasePermission

# Role / Group name constants — synced with seeded groups.
ROLE_ADMIN = 'Admin'
ROLE_CASHIER = 'Cashier'
ROLE_STOCK_MANAGER = 'Stock Manager'
ROLE_STORE_MANAGER = 'Store Manager'
ROLE_SYSTEM_ADMIN = 'System Administrator'
# Decision 02 (Phase 1): the CPMS service account. It is NOT a POS role: it may call
# `/api/v1/integration/cpms/` and nothing else, enforced by the fence in
# `apps/users/authentication.py`. It is deliberately absent from every `*_ROLES` list
# below, so it inherits no till, stock, reporting or admin access.
ROLE_CPMS_SERVICE = 'CPMS Service'

# The UI code for `ROLE_CPMS_SERVICE` (Phase 4 task B3): accepted on a role write, never
# read back as an area.
ROLE_CODE_CPMS = 'cpms'

# Administrative roles with full access.
STAFF_ROLES = [ROLE_ADMIN, ROLE_SYSTEM_ADMIN]

# Decision 02 (Phase 2): who may READ sales data. `inventory` is in the list by the P2
# Ruling: the built Stock Manager Sales tab reads ALL sales, so a stocker who could not
# read `/transactions/` would be looking at a broken screen.
SALES_READER_ROLES = [
    ROLE_CASHIER, ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES,
]

# Who may read receivables (utang ledgers, aging). A stocker does not see customers'
# debts, so `inventory` is deliberately absent here even though it is a sales reader.
RECEIVABLES_READER_ROLES = [ROLE_CASHIER, ROLE_STORE_MANAGER, *STAFF_ROLES]

# Roles that see the WHOLE store's sales. A cashier who also holds one of these is not
# "cashier-only" and is not scoped to their own rows.
_SALES_WIDE_ROLES = [ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES]

# ---------------------------------------------------------------------------
# Frontend role codes (Phase 4 task B3, decision 18)
# ---------------------------------------------------------------------------
# A user payload's role object carries a `name` that is a UI *code*, not a Group name:
# `admin`, `sales`, `inventory`, `pos`. One account may hold several. This map is the
# only place that translates between the two, so the serializer's read shape and every
# write path (`register`, `PATCH /users/{id}/`, `assign_role`, `remove_role`) agree on
# what a code means.
#
# Two codes cover two Group names because seeding and older accounts use both spelling
# (decision 04 keeps `System Administrator` beside `Admin`). Reading folds them into one
# code; writing a code grants its CANONICAL group (`ROLE_CODE_GROUP`), because a code
# names an area, not a particular row in `auth_group`.
ROLE_CODE_GROUPS = {
    'admin': (ROLE_ADMIN, ROLE_SYSTEM_ADMIN),
    'sales': (ROLE_STORE_MANAGER, 'Sales'),
    'inventory': (ROLE_STOCK_MANAGER,),
    'pos': (ROLE_CASHIER,),
    # Write-only in practice: the service account is not a POS area, so `roles[]` never
    # emits it (see `ROLE_CODE_ORDER`), but a role write may still name it and the CPMS
    # guard has to see it.
    ROLE_CODE_CPMS: (ROLE_CPMS_SERVICE,),
}

# The order `roles[]` is emitted in: widest authority first, so the area picker can open
# on `roles[0]` and an old client's `role` stays the account's strongest area.
ROLE_CODE_ORDER = ['admin', 'sales', 'inventory', 'pos']

# The Group a code grants when it is written.
ROLE_CODE_GROUP = {
    'admin': ROLE_ADMIN,
    'sales': ROLE_STORE_MANAGER,
    'inventory': ROLE_STOCK_MANAGER,
    'pos': ROLE_CASHIER,
    ROLE_CODE_CPMS: ROLE_CPMS_SERVICE,
}


def role_code_for_group(group_name):
    """The UI code for a Group name, or None when the group is not a POS area."""
    for code, names in ROLE_CODE_GROUPS.items():
        if group_name in names:
            return code
    return None


def role_codes_for(user):
    """Codes of the areas ``user`` holds, deduplicated, in ``ROLE_CODE_ORDER``.

    A superuser reads as `admin` even with no group, because it passes every role check
    (`has_role`): the client must show an area it can actually enter. Deactivated
    accounts keep their codes - the payload describes membership, and the 401 on their
    token is what enforces the account state.
    """
    held = set(user.groups.values_list('name', flat=True))
    codes = [
        code for code in ROLE_CODE_ORDER
        if held & set(ROLE_CODE_GROUPS[code])
    ]
    if user.is_superuser and 'admin' not in codes:
        codes.insert(0, 'admin')
    return codes


def has_role(user, roles) -> bool:
    """True when ``user`` is authenticated and a member of one of ``roles``.

    Superusers pass every role check - the rule `RoleRequired` has always had, kept in
    one place now that several call sites need it (permission classes, queryset
    scoping, the customer credit-limit guard).
    """
    if not (user and getattr(user, 'is_authenticated', False)):
        return False
    if user.is_superuser:
        return True
    return user.groups.filter(name__in=list(roles)).exists()


def is_cashier_only(user):
    """True for a till account that may only see the sales IT rang.

    "Cashier-only" = has the Cashier role and none of the store-wide ones (Stock
    Manager / Store Manager / Admin), and is not a superuser. A cashier who was also
    promoted to Store Manager keeps the manager's view: the wider role wins.
    """
    if not (user and getattr(user, 'is_authenticated', False)):
        return False
    if user.is_superuser:
        return False
    names = set(user.groups.values_list('name', flat=True))
    if ROLE_CASHIER not in names:
        return False
    return not (names & set(_SALES_WIDE_ROLES))


class RoleRequired(BasePermission):
    """Base permission: require membership in one of ``required_roles``.

    Superusers bypass role checks. Keep ``required_roles`` empty in the
    base class so it is never accidentally used directly.
    """

    required_roles: list = []
    message = 'You do not have the required role.'

    def has_permission(self, request, view) -> bool:  # pyright: ignore[reportIncompatibleMethodOverride]
        return has_role(request.user, self.required_roles)


class IsAdminRole(RoleRequired):
    """Admin / System Administrator only."""

    required_roles = STAFF_ROLES


class IsUserManagerRole(RoleRequired):
    """Store Manager / Admin — user account offboarding (Phase 5).

    A store manager offboards their own leavers; Admins keep full authority.
    Membership here grants NO access to admin-authority targets — the
    UserViewSet refuses those per-call (USER_ADMIN_FORBIDDEN), so this class
    alone never lets a manager touch, grant, or revive admin power.
    """

    required_roles = [ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsInventoryRole(RoleRequired):
    """Stock Manager / Store Manager / Admin — inventory & catalog writes."""

    required_roles = [ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsPOSRole(RoleRequired):
    """Cashier / Store Manager / Admin — sales & payment writes."""

    required_roles = [ROLE_CASHIER, ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsManagerRole(RoleRequired):
    """Store Manager / Admin — approval-level actions (requisitions)."""

    required_roles = [ROLE_STORE_MANAGER, *STAFF_ROLES]


def is_cpms_service_account(user) -> bool:
    """True for the CPMS service account: authenticated, active, in its group.

    Deliberately NOT `has_role`, which lets a superuser pass every check: the fence in
    `apps.users.authentication` asks this same question, and "may enter the CPMS
    namespace" and "may call a CPMS endpoint" must be one answer. Group membership is
    the whole key, in both directions.
    """
    if not (user and getattr(user, 'is_authenticated', False)):
        return False
    if not user.is_active:
        return False
    return user.groups.filter(name=ROLE_CPMS_SERVICE).exists()


class IsCpmsService(BasePermission):
    """The CPMS service account alone (decision 02) — the integration endpoints."""

    message = 'Only the CPMS service account may call this endpoint.'

    def has_permission(self, request, view) -> bool:  # pyright: ignore[reportIncompatibleMethodOverride]
        return is_cpms_service_account(request.user)


class ReadOnlyOr(RoleRequired):
    """Read for any authenticated user; writes require ``required_roles``."""

    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            user = request.user
            return bool(user and user.is_authenticated)
        return super().has_permission(request, view)


class IsInventoryOrReadOnly(ReadOnlyOr):
    required_roles = IsInventoryRole.required_roles


class IsPOSOrReadOnly(ReadOnlyOr):
    required_roles = IsPOSRole.required_roles


class IsReceivablesReader(RoleRequired):
    """Read receivables: Cashier / Store Manager / Admin."""

    required_roles = RECEIVABLES_READER_ROLES
    message = 'You do not have access to receivables.'


class SalesReadPOSWrite(RoleRequired):
    """Read sales data with any sales role; write only with a POS role.

    Decision 02: a groupless account gets **403** on `/transactions/`, `/customers/`,
    `/quotations/`, `/sales-orders/`, `/payments/` and `/receipts/`, while a Cashier /
    Stock Manager / Store Manager / Admin may read. Writes need
    `IsPOSRole` exactly as before, so a Stock Manager still cannot ring a sale.
    """

    required_roles = IsPOSRole.required_roles

    def has_permission(self, request, view) -> bool:  # pyright: ignore[reportIncompatibleMethodOverride]
        if request.method in SAFE_METHODS:
            return has_role(request.user, SALES_READER_ROLES)
        return has_role(request.user, self.required_roles)


class ReceivablesReadPOSWrite(RoleRequired):
    """Read receivables with a receivables role; write only with a POS role.

    Same two-tier shape as `SalesReadPOSWrite`, with the narrower reader set: a Stock
    Manager reads sales but not customers' debts.
    """

    required_roles = IsPOSRole.required_roles

    def has_permission(self, request, view) -> bool:  # pyright: ignore[reportIncompatibleMethodOverride]
        if request.method in SAFE_METHODS:
            return has_role(request.user, RECEIVABLES_READER_ROLES)
        return has_role(request.user, self.required_roles)
