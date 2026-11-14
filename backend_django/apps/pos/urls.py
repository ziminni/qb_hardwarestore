# pyright: reportMissingImports=false
from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    ChequeViewSet,
    CustomerViewSet,
    DeliveryViewSet,
    DiscountApprovalView,
    HeldCartViewSet,
    OfficialReceiptViewSet,
    PaymentViewSet,
    QuotationViewSet,
    SalesOrderViewSet,
    SalesTransactionViewSet,
    ShiftViewSet,
    StoreSettingsView,
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
# Phase 4 task B2 (decision 18): the cheque queue. A cheque is a `Payment` with
# `method=CHEQUE`, exposed on its own path because the clearance screen is not a payments
# screen - it shows what the shop is still waiting for on, and only two POSTs can move it.
router.register(r'cheques', ChequeViewSet, basename='cheque')
# Phase 5 task B3 (decision 18): the delivery schedule. Created BY a sale or an order,
# so the collection has no POST of its own - only the three status actions.
router.register(r'deliveries', DeliveryViewSet, basename='delivery')

# Phase 4 task B1 (decision 18): TWO singletons, not collections - the shop's settings
# row and the mint that turns a manager's password into a one-time discount approval.
# Registered as plain views on purpose: there is no list, no detail and no delete to
# route, and an APIView is the whole contract (`StoreSettingsView` accepts GET and PATCH
# only; `DiscountApprovalView` accepts POST only).
urlpatterns = [
    path('store-settings/', StoreSettingsView.as_view(), name='store-settings'),
    path('discount-approvals/', DiscountApprovalView.as_view(),
         name='discount-approvals'),
    path('', include(router.urls)),
]
