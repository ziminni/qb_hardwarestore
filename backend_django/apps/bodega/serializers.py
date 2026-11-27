# pyright: reportAttributeAccessIssue=false
"""Bodega wire shapes (decision 25; ENDPOINTS.md §3.8). Quantities are base units."""

from rest_framework import serializers

from common.serializer_fields import QtyDecimalField

from apps.inventory.models import ProductVariant, StorageLocation
from apps.users.photos import photo_url

from .models import (
    BodegaDelivery,
    BodegaDeliveryLine,
    BodegaRelease,
    BodegaReleaseLine,
)


def _variant_label(variant):
    return f"{variant.product.base_name} — {variant.variant_name}"


class BodegaReleaseLineSerializer(serializers.ModelSerializer):
    label = serializers.SerializerMethodField()
    unit = serializers.CharField(source="variant.base_uom.code", read_only=True)
    location_name = serializers.CharField(source="location.name", read_only=True)

    class Meta:
        model = BodegaReleaseLine
        fields = ["variant", "label", "unit", "location", "location_name", "qty"]  # noqa: RUF012

    def get_label(self, obj):
        return _variant_label(obj.variant)


class BodegaReleaseSerializer(serializers.ModelSerializer):
    transaction_no = serializers.CharField(source="sale.transaction_no", read_only=True)
    customer_name = serializers.SerializerMethodField()
    checker_name = serializers.SerializerMethodField()
    lines = BodegaReleaseLineSerializer(many=True, read_only=True)

    class Meta:
        model = BodegaRelease
        fields = [  # noqa: RUF012
            "id",
            "number",
            "sale",
            "transaction_no",
            "customer_name",
            "checker_name",
            "received_by",
            "plate_no",
            "notes",
            "created_at",
            "lines",
        ]

    def get_customer_name(self, obj):
        return obj.sale.customer.name if obj.sale.customer_id else ""

    def get_checker_name(self, obj):
        return obj.checker.full_name or obj.checker.get_username()


class ReleaseLineInput(serializers.Serializer):
    variant = serializers.PrimaryKeyRelatedField(
        queryset=ProductVariant.objects.select_related("product", "base_uom")
    )
    location = serializers.PrimaryKeyRelatedField(queryset=StorageLocation.objects.all())
    qty = QtyDecimalField(max_digits=18, decimal_places=6)


class ReleaseInput(serializers.Serializer):
    receipt = serializers.CharField(max_length=60)
    received_by = serializers.CharField(max_length=150, allow_blank=True)
    plate_no = serializers.CharField(max_length=30, allow_blank=True, required=False)
    notes = serializers.CharField(max_length=255, allow_blank=True, required=False)
    lines = ReleaseLineInput(many=True)


class BodegaDeliveryLineSerializer(serializers.ModelSerializer):
    label = serializers.SerializerMethodField()
    unit = serializers.CharField(source="variant.base_uom.code", read_only=True)
    is_whole = serializers.BooleanField(source="variant.base_uom.is_whole", read_only=True)
    missing_qty = QtyDecimalField(
        max_digits=18, decimal_places=6, read_only=True, allow_null=True
    )
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = BodegaDeliveryLine
        fields = [  # noqa: RUF012
            "id",
            "variant",
            "label",
            "unit",
            "is_whole",
            "delivered_qty",
            "good_qty",
            "damaged_qty",
            "missing_qty",
            "remarks",
            "photo_url",
        ]

    def get_label(self, obj):
        return _variant_label(obj.variant)

    def get_photo_url(self, obj):
        return photo_url(self.context.get("request"), obj.photo)


class BodegaDeliverySerializer(serializers.ModelSerializer):
    location_name = serializers.CharField(source="location.name", read_only=True)
    supplier_name = serializers.CharField(
        source="receipt.po.supplier.company_name", read_only=True
    )
    received_by_name = serializers.SerializerMethodField()
    checked_by_name = serializers.SerializerMethodField()
    lines = BodegaDeliveryLineSerializer(many=True, read_only=True)

    class Meta:
        model = BodegaDelivery
        fields = [  # noqa: RUF012
            "id",
            "number",
            "receipt",
            "location",
            "location_name",
            "supplier_name",
            "received_by_name",
            "status",
            "checked_by_name",
            "checked_at",
            "notes",
            "created_at",
            "lines",
        ]

    def get_received_by_name(self, obj):
        user = obj.receipt.received_by
        return (user.full_name or user.get_username()) if user else ""

    def get_checked_by_name(self, obj):
        if obj.checked_by is None:
            return ""
        return obj.checked_by.full_name or obj.checked_by.get_username()


class DeliveryLineInput(serializers.Serializer):
    line = serializers.IntegerField()
    good_qty = QtyDecimalField(max_digits=18, decimal_places=6)
    damaged_qty = QtyDecimalField(max_digits=18, decimal_places=6)
    remarks = serializers.CharField(max_length=255, allow_blank=True, required=False)


class DeliveryConfirmInput(serializers.Serializer):
    notes = serializers.CharField(max_length=255, allow_blank=True, required=False)
    lines = DeliveryLineInput(many=True)
