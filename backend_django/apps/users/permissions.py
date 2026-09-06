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


class RoleRequired(BasePermission):
    """Base permission: require membership in one of ``required_roles``.

    Superusers bypass role checks. Keep ``required_roles`` empty in the
    base class so it is never accidentally used directly.
    """

    required_roles: list = []
    message = 'You do not have the required role.'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        if user.is_superuser:
            return True
        return user.groups.filter(name__in=self.required_roles).exists()


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
