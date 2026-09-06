"""Inventory app — ViewSets for catalog, purchasing & stock."""

from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser, IsAuthenticated
from rest_framework.response import Response

from apps.users.permissions import (
    IsAdminRole,
    IsInventoryRole,
)
from .models import (
    Brand, Category, Product, ProductVariant, UnitOfMeasure, VariantUOM,
    Supplier, PurchaseOrder, POItem, GoodsReceipt,
    InventoryBatch, StockAdjustment, SystemAlert,
)
from .serializers import (
    BrandSerializer, CategorySerializer, ProductSerializer,
    ProductVariantSerializer, UnitOfMeasureSerializer, VariantUOMSerializer,
    SupplierSerializer, PurchaseOrderSerializer, POItemSerializer,
    GoodsReceiptSerializer, InventoryBatchSerializer,
    StockAdjustmentSerializer, SystemAlertSerializer,
)
from .services import process_goods_receipt, apply_stock_adjustment


class _CatalogBaseViewSet(viewsets.ModelViewSet):
    """Base: read requires auth; write requires inventory role."""

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsInventoryRole()]


class CategoryViewSet(_CatalogBaseViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class BrandViewSet(_CatalogBaseViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer


class UnitOfMeasureViewSet(_CatalogBaseViewSet):
    queryset = UnitOfMeasure.objects.all()
    serializer_class = UnitOfMeasureSerializer


class ProductViewSet(_CatalogBaseViewSet):
    queryset = Product.objects.select_related(
        'category', 'brand',
    ).prefetch_related(
        'variants__selling_uoms__uom',
        'variants__base_uom',
    ).all()
    serializer_class = ProductSerializer


class ProductVariantViewSet(_CatalogBaseViewSet):
    queryset = ProductVariant.objects.select_related(
        'product', 'base_uom',
    ).prefetch_related(
        'selling_uoms__uom',
    ).all()
    serializer_class = ProductVariantSerializer


class VariantUOMViewSet(_CatalogBaseViewSet):
    queryset = VariantUOM.objects.select_related('variant', 'uom').all()
    serializer_class = VariantUOMSerializer


# =========================================================================
# Purchasing & Stock ViewSets  (Phase 2)
# =========================================================================

class SupplierViewSet(_CatalogBaseViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer


class PurchaseOrderViewSet(_CatalogBaseViewSet):
    queryset = PurchaseOrder.objects.select_related(
        'supplier', 'created_by',
    ).prefetch_related('items__variant').all()
    serializer_class = PurchaseOrderSerializer


class GoodsReceiptViewSet(_CatalogBaseViewSet):
    queryset = GoodsReceipt.objects.select_related(
        'po', 'received_by',
    ).prefetch_related('batches').all()
    serializer_class = GoodsReceiptSerializer

    @action(detail=True, methods=['post'])
    def process(self, request, pk=None):
        receipt = self.get_object()
        batches = process_goods_receipt(receipt=receipt, user=request.user)
        return Response(
            InventoryBatchSerializer(batches, many=True).data)


class InventoryBatchViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = InventoryBatch.objects.select_related('variant', 'receipt').all()
    serializer_class = InventoryBatchSerializer
    permission_classes = [IsAuthenticated]


class StockAdjustmentViewSet(_CatalogBaseViewSet):
    queryset = StockAdjustment.objects.select_related('variant', 'user').all()
    serializer_class = StockAdjustmentSerializer

    def perform_create(self, serializer):
        adj = serializer.save(user=self.request.user)
        apply_stock_adjustment(adjustment=adj)


class SystemAlertViewSet(viewsets.ModelViewSet):
    queryset = SystemAlert.objects.select_related('variant').all()
    serializer_class = SystemAlertSerializer

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdminRole()]

    @action(detail=True, methods=['post'])
    def resolve(self, request, pk=None):
        """Resolve an alert (Admin only — enforced via get_permissions)."""
        alert = self.get_object()
        alert.is_resolved = True
        alert.save(update_fields=['is_resolved'])
        return Response({'detail': 'Alert resolved.'})
