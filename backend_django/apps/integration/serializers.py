"""CPMS boundary serializers — the wire shapes of the contract, and nothing more."""

from decimal import Decimal

from rest_framework import serializers

from apps.inventory.models import VariantUOM
from apps.pos.models import Customer


class CpmsCustomerSerializer(serializers.ModelSerializer):
    """`{id, name}` (decision 02, P1) — the payer a push may name, nothing else.

    `fields` is the whole allowlist, so no balance, credit limit, TIN or contact
    detail can reach CPMS, and a field added to `Customer` tomorrow does not leak in
    by default.
    """

    class Meta:
        model = Customer
        fields = ('id', 'name')
        read_only_fields = fields


class CpmsMaterialSerializer(serializers.ModelSerializer):
    """`{code, product, unit}` (decision 04) — what CPMS may order, nothing more.

    `code` is the selling unit's own barcode (`VariantUOM.barcode_qr`), the same string a
    scan produces, and `product` is the human label CPMS shows its picker. There is
    deliberately no stock, price, cost or id: CPMS orders materials, it does not trade.

    `fields` is the whole allowlist, so no price or stock figure can sneak in later.
    """

    code = serializers.CharField(source='barcode_qr', read_only=True)
    product = serializers.SerializerMethodField()
    unit = serializers.CharField(source='uom.code', read_only=True)

    class Meta:
        model = VariantUOM
        fields = ('code', 'product', 'unit')
        read_only_fields = fields

    def get_product(self, obj):
        return f'{obj.variant.product.base_name} {obj.variant.variant_name}'


class CpmsProjectPayloadSerializer(serializers.Serializer):
    """The project block of a push (decisions 02 and 03).

    `cpms_project_id` is CPMS's own key, so a later push finds the same POS row; `payer`
    is a POS customer id read from `GET customers/` (P1), refused by the service when it
    names no active contractor or construction firm.
    """

    cpms_project_id = serializers.CharField(max_length=100)
    name = serializers.CharField(max_length=255)
    payer = serializers.IntegerField()


class CpmsRequestItemSerializer(serializers.Serializer):
    """One requested line: a material-list code and a quantity in that selling unit.

    The quantity is `>= 0.01` and at most two decimals — the same precision
    `RequisitionItem.quantity` stores (decision 04), so what CPMS approved is what the
    copy holds. The code is normalised and matched by the service, not here: matching
    needs the catalogue and answers 400 UNKNOWN_MATERIAL.
    """

    code = serializers.CharField(max_length=100)
    quantity = serializers.DecimalField(
        max_digits=12, decimal_places=2, min_value=Decimal('0.01'))


class CpmsRequestImportSerializer(serializers.Serializer):
    """`POST requests/` — one approved CPMS request (decisions 02 and 04).

    Only SHAPE is checked here: whether the payer exists, whether the codes are sellable,
    whether the token is free and whether this `cpms_request_id` is a retry are the
    service's rules, because each of them has its own status code or its own silence.
    """

    cpms_request_id = serializers.CharField(max_length=100)
    token = serializers.UUIDField()
    project = CpmsProjectPayloadSerializer()
    requester_name = serializers.CharField(max_length=255)
    approver_name = serializers.CharField(max_length=255)
    notes = serializers.CharField(required=False, allow_blank=True, default='')
    items = CpmsRequestItemSerializer(many=True, allow_empty=False)
