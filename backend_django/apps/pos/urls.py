from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .views import (
    CustomerViewSet, SalesTransactionViewSet, PaymentViewSet, OfficialReceiptViewSet,
    QuotationViewSet, SalesOrderViewSet, HeldCartViewSet, ShiftViewSet,
)

router = DefaultRouter()
router.register(r'customers', CustomerViewSet, basename='customer')
router.register(r'transactions', SalesTransactionViewSet, basename='transaction')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'receipts', OfficialReceiptViewSet, basename='receipt')
router.register(r'quotations', QuotationViewSet, basename='quotation')
router.register(r'sales-orders', SalesOrderViewSet, basename='sales-order')
router.register(r'held-carts', HeldCartViewSet, basename='held-cart')
router.register(r'shifts', ShiftViewSet, basename='shift')

urlpatterns = [path('', include(router.urls))]