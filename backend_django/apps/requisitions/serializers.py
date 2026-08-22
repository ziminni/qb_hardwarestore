"""Requisitions app — serializers."""

from rest_framework import serializers

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
    token = serializers.UUIDField(source='token.token', read_only=True)

    class Meta:
        model = Requisition
        fields = [
            'id', 'project', 'project_name', 'req_number',
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