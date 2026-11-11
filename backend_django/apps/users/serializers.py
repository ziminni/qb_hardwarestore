# pyright: reportMissingImports=false
#
# Same false-positive class documented in apps/users/models.py: this checker runs with a
# working directory outside the repo, so it resolves neither pyrightconfig.json nor
# django-stubs.
"""Users app — serializers for registration, login, profile."""

from django.contrib.auth.models import Group
from django.db.models import Q
from rest_framework import serializers

from .models import AuditLog, User
from .permissions import (
    ROLE_CODE_CPMS,
    ROLE_CODE_GROUPS,
    ROLE_CODE_ORDER,
    ROLE_CODE_GROUP,
    role_code_for_group,
)


ROLES_CONFLICT_CODE = 'ROLES_CONFLICT'
ROLES_CONFLICT_DETAIL = (
    'Send either `roles` (several role codes) or `group_name` (one group), not both: '
    'a body that names both cannot say which one it means.'
)


# ---------------------------------------------------------------------------
# Roles (Phase 4 task B3, decision 18)
# ---------------------------------------------------------------------------

def role_objects_for(user):
    """``roles[]``: one role object per recognised group, in stable order.

    Same object shape as ``role`` (the old single-role field), so a client parses one
    type. Only POS areas appear: the CPMS service group and any ad-hoc group a
    superuser made in Django admin are not areas the picker can switch to. Codes are
    deduplicated (Admin + System Administrator = one `admin`), keeping the lowest-id
    group's id, so the same area never shows twice.
    """
    objects = []
    if user.is_superuser:
        objects.append({
            'id': 0, 'name': 'admin', 'display_name': 'Administrator',
            'permissions': [],
        })
    seen = {entry['name'] for entry in objects}
    found = {}
    for group in sorted(user.groups.all(), key=lambda row: (row.id, row.name)):
        code = role_code_for_group(group.name)
        # `code in ROLE_CODE_ORDER` skips the CPMS service group and any ad-hoc group:
        # they are recognised codes but not areas the picker can switch to.
        if code is None or code not in ROLE_CODE_ORDER or code in seen:
            continue
        seen.add(code)
        found[code] = {
            'id': group.id,
            'name': code,
            'display_name': group.name,
            'permissions': [],
        }
    objects.extend(found[code] for code in ROLE_CODE_ORDER if code in found)
    return objects


def parse_role_codes(value):
    """Validate a ``roles[]`` write payload and return its codes in stable order.

    Refuses every shape the client cannot have meant: not a list, empty, a code nobody
    has defined, the same code twice, and the CPMS service account beside a staff role
    (it holds one namespace only - decision 02 - so combining it would hand a machine
    account till/stock/manager/admin authority).
    """
    if isinstance(value, (str, bytes)) or not isinstance(value, (list, tuple)):
        raise serializers.ValidationError('roles must be a list of role codes.')
    if not value:
        raise serializers.ValidationError(
            'roles cannot be empty: pass at least one of '
            f'{", ".join(ROLE_CODE_ORDER)}.')
    codes = []
    for entry in value:
        code = entry.strip().lower() if isinstance(entry, str) else None
        if not code or code not in ROLE_CODE_GROUPS:
            raise serializers.ValidationError(
                f'"{entry}" is not a known role. Use one of: '
                f'{", ".join(sorted(ROLE_CODE_GROUPS))}.')
        if code in codes:
            raise serializers.ValidationError(f'"{code}" is listed twice.')
        codes.append(code)
    if ROLE_CODE_CPMS in codes and len(codes) > 1:
        raise serializers.ValidationError(
            'CPMS Service cannot be combined with staff roles: the service account may '
            'only call the CPMS integration endpoints.')
    order = ROLE_CODE_ORDER + [ROLE_CODE_CPMS]
    return sorted(codes, key=order.index)


def groups_for_role_codes(codes):
    """The Group rows a list of codes grants, in the same order."""
    groups = []
    for code in codes:
        name = ROLE_CODE_GROUP[code]
        try:
            groups.append(Group.objects.get(name=name))
        except Group.DoesNotExist as exc:
            raise serializers.ValidationError(
                f'The "{name}" group does not exist on this server.') from exc
    return groups


