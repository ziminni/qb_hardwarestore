# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false, reportMissingImports=false
#
# The second half of that directive list is the same false-positive class documented in
# apps/collectibles/views.py: without django-stubs this checker cannot see that
# `transaction.atomic()` is a context manager.
"""Users app — ViewSets and auth views."""

from django.contrib.auth.models import Group
from django.db import transaction
from django.db.models import Q
from rest_framework import serializers, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework_simplejwt.tokens import RefreshToken

from . import lockout
from .models import AuditLog, User
from .permissions import (
    STAFF_ROLES,
    IsAdminRole,
    IsUserManagerRole,
    has_role,
    role_codes_for,
)
from .serializers import (
    ROLES_CONFLICT_CODE,
    ROLES_CONFLICT_DETAIL,
    AuditLogSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserSerializer,
    body_mixes_role_fields,
    find_user_by_identifier,
    group_names_for_codes,
    groups_for_role_codes,
    parse_role_codes,
    requested_group_names,
    roles_conflict_response,
)
from .services import (
    audit_request,
    is_active_admin,
    lock_admin_rows,
    other_active_admin_exists,
    update_last_login,
)

LOGIN_LOCKED_CODE = "LOGIN_LOCKED"
LOGIN_LOCKED_DETAIL = (
    "Too many failed sign-in attempts. Try again in {minutes} minutes."
)


LAST_ADMIN_DETAIL = (
    "This change would leave no active admin. Promote or activate another "
    "admin account first."
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
        {"code": "LAST_ADMIN", "detail": LAST_ADMIN_DETAIL},
        status=status.HTTP_400_BAD_REQUEST,
    )


# ---------------------------------------------------------------------------
# Auth endpoints (public)
# ---------------------------------------------------------------------------


@api_view(["POST"])
@permission_classes([IsAdminRole])
def register_view(request):
    """Create an account; public registration is intentionally disabled.

    Authority is the Admin *group* (decision 04) — ``is_staff`` only decides who
    may open Django's ``/admin`` site. The body names the account's roles with
    ``roles`` (Phase 4 B3) or the legacy ``group_name``; naming both is refused before
    the serializer runs, so the answer is the flat ``{code, detail}`` a client expects.
    """
    if body_mixes_role_fields(request.data):
        return roles_conflict_response()
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    # One atomic block: the account and the row that records who created it commit or
    # roll back together (decision 07).
    with transaction.atomic():
        user = serializer.save()
        audit_request(
            request,
            AuditLog.ActionType.CREATE,
            f"User {user.username} created.",
        )
    return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me_view(request):
    return Response(UserSerializer(request.user).data)


@api_view(["POST"])
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
        f"{request.user.username} logged out.",
    )
    return Response(status=status.HTTP_204_NO_CONTENT)


def _refresh_value(request):
    data = request.data
    return data.get("refresh") if hasattr(data, "get") else None


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


