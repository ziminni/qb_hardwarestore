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
    SystemAlertViewSet,
)

router = DefaultRouter()
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'brands', BrandViewSet, basename='brand')
router.register(r'uoms', UnitOfMeasureViewSet, basename='uom')
router.register(r'products', ProductViewSet, basename='product')
router.register(r'variants', ProductVariantViewSet, basename='variant')
router.register(r'variant-uoms', VariantUOMViewSet, basename='variantuom')
router.register(r'suppliers', SupplierViewSet, basename='supplier')
router.register(r'purchase-orders', PurchaseOrderViewSet, basename='purchaseorder')
router.register(r'goods-receipts', GoodsReceiptViewSet, basename='goodsreceipt')
router.register(r'batches', InventoryBatchViewSet, basename='batch')
router.register(r'adjustments', StockAdjustmentViewSet, basename='adjustment')
router.register(r'alerts', SystemAlertViewSet, basename='alert')

urlpatterns = [
    path('', include(router.urls)),
]