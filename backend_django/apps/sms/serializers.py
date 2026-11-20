# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""SMS wire shapes (ENDPOINTS.md §3.9)."""

from collections.abc import Mapping

from rest_framework import serializers

from . import services
from .models import BodegaSmsTicket, SmsContact, SmsGatewayHeartbeat, SmsMessage
from .phone import InvalidPhoneNumber, normalize_phone


class SmsContactSerializer(serializers.ModelSerializer):
    user_name = serializers.SerializerMethodField()
    # The number the person typed. Always rewritten to `+639XXXXXXXXX` before it is
    # stored, so a contact registered one way still matches a modem that reports the
    # caller ID another way.
    phone = serializers.CharField(max_length=20)

    class Meta:
        model = SmsContact
        fields = [  # noqa: RUF012
            "id",
            "phone",
            "user",
            "user_name",
            "label",
            "active",
            "created_at",
        ]
        read_only_fields = ("created_at",)

    def get_user_name(self, obj):
        if obj.user is None:
            return ""
        return obj.user.full_name or obj.user.username

    def validate_phone(self, value):
        try:
            return normalize_phone(value)
        except InvalidPhoneNumber as error:
            raise serializers.ValidationError(str(error)) from error

    def validate(self, attrs):
        phone = attrs.get("phone") or (self.instance.phone if self.instance else "")
        if not phone:
            attrs["phone"] = phone = self.instance.phone if self.instance else ""
        user = attrs.get("user", getattr(self.instance, "user", None))
        if user is not None and not services.holds_bodega_role(user):
            raise serializers.ValidationError(
                {
                    "user": (
                        "This account may not work the Bodega screens. Give it the "
                        "Bodega Checker role first."
                    )
                }
            )
        clash = SmsContact.objects.filter(phone=phone)
        if self.instance is not None:
            clash = clash.exclude(pk=self.instance.pk)
        if clash.exists():
            raise serializers.ValidationError(
                {"phone": f"{phone} is already registered."}
            )
        attrs["phone"] = phone
        return attrs


class SmsMessageSerializer(serializers.ModelSerializer):
    transaction_no = serializers.CharField(
        source="sale.transaction_no", read_only=True, default=""
    )
    release_number = serializers.CharField(
        source="release.number", read_only=True, default=""
    )

    class Meta:
        model = SmsMessage
        fields = [  # noqa: RUF012
            "id",
            "direction",
            "phone",
            "body",
            "status",
            "attempts",
            "last_error",
            "sent_at",
            "created_at",
            "transaction_no",
            "release_number",
            "result",
        ]
        read_only_fields = fields


class BodegaSmsTicketSerializer(serializers.ModelSerializer):
    transaction_no = serializers.CharField(source="sale.transaction_no", read_only=True)

    class Meta:
        model = BodegaSmsTicket
        fields = [  # noqa: RUF012
            "id",
            "sale",
            "transaction_no",
            "code",
            "created_at",
            "used_at",
            "failed_attempts",
        ]


class HeartbeatSerializer(serializers.ModelSerializer):
    class Meta:
        model = SmsGatewayHeartbeat
        fields = ["last_seen", "info"]  # noqa: RUF012


class GatewayInboundInput(serializers.Serializer):
    """What the bridge posts for each SMS the modem holds.

    The JSON key is `from` (the modem's own word); `from` is a Python keyword, so the
    FIELD is `from_` with `source="from"` and `to_internal_value` accepts the wire name.
    """

    from_ = serializers.CharField(source="from", max_length=64)
    body = serializers.CharField(allow_blank=True)
    # GSM 07.05 `+CMGL` service-centre timestamps arrive as `YY/MM/DD,HH:MM:SS±ZZ`
    # (quarter-hour offset, e.g. `26/11/20,14:30:12+32`), not ISO-8601.
    received_at = serializers.CharField(
        required=False, allow_blank=True, allow_null=True, max_length=64
    )
    key = serializers.CharField(required=False, allow_blank=True, max_length=64)

    def to_internal_value(self, data):
        if isinstance(data, Mapping) and "from" in data:
            data = {**data, "from_": data["from"]}
        return super().to_internal_value(data)


class GatewayResultInput(serializers.Serializer):
    ok = serializers.BooleanField()
    error = serializers.CharField(required=False, allow_blank=True, default="")
