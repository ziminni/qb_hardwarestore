"""Requisitions app — serializers."""

from django.core.exceptions import ObjectDoesNotExist
from rest_framework import serializers

from apps.users.permissions import IsManagerRole, has_role

from .models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)
from .services import (
    expected_amount as compute_expected_amount,
    money_wire,
)


class ProjectSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source='customer.name', read_only=True)

    class Meta:
        model = Project
        fields = [
            'id', 'name', 'cpms_project_id', 'customer', 'customer_name',
            'location', 'start_date', 'end_date',
            'is_active', 'notes', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at']


class RequisitionItemSerializer(serializers.ModelSerializer):
    """A requisition line, priced and counted in its SELLING unit (decision 04).

    `variant` and `variant_name` stay on the wire exactly as they were, read-only and
    derived from `variant_uom`: the Flutter `RequisitionItem` model still decodes those two
    keys, and dropping them would break the release screen. Writes take `variant_uom`.

    Phase 1b: the store's answer travels here too (`available` NULL = nobody answered
    yet, which is NOT `false`), together with the words the review screen shows so no
    second catalog fetch is needed — `product_name` and `unit` come from the referenced
    selling unit.
    """
    variant = serializers.IntegerField(
        source='variant_uom.variant_id', read_only=True)
    variant_name = serializers.CharField(
        source='variant_uom.variant.variant_name', read_only=True)
    product_name = serializers.CharField(
        source='variant_uom.variant.product.base_name', read_only=True)
    unit = serializers.CharField(source='variant_uom.uom.code', read_only=True)

    class Meta:
        model = RequisitionItem
        fields = [
            'id', 'requisition', 'variant_uom', 'variant', 'variant_name',
            'product_name', 'unit', 'quantity', 'released_qty', 'notes',
            'available', 'decline_reason',
        ]
        read_only_fields = ['id']


class RequisitionSerializer(serializers.ModelSerializer):
    items = RequisitionItemSerializer(many=True, read_only=True)
    # Same wire key the Flutter model reads; the value now comes from CPMS, not a FK.
    requested_by_name = serializers.CharField(
        source='requester_name', read_only=True)
    approver_name = serializers.CharField(read_only=True)
    project_name = serializers.CharField(source='project.name', read_only=True)
    # Decision 09: the approve queue must show WHERE a requisition came from, and the
    # list endpoint is that queue's only data source. A read-only representation field
    # adds no endpoint and touches no model, so the map's backend invariant holds.
    project_customer_name = serializers.CharField(
        source='project.customer.name', read_only=True)
    token = serializers.SerializerMethodField()
    # Decision 11/13: the queue shows the same live budget CPMS reads, computed by the
    # ONE service helper so the two wires can never disagree.
    expected_amount = serializers.SerializerMethodField()

    class Meta:
        model = Requisition
        fields = [
            'id', 'project', 'project_name', 'project_customer_name', 'req_number',
            'requested_by_name', 'approver_name', 'cpms_request_id', 'status', 'notes',
            # Phase 1b (decision 13): the store's whole-request refusal reason. Blank for
            # every request nobody declined, so the key is always present and the client
            # never has to tell missing from empty.
            'decline_reason', 'expected_amount',
            'items', 'token', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'req_number', 'cpms_request_id',
            # `status` is ACTION-only (review F2): it moves through
            # `submit` / `approve` / `reject` and nowhere else. It used to be writable,
            # so `PATCH {"status": "<approved>"}` walked a DRAFT to an approved (or
            # RELEASED) state around the action — no separation-of-duties check, no
            # `MaterialToken` minted, no `REQ_APPROVE` audit row, and a requisition that
            # could never be approved afterwards. A read-only field is IGNORED, so an
            # old client that still sends it is not broken by a 400. Phase 1b renamed
            # that state from `APPROVED` to `ACCEPTED` (decision 13).
            'status',
            'created_at', 'updated_at',
        ]

    def get_expected_amount(self, obj):
        """A 2dp string, or None when the figure would be a guess (decisions 13/14).

        Reuses the viewset's prefetched `items` (with their selling units), so a queue
        page costs no per-row queries.
        """
        return money_wire(compute_expected_amount(obj))

    def get_token(self, obj):
        """The material token UUID — a BEARER credential, so it needs a named reader.

        Whoever holds this UUID can release the goods on credit, so `GET /requisitions/`
        must not hand it to anyone who can log in. Only a manager/admin sees it; everyone
        else gets `None`.

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
        return has_role(user, IsManagerRole.required_roles)


class TokenVerifySerializer(serializers.Serializer):
    token = serializers.UUIDField(
        help_text='UUID of the MaterialToken to verify.')


class StrictSerializer(serializers.Serializer):
    """A serializer that refuses the keys it does not accept.

    DRF's default is to ignore an unknown key, which would quietly accept
    `{"items": [...], "status": "CLOSED"}` — the one payload a store decision must
    never honour. Phase 1b: a client trying to edit a quantity, a price or the status
    gets a 400 naming the field it should not have sent.
    """

    def to_internal_value(self, data):
        if isinstance(data, dict):
            unknown = sorted(set(data) - set(self.get_fields()))
            if unknown:
                raise serializers.ValidationError({
                    key: ['This field is not accepted here.'] for key in unknown})
        return super().to_internal_value(data)


class StrictBooleanField(serializers.BooleanField):
    """A JSON `true`/`false` only: `"true"`, `1` and `"0"` are payload bugs.

    A store answer is a decision, so it must arrive as the boolean the contract names —
    not as a string DRF's permissive default would happily coerce.
    """

    def to_internal_value(self, data):
        if not isinstance(data, bool):
            self.fail('invalid')
        return data


class RequisitionReviewLineSerializer(StrictSerializer):
    """One line's answer: Available, or Not available with a short reason (decision 10).

    The reason is required ONLY for a false line and must be blank for a true one, so a
    stored row can never read "available, because it is not stocked".
    """

    id = serializers.IntegerField(min_value=1)
    available = StrictBooleanField()
    # Not `required`: an Available line may omit it, and `null` reads as blank.
    decline_reason = serializers.CharField(
        max_length=255, required=False, allow_blank=True, allow_null=True,
        default='')

    def validate(self, attrs):
        reason = (attrs.get('decline_reason') or '').strip()
        if attrs['available'] and reason:
            raise serializers.ValidationError({
                'decline_reason': ['An available line carries no decline reason.']})
        if not attrs['available'] and not reason:
            raise serializers.ValidationError({
                'decline_reason': ['Say why this line is not available.']})
        attrs['decline_reason'] = reason
        return attrs


class RequisitionAcceptSerializer(StrictSerializer):
    """`POST /requisitions/{id}/accept/` (decisions 09 and 10).

    Exactly one answer per stored line. Duplicates are caught here; omissions, unknown
    and foreign ids need the stored rows, so the service refuses those under the lock
    (`_line_answers`). An all-Not-available answer is a 400 naming the other action: it
    is never silently turned into a whole Decline.
    """

    items = serializers.ListField(
        child=RequisitionReviewLineSerializer(), allow_empty=False)

    def validate_items(self, items):
        ids = [item['id'] for item in items]
        if len(ids) != len(set(ids)):
            raise serializers.ValidationError('A line may be answered only once.')
        if not any(item['available'] for item in items):
            raise serializers.ValidationError(
                'No line is available. Decline the request instead.')
        return items


class RequisitionDeclineSerializer(StrictSerializer):
    """`POST /requisitions/{id}/decline/` — one reason, required and trimmed."""

    decline_reason = serializers.CharField(max_length=255)

    def validate_decline_reason(self, value):
        reason = value.strip()
        if not reason:
            raise serializers.ValidationError(
                'Say why you cannot supply this request.')
        return reason


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
