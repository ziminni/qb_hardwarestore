"""Inventory app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    BrandViewSet,
    CategoryViewSet,
    ProductVariantViewSet,
    ProductViewSet,
    UnitOfMeasureViewSet,
    VariantUOMViewSet,
    SupplierViewSet,
    PurchaseOrderViewSet,
    GoodsReceiptViewSet,
    InventoryBatchViewSet,
    StockAdjustmentViewSet,
    StorageLocationViewSet,
    SupplierBillViewSet,
    SupplierPaymentViewSet,
    SystemAlertViewSet,
)

router = DefaultRouter()
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'brands', BrandViewSet, basename='brand')
router.register(r'uoms', UnitOfMeasureViewSet, basename='uom')
# Phase 5 B4 (decision 18): "stored at" - Admin writes, every logged-in role reads the
# active ones (the till prints the label). No DELETE: products PROTECT-reference it.
router.register(r'storage-locations', StorageLocationViewSet, basename='storagelocation')
router.register(r'products', ProductViewSet, basename='product')
router.register(r'variants', ProductVariantViewSet, basename='variant')
router.register(r'variant-uoms', VariantUOMViewSet, basename='variantuom')
router.register(r'suppliers', SupplierViewSet, basename='supplier')
router.register(r'purchase-orders', PurchaseOrderViewSet, basename='purchaseorder')
router.register(r'goods-receipts', GoodsReceiptViewSet, basename='goodsreceipt')
router.register(r'batches', InventoryBatchViewSet, basename='batch')
router.register(r'adjustments', StockAdjustmentViewSet, basename='adjustment')
router.register(r'alerts', SystemAlertViewSet, basename='alert')
# Phase 5 B2 (decision 18): bills are written only by processing a receipt, so this
# route set is READ-ONLY; payments are append-only (POST + read).
router.register(r'supplier-bills', SupplierBillViewSet, basename='supplierbill')
router.register(r'supplier-payments', SupplierPaymentViewSet, basename='supplierpayment')

urlpatterns = [
    path('', include(router.urls)),
]