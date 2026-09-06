"""Collectibles app URL routing — DRF DefaultRouter."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import CollectibleLedgerViewSet, CollectiblePaymentViewSet

router = DefaultRouter()
router.register(r'ledgers', CollectibleLedgerViewSet, basename='collectible-ledger')
router.register(r'ledger-payments', CollectiblePaymentViewSet, basename='collectible-payment')

urlpatterns = [
    path('', include(router.urls)),
]