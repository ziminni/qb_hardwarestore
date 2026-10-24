# pyright: reportAttributeAccessIssue=false
"""Users app — services for auth-related business logic."""

from django.db.models import Q
from django.utils import timezone

from .models import AuditLog, User
from .permissions import STAFF_ROLES


def log_audit(*, user, action_type, description, ip_address=None):
    """Create an immutable audit log entry."""
    AuditLog.objects.create(
        user=user,
        action_type=action_type,
        description=description,
        ip_address=ip_address or '',
    )


def is_active_admin(user):
    """True when ``user`` is an admin who can still act (decision 04).

    Admin authority comes from the Admin / System Administrator group, or from
    ``is_superuser`` (which bypasses every role check). A deactivated account
    holds no authority at all, whatever its group says.
    """
    if not user.is_active:
        return False
    return user.is_superuser or user.groups.filter(name__in=STAFF_ROLES).exists()


def other_active_admin_exists(user):
    """True when an active admin *other than* ``user`` exists.

    The last-admin guard asks this question about the post-change state: if the
    account being changed is the only active admin, the change would lock every
    administrator out of user management.
    """
    return (
        User.objects.filter(is_active=True)
        .exclude(pk=user.pk)
        .filter(Q(is_superuser=True) | Q(groups__name__in=STAFF_ROLES))
        .exists()
    )


def update_last_login(user):
    """Update last_login without triggering a full save() chain."""
    User = type(user)
    User.objects.filter(pk=user.pk).update(last_login=timezone.now())