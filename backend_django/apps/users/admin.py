# pyright: reportAttributeAccessIssue=false
#
# Same directive and reason as apps/users/models.py: the checker runs without
# django-stubs from a working directory outside the repo, so `Model._meta` and the
# `admin.ModelAdmin` hook calls are false positives on valid Django.
"""Django Admin registration for the Users app."""

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import Group, Permission

from .models import AuditLog, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = ('username', 'email', 'full_name', 'is_active', 'is_staff', 'created_at')
    list_filter = ('is_active', 'is_staff', 'groups')
    search_fields = ('username', 'email', 'full_name')
    ordering = ('username',)
    readonly_fields = ('last_login', 'created_at', 'updated_at')

    fieldsets = (
        (None, {'fields': ('username', 'email', 'password')}),
        ('Personal info', {'fields': ('full_name',)}),
        ('Permissions', {
            'fields': (
                'is_active',
                'is_staff',
                'is_superuser',
                'groups',
                'user_permissions',
            ),
        }),
        ('Timestamps', {'fields': ('last_login', 'created_at', 'updated_at')}),
    )

    add_fieldsets = (
        (None, {
            'classes': ('wide',),
            'fields': (
                'username', 'email', 'full_name', 'password1', 'password2',
                'is_active', 'is_staff', 'groups',
            ),
        }),
    )


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    """Read-only by construction (decision 07): the trail is append-only.

    Add / change / delete are refused even for a Django superuser. The row-level guards
    in the model are the real protection; this stops the admin UI from offering a button
    that could only fail.
    """

    list_display = (
        'action_type', 'username_snapshot', 'user', 'ip_address', 'timestamp')
    list_filter = ('action_type',)
    search_fields = ('description', 'username_snapshot', 'user__email')
    readonly_fields = [f.name for f in AuditLog._meta.fields]
    ordering = ('-timestamp',)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
