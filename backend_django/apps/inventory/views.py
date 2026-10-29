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

from django.db import IntegrityError
from django.db import transaction
from django.http import Http404
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.users.models import AuditLog
from apps.users.permissions import (
    IsInventoryRole,
)
from apps.users.services import audit_request
from .exceptions import (
    BarcodeTaken,
    InvalidPurchaseOrderState,
    PurchaseOrderHasReceipts,
    PurchaseOrderLocked,
    PurchaseOrderNotOrdered,
    PurchaseOrderNotReceivable,
)
from .models import (
    Brand, Category, Product, ProductVariant, UnitOfMeasure, VariantUOM,
    Supplier, PurchaseOrder, GoodsReceipt, GoodsReceiptItem,
    InventoryBatch, StockAdjustment, SystemAlert,
    normalise_barcode,
)
from .serializers import (
    BrandSerializer, CategorySerializer, ProductSerializer,
    ProductVariantSerializer, UnitOfMeasureSerializer, VariantUOMSerializer,
    SupplierSerializer, PurchaseOrderSerializer,
    GoodsReceiptSerializer, InventoryBatchSerializer,
    StockAdjustmentSerializer, SystemAlertSerializer,
)
from .services import process_goods_receipt, apply_stock_adjustment


class _InventoryWritePermissions:
    """Read requires auth; every write requires the inventory role."""

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsInventoryRole()]


def _refuse_lost_barcode_race(exc):
    """Turn the barcode unique-constraint violation into the API's 400 `BARCODE_TAKEN`.

    `VariantUOMSerializer`'s pre-check reads then writes, so two tills can both read "no
    holder" and both insert; only `uniq_variantuom_barcode` can refuse the second. Called
    from OUTSIDE the `atomic` block `_AuditedCatalogViewSet` wraps around `save()` (the
    same reason `apps/pos/views.py` keeps its `except IntegrityError` outside its block),
    so the savepoint is already rolled back and no half-write survives. Any other
    constraint failure is re-raised untouched — it is not this handler's to explain.
    """
    if 'uniq_variantuom_barcode' not in str(exc):
        raise exc
    raise BarcodeTaken(
        'That barcode was assigned to another selling unit at the same moment: reload '
        'and use a different code.') from exc


def _nothing_changed(serializer) -> bool:
    """True when an update payload changes nothing on the row (M3).

    Two shapes count as "nothing": a body with **no writable field** — `{}`, or only
    read-only ones such as `{"status": "ORDERED"}` on a purchase order — and a body
    whose every value the row already holds. Both used to write an `UPDATE` audit row
    claiming an edit that never happened, so a screen that re-patches on blur filled the
    trail with fake edits and the trail stopped meaning "something changed".

    Nested lines (`items`, `variants`) are always a change: they are replaced wholesale,
    so comparing them to the stored rows would be a second, weaker implementation of the
    write itself. This runs BEFORE `serializer.save()`, which is why `validated_data` is
    still intact (`PurchaseOrderSerializer.update` pops `items` out of it).
    """
    for field, value in serializer.validated_data.items():
        if isinstance(value, (list, dict)):
            return False
        if getattr(serializer.instance, field, None) != value:
            return False
    return True


class _CatalogBaseViewSet(
        _InventoryWritePermissions,
        mixins.CreateModelMixin,
        mixins.ListModelMixin,
        mixins.RetrieveModelMixin,
        mixins.UpdateModelMixin,
        viewsets.GenericViewSet):
    """Base for the catalog and purchasing: **there is no DELETE** (Phase 4 Task 1).

    Every one of these rows is referenced through `PROTECT` - a category by its products,
    a product by its variants, a variant by batches, a selling unit by sale lines, a
    supplier by purchase orders - so `DELETE` either raised `ProtectedError` (a **500** to
    the client, not a refusal) or, where nothing pointed at the row yet, quietly erased
    the master data other screens were showing. Archiving is the supported exit: PATCH
    `is_active: false` on a category, product, variant or supplier.

    Composed from mixins rather than `ModelViewSet` for exactly that reason: without
    `DestroyModelMixin` the router does not map a `delete` action at all, so the verb
    answers **405** for every role, Admin included, and no `perform_destroy` exists to be
    called by accident later.
    """


