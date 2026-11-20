"""SMS URLs (ENDPOINTS.md §3.9), mounted under `/api/v1/`."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    GatewayHeartbeatView,
    GatewayInboundView,
    GatewayOutboxView,
    GatewayResultView,
    SmsContactViewSet,
    SmsMessageViewSet,
    SmsStatusView,
)

router = DefaultRouter()
router.register(r"sms/messages", SmsMessageViewSet, basename="sms-message")
router.register(r"sms/contacts", SmsContactViewSet, basename="sms-contact")

urlpatterns = [
    # The bridge. Key header, no JWT.
    path("sms/gateway/outbox/", GatewayOutboxView.as_view(), name="sms-gateway-outbox"),
    path(
        "sms/gateway/outbox/<int:pk>/result/",
        GatewayResultView.as_view(),
        name="sms-gateway-result",
    ),
    path(
        "sms/gateway/inbound/", GatewayInboundView.as_view(), name="sms-gateway-inbound"
    ),
    path(
        "sms/gateway/heartbeat/",
        GatewayHeartbeatView.as_view(),
        name="sms-gateway-heartbeat",
    ),
    # Staff.
    path("sms/status/", SmsStatusView.as_view(), name="sms-status"),
    path("", include(router.urls)),
]
