"""Users app — services for auth-related business logic."""

from django.utils import timezone

from .models import AuditLog


def log_audit(*, user, action_type, description, ip_address=None):
    """Create an immutable audit log entry."""
    AuditLog.objects.create(
        user=user,
        action_type=action_type,
        description=description,
        ip_address=ip_address or '',
    )


def update_last_login(user):
    """Update last_login without triggering a full save() chain."""
    User = type(user)
    User.objects.filter(pk=user.pk).update(last_login=timezone.now())