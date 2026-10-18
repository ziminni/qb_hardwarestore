from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .views import (
    CustomerViewSet, SalesTransactionViewSet, PaymentViewSet, OfficialReceiptViewSet,
    QuotationViewSet,
)

router = DefaultRouter()
router.register(r'customers', CustomerViewSet, basename='customer')
router.register(r'transactions', SalesTransactionViewSet, basename='transaction')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'receipts', OfficialReceiptViewSet, basename='receipt')
router.register(r'quotations', QuotationViewSet, basename='quotation')

urlpatterns = [path('', include(router.urls))]