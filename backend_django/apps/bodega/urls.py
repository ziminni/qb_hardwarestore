"""Bodega URLs (decision 25), mounted under `/api/v1/`."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BodegaClaimListView,
    BodegaClaimLookupView,
    BodegaDeliveryViewSet,
    BodegaReleaseViewSet,
    BodegaStockView,
)

router = DefaultRouter()
router.register(r"bodega/releases", BodegaReleaseViewSet, basename="bodega-release")
router.register(r"bodega/deliveries", BodegaDeliveryViewSet, basename="bodega-delivery")

urlpatterns = [
    path("bodega/stock/", BodegaStockView.as_view(), name="bodega-stock"),
    path("bodega/claims/", BodegaClaimListView.as_view(), name="bodega-claims"),
    path(
        "bodega/claims/lookup/",
        BodegaClaimLookupView.as_view(),
        name="bodega-claim-lookup",
    ),
    path("", include(router.urls)),
]
