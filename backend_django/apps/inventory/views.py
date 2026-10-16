# pyright: reportAttributeAccessIssue=false
#
# Why a file-level directive rather than a pyrightconfig.json:
# the checker resolves its config by walking up from its WORKING DIRECTORY, and in this
# environment it does not run from inside this repo, so neither a repo-root nor a
# workspace-root config is found (measured: 0 errors from qb_ecosystem or the repo root,
# 14 from /home/yaji or /home/yaji/projects). A directive travels with the file and
# therefore works regardless. It disables exactly one rule, the one that cannot model
# Django's `Model.objects` without django-stubs; installing django-stubs would let it be
# removed. `reportGeneralTypeIssues` is deliberately left ON.
"""Inventory app — ViewSets for catalog, purchasing & stock."""

from django.db import transaction
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.users.permissions import (
    IsAdminRole,
    IsInventoryRole,
)
from .models import (
    Brand, Category, Product, ProductVariant, UnitOfMeasure, VariantUOM,
    Supplier, PurchaseOrder, GoodsReceipt,
    InventoryBatch, StockAdjustment, SystemAlert,
)
from .serializers import (
    BrandSerializer, CategorySerializer, ProductSerializer,
    ProductVariantSerializer, UnitOfMeasureSerializer, VariantUOMSerializer,
    SupplierSerializer, PurchaseOrderSerializer,
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
    """The inventory write path. An adjustment moves stock, so it is not a plain CRUD.

    Two invariants live here, both learned the hard way in Phase 2:

    1. **The actor is the server's to assign, never the client's.** `user` is read-only on
       the serializer, and `perform_create` sets it from `request.user`. While the field
       was writable, DRF demanded it in the payload and then overwrote it anyway, so every
       client had to send a value that had no effect and could have attributed an
       adjustment to somebody else.

    2. **Creating the row and moving the stock are ONE transaction.** `apply_stock_adjustment`
       reaches `allocate_fifo`, which uses `select_for_update` and therefore refuses to run
       outside a transaction. Without the wrapper below the POST raised
       TransactionManagementError *after* the row was saved, leaving the ledger asserting an
       adjustment that never moved any stock. Do not 'tidy' the atomic away, and do not move
       it inside `apply_stock_adjustment` alone -- that would still commit the row first.
    """

    queryset = StockAdjustment.objects.select_related('variant', 'user').all()
    serializer_class = StockAdjustmentSerializer

    def perform_create(self, serializer):
        # `with` on transaction.atomic() is a verified false positive: pyright cannot pick
        # the context-manager overload without stubs, and the same idiom at 5 pre-existing
        # sites is flagged identically. Ignored at the LINE, so the rule still guards every
        # other line in this file.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
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
