"""Permissions based on Django Group (Role) membership."""

from rest_framework.permissions import BasePermission

# Role / Group name constants — synced with seeded groups.
ROLE_ADMIN = 'Admin'
ROLE_CASHIER = 'Cashier'
ROLE_STOCK_MANAGER = 'Stock Manager'
ROLE_STORE_MANAGER = 'Store Manager'
ROLE_SITE_FOREMAN = 'Site Foreman'
ROLE_SYSTEM_ADMIN = 'System Administrator'


class HasRole(BasePermission):
    """Grant access if the user belongs to the named group."""

    message = 'You do not have the required role.'

    def __init__(self, role_name):
        self.role_name = role_name

    def __call__(self):
        # DRF calls permission classes; we allow instantiation with role.
        return self

    def has_permission(self, request, view):
        return request.user.is_authenticated and request.user.groups.filter(
            name=self.role_name
        ).exists()


def IsAdmin():
    return HasRole(ROLE_ADMIN)

def IsCashier():
    return HasRole(ROLE_CASHIER)

def IsStockManager():
    return HasRole(ROLE_STOCK_MANAGER)

def IsStoreManager():
    return HasRole(ROLE_STORE_MANAGER)

def IsSiteForeman():
    return HasRole(ROLE_SITE_FOREMAN)