def group_names_for_codes(codes):
    """Every group name a code covers (a code names an area, not one row)."""
    return {name for code in codes for name in ROLE_CODE_GROUPS[code]}


def requested_group_names(data):
    """Group names a user-write body asks for, read defensively (before validation).

    Authorization must not depend on the rest of the body being valid, so the caller's
    attempt to name admin authority is refused (403) even when the same body is also
    malformed. Both fields are read: an unknown or malformed entry contributes nothing
    here and is refused by ``parse_role_codes``/the legacy path afterwards.
    """
    if not hasattr(data, 'get'):
        return []
    names = []
    group_name = data.get('group_name')
    if isinstance(group_name, str) and group_name:
        names.append(group_name)
    roles = data.get('roles')
    if isinstance(roles, (list, tuple)):
        for entry in roles:
            if isinstance(entry, str):
                names.extend(ROLE_CODE_GROUPS.get(entry.strip().lower(), ()))
    return names


def roles_conflict_response():
    """The 400 for a body that sends both ``roles`` and ``group_name``.

    A view-level Response, not a serializer ValidationError, so the body is the project's
    flat ``{code, detail}`` shape: DRF wraps a validation dict into lists, which would
    make ``data['code']`` a list and force the client to unwrap it.
    """
    from rest_framework import status
    from rest_framework.response import Response

    return Response(
        {'code': ROLES_CONFLICT_CODE, 'detail': ROLES_CONFLICT_DETAIL},
        status=status.HTTP_400_BAD_REQUEST,
    )


def roles_conflict_refusal():
    """Serializer-side copy of the same refusal (a safety net under the view check)."""
    return serializers.ValidationError({'detail': ROLES_CONFLICT_DETAIL})


def body_mixes_role_fields(data):
    """True when the body names both role fields (or `roles` and a role change action)."""
    return hasattr(data, 'get') and 'roles' in data and 'group_name' in data


class UserSerializer(serializers.ModelSerializer):
    """Read / list representation, and the ``PATCH`` write shape for roles.

    ``role`` stays exactly as it was (the lowest-id group, or a synthetic admin for a
    superuser) because released clients parse it; ``roles[]`` is the multi-role view.
    ``roles`` is read through a method field and written by ``validate()``: a User has
    no ``roles`` attribute (groups are the storage), so the field is not a model field.
    """
    role_names = serializers.SerializerMethodField()
    role = serializers.SerializerMethodField()
    roles = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'full_name', 'is_active', 'is_staff',
            'role', 'roles', 'role_names', 'last_login', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'is_staff', 'last_login', 'created_at', 'updated_at',
        ]

    def validate(self, attrs):
        """Resolve a ``roles`` write into Group rows; refuse a mixed body.

        Sending ``roles`` is a full replacement of the account's memberships (the same
        meaning ``assign_role`` has), decided under the view's row lock, and never an
        addition - a half-applied role list would be an untraceable permission change.
        """
        data = self.initial_data if hasattr(self.initial_data, 'get') else {}
        if 'roles' in data:
            if 'group_name' in data:
                raise roles_conflict_refusal()
            try:
                codes = parse_role_codes(data.get('roles'))
            except serializers.ValidationError as exc:
                # Field-scoped so the client reads the refusal where it made the mistake.
                raise serializers.ValidationError({'roles': exc.detail}) from exc
            attrs['roles'] = groups_for_role_codes(codes)
        return attrs

    @staticmethod
    def get_roles(obj):
        return role_objects_for(obj)

    @staticmethod
    def get_role_names(obj):
        return obj.role_names

    @staticmethod
    def get_role(obj):
        group = obj.groups.order_by('id').first()
        if obj.is_superuser:
            return {'id': 0, 'name': 'admin', 'display_name': 'Administrator', 'permissions': []}
        if group is None:
            return None
        return {
            'id': group.id,
            'name': role_code_for_group(group.name) or group.name.lower().replace(' ', '_'),
            'display_name': group.name,
            'permissions': [],
        }

    def update(self, instance, validated_data):
        groups = validated_data.pop('roles', None)
        instance = super().update(instance, validated_data)
        if groups is not None:
            instance.groups.set(groups)
        return instance

    def create(self, validated_data):
        groups = validated_data.pop('roles', None)
        instance = super().create(validated_data)
        if groups is not None:
            instance.groups.set(groups)
        return instance


