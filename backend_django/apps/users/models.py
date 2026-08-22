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


class AuditLog(models.Model):
    """Immutable audit trail for critical actions.

    ERD: AUDIT_LOG
    """

    class ActionType(models.TextChoices):
        LOGIN = 'LOGIN', 'Login'
        LOGOUT = 'LOGOUT', 'Logout'
        CREATE = 'CREATE', 'Create'
        UPDATE = 'UPDATE', 'Update'
        DELETE = 'DELETE', 'Delete'
        SALE = 'SALE', 'Sale'
        STOCK_ADJUST = 'STOCK_ADJUST', 'Stock Adjustment'
        RECEIPT = 'RECEIPT', 'Goods Receipt'
        PAYMENT = 'PAYMENT', 'Payment'

    user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        related_name='audit_logs',
    )
    action_type = models.CharField(max_length=20, choices=ActionType.choices)
    description = models.TextField()
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True, db_index=True)

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
        return f'[{self.action_type}] {self.user} @ {self.timestamp:%Y-%m-%d %H:%M}'
