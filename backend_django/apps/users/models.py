# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportCallIssue=false, reportAssignmentType=false, reportGeneralTypeIssues=false, reportIncompatibleVariableOverride=false
#
# Same directive and reason as apps/pos/views.py and apps/inventory/views.py: this checker
# runs with a working directory outside the repo, so it resolves no pyrightconfig.json and
# no django-stubs, and every `models.BooleanField(default=...)`, `ManyToManyField`
# `.values_list(...)`, `Meta` override and `QuerySet.as_manager()` is a false positive on
# valid Django. `manage.py check` and the test run remain the authority.
"""
BuildPro User model — custom AbstractBaseUser using username as the
primary login identifier (familiar to store staff). Integrates with
Django's built-in Group / Permission RBAC.

ERD mapping:
    USER        → apps_users.User
    ROLE        → auth.Group (Django built-in)
    PERMISSION  → auth.Permission (Django built-in)
    AUDIT_LOG   → apps_users.AuditLog
"""

from django.contrib.auth.models import (
    AbstractBaseUser,
    BaseUserManager,
    PermissionsMixin,
)
from django.db import models
from django.utils import timezone

from .exceptions import ImmutableAuditLog


class UserManager(BaseUserManager):
    """Custom manager: username is the unique login identifier."""

    def _create_user(self, username, email, password, **extra_fields):
        if not username:
            raise ValueError('Username is required')
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(username=username, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        return self._create_user(username, email, password, **extra_fields)

    def create_superuser(self, username, email=None, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        if not extra_fields.get('is_staff'):
            raise ValueError('Superuser must have is_staff=True.')
        if not extra_fields.get('is_superuser'):
            raise ValueError('Superuser must have is_superuser=True.')
        return self._create_user(username, email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Custom User with username-based authentication.

    username is the primary login field (short, familiar to store staff).
    email is still required and unique for password resets / notifications.

    Roles are managed via Django's built-in Group (auth_group)
    and Permission (auth_permission).
    """
    username = models.CharField(
        max_length=80,
        unique=True,
        db_index=True,
        help_text='Short login name (e.g. staff ID, first name).',
    )
    email = models.EmailField(
        unique=True,
        db_index=True,
        help_text='Used for notifications and password resets.',
    )
    full_name = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(
        default=False,
        help_text='Designates whether the user can log into Django Admin.',
    )
    last_login = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = 'username'
    REQUIRED_FIELDS = ['email', 'full_name']

    class Meta:
        db_table = 'apps_users'
        verbose_name = 'user'
        verbose_name_plural = 'users'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['username']),
            models.Index(fields=['email']),
            models.Index(fields=['is_active']),
            models.Index(fields=['-created_at']),
        ]

    def __str__(self):
        return f'{self.username} ({self.full_name})'

    @property
    def role_names(self):
        """Convenience: list of group/role names this user belongs to."""
        return list(self.groups.values_list('name', flat=True))


class AuditLogQuerySet(models.QuerySet):
    """The trail is append-only at the ORM level, not by convention (decision 07).

    `update()` and `delete()` are the two ways a row can change after the fact without
    going through `save()`, so both refuse here. Reads (including `.filter(...)`) are
    untouched: only the mutations raise.
    """

    def update(self, **kwargs):
        raise ImmutableAuditLog()

    def delete(self):
        raise ImmutableAuditLog()


class AuditLog(models.Model):
    """Immutable audit trail for critical actions.

    ERD: AUDIT_LOG

    Three independent guards keep a written row written, and each covers a different
    door: `save()` refuses an UPDATE of an existing pk, `delete()` refuses removal on the
    instance, and the custom queryset refuses the bulk `update()`/`delete()` that never
    touch an instance at all. `user` is `PROTECT` so the account a row names cannot be
    deleted out from under its own history; `username_snapshot` keeps that name readable
    on the row itself, including for a row written for an actor who does not exist (a
    failed login by an unknown identifier).
    """

    class ActionType(models.TextChoices):
        LOGIN = 'LOGIN', 'Login'
        LOGIN_FAILED = 'LOGIN_FAILED', 'Failed Login'
        LOGOUT = 'LOGOUT', 'Logout'
        CREATE = 'CREATE', 'Create'
        UPDATE = 'UPDATE', 'Update'
        DELETE = 'DELETE', 'Delete'
        SALE = 'SALE', 'Sale'
        RETURN = 'RETURN', 'Return'
        RELEASE = 'RELEASE', 'Material Release'
        STOCK_ADJUST = 'STOCK_ADJUST', 'Stock Adjustment'
        RECEIPT = 'RECEIPT', 'Goods Receipt'
        PAYMENT = 'PAYMENT', 'Payment'
        REQ_APPROVE = 'REQ_APPROVE', 'Requisition Approved'
        REQ_REJECT = 'REQ_REJECT', 'Requisition Rejected'
        ALERT_RESOLVE = 'ALERT_RESOLVE', 'Alert Resolved'
        SHIFT_OPEN = 'SHIFT_OPEN', 'Shift Opened'
        SHIFT_CLOSE = 'SHIFT_CLOSE', 'Shift Closed'
        CART_VOID = 'CART_VOID', 'Held Cart Voided'
        ROLE_CHANGE = 'ROLE_CHANGE', 'Role Changed'
        USER_DEACTIVATE = 'USER_DEACTIVATE', 'User Deactivated'

    user = models.ForeignKey(
        User,
        on_delete=models.PROTECT,
        null=True,
        related_name='audit_logs',
    )
    # Filled by `log_audit` from `user.username`, or from the `username=` kwarg when the
    # actor is unknown. It is the row's own copy of the name, so a deactivated account
    # still reads correctly in the trail, and it is never taken from the request body.
    username_snapshot = models.CharField(max_length=150, blank=True)
    action_type = models.CharField(max_length=20, choices=ActionType.choices)
    description = models.TextField()
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

    objects = AuditLogQuerySet.as_manager()

    class Meta:
        db_table = 'apps_audit_log'
        verbose_name = 'audit log'
        verbose_name_plural = 'audit logs'
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['user', '-timestamp']),
            models.Index(fields=['action_type']),
        ]

    def __str__(self):
        actor = self.username_snapshot or self.user
        return f'[{self.action_type}] {actor} @ {self.timestamp:%Y-%m-%d %H:%M}'

    def save(self, *args, **kwargs):
        """Insert only. A pk that already exists is an attempt to rewrite history."""
        if self.pk is not None:
            exists = type(self).objects.filter(pk=self.pk).exists()
            if exists:
                raise ImmutableAuditLog()
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ImmutableAuditLog()
