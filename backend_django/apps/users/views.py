# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false
#
# The second half of that directive list is the same false-positive class documented in
# apps/collectibles/views.py: without django-stubs this checker cannot see that
# `transaction.atomic()` is a context manager.
"""Users app — ViewSets and auth views."""

from django.contrib.auth.models import Group
from django.db import transaction
from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import AuditLog, User
from .permissions import STAFF_ROLES, IsAdminRole
from .serializers import (
    AuditLogSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserSerializer,
)
from .services import (
    audit_request,
    is_active_admin,
    other_active_admin_exists,
    update_last_login,
)


LAST_ADMIN_DETAIL = (
    'This change would leave no active admin. Promote or activate another '
    'admin account first.'
)


def last_admin_refusal(target, *, keeps_admin_authority):
    """400 LAST_ADMIN when a change would strip the only active admin.

    ``keeps_admin_authority`` is the *post-change* answer to "is this account
    still an active admin?" — callers compute it from the fields they are about
    to write (``is_active`` or group membership). The guard only fires when the
    target is today an active admin and nobody else is: accounts without
    authority can always be changed, because that removes no admin.
    """
    if keeps_admin_authority or not is_active_admin(target):
        return None
    if other_active_admin_exists(target):
        return None
    return Response(
        {'code': 'LAST_ADMIN', 'detail': LAST_ADMIN_DETAIL},
        status=status.HTTP_400_BAD_REQUEST,
    )


# ---------------------------------------------------------------------------
# Auth endpoints (public)
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsAdminRole])
def register_view(request):
    """Create an account; public registration is intentionally disabled.

    Authority is the Admin *group* (decision 04) — ``is_staff`` only decides who
    may open Django's ``/admin`` site.
    """
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    # One atomic block: the account and the row that records who created it commit or
    # roll back together (decision 07).
    with transaction.atomic():
        user = serializer.save()
        audit_request(
            request,
            AuditLog.ActionType.CREATE,
            f'User {user.username} created.',
        )
    return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def me_view(request):
    return Response(UserSerializer(request.user).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def logout_view(request):
    audit_request(
        request,
        AuditLog.ActionType.LOGOUT,
        f'{request.user.username} logged out.',
    )
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """Login: validate credentials and return JWT pair."""
    serializer = LoginSerializer(
        data=request.data,
        context={'request': request},
    )
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']

    update_last_login(user)
    # `user=user`: this endpoint is AllowAny, so `request.user` is still anonymous.
    audit_request(
        request,
        AuditLog.ActionType.LOGIN,
        f'{user.username} logged in.',
        user=user,
    )

    refresh = RefreshToken.for_user(user)
    return Response({
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user': UserSerializer(user).data,
    })


# ---------------------------------------------------------------------------
# User ViewSet
# ---------------------------------------------------------------------------

class UserViewSet(viewsets.ModelViewSet):
    """Admin CRUD for user accounts.

    Accounts are deactivated, never deleted: audit rows will PROTECT their user
    (decision 07), so ``DELETE`` is not routed at all — it answers 405.
    """
    queryset = User.objects.prefetch_related('groups').all()
    serializer_class = UserSerializer
    permission_classes = [IsAdminRole]
    http_method_names = ['get', 'post', 'put', 'patch', 'head', 'options']

    def get_queryset(self):
        qs = super().get_queryset()
        search = self.request.query_params.get('search')
        if search:
            qs = qs.filter(
                Q(email__icontains=search)
                | Q(full_name__icontains=search)
                | Q(username__icontains=search),
            )
        return qs

    def update(self, request, *args, **kwargs):
        """PATCH / PUT, guarded so the last active admin cannot be disabled."""
        instance = self.get_object()
        was_active = instance.is_active
        serializer = self.get_serializer(
            instance, data=request.data, partial=kwargs.get('partial', False))
        serializer.is_valid(raise_exception=True)
        is_active_after = serializer.validated_data.get(
            'is_active', instance.is_active)
        refusal = last_admin_refusal(
            instance,
            keeps_admin_authority=is_active_after and is_active_admin(instance),
        )
        if refusal is not None:
            return refusal
        # The write and its audit row are one transaction (decision 07): a refused or
        # rolled-back update leaves no row claiming the change happened.
        with transaction.atomic():
            response = super().update(request, *args, **kwargs)
            instance.refresh_from_db()
            if was_active and not instance.is_active:
                audit_request(
                    request,
                    AuditLog.ActionType.USER_DEACTIVATE,
                    f'User {instance.username} deactivated.',
                )
            else:
                audit_request(
                    request,
                    AuditLog.ActionType.UPDATE,
                    f'User {instance.username} updated.',
                )
        return response

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """Account summary for the admin User Management dashboard cards."""
        total = User.objects.count()
        active = User.objects.filter(is_active=True).count()
        roles_assigned = (
            User.objects.exclude(groups=None)
            .values('groups')
            .distinct()
            .count()
        )
        return Response({
            'total': total,
            'active': active,
            'inactive': total - active,
            'roles_assigned': roles_assigned,
        })

    @action(detail=True, methods=['post'])
    def assign_role(self, request, pk=None):
        """POST /api/users/{id}/assign_role/  { "group_name": "Cashier" }

        Membership is replaced, so assigning a non-admin group demotes the
        account — refused when that account is the last active admin.
        """
        user = self.get_object()
        group_name = request.data.get('group_name')
        if not group_name:
            return Response(
                {'detail': 'group_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            group = Group.objects.get(name=group_name)
        except Group.DoesNotExist:
            return Response(
                {'detail': f'Group "{group_name}" does not exist.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        refusal = last_admin_refusal(
            user,
            keeps_admin_authority=user.is_active and (
                user.is_superuser or group.name in STAFF_ROLES),
        )
        if refusal is not None:
            return refusal
        with transaction.atomic():
            user.groups.set([group])
            audit_request(
                request,
                AuditLog.ActionType.ROLE_CHANGE,
                f'{user.username} assigned to {group_name}.',
            )
        return Response({'detail': f'{user.username} assigned to {group_name}.'})

    @action(detail=True, methods=['post'])
    def remove_role(self, request, pk=None):
        """POST /api/users/{id}/remove_role/  { "group_name": "Cashier" }"""
        user = self.get_object()
        group_name = request.data.get('group_name')
        if not group_name:
            return Response(
                {'detail': 'group_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            group = Group.objects.get(name=group_name)
        except Group.DoesNotExist:
            return Response(
                {'detail': f'Group "{group_name}" does not exist.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        still_has_admin_group = (
            user.groups.filter(name__in=STAFF_ROLES)
            .exclude(pk=group.pk)
            .exists()
        )
        refusal = last_admin_refusal(
            user,
            keeps_admin_authority=user.is_active and (
                user.is_superuser or still_has_admin_group),
        )
        if refusal is not None:
            return refusal
        with transaction.atomic():
            user.groups.remove(group)
            audit_request(
                request,
                AuditLog.ActionType.ROLE_CHANGE,
                f'{group_name} removed from {user.username}.',
            )
        return Response({'detail': f'{group_name} removed from {user.username}.'})


# ---------------------------------------------------------------------------
# AuditLog ViewSet (read-only)
# ---------------------------------------------------------------------------

class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AuditLog.objects.select_related('user').all()
    serializer_class = AuditLogSerializer
    permission_classes = [IsAdminRole]
