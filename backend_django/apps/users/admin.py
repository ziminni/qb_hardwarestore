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
    list_display = ('action_type', 'user', 'ip_address', 'timestamp')
    list_filter = ('action_type',)
    search_fields = ('description', 'user__email')
    readonly_fields = [f.name for f in AuditLog._meta.fields]
    ordering = ('-timestamp',)