class _StockRecordBaseViewSet(_InventoryWritePermissions, viewsets.ModelViewSet):
    """Stock evidence: append-only, so `PUT`/`PATCH`/`DELETE` are **405**.

    A goods receipt and a stock adjustment are the same kind of record a sale is: by the
    time the row exists, the stock has ALREADY moved. An adjustment deducts through FIFO
    (or reopens the newest batch) inside the POST that creates it, and `process/` mints
    the batches from a receipt's lines. Editing `qty_adjusted` afterwards therefore
    re-writes what the ledger says moved without moving anything back, and deleting
    either row erases the only evidence that it did move - and, where batches point at
    the receipt, that DELETE raises `ProtectedError` (a **500**, not a refusal).

    Still a `ModelViewSet` and not mixins, because `post` must stay: the collection POST
    IS the adjustment, and `process/` is an action POST. `http_method_names` is what
    removes the other three verbs, exactly as `CollectiblePaymentViewSet` does for a
    payment - the router keeps its routes and DRF answers **405 for every role, Admin
    included**, before any permission-free object lookup or serializer validation runs.

    **The cost, accepted deliberately.** A mistaken UNPROCESSED receipt cannot be
    withdrawn either: no header edit, no delete. It is left unprocessed - it minted no
    batches and moved no stock, so its `received_qty` contribution is the only trace -
    and the correction is a new business event (a further receipt, or an adjustment),
    never an edit of a past one.
    """

    http_method_names = ['get', 'head', 'options', 'post']


class _AuditedCatalogViewSet(_CatalogBaseViewSet):
    """A catalog write that changes money or stock meaning leaves ONE audit row.

    Decision 07 (Phase 2) and Phase 4 Task 1: create/edit/archive of a product, variant,
    selling unit, category and supplier are the writes that decide what the shelf and the
    till mean, so each one is a named event in the trail. The row is written INSIDE the
    same `atomic` block as the write, so a refused or rolled-back write leaves no row
    claiming it happened - and every refusal here happens during validation, before the
    first `save()`.

    Subclasses say what they are (`audit_label`) and, when the OLD value matters, what
    changed (`audit_snapshot` / `audit_changes`). A selling unit's price is money: the
    trail has to read "10.00 -> 12.50", not only "12.50".
    """

    audit_label = 'Catalog row'

    def audit_detail(self, instance):
        return str(instance)

    def audit_snapshot(self, instance):
        return {}

    def audit_changes(self, snapshot, instance) -> str:
        return ''

    def perform_create(self, serializer):
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            instance = serializer.save()
            audit_request(
                self.request,
                AuditLog.ActionType.CREATE,
                f'{self.audit_label} {self.audit_detail(instance)} created.',
            )

    def perform_update(self, serializer):
        # A PATCH that changes nothing is not an event: no writable field at all (`{}`, or
        # only read-only ones such as `{"status": "ORDERED"}` on a purchase order), or
        # every value it names is already stored. It used to write an `UPDATE` row saying
        # the row was edited, so a screen that re-patches on blur filled the trail with
        # edits that never happened.
        if _nothing_changed(serializer):
            serializer.save()
            return
        # Snapshot BEFORE save(): `serializer.instance` is untouched until `save()` runs,
        # so this is the row as it was, which is the half of the change worth auditing.
        snapshot = self.audit_snapshot(serializer.instance)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            instance = serializer.save()
            changes = self.audit_changes(snapshot, instance)
            description = (
                f'{self.audit_label} {self.audit_detail(instance)} updated')
            if changes:
                description = f'{description}: {changes}'
            audit_request(
                self.request,
                AuditLog.ActionType.UPDATE,
                f'{description}.',
            )