@api_view(["POST"])
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
    key = lockout.attempt_key(identifier, request.META.get("REMOTE_ADDR"))

    if lockout.is_locked(key):
        retry_after = lockout.retry_after_seconds(key)
        return Response(
            {
                "code": LOGIN_LOCKED_CODE,
                "detail": LOGIN_LOCKED_DETAIL.format(
                    minutes=max(1, -(-retry_after // 60))
                ),
                "retry_after": retry_after,
            },
            status=status.HTTP_429_TOO_MANY_REQUESTS,
        )

    serializer = LoginSerializer(
        data=request.data,
        context={"request": request},
    )
    if not serializer.is_valid():
        lockout.record_failure(key)
        record_login_failure(request, identifier)
        # Same body a plain raise_exception=True produced: this endpoint's refusals are
        # not allowed to grow distinguishing detail just because it is now counted.
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    user = serializer.validated_data["user"]
    lockout.reset(key)

    update_last_login(user)
    # `user=user`: this endpoint is AllowAny, so `request.user` is still anonymous.
    audit_request(
        request,
        AuditLog.ActionType.LOGIN,
        f"{user.username} logged in.",
        user=user,
    )

    refresh = RefreshToken.for_user(user)
    return Response(
        {
            "access": str(refresh.access_token),
            "refresh": str(refresh),
            "user": UserSerializer(user).data,
        }
    )


def _login_identifier(request):
    """The name the caller tried to sign in as (``identifier``, else ``username``)."""
    data = request.data
    if not hasattr(data, "get"):
        return ""
    return (data.get("identifier") or data.get("username") or "").strip()


def record_login_failure(request, identifier):
    """One ``LOGIN_FAILED`` row for one refused attempt.

    The actor is the matched account when the identifier names one, so an admin can read
    "who was attacked" from the row's FK. When it names nobody, the attempted name goes
    into ``username_snapshot`` — the reason that column exists.

    The description carries the attempted identifier (truncated to the column width) and
    never the password, and the row's IP comes from ``REMOTE_ADDR`` via ``audit_request``.
    """
    user = find_user_by_identifier(identifier)
    attempted = (identifier or "(blank)")[:150]
    audit_request(
        request,
        AuditLog.ActionType.LOGIN_FAILED,
        f"Failed sign-in attempt for {attempted}.",
        user=user,
        username=None if user is not None else attempted,
    )


# ---------------------------------------------------------------------------
# User ViewSet
# ---------------------------------------------------------------------------

USER_ADMIN_FORBIDDEN_CODE = "USER_ADMIN_FORBIDDEN"
USER_ADMIN_FORBIDDEN_DETAIL = (
    "Only an Admin may change an admin account or grant admin authority."
)


def user_admin_refusal(request, target, group_names=()):
    """403 when a non-admin caller reaches for admin authority (Phase 5).

    Store Managers offboard non-admin staff; admin accounts (Admin / System
    Administrator groups or superuser, active OR deactivated — reviving a
    dormant admin is still seizing admin power) and admin GROUP grants stay
    Admin-only. Admin callers never see this refusal.

    ``group_names`` is every group the body asks for, from BOTH role fields: a body
    that names `roles: ["admin"]` beside a legacy `group_name` is refused here, so no
    caller can trade on which field a guard happens to read (Phase 4 task B3).
    """
    if has_role(request.user, STAFF_ROLES):
        return None
    if target is not None and (
        target.is_superuser or target.groups.filter(name__in=STAFF_ROLES).exists()
    ):
        return Response(
            {"code": USER_ADMIN_FORBIDDEN_CODE, "detail": USER_ADMIN_FORBIDDEN_DETAIL},
            status=status.HTTP_403_FORBIDDEN,
        )
    if set(group_names) & set(STAFF_ROLES):
        return Response(
            {"code": USER_ADMIN_FORBIDDEN_CODE, "detail": USER_ADMIN_FORBIDDEN_DETAIL},
            status=status.HTTP_403_FORBIDDEN,
        )
    return None


class RoleChangeRefused(Exception):
    """A role-change body the server refuses, carrying its own HTTP status.

    ``assign_role`` / ``remove_role`` answer 400 for a missing name and 404 for an
    unknown Group (the shape released clients already branch on), so the resolution
    helper carries the status instead of forcing one.
    """

    def __init__(self, detail, status_code=status.HTTP_400_BAD_REQUEST, code=None):
        self.payload = {"detail": detail}
        if code:
            self.payload["code"] = code
        self.status_code = status_code
        super().__init__(detail)


def resolve_role_change(data):
    """Groups a role-change body asks for, from `roles[]` or legacy `group_name`.

    Returns ``(groups, codes)`` where ``codes`` is the validated code list for a
    `roles[]` body and ``None`` for a legacy `group_name` body. A body that names both
    fields is refused rather than resolved, and an invalid `roles[]` reuses the
    serializer's messages so every write path answers the same way.
    """
    if body_mixes_role_fields(data):
        raise RoleChangeRefused(
            ROLES_CONFLICT_DETAIL,
            status_code=status.HTTP_400_BAD_REQUEST,
            code=ROLES_CONFLICT_CODE,
        )
    if "roles" in data:
        try:
            codes = parse_role_codes(data.get("roles"))
            return groups_for_role_codes(codes), codes
        except serializers.ValidationError as exc:
            # ONLY the expected refusal is a 400. A broader `except` here re-served any
            # real bug as a bad-body answer, hiding it from the client and the logs.
            messages = exc.detail
            raise RoleChangeRefused(
                messages[0] if isinstance(messages, list) and messages else str(exc),
            ) from exc
    group_name = data.get("group_name")
    if not group_name:
        raise RoleChangeRefused("group_name (or roles) is required.")
    try:
        return [Group.objects.get(name=group_name)], None
    except Group.DoesNotExist as exc:
        raise RoleChangeRefused(
            f'Group "{group_name}" does not exist.',
            status_code=status.HTTP_404_NOT_FOUND,
        ) from exc


def role_names_text(groups):
    """The group names in a body, for an audit description (never credentials)."""
    return ", ".join(group.name for group in groups)


class UserViewSet(viewsets.ModelViewSet):
    """Store Manager / Admin writes for user accounts (Phase 5).

    Accounts are deactivated, never deleted: audit rows will PROTECT their user
    (decision 07), so ``DELETE`` is not routed at all — it answers 405.
    Store Managers may deactivate/reactivate and assign/remove NON-admin
    roles; anything reaching admin authority is 403 USER_ADMIN_FORBIDDEN.
    Account creation stays Admin-only via ``register_view``.
    """

    queryset = User.objects.prefetch_related("groups").all()
    serializer_class = UserSerializer
    permission_classes = [IsUserManagerRole]
    http_method_names = ["get", "post", "put", "patch", "head", "options"]

    def get_queryset(self):
        qs = super().get_queryset()
        search = self.request.query_params.get("search")
        if search:
            qs = qs.filter(
                Q(email__icontains=search)
                | Q(full_name__icontains=search)
                | Q(username__icontains=search),
            )
        return qs

    def create(self, request, *args, **kwargs):
        """Account creation stays Admin-only; managers change existing rows."""
        refusal = user_admin_refusal(request, None, group_names=STAFF_ROLES)
        if refusal is not None:
            return refusal
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        """PATCH / PUT, guarded so the last active admin cannot be disabled.

        A body may also send ``roles`` (Phase 4 B3): the account's groups are replaced
        and the same guards run on the ROLE change as on a deactivation - the last
        active admin cannot be demoted this way either. The refusal for admin authority
        is decided from both fields BEFORE validation, so a caller who names admin in
        either field is 403 whatever else the body contains.
        """
        instance = self.get_object()
        refusal = user_admin_refusal(
            request, instance, group_names=requested_group_names(request.data)
        )
        if refusal is not None:
            return refusal
        if body_mixes_role_fields(request.data):
            return roles_conflict_response()
        was_active = instance.is_active
        serializer = self.get_serializer(
            instance, data=request.data, partial=kwargs.get("partial", False)
        )
        serializer.is_valid(raise_exception=True)
        is_active_after = serializer.validated_data.get("is_active", instance.is_active)
        new_groups = serializer.validated_data.get("roles")
        # The guard DECIDES UNDER THE LOCK (review F3): the target and every other
        # active admin are row-locked first, and the decision is made on the re-read
        # row, so "another admin is alive" cannot go stale before this write commits.
        # The write and its audit row stay in the same block (decision 07).
        with transaction.atomic():
            locked = lock_admin_rows(instance)
            if new_groups is None:
                keeps_admin_group = locked.groups.filter(name__in=STAFF_ROLES).exists()
            else:
                keeps_admin_group = any(
                    group.name in STAFF_ROLES for group in new_groups
                )
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=is_active_after
                and (locked.is_superuser or keeps_admin_group),
            )
            if refusal is not None:
                return refusal
            response = super().update(request, *args, **kwargs)
            instance.refresh_from_db()
            if was_active and not instance.is_active:
                audit_request(
                    request,
                    AuditLog.ActionType.USER_DEACTIVATE,
                    f"User {instance.username} deactivated.",
                )
            elif new_groups is not None:
                audit_request(
                    request,
                    AuditLog.ActionType.ROLE_CHANGE,
                    f"User {instance.username} roles set to "
                    f"{', '.join(role_codes_for(instance)) or 'none'}.",
                )
            else:
                audit_request(
                    request,
                    AuditLog.ActionType.UPDATE,
                    f"User {instance.username} updated.",
                )
        return response

    @action(detail=False, methods=["get"])
    def stats(self, request):
        """Account summary for the admin User Management dashboard cards."""
        total = User.objects.count()
        active = User.objects.filter(is_active=True).count()
        roles_assigned = (
            User.objects.exclude(groups=None).values("groups").distinct().count()
        )
        return Response(
            {
                "total": total,
                "active": active,
                "inactive": total - active,
                "roles_assigned": roles_assigned,
            }
        )

    @action(detail=True, methods=["post"])
    def assign_role(self, request, pk=None):
        """POST /api/users/{id}/assign_role/

        Body is ``{"roles": ["pos", "sales"]}`` (Phase 4 B3) or the legacy
        ``{"group_name": "Cashier"}``. Membership is REPLACED, so assigning a
        non-admin role demotes the account — refused when that account is the last
        active admin. Non-admin callers cannot touch admin accounts or grant admin
        authority with either field.
        """
        user = self.get_object()
        refusal = user_admin_refusal(
            request, user, group_names=requested_group_names(request.data)
        )
        if refusal is not None:
            return refusal
        try:
            groups, codes = resolve_role_change(request.data)
        except RoleChangeRefused as exc:
            return Response(exc.payload, status=exc.status_code)
        # Codes when the body used codes (what the client read back), group names for a
        # legacy `group_name` body (what that client sent).
        assigned_text = ", ".join(codes) if codes else role_names_text(groups)
        # Lock first, then decide (review F3): assigning a non-admin group demotes the
        # account, and the "is another admin alive?" answer must not go stale before the
        # write. The membership change and its audit row commit together (decision 07).
        with transaction.atomic():
            locked = lock_admin_rows(user)
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=locked.is_active
                and (
                    locked.is_superuser
                    or any(group.name in STAFF_ROLES for group in groups)
                ),
            )
            if refusal is not None:
                return refusal
            user.groups.set(groups)
            audit_request(
                request,
                AuditLog.ActionType.ROLE_CHANGE,
                f"{user.username} assigned to {assigned_text}.",
            )
        return Response(
            {
                "detail": f"{user.username} assigned to {assigned_text}.",
                "user": UserSerializer(user).data,
            }
        )

    @action(detail=True, methods=["post"])
    def remove_role(self, request, pk=None):
        """POST /api/users/{id}/remove_role/

        Body is ``{"roles": ["pos"]}`` (a code drops every group that code covers, so
        ``admin`` removes Admin or System Administrator) or the legacy
        ``{"group_name": "Cashier"}``. Non-admin callers cannot touch admin accounts
        or admin groups.
        """
        user = self.get_object()
        refusal = user_admin_refusal(
            request, user, group_names=requested_group_names(request.data)
        )
        if refusal is not None:
            return refusal
        try:
            groups, codes = resolve_role_change(request.data)
        except RoleChangeRefused as exc:
            return Response(exc.payload, status=exc.status_code)
        if codes is not None:
            # A code is an AREA, not one row: `admin` must drop whichever of Admin /
            # System Administrator the account actually holds.
            groups = list(Group.objects.filter(name__in=group_names_for_codes(codes)))
        doomed = {group.pk for group in groups}
        # Same shape as assign_role (review F3): lock the admin rows, then read the
        # remaining admin membership from the LOCKED row, then write.
        with transaction.atomic():
            locked = lock_admin_rows(user)
            still_has_admin_group = (
                locked.groups.filter(name__in=STAFF_ROLES)
                .exclude(pk__in=doomed)
                .exists()
            )
            refusal = last_admin_refusal(
                locked,
                keeps_admin_authority=locked.is_active
                and (locked.is_superuser or still_has_admin_group),
            )
            if refusal is not None:
                return refusal
            removed_text = ", ".join(codes) if codes else role_names_text(groups)
            for group in groups:
                locked.groups.remove(group)
            audit_request(
                request,
                AuditLog.ActionType.ROLE_CHANGE,
                f"{removed_text} removed from {user.username}.",
            )
        user.refresh_from_db()
        return Response(
            {
                "detail": f"{removed_text} removed from {user.username}.",
                "user": UserSerializer(user).data,
            }
        )


# ---------------------------------------------------------------------------
# AuditLog ViewSet (read-only)
# ---------------------------------------------------------------------------


class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AuditLog.objects.select_related("user").all()
    serializer_class = AuditLogSerializer
    permission_classes = [IsAdminRole]
