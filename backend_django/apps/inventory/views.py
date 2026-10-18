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

    def create(self, request, *args, **kwargs):
        """Record a receipt, optionally carrying received quantities.

        `items: [{po_item, qty}]` sets POItem.received_qty so a later
        POST /goods-receipts/{id}/process/ has something to turn into batches.
        Without it the receipt is still recorded (backward compatible), but the
        process step finds nothing to receive. Task 6B.2: received_qty has no
        other API write path.
        """
        from decimal import Decimal

        from rest_framework import status as drf_status

        from .models import POItem

        data = dict(request.data)
        raw_items = data.pop('items', [])
        if raw_items is None:
            raw_items = []
        if not isinstance(raw_items, list):
            return Response(
                {'detail': 'items must be a list of {po_item, qty}.'},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        ser = self.get_serializer(data=data)
        ser.is_valid(raise_exception=True)

        po = ser.validated_data['po']
        if po.status in (
                PurchaseOrder.Status.COMPLETE, PurchaseOrder.Status.CANCELLED):
            return Response(
                {'detail': f'PO {po.pk} is {po.status} and cannot receive more.'},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        parsed = []
        for entry in raw_items:
            if not isinstance(entry, dict):
                return Response(
                    {'detail': 'each item must be {po_item, qty}.'},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            try:
                po_item = POItem.objects.select_related('po').get(
                    pk=entry.get('po_item'))
            except (POItem.DoesNotExist, ValueError, TypeError):
                return Response(
                    {'detail': f"unknown po_item: {entry.get('po_item')!r}."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            if po_item.po_id != po.id:
                return Response(
                    {'detail': f'po_item {po_item.pk} is not on this PO.'},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            try:
                qty = Decimal(str(entry.get('qty', 0)))
            except Exception:
                return Response(
                    {'detail': f"qty for po_item {po_item.pk} is not a number."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            if qty < 0:
                return Response(
                    {'detail': f'qty for po_item {po_item.pk} must not be negative.'},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            # Accumulate: each delivery adds to what is already received, capped
            # at ordered. Overwriting would silently under-count a split delivery.
            total = po_item.received_qty + qty
            if total > po_item.ordered_qty:
                return Response(
                    {'detail': f'qty for po_item {po_item.pk} would exceed the '
                               f'ordered {po_item.ordered_qty} '
                               f'({po_item.received_qty} already received).'},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            parsed.append((po_item, total))

        with transaction.atomic():
            receipt = ser.save(received_by=request.user)
            for po_item, qty in parsed:
                po_item.received_qty = qty
                po_item.save(update_fields=['received_qty'])
        return Response(
            self.get_serializer(receipt).data,
            status=drf_status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def process(self, request, pk=None):
        from rest_framework import status as drf_status

        receipt = self.get_object()
        if receipt.batches.exists():
            # No receipt-level guard in process_goods_receipt: every call mints
            # fresh batches, so a double-tap double-counts stock. Refuse here,
            # where the receipt's history is visible.
            return Response(
                {'detail': f'Goods receipt {receipt.pk} was already processed.'},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
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