class CategoryViewSet(_AuditedCatalogViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer

    audit_label = 'Category'

    def audit_detail(self, instance):
        return f'{instance.name} (active={instance.is_active})'


class BrandViewSet(_CatalogBaseViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer


class UnitOfMeasureViewSet(_CatalogBaseViewSet):
    queryset = UnitOfMeasure.objects.all()
    serializer_class = UnitOfMeasureSerializer


class ProductViewSet(_AuditedCatalogViewSet):
    queryset = Product.objects.select_related(
        'category', 'brand',
    ).prefetch_related(
        'variants__selling_uoms__uom',
        'variants__base_uom',
    ).all()
    serializer_class = ProductSerializer

    audit_label = 'Product'

    def audit_detail(self, instance):
        return f'{instance.base_name} (active={instance.is_active})'


class ProductVariantViewSet(_AuditedCatalogViewSet):
    queryset = ProductVariant.objects.select_related(
        'product', 'base_uom',
    ).prefetch_related(
        'selling_uoms__uom',
    ).all()
    serializer_class = ProductVariantSerializer

    audit_label = 'Variant'


class VariantUOMViewSet(_AuditedCatalogViewSet):
    queryset = VariantUOM.objects.select_related('variant', 'uom').all()
    serializer_class = VariantUOMSerializer

    audit_label = 'Selling unit'

    def audit_snapshot(self, instance):
        return {'default_selling_price': instance.default_selling_price}

    def audit_changes(self, snapshot, instance):
        before = snapshot.get('default_selling_price')
        if before is None or before == instance.default_selling_price:
            return ''
        return (
            f'price {before:.2f} -> {instance.default_selling_price:.2f}')

    def get_queryset(self):
        """`?barcode=` resolves a scan to the exact selling unit (decision 13).

        Exact and case-insensitive on the normalised value, because the till normalises
        the scanned text the same way before it asks. Archived variants and products are
        NOT filtered out: the till has to say "that code belongs to X, which is archived"
        rather than "no product has that code", and that needs the row.
        """
        queryset = super().get_queryset()
        code = normalise_barcode(self.request.query_params.get('barcode'))
        if not code:
            return queryset
        return queryset.filter(barcode_qr__iexact=code)

    def perform_create(self, serializer):
        try:
            super().perform_create(serializer)
        except IntegrityError as exc:
            _refuse_lost_barcode_race(exc)

    def perform_update(self, serializer):
        try:
            super().perform_update(serializer)
        except IntegrityError as exc:
            _refuse_lost_barcode_race(exc)


# =========================================================================
# Purchasing & Stock ViewSets  (Phase 2)
# =========================================================================

class SupplierViewSet(_AuditedCatalogViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer

    audit_label = 'Supplier'

    def audit_detail(self, instance):
        return f'{instance.company_name} (active={instance.is_active})'


class PurchaseOrderViewSet(_CatalogBaseViewSet):
    """Purchase orders: create with nested lines, then `place` / `cancel` (Task 4.2).

    Three rules live here rather than on the serializer, because each is about the
    DOCUMENT's life rather than its payload:

    1. **`created_by` is the caller.** Assigned from `request.user` in `perform_create`,
       so a body that says otherwise is not an input (same invariant as the checkout's
       `cashier` and an adjustment's `user`).
    2. **Edit only while DRAFT** (`PO_LOCKED`). Once placed, the supplier has been told
       what to deliver; a later edit would make the receipt disagree with the order.
    3. **Status moves by ACTION only.** `place/` (DRAFT → ORDERED) and `cancel/` (DRAFT or
       ORDERED with nothing received → CANCELLED) each take the row lock, check the state
       they are allowed to leave and write their audit row inside one transaction, so two
       tills cannot both place the same order.
    """

    queryset = PurchaseOrder.objects.select_related(
        'supplier', 'created_by',
    ).prefetch_related('items__variant').all()
    serializer_class = PurchaseOrderSerializer

    def perform_create(self, serializer):
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = serializer.save(created_by=self.request.user)
            audit_request(
                self.request,
                AuditLog.ActionType.CREATE,
                f'Purchase order #{po.pk} created for {po.supplier.company_name} '
                f'with {po.items.count()} line(s).',
            )

    def perform_update(self, serializer):
        if _nothing_changed(serializer):
            # Same rule as the catalog (M3): a PATCH of only read-only fields, or of
            # values the order already holds, is not an edit and writes no audit row.
            serializer.save()
            return
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = serializer.save()
            audit_request(
                self.request,
                AuditLog.ActionType.UPDATE,
                f'Purchase order #{po.pk} edited for {po.supplier.company_name} '
                f'({po.items.count()} line(s)).',
            )

    def update(self, request, *args, **kwargs):
        """Edit only a DRAFT — decided UNDER the purchase order's row lock (B2).

        The status used to be read with a plain `get_object()` and the write handed to
        `perform_update` afterwards, so the read and the write were two separate steps:
        `place/` or `cancel/` could commit in between and the lines were replaced on an
        order the supplier had already been told about. Now the row is locked first, the
        status decided under that lock, and `super().update()` is handed the SAME locked
        row (`get_object()` below), so the verdict cannot go stale before its own write
        commits. Callers take the lock in this order everywhere (place, cancel, receive,
        process), so they serialize instead of deadlocking.
        """
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = self._locked(kwargs.get('pk'))
            self.check_object_permissions(request, po)
            if po.status != PurchaseOrder.Status.DRAFT:
                raise PurchaseOrderLocked(po)
            self._locked_instance = po
            try:
                return super().update(request, *args, **kwargs)
            finally:
                self._locked_instance = None

    def get_object(self):
        """The row `update()` already locked, when this request is an edit.

        DRF's `update()` looks the object up once more after `update()` returns to the
        viewset; without this hook that second lookup would be an UNLOCKED read of a row
        whose status was just decided against.
        """
        locked = getattr(self, '_locked_instance', None)
        if locked is not None:
            return locked
        return super().get_object()

    def _locked(self, pk) -> PurchaseOrder:
        """The order, row-locked, for one of the status actions.

        MUST run inside an atomic block (both actions do). `get_object()` would read
        without a lock, so two concurrent `place/` calls could both see DRAFT and both
        write an audit row for the same transition.
        """
        po = PurchaseOrder.objects.select_for_update().filter(pk=pk).first()
        if po is None:
            raise Http404
        return po

    @action(detail=True, methods=['post'])
    def place(self, request, pk=None):
        """DRAFT → ORDERED. Anything else is `INVALID_PO_STATE`."""
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = self._locked(pk)
            if po.status != PurchaseOrder.Status.DRAFT:
                raise InvalidPurchaseOrderState(
                    f'PO #{po.pk} is {po.status}: only a DRAFT can be placed.')
            po.status = PurchaseOrder.Status.ORDERED
            po.save(update_fields=['status', 'updated_at'])
            audit_request(
                request,
                AuditLog.ActionType.UPDATE,
                f'Purchase order #{po.pk} placed with {po.supplier.company_name}.',
            )
        return Response(self.get_serializer(po).data)

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        """DRAFT/ORDERED with nothing received → CANCELLED.

        A PARTIAL/COMPLETE order has stock in the rack explained by this document, so it
        is refused with `PO_HAS_RECEIPTS` rather than cancelled out from under it. The
        `received_qty` check sits beside the receipt check on purpose: a legacy receipt
        (the fixtures and `seed_demo` set `received_qty` directly) has no `receipts` row
        but did deliver goods.
        """
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = self._locked(pk)
            if po.status in (
                    PurchaseOrder.Status.PARTIAL, PurchaseOrder.Status.COMPLETE):
                raise PurchaseOrderHasReceipts(po)
            if po.status != PurchaseOrder.Status.DRAFT and \
                    po.status != PurchaseOrder.Status.ORDERED:
                raise InvalidPurchaseOrderState(
                    f'PO #{po.pk} is {po.status} and cannot be cancelled.')
            if po.receipts.exists() or po.items.filter(received_qty__gt=0).exists():
                raise PurchaseOrderHasReceipts(po)
            po.status = PurchaseOrder.Status.CANCELLED
            po.save(update_fields=['status', 'updated_at'])
            audit_request(
                request,
                AuditLog.ActionType.UPDATE,
                f'Purchase order #{po.pk} cancelled '
                f'({po.supplier.company_name}).',
            )
        return Response(self.get_serializer(po).data)


class _ReceiptRefused(Exception):
    """A receipt the server refuses to record; `str(exc)` is the client's detail.

    Exists so the over-order cap can be raised FROM INSIDE the atomic block — where the
    POItem row is locked and `received_qty` is trustworthy — and still leave as a plain
    400. Returning a Response from inside the block would commit it; raising rolls back
    the receipt row and every accumulated quantity first, and this class is caught one
    line later. Deliberately not a `ValueError`: nothing outside this view catches it.
    """


class GoodsReceiptViewSet(_StockRecordBaseViewSet):
    queryset = GoodsReceipt.objects.select_related(
        'po', 'received_by',
    ).prefetch_related(
        'batches', 'lines__po_item__variant').all()
    serializer_class = GoodsReceiptSerializer

    def create(self, request, *args, **kwargs):
        """Record a receipt, optionally carrying received quantities.

        `items: [{po_item, qty}]` does two things, and both matter:

        * adds `qty` to `POItem.received_qty` — the running total across every receipt of
          the PO, and the cap the next delivery is checked against; and
        * writes one `GoodsReceiptItem` per entry, so `process/` can batch THIS delivery
          instead of the running total (decision 09 item 4).

        The two are deliberately not the same field. Before the lines existed, process/
        had only `received_qty` to work from and minted a batch from it on every receipt —
        deliveries of 5 then 2 stocked 12 units for 7 received.

        `received_qty` has no other API write path (Task 6B.2).
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
        # Task 4.2: only an ORDERED or PARTIAL order can receive. A DRAFT was never
        # placed, so what arrives is not what this document asked for; a COMPLETE or
        # CANCELLED one is closed. Both were reachable before this gate - a DRAFT receipt
        # is what the receiving screen's own fixtures did. Each refusal carries its own
        # stable code, so a client can tell "place it first" from "this order is done".
        #
        # The gate reads the row again INSIDE the transaction below, under
        # `select_for_update`, because an unlocked read here could be answered by a
        # status that `cancel/` replaced before the receipt row was written - the receipt
        # then existed on a CANCELLED order and `process/` stocked it.
        po_id = po.pk
        # Shape checks first, outside the transaction: they need no lock, and answering
        # them before the atomic block keeps the block to the part that must be atomic.
        parsed = []  # (po_item_id, qty) — one entry per delivered line, in payload order
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
            parsed.append((po_item.pk, qty))

        try:
            with transaction.atomic():
                # Locked BEFORE the status is decided, so this receipt and `cancel/`
                # serialize: the cancel either sees this receipt (and refuses with
                # PO_HAS_RECEIPTS) or waits here until the receipt is committed.
                po = PurchaseOrder.objects.select_for_update().get(pk=po_id)
                if po.status == PurchaseOrder.Status.DRAFT:
                    raise PurchaseOrderNotOrdered(po)
                if po.status in (
                        PurchaseOrder.Status.COMPLETE,
                        PurchaseOrder.Status.CANCELLED):
                    raise PurchaseOrderNotReceivable(
                        f'PO {po.pk} is {po.status} and cannot receive more.')
                receipt = ser.save(received_by=request.user)
                for po_item_pk, qty in parsed:
                    # LOCKED before accumulating: two deliveries recorded at the same
                    # moment would otherwise both read the same `received_qty` and the
                    # loser's quantity would vanish (or the over-order cap would be
                    # waved through twice). Re-read here, inside the lock, so a second
                    # entry for the SAME po_item also sees the first one's write.
                    locked = POItem.objects.select_for_update().get(pk=po_item_pk)
                    # Accumulate: each delivery adds to what is already received, capped
                    # at ordered. Overwriting would silently under-count a split delivery.
                    total = locked.received_qty + qty
                    if total > locked.ordered_qty:
                        raise _ReceiptRefused(
                            f'qty for po_item {locked.pk} would exceed the '
                            f'ordered {locked.ordered_qty} '
                            f'({locked.received_qty} already received).')
                    locked.received_qty = total
                    locked.save(update_fields=['received_qty'])
                    if qty > 0:
                        GoodsReceiptItem.objects.create(
                            receipt=receipt, po_item=locked, qty=qty)
        except _ReceiptRefused as exc:
            # Raised inside the atomic block, so the receipt row and every accumulated
            # quantity are rolled back with it — a refused delivery leaves no trace.
            return Response(
                {'detail': str(exc)}, status=drf_status.HTTP_400_BAD_REQUEST)
        return Response(
            self.get_serializer(receipt).data,
            status=drf_status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def process(self, request, pk=None):
        """Turn THIS receipt's lines into FIFO batches.

        The double-process guard is `process_goods_receipt`'s job now (decision 09 item
        4): it checks `processed_at` with the receipt row locked, so two concurrent calls
        serialize and the second one is refused. The old guard sat here as
        `receipt.batches.exists()` — an unlocked read — and both callers could pass it.
        """
        from rest_framework import status as drf_status

        from .exceptions import ReceiptAlreadyProcessed

        receipt = self.get_object()
        try:
            # The batches and the audit row are one transaction (decision 07).
            # `process_goods_receipt` owns its own atomic block and the receipt row lock,
            # so this wraps it rather than re-implementing the lock.
            with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
                batches = process_goods_receipt(receipt=receipt, user=request.user)
                audit_request(
                    request,
                    AuditLog.ActionType.RECEIPT,
                    f'Goods receipt #{receipt.pk} processed into '
                    f'{len(batches)} batch(es) for PO #{receipt.po_id}.',
                )
        except ReceiptAlreadyProcessed as exc:
            # Same 400 and same sentence the view-level guard used to answer with; the
            # added `code` is what lets a client tell this apart from a bad payload.
            return Response(
                {'code': exc.code, 'detail': str(exc)},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        return Response(
            InventoryBatchSerializer(batches, many=True).data)


class InventoryBatchViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = InventoryBatch.objects.select_related('variant', 'receipt').all()
    serializer_class = InventoryBatchSerializer
    permission_classes = [IsAuthenticated]


class StockAdjustmentViewSet(_StockRecordBaseViewSet):
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
            # Same block, so a refused adjustment (no batch history, negative beyond
            # stock) writes no audit row (decision 07).
            audit_request(
                self.request,
                AuditLog.ActionType.STOCK_ADJUST,
                f'Stock adjustment #{adj.pk} {adj.adjustment_type} '
                f'{adj.qty_adjusted} on {adj.variant}.',
            )


class SystemAlertViewSet(viewsets.ReadOnlyModelViewSet):
    """The system alert feed: read it, and `resolve` an alert. Nothing else.

    **Why read-only (decision 06).** Alerts are raised by the system — `_check_low_stock`
    on a sale, the expiring-batch scan — so a hand-written row is a claim the dashboard
    would believe and nobody derived from stock. Leaving `ModelViewSet` in place also
    meant `POST /alerts/` was reachable; making the viewset read-only removes the route
    itself, so POST/PUT/PATCH/DELETE answer **405 for every role**, Admin included,
    rather than 403 for some and 201 for others.

    **Why `resolve` allows the Stock Manager (P2 Ruling).** Decision 06 named Admin only,
    but the stocker is the person who restocks and therefore the person who clears the
    alert; the ruling reuses the existing `IsInventoryRole` class (Stock Manager + Store
    Manager + Admin) instead of inventing a new one.

    Reads stay `IsAuthenticated` on purpose: the low-stock page and the admin overview
    both read this feed, and third-role accounts on those screens have no other source.
    """

    queryset = SystemAlert.objects.select_related('variant', 'resolved_by').all()
    serializer_class = SystemAlertSerializer

    def get_permissions(self):
        # `resolve` is the only write on this viewset; everything else it can reach is a
        # read (the viewset itself no longer registers create/update/destroy).
        if self.action == 'resolve':
            return [IsInventoryRole()]
        return [IsAuthenticated()]

    @action(detail=True, methods=['post'])
    def resolve(self, request, pk=None):
        """Mark one alert resolved, recording WHO and WHEN.

        The row is re-read under `select_for_update` inside an atomic block because the
        guard and the write must be one step: an unlocked `get_object()` would let two
        concurrent resolves both see `is_resolved=False`, and the second one would stamp
        its own name over the first resolver's - losing the audit trail this task exists
        to create.

        The response is the serialized alert (so a client can refresh the row in place)
        plus the legacy `detail` sentence the old Admin-only endpoint returned, which
        keeps any existing caller working.
        """
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            alert = (
                SystemAlert.objects.select_for_update()
                .filter(pk=pk).first()
            )
            if alert is None:
                raise Http404
            if alert.is_resolved:
                return Response(
                    {
                        'code': 'ALERT_ALREADY_RESOLVED',
                        'detail': f'Alert {alert.pk} was already resolved.',
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            alert.is_resolved = True
            alert.resolved_by = request.user
            alert.resolved_at = timezone.now()
            alert.save(
                update_fields=['is_resolved', 'resolved_by', 'resolved_at'])
            # Inside the same block as the write (decision 07): the refused second
            # resolve returns above, so it writes no second row.
            audit_request(
                request,
                AuditLog.ActionType.ALERT_RESOLVE,
                f'Alert #{alert.pk} ({alert.alert_type}) resolved.',
            )

        # `dict(...)` copy, not the ReturnDict itself: the serializer's `.data` is typed
        # as index-only by pyright without django-stubs, but a plain dict accepts the
        # legacy `detail` key below.
        data = dict(SystemAlertSerializer(alert).data)
        data['detail'] = 'Alert resolved.'
        return Response(data)
