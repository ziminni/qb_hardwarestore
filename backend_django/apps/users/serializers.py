"""Users app — serializers for registration, login, profile."""

from django.contrib.auth import authenticate
from django.contrib.auth.models import Group
from rest_framework import serializers

from .models import AuditLog, User


# ---------------------------------------------------------------------------
# User
# ---------------------------------------------------------------------------

class UserSerializer(serializers.ModelSerializer):
    """Read / list representation."""
    role_names = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'username', 'email', 'full_name', 'is_active', 'is_staff',
            'role_names', 'last_login', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'last_login', 'created_at', 'updated_at']

    @staticmethod
    def get_role_names(obj):
        return obj.role_names


class RegisterSerializer(serializers.ModelSerializer):
    """Create a new user account.  Optionally assign a Group."""

    password = serializers.CharField(write_only=True, min_length=8)
    group_name = serializers.CharField(write_only=True, required=False)

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


class LoginSerializer(serializers.Serializer):
    """Accepts username + password, validates, returns the User object."""

    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        username = attrs.get('username')
        password = attrs.get('password')

        user = authenticate(
            request=self.context.get('request'),
            username=username,
            password=password,
        )
        if not user:
            raise serializers.ValidationError('Invalid username or password.')
        if not user.is_active:
            raise serializers.ValidationError('This account is disabled.')

        attrs['user'] = user
        return attrs


# ---------------------------------------------------------------------------
# AuditLog
# ---------------------------------------------------------------------------

class AuditLogSerializer(serializers.ModelSerializer):
    user_email = serializers.EmailField(source='user.email', read_only=True)

    class Meta:
        model = AuditLog
        fields = [
            'id', 'user', 'user_email', 'action_type',
            'description', 'ip_address', 'timestamp',
        ]
        read_only_fields = fields