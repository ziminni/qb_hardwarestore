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
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework_simplejwt.tokens import RefreshToken

from . import lockout
from .models import AuditLog, User
from .permissions import STAFF_ROLES, IsAdminRole
from .serializers import (
    AuditLogSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserSerializer,
    find_user_by_identifier,
)
from .services import (
    audit_request,
    is_active_admin,
    lock_admin_rows,
    other_active_admin_exists,
    update_last_login,
)


LOGIN_LOCKED_CODE = 'LOGIN_LOCKED'
LOGIN_LOCKED_DETAIL = (
    'Too many failed sign-in attempts. Try again in {minutes} minutes.'
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
    """Sign out: revoke ``{refresh}`` when it is the caller's, then audit. Always 204.

    Local sign-out must never fail: an unparseable, expired, already-blacklisted or
    someone else's token is simply ignored, so the client can always clear its own
    tokens. The audit row is written either way — the LOGOUT event is the fact that the
    user asked to sign out, not that a particular token was revoked.
    """
    revoke_refresh_token(request, _refresh_value(request))
    audit_request(
        request,
        AuditLog.ActionType.LOGOUT,
        f'{request.user.username} logged out.',
    )
    return Response(status=status.HTTP_204_NO_CONTENT)


def _refresh_value(request):
    data = request.data
    return data.get('refresh') if hasattr(data, 'get') else None


def revoke_refresh_token(request, value):
    """Blacklist ``value`` if it parses and belongs to ``request.user``; else ignore.

    The ownership check is the point: without it any authenticated session could
    blacklist a refresh token it merely happened to see. A foreign token is not an
    error (that would disclose whether the token is real), and neither is a garbage
    body — both are silent no-ops.
    """
    if not isinstance(value, str) or not value:
        return False
    try:
        token = RefreshToken(value)
    except TokenError:
        return False
    if str(token.payload.get(jwt_settings.USER_ID_CLAIM)) != str(request.user.pk):
        return False
    try:
        token.blacklist()
    except TokenError:
        return False
    return True


@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """Login: validate credentials and return JWT pair.

    Order matters: the lockout is answered **before** the password is looked at. A
    locked pair that still validated the password would tell an attacker which guesses
    were right, which is the one thing a lockout exists to prevent. Every counted
    failure writes a ``LOGIN_FAILED`` row (decision 07); the response body stays the
    same for an unknown user and a wrong password, and an inactive account's refusal
    counts as a failure too, so a lockout cannot be dodged by pointing at a disabled
    account.
    """
    identifier = _login_identifier(request)
    key = lockout.attempt_key(identifier, request.META.get('REMOTE_ADDR'))

    if lockout.is_locked(key):
        retry_after = lockout.retry_after_seconds(key)
        return Response(
            {
                'code': LOGIN_LOCKED_CODE,
                'detail': LOGIN_LOCKED_DETAIL.format(
                    minutes=max(1, -(-retry_after // 60))),
                'retry_after': retry_after,
            },
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    serializer = LoginSerializer(
        data=request.data,
        context={'request': request},
    )
    if not serializer.is_valid():
        lockout.record_failure(key)
        record_login_failure(request, identifier)
        # Same body a plain raise_exception=True produced: this endpoint's refusals are
        # not allowed to grow distinguishing detail just because it is now counted.
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    user = serializer.validated_data['user']
    lockout.reset(key)

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


def _login_identifier(request):
    """The name the caller tried to sign in as (``identifier``, else ``username``)."""
    data = request.data
    if not hasattr(data, 'get'):
        return ''
    return (data.get('identifier') or data.get('username') or '').strip()


def record_login_failure(request, identifier):
    """One ``LOGIN_FAILED`` row for one refused attempt.

    The actor is the matched account when the identifier names one, so an admin can read
    "who was attacked" from the row's FK. When it names nobody, the attempted name goes
    into ``username_snapshot`` — the reason that column exists.

    The description carries the attempted identifier (truncated to the column width) and
    never the password, and the row's IP comes from ``REMOTE_ADDR`` via ``audit_request``.
    """
    user = find_user_by_identifier(identifier)
    attempted = (identifier or '(blank)')[:150]
    audit_request(
        request,
        AuditLog.ActionType.LOGIN_FAILED,
        f'Failed sign-in attempt for {attempted}.',
        user=user,
        username=None if user is not None else attempted,
    )


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
        # The guard DECIDES UNDER THE LOCK (review F3): the target and every other
        # active admin are row-locked first, and the decision is made on the re-read
        # row, so "another admin is alive" cannot go stale before this write commits.
        # The write and its audit row stay in the same block (decision 07).
        with transaction.atomic():
            locked = lock_admin_rows(instance)
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=is_active_after and is_active_admin(locked),
            )
            if refusal is not None:
                return refusal
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
        # Lock first, then decide (review F3): assigning a non-admin group demotes the
        # account, and the "is another admin alive?" answer must not go stale before the
        # write. The membership change and its audit row commit together (decision 07).
        with transaction.atomic():
            locked = lock_admin_rows(user)
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=locked.is_active and (
                    locked.is_superuser or group.name in STAFF_ROLES),
            )
            if refusal is not None:
                return refusal
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
        # Same shape as assign_role (review F3): lock the admin rows, then read the
        # remaining admin membership from the LOCKED row, then write.
        with transaction.atomic():
            locked = lock_admin_rows(user)
            still_has_admin_group = (
                locked.groups.filter(name__in=STAFF_ROLES)
                .exclude(pk=group.pk)
                .exists()
            )
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=locked.is_active and (
                    locked.is_superuser or still_has_admin_group),
            )
            if refusal is not None:
                return refusal
            locked.groups.remove(group)
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
