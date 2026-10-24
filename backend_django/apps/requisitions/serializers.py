"""Requisitions app — serializers."""

from django.core.exceptions import ObjectDoesNotExist
from rest_framework import serializers

from apps.users.permissions import ROLE_SITE_FOREMAN, IsManagerRole, has_role

from .models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)


class ProjectSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source='customer.name', read_only=True)

    class Meta:
        model = Project
        fields = [
            'id', 'name', 'customer', 'customer_name',
            'location', 'start_date', 'end_date',
            'is_active', 'notes', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class RequisitionItemSerializer(serializers.ModelSerializer):
    variant_name = serializers.CharField(source='variant.variant_name', read_only=True)

    class Meta:
        model = RequisitionItem
        fields = [
            'id', 'requisition', 'variant', 'variant_name',
            'quantity', 'released_qty', 'notes',
        ]
        read_only_fields = ['id']


class RequisitionSerializer(serializers.ModelSerializer):
    items = RequisitionItemSerializer(many=True, read_only=True)
    requested_by_name = serializers.CharField(
        source='requested_by.full_name', read_only=True)
    project_name = serializers.CharField(source='project.name', read_only=True)
    # Decision 09: the approve queue must show WHERE a requisition came from, and the
    # list endpoint is that queue's only data source. A read-only representation field
    # adds no endpoint and touches no model, so the map's backend invariant holds.
    project_customer_name = serializers.CharField(
        source='project.customer.name', read_only=True)
    token = serializers.SerializerMethodField()

    class Meta:
        model = Requisition
        fields = [
            'id', 'project', 'project_name', 'project_customer_name', 'req_number',
            'requested_by', 'requested_by_name',
            'approved_by', 'status', 'notes',
            'items', 'token', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'req_number', 'approved_by',
            'created_at', 'updated_at',
        ]
        extra_kwargs = {
            'requested_by': {'read_only': True},
        }

    def get_token(self, obj):
        """The material token UUID — a BEARER credential, so it needs a named reader.

        Whoever holds this UUID can release the goods on credit, so `GET /requisitions/`
        must not hand it to anyone who can log in. Only a manager/admin (any row) or the
        requesting foreman sees it; everyone else gets `None`.

        The key stays PRESENT with `null` because the Flutter `Requisition` model reads a
        nullable `token` — dropping the key would break that decode.
        """
        if not self._may_see_token(obj):
            return None
        try:
            # `obj.token` is a reverse OneToOne: it raises when the requisition was never
            # approved. The view select_related's it, so this costs no extra query.
            material_token = obj.token
        except ObjectDoesNotExist:
            return None
        return str(material_token.token) if material_token else None

    def _may_see_token(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if not user or not getattr(user, 'is_authenticated', False):
            # No request context (a direct serializer use, a test): nothing to authorise
            # against, so the credential is not disclosed.
            return False
        if has_role(user, IsManagerRole.required_roles):
            return True
        return has_role(user, [ROLE_SITE_FOREMAN]) and obj.requested_by_id == user.pk


class TokenVerifySerializer(serializers.Serializer):
    token = serializers.UUIDField(
        help_text='UUID of the MaterialToken to verify.')


class MaterialTokenSerializer(serializers.ModelSerializer):
    req_number = serializers.CharField(
        source='requisition.req_number', read_only=True)

    class Meta:
        model = MaterialToken
        fields = [
            'id', 'requisition', 'req_number', 'token',
            'is_used', 'used_at', 'created_at',
        ]
        read_only_fields = fields