class RegisterSerializer(serializers.ModelSerializer):
    """Create a new user account with one or several roles.

    Two payloads are accepted and exactly one must be present: ``roles`` (the multi-role
    codes, Phase 4 B3) or the legacy ``group_name`` (one Group name, still what released
    clients send). A body that sends both is refused rather than guessed at - see
    ``ROLES_CONFLICT_DETAIL``.
    """

    password = serializers.CharField(write_only=True, min_length=8)
    # A role is mandatory: the frontend (`User.fromJson`) expects a non-null
    # `role` object, so accounts must always be created with at least one.
    group_name = serializers.CharField(write_only=True, required=False)
    roles = serializers.ListField(child=serializers.CharField(), write_only=True,
                                  required=False)

    class Meta:
        model = User
        fields = ['username', 'email', 'full_name', 'password', 'group_name', 'roles']

    def validate(self, attrs):
        roles = attrs.get('roles')
        group_name = attrs.get('group_name')
        if roles is not None and group_name:
            raise roles_conflict_refusal()
        if roles is None and not group_name:
            raise serializers.ValidationError({
                'group_name': ['A role is required: pass `roles` (for example '
                               '["pos"]) or the legacy `group_name` (Admin, Stock '
                               'Manager, Cashier, Store Manager).'],
            })
        if roles is not None:
            try:
                codes = parse_role_codes(roles)
            except serializers.ValidationError as exc:
                # Field-scoped so the client reads the refusal where it made the mistake.
                raise serializers.ValidationError({'roles': exc.detail}) from exc
            # `group_names` is what create() assigns: canonical group per code.
            attrs['group_names'] = [ROLE_CODE_GROUP[code] for code in codes]
        else:
            if not Group.objects.filter(name=group_name).exists():
                raise serializers.ValidationError({
                    'group_name': [f'Group "{group_name}" does not exist.'],
                })
            attrs['group_names'] = [group_name]
        attrs.pop('roles', None)
        attrs.pop('group_name', None)
        return attrs

    def create(self, validated_data):
        group_names = validated_data.pop('group_names', [])
        password = validated_data.pop('password')
        user = User.objects.create_user(password=password, **validated_data)
        if group_names:
            user.groups.set(Group.objects.filter(name__in=group_names))
        return user


def find_user_by_identifier(identifier):
    """The account a login body names — username or email, case-insensitive.

    Shared by the serializer and the login view on purpose: the view needs the same
    answer to decide who a ``LOGIN_FAILED`` audit row belongs to, and two lookups that
    can drift apart would let the audit trail name a different account than the one
    whose password was refused.
    """
    if not identifier:
        return None
    return User.objects.filter(
        Q(username__iexact=identifier) | Q(email__iexact=identifier),
    ).first()


class LoginSerializer(serializers.Serializer):
    """Accepts username or email plus password."""

    identifier = serializers.CharField(required=False)
    username = serializers.CharField(required=False)
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        identifier = attrs.get('identifier') or attrs.get('username')
        password = attrs.get('password')
        if not identifier:
            raise serializers.ValidationError('Username or email is required.')
        user = find_user_by_identifier(identifier)
        if user is None or not user.check_password(password):
            raise serializers.ValidationError('Invalid username or password.')
        if not user.is_active:
            raise serializers.ValidationError('This account is disabled.')

        attrs['user'] = user
        return attrs


# ---------------------------------------------------------------------------
# AuditLog
# ---------------------------------------------------------------------------

class AuditLogSerializer(serializers.ModelSerializer):
    """Read-only view of one audit row.

    ``user_email`` goes through a method field so a row whose actor is NULL (a failed
    login by an unknown identifier) still serializes: a ``source='user.email'`` chain
    cannot walk a null FK. ``username_snapshot`` is the row's own copy of the actor's
    name and is never writable here — the viewset is read-only and the model refuses
    updates anyway.
    """

    user_email = serializers.SerializerMethodField()

    class Meta:
        model = AuditLog
        fields = [
            'id', 'user', 'user_email', 'username_snapshot', 'action_type',
            'description', 'ip_address', 'timestamp',
        ]
        read_only_fields = fields

    @staticmethod
    def get_user_email(obj):
        return obj.user.email if obj.user_id else None
