# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportCallIssue=false, reportGeneralTypeIssues=false, reportIncompatibleVariableOverride=false, reportOptionalSubscript=false, reportIndexIssue=false, reportInvalidTypeArguments=false, reportOptionalMemberAccess=false
#
# Same directive set and reason as `apps/bodega/views.py` and `apps/pos/views.py`:
# pyright resolves neither this repo's config nor django-stubs in every checker run,
# so each `Model.objects` access and `request.data` item is a false positive on valid
# Django. `manage.py check` and the test run remain the authority.
"""SMS endpoints (ENDPOINTS.md §3.9).

Two audiences, two guards, in one file because they are one feature:

* **The bridge** (`/sms/gateway/...`) is a machine on the shop's own computer. It has no
  login and must not need one: it authenticates with `X-SMS-Gateway-Key`, compared in
  constant time against `settings.SMS_GATEWAY_KEY`. An empty or short key refuses every
  call - a machine that can send paid SMS must not accept a guessable one.
* **Staff** (`/sms/status/`, `/sms/messages/`, `/sms/contacts/`) is ordinary JWT traffic:
  Store Manager / Admin read and retry, Admin alone registers a number.
"""

import hmac

from django.conf import settings
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import BasePermission
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.users.models import AuditLog
from apps.users.permissions import IsAdminRole, IsManagerRole
from apps.users.services import log_audit

from . import services
from .exceptions import SmsGatewayRefused, SmsGatewayUnauthorized
from .models import SmsContact, SmsGatewayHeartbeat, SmsMessage
from .serializers import (
    GatewayInboundInput,
    GatewayResultInput,
    SmsContactSerializer,
    SmsMessageSerializer,
)

#: Shortest gateway key accepted. Same floor as the tunnel's `QB_GATEWAY_KEY`.
MIN_KEY_LENGTH = 24


class SmsGatewayKey(BasePermission):
    """`X-SMS-Gateway-Key` against `settings.SMS_GATEWAY_KEY`, in constant time."""

    def has_permission(self, request, view):
        expected = getattr(settings, "SMS_GATEWAY_KEY", "") or ""
        if len(expected) < MIN_KEY_LENGTH:
            raise SmsGatewayRefused()
        sent = request.headers.get("X-SMS-Gateway-Key", "")
        if not sent:
            raise SmsGatewayUnauthorized()
        if not hmac.compare_digest(sent, expected):
            raise SmsGatewayRefused("The SMS gateway key is wrong.")
        return True


class GatewayAPIView(APIView):
    """Base for the bridge's endpoints: no JWT, no session, the key header alone."""

    authentication_classes = ()
    permission_classes = (SmsGatewayKey,)


class GatewayOutboxView(GatewayAPIView):
    """`GET /sms/gateway/outbox/?limit=5` - claim messages and mark them SENDING.

    Row-locked `SKIP LOCKED` selection keeps a live lease exclusive. Lost send
    acknowledgements can still cause duplicate texts after the lease expires.
    """

    def get(self, request):
        try:
            limit = int(request.query_params.get("limit", 5))
        except (TypeError, ValueError):
            limit = 5
        return Response(services.claim_outbox(limit))


class GatewayResultView(GatewayAPIView):
    """`POST /sms/gateway/outbox/<id>/result/` - what the modem said."""

    def post(self, request, pk):
        data = GatewayResultInput(data=request.data)
        data.is_valid(raise_exception=True)
        message = services.report_send_result(
            pk,
            ok=data.validated_data["ok"],
            error=data.validated_data.get("error", ""),
        )
        return Response(
            {"id": message.pk, "status": message.status, "attempts": message.attempts}
        )


