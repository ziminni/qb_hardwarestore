"""Users app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from .system_views import (
    system_backup_download_view,
    system_backup_restore_view,
    system_backup_schedule_view,
    system_backups_view,
    system_revoke_session_view,
    system_security_overview_view,
    system_security_policy_view,
)
from .views import (
    AuditLogViewSet,
    UserViewSet,
    login_view,
    logout_view,
    me_view,
    my_avatar_view,
    register_view,
)

router = DefaultRouter()
router.register(r'users', UserViewSet, basename='user')
router.register(r'audit-logs', AuditLogViewSet, basename='auditlog')

urlpatterns = [
    path('auth/register/', register_view, name='auth-register'),
    path('auth/login/', login_view, name='auth-login'),
    path('auth/refresh/', TokenRefreshView.as_view(), name='auth-refresh'),
    path('auth/logout/', logout_view, name='auth-logout'),
    path('auth/me/', me_view, name='auth-me'),
    path('auth/me/avatar/', my_avatar_view, name='auth-me-avatar'),
    path('system/security/', system_security_overview_view, name='system-security'),
    path('system/security/policy/', system_security_policy_view, name='system-security-policy'),
    path(
        'system/security/sessions/<str:session_id>/revoke/',
        system_revoke_session_view,
        name='system-security-revoke-session',
    ),
    path('system/backups/', system_backups_view, name='system-backups'),
    path('system/backups/schedule/', system_backup_schedule_view, name='system-backups-schedule'),
    path('system/backups/restore/', system_backup_restore_view, name='system-backups-restore'),
    path(
        'system/backups/<str:backup_id>/download/',
        system_backup_download_view,
        name='system-backups-download',
    ),
    path('', include(router.urls)),
]
