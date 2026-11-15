"""Collectibles app URL routing — DRF DefaultRouter."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    CollectibleLedgerViewSet,
    CollectiblePaymentViewSet,
    ProjectPaymentReceiptViewSet,
)

router = DefaultRouter()
router.register(r'ledgers', CollectibleLedgerViewSet, basename='collectible-ledger')
router.register(r'ledger-payments', CollectiblePaymentViewSet, basename='collectible-payment')
router.register(
    r'payment-receipts',
    ProjectPaymentReceiptViewSet,
    basename='project-payment-receipt',
)

urlpatterns = [
    path('', include(router.urls)),
]