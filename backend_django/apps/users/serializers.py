"""Users app — serializers for registration, login, profile."""

from django.contrib.auth.models import Group
from django.db.models import Q
from rest_framework import serializers

from .models import AuditLog, User


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class UserSerializer(serializers.ModelSerializer):
    """Read / list representation."""
    role_names = serializers.SerializerMethodField()
    role = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'full_name', 'is_active', 'is_staff',
            'role', 'role_names', 'last_login', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'is_staff', 'last_login', 'created_at', 'updated_at',
        ]

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
        names = {
            'Admin': 'admin', 'System Administrator': 'admin',
            'Stock Manager': 'inventory', 'Cashier': 'pos',
            'Store Manager': 'sales', 'Sales': 'sales',
        }
        return {
            'id': group.id,
            'name': names.get(group.name, group.name.lower().replace(' ', '_')),
            'display_name': group.name,
            'permissions': [],
        }


class RegisterSerializer(serializers.ModelSerializer):
    """Create a new user account.  Optionally assign a Group."""

    password = serializers.CharField(write_only=True, min_length=8)
    # A role is mandatory: the frontend (`User.fromJson`) expects a non-null
    # `role` object, so accounts must always be created with a Group.
    group_name = serializers.CharField(
        write_only=True,
        required=True,
        error_messages={'required': 'A role is required: pass `group_name` '
                                    '(Admin, Stock Manager, Cashier, Store Manager).'},
    )

    class Meta:
        model = User
        fields = ['username', 'email', 'full_name', 'password', 'group_name']

    def validate_group_name(self, value):
        if value and not Group.objects.filter(name=value).exists():
            raise serializers.ValidationError(f'Group "{value}" does not exist.')
        return value

    def create(self, validated_data):
        group_name = validated_data.pop('group_name', None)
        password = validated_data.pop('password')
        user = User.objects.create_user(password=password, **validated_data)
        if group_name:
            user.groups.add(Group.objects.get(name=group_name))
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