class GatewayInboundView(GatewayAPIView):
    """`POST /sms/gateway/inbound/` - one SMS the modem received.

    `key` is the bridge's own idempotency token (hash of sender, timestamp and body): a
    redelivery returns the FIRST answer instead of releasing twice.
    """

    def post(self, request):
        data = GatewayInboundInput(data=request.data)
        data.is_valid(raise_exception=True)
        body = data.validated_data
        result = services.process_inbound(
            phone=body["from"],
            body=body["body"],
            inbound_key=body.get("key") or None,
            received_at=body.get("received_at"),
        )
        return Response(result)


class GatewayHeartbeatView(GatewayAPIView):
    """`POST /sms/gateway/heartbeat/` - the bridge is alive: `{info}`."""

    def post(self, request):
        info = request.data.get("info", request.data) if request.data else {}
        row = services.heartbeat(info)
        return Response({"last_seen": row.last_seen, "info": row.info})


# ---------------------------------------------------------------------------
# Staff
# ---------------------------------------------------------------------------


class SmsStatusView(APIView):
    """`GET /sms/status/` - is the link alive, and what is stuck in it."""

    permission_classes = (IsManagerRole,)

    def get(self, request):
        beat = SmsGatewayHeartbeat.objects.filter(pk=1).first()
        return Response(
            {
                "enabled": bool(getattr(settings, "SMS_ENABLED", False)),
                "gateway_configured": len(
                    getattr(settings, "SMS_GATEWAY_KEY", "") or ""
                )
                >= MIN_KEY_LENGTH,
                "last_heartbeat": beat.last_seen if beat else None,
                "heartbeat_info": beat.info if beat else {},
                "queued": SmsMessage.objects.filter(
                    direction=SmsMessage.Direction.OUT,
                    status__in=[
                        SmsMessage.Status.QUEUED,
                        SmsMessage.Status.SENDING,
                    ],
                ).count(),
                "failed": SmsMessage.objects.filter(
                    direction=SmsMessage.Direction.OUT,
                    status=SmsMessage.Status.FAILED,
                ).count(),
                "contacts": SmsContact.objects.filter(active=True).count(),
            }
        )


class SmsMessageViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet
):
    """`/sms/messages/` - the two-way log, newest first, and `…/{id}/retry/`.

    Read-only apart from retry: a sent message is evidence of what the checker was told,
    so it is never edited or deleted. A write verb other than retry is a 405 by DRF's own
    reasoning (no create/update/delete mixin is included).
    """

    permission_classes = (IsManagerRole,)
    serializer_class = SmsMessageSerializer

    def get_queryset(self):
        rows = SmsMessage.objects.select_related("sale", "release")
        direction = self.request.query_params.get("direction", "").strip().upper()
        if direction:
            rows = rows.filter(direction=direction)
        message_status = self.request.query_params.get("status", "").strip().upper()
        if message_status:
            rows = rows.filter(status=message_status)
        phone = self.request.query_params.get("phone", "").strip()
        if phone:
            rows = rows.filter(phone__icontains=phone)
        return rows

    @action(detail=True, methods=["post"])
    def retry(self, request, pk=None):
        """`POST /sms/messages/<id>/retry/` - a FAILED outbound message goes back out."""
        message = services.retry_message(pk)
        log_audit(
            user=request.user,
            action_type=AuditLog.ActionType.UPDATE,
            ip_address=request.META.get("REMOTE_ADDR"),
            description=(
                f"SMS {message.pk} to {message.phone} requeued for another attempt."
            ),
        )
        return Response(
            SmsMessageSerializer(self.get_queryset().get(pk=message.pk)).data
        )


class SmsContactViewSet(viewsets.ModelViewSet):
    """`/sms/contacts/` - which numbers may release goods, and as whom (Admin only).

    A contact is the one place a phone number becomes authority, so only an Admin writes
    here; the number is normalized on the way in and the account must hold the Bodega
    Checker role.
    """

    permission_classes = (IsAdminRole,)
    serializer_class = SmsContactSerializer

    def get_queryset(self):
        return SmsContact.objects.select_related("user")
