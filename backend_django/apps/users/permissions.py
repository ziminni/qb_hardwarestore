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
ROLE_SITE_FOREMAN = 'Site Foreman'
ROLE_SYSTEM_ADMIN = 'System Administrator'

# Administrative roles with full access.
STAFF_ROLES = [ROLE_ADMIN, ROLE_SYSTEM_ADMIN]

# Decision 02 (Phase 2): who may READ sales data. `inventory` is in the list by the P2
# Ruling: the built Stock Manager Sales tab reads ALL sales, so a stocker who could not
# read `/transactions/` would be looking at a broken screen. `foreman` is deliberately
# absent - a site foreman has no reason to see the till's money.
SALES_READER_ROLES = [
    ROLE_CASHIER, ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES,
]

# Who may read receivables (utang ledgers, aging). A stocker does not see customers'
# debts, so `inventory` is deliberately absent here even though it is a sales reader.
RECEIVABLES_READER_ROLES = [ROLE_CASHIER, ROLE_STORE_MANAGER, *STAFF_ROLES]

# Roles that see the WHOLE store's sales. A cashier who also holds one of these is not
# "cashier-only" and is not scoped to their own rows.
_SALES_WIDE_ROLES = [ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES]


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


class IsInventoryRole(RoleRequired):
    """Stock Manager / Store Manager / Admin — inventory & catalog writes."""

    required_roles = [ROLE_STOCK_MANAGER, ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsPOSRole(RoleRequired):
    """Cashier / Store Manager / Admin — sales & payment writes."""

    required_roles = [ROLE_CASHIER, ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsManagerRole(RoleRequired):
    """Store Manager / Admin — approval-level actions (requisitions)."""

    required_roles = [ROLE_STORE_MANAGER, *STAFF_ROLES]


class IsForemanOrManager(RoleRequired):
    """Site Foreman / Store Manager / Admin — project & requisition writes."""

    required_roles = [ROLE_SITE_FOREMAN, ROLE_STORE_MANAGER, *STAFF_ROLES]


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


class IsForemanOrManagerOrReadOnly(ReadOnlyOr):
    required_roles = IsForemanOrManager.required_roles


class IsReceivablesReader(RoleRequired):
    """Read receivables: Cashier / Store Manager / Admin."""

    required_roles = RECEIVABLES_READER_ROLES
    message = 'You do not have access to receivables.'


class SalesReadPOSWrite(RoleRequired):
    """Read sales data with any sales role; write only with a POS role.

    Decision 02: a Site Foreman or a groupless account gets **403** on `/transactions/`,
    `/customers/`, `/quotations/`, `/sales-orders/`, `/payments/` and `/receipts/`,
    while a Cashier / Stock Manager / Store Manager / Admin may read. Writes need
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
