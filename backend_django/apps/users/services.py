# pyright: reportAttributeAccessIssue=false
"""Users app — services for auth-related business logic."""

from django.db.models import Q
from django.utils import timezone

from .models import AuditLog, User
from .permissions import STAFF_ROLES


def log_audit(*, user, action_type, description, ip_address=None, username=None):
    """Append one immutable audit row and return it.

    ``username`` overrides the snapshot for a row whose actor is unknown (a failed login
    against a username that matches no account) — that is why the column exists rather
    than the FK alone.

    ``ip_address`` is stored as NULL when absent: the column is a
    ``GenericIPAddressField``, and an empty string is not a valid address.

    Callers pass document numbers, never credentials: no password, JWT or material-token
    UUID may appear in ``description`` (decision 07).
    """
    if username is None:
        username = getattr(user, 'username', '') or ''
    return AuditLog.objects.create(
        user=user,
        username_snapshot=str(username)[:150],
        action_type=action_type,
        description=description,
        ip_address=ip_address or None,
    )


def audit_request(request, action_type, description, user=None, username=None):
    """``log_audit`` from a request: actor and IP plumbing in one place.

    The actor is ``request.user`` unless ``user`` is passed explicitly. The one caller
    that needs the override is LOGIN: the endpoint is ``AllowAny`` and the request's
    user is still anonymous at the moment the row is written, while the account that
    logged in is known from the validated credentials. Getting this wrong silently wrote
    LOGIN rows with a blank actor — the trail's most-read event.

    ``username`` overrides the snapshot for the other half of that case: a failed login
    whose identifier names no account has no actor at all, and the attempted name is the
    only thing that can identify the row. Passed through rather than re-derived here so
    the snapshot rule keeps living in ``log_audit``.

    The IP is ``REMOTE_ADDR`` only. ``X-Forwarded-For`` is client-controlled, and an
    audit trail that records what the caller claims about itself is not evidence.

    **The caller owns the transaction.** Call this inside the same ``atomic()`` block as
    the event it describes, so a refused or rolled-back event leaves no row claiming it
    happened.
    """
    if user is None:
        candidate = getattr(request, 'user', None)
        if candidate is not None and getattr(candidate, 'is_authenticated', False):
            user = candidate
    ip_address = request.META.get('REMOTE_ADDR') if request is not None else None
    return log_audit(
        user=user,
        action_type=action_type,
        description=description,
        ip_address=ip_address,
        username=username,
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
