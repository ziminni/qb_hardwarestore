# pyright: reportAttributeAccessIssue=false, reportMissingImports=false
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

from typing import cast

from django.db import IntegrityError, transaction
from django.db.models import Count, F, Prefetch, Sum
from django.db.models.deletion import ProtectedError
from django.http import Http404
from django.utils import timezone
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.users.models import AuditLog
from apps.users.permissions import (
    STAFF_ROLES,
    IsAdminRole,
    IsInventoryRole,
    IsManagerRole,
    has_role,
)
from apps.users.services import audit_request
from common.exceptions import refuse_fractional_whole_unit

from .exceptions import (
    BarcodeTaken,
    BaseUnitRequired,
    InvalidPurchaseOrderState,
    InvalidStorageLocation,
    PurchaseOrderHasReceipts,
    PurchaseOrderLocked,
    PurchaseOrderNotOrdered,
    PurchaseOrderNotReceivable,
    SellingUnitInUse,
)
from .models import (
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    StockTransfer,
    StorageLocation,
    Supplier,
    SupplierBill,
    SupplierCreditNote,
    SupplierPayment,
    SupplierReturn,
    SupplierReturnLine,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
    normalise_barcode,
)
from .payables import (
    apply_credit_to_source_bill,
    apply_supplier_credit,
    create_credit_note_for_return,
    decide_supplier_cheque,
    record_supplier_payment,
)
from .serializers import (
    BrandSerializer,
    CategorySerializer,
    GoodsReceiptSerializer,
    InventoryBatchSerializer,
    ProductSerializer,
    ProductVariantSerializer,
    PurchaseOrderSerializer,
    StockAdjustmentSerializer,
    StockTransferCreateSerializer,
    StockTransferSerializer,
    StorageLocationSerializer,
    SupplierBillSerializer,
    SupplierCreditNoteSerializer,
    SupplierPaymentSerializer,
    SupplierReturnCreateSerializer,
    SupplierReturnSerializer,
    SupplierSerializer,
    SystemAlertSerializer,
    UnitOfMeasureSerializer,
    VariantUOMSerializer,
    annotate_unit_in_use,
    unit_in_use,
)
from .services import (
    apply_stock_adjustment,
    line_factor,
    process_goods_receipt,
    record_supplier_return,
    refuse_unrepresentable_stock,
)
from .transfers import record_stock_transfer


class _InventoryWritePermissions:
    """Read requires auth; every write requires the inventory role."""

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
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
    if "uniq_variantuom_barcode" not in str(exc):
        raise exc
    raise BarcodeTaken(
        "That barcode was assigned to another selling unit at the same moment: reload "
        "and use a different code."
    ) from exc


def _refuse_lost_storage_name_race(exc):
    """Turn the location-name unique violation into the API's 400, never a 500.

    `StorageLocationSerializer`'s pre-check reads then writes, so two Admins can both
    read "free" and both insert/rename; only `uniq_storage_location_name` can refuse the
    second. Called from OUTSIDE the `atomic` block (the same placement as
    `_refuse_lost_barcode_race`), so the savepoint is rolled back and neither the losing
    write nor its audit row survives. Any other constraint failure is re-raised.
    """
    if "uniq_storage_location_name" not in str(exc):
        raise exc
    raise InvalidStorageLocation(
        "That location name was taken by another Admin at the same moment: reload the "
        "list and pick a different name."
    ) from exc


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
    viewsets.GenericViewSet,
):
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

    # A tuple, not the list DRF's default uses: nobody mutates a class attribute, and a
    # shared list would let one instance's edit change every viewset's verbs.
    http_method_names = ("get", "head", "options", "post")


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

    audit_label = "Catalog row"

    def audit_detail(self, instance):
        return str(instance)

    def audit_snapshot(self, instance):
        return {}

    def audit_changes(self, snapshot, instance) -> str:
        return ""

    def perform_create(self, serializer):
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            instance = serializer.save()
            audit_request(
                self.request,
                AuditLog.ActionType.CREATE,
                f"{self.audit_label} {self.audit_detail(instance)} created.",
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
            description = f"{self.audit_label} {self.audit_detail(instance)} updated"
            if changes:
                description = f"{description}: {changes}"
            audit_request(
                self.request,
                AuditLog.ActionType.UPDATE,
                f"{description}.",
            )


class CategoryViewSet(_AuditedCatalogViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer

    audit_label = "Category"

    def audit_detail(self, instance):
        return f"{instance.name} (active={instance.is_active})"


class BrandViewSet(_CatalogBaseViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer


class UnitOfMeasureViewSet(_CatalogBaseViewSet):
    queryset = UnitOfMeasure.objects.all()
    serializer_class = UnitOfMeasureSerializer


class StorageLocationViewSet(_AuditedCatalogViewSet):
    """`/storage-locations/` — where a product is kept (Phase 5 B4, decision 18).

    **Admin writes, everyone logged in reads.** The label is printed on the till line and
    on the delivery slip, so a Cashier must be able to resolve it without being able to
    edit the shop's list; adding, renaming and deactivating is an Admin act
    (`IsAdminRole`), which is narrower than the `IsInventoryRole` the rest of the catalog
    uses — a Stock Manager reads this list, they do not decide the shop's places.

    **An Admin also reads the deactivated ones** (`STAFF_ROLES`): they are the only role
    that can restore a place, and a list that hid it would leave "Bodega" unreachable the
    moment it was switched off. Everyone else sees `is_active=True` only, which is what
    a picker should offer.

    **No DELETE** (`_CatalogBaseViewSet`): a location a product still points at is
    `PROTECT`-referenced, and the supported exit is `PATCH {"is_active": false}`. A
    deactivated location keeps labelling the products that already point at it; only NEW
    assignments are refused (`INVALID_STORAGE_LOCATION`).
    """

    queryset = StorageLocation.objects.all()
    serializer_class = StorageLocationSerializer

    audit_label = "Storage location"

    def audit_detail(self, instance):
        return f"{instance.name} (active={instance.is_active})"

    def get_permissions(self):  # pyright: ignore[reportIncompatibleMethodOverride]
        if self.action in ("list", "retrieve"):
            return [IsAuthenticated()]
        return [IsAdminRole()]

    def get_queryset(self):
        queryset = super().get_queryset()
        if has_role(self.request.user, STAFF_ROLES):
            return queryset
        return queryset.filter(is_active=True)

    def perform_create(self, serializer):
        try:
            super().perform_create(serializer)
        except IntegrityError as exc:
            _refuse_lost_storage_name_race(exc)

    def perform_update(self, serializer):
        try:
            super().perform_update(serializer)
        except IntegrityError as exc:
            _refuse_lost_storage_name_race(exc)


class ProductViewSet(_AuditedCatalogViewSet):
    # `annotate_unit_in_use` rides along with the prefetch: every nested selling unit
    # answers `in_use` from the same query the list already ran (Phase 1d Task 1).
    # `stored_at` and `variant__product__stored_at` are joined for the B4 label, so no
    # row of a list asks for its own location.
    queryset = (
        Product.objects.select_related(
            "category",
            "brand",
            "stored_at",
        )
        .prefetch_related(
            Prefetch(
                "variants__selling_uoms",
                queryset=annotate_unit_in_use(
                    VariantUOM.objects.select_related(
                        "uom", "variant__product__stored_at"
                    )
                ),
            ),
            "variants__base_uom",
        )
        .all()
    )
    serializer_class = ProductSerializer

    audit_label = "Product"

    def audit_detail(self, instance):
        return f"{instance.base_name} (active={instance.is_active})"


class ProductVariantViewSet(_AuditedCatalogViewSet):
    queryset = (
        ProductVariant.objects.select_related(
            "product",
            "product__stored_at",
            "base_uom",
        )
        .prefetch_related(
            Prefetch(
                "selling_uoms",
                queryset=annotate_unit_in_use(
                    VariantUOM.objects.select_related(
                        "uom", "variant__product__stored_at"
                    )
                ),
            ),
        )
        .all()
    )
    serializer_class = ProductVariantSerializer

    audit_label = "Variant"


class VariantUOMViewSet(_AuditedCatalogViewSet):
    # `variant__product` is joined because the response explains WHY a scanned unit
    # cannot be sold (`product_name`, `product_is_active`): one query, not three per row.
    # `in_use` comes from the same statement (Phase 1d Task 1), so it costs no second one.
    # `variant__product__stored_at` joins the B4 label for the same reason: the till's
    # catalogue and its `?barcode=` lookup must not cost a query per row.
    queryset = annotate_unit_in_use(
        VariantUOM.objects.select_related(
            "variant__product", "variant__product__stored_at", "uom"
        )
    ).all()
    serializer_class = VariantUOMSerializer

    audit_label = "Selling unit"

    def audit_snapshot(self, instance):
        return {
            "default_selling_price": instance.default_selling_price,
            "barcode_qr": instance.barcode_qr,
        }

    def audit_changes(self, snapshot, instance):
        """What the edit changed: the price (money) and the code (what a scan resolves).

        Reachable in one PATCH, so the two are joined rather than one replacing the
        other. A code that ends up re-derived from a blank PATCH shows as a real change,
        which is what happened: the unit's code went from an EAN back to its own QB.
        """
        changes = []
        before = snapshot.get("default_selling_price")
        if before is not None and before != instance.default_selling_price:
            changes.append(
                f"price {before:.2f} -> {instance.default_selling_price:.2f}"
            )
        code_before = snapshot.get("barcode_qr", "")
        if code_before != instance.barcode_qr:
            changes.append(f"barcode '{code_before}' -> '{instance.barcode_qr}'")
        return "; ".join(changes)

    def get_queryset(self):
        """`?barcode=` resolves a scan to the exact selling unit (decision 13).

        Exact and case-insensitive on the normalised value, because the till normalises
        the scanned text the same way before it asks. Archived variants and products are
        NOT filtered out: the till has to say "that code belongs to X, which is archived"
        rather than "no product has that code", and that needs the row.
        """
        queryset = super().get_queryset()
        code = normalise_barcode(self.request.query_params.get("barcode"))
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

    def destroy(self, request, *args, **kwargs):
        """`DELETE /variant-uoms/{id}/` — remove a selling unit nothing references.

        Phase 1d Task 3 (decision 16). Every other catalog row stays 405: a category, a
        product, a variant or a supplier is ARCHIVED because history points at it, and a
        goods receipt is stock evidence. A selling unit is the one catalog row a clerk
        creates by hand and can create by mistake ("Bag = 40 kg" for a product sold in
        bags only), so it gets a real exit — and only while nothing points at it.

        One atomic block holding the row's lock (`select_for_update`), because the two
        refusals below are read-then-write: without the lock two tills could both read
        "nothing uses this unit" and the loser's `delete()` would answer a 500 from the
        FK. A hold that starts meanwhile takes a `FOR KEY SHARE` lock on this row, so it
        either commits first (and this DELETE waits, sees the cart line and refuses) or
        waits for this DELETE and is told the unit is gone — never a lost cart line. A
        WRITER (sale, quote, order, push) takes the same lock before its first write, so
        it either commits first or is told the unit is gone.

        The audit row is written INSIDE the same transaction: a success is 204 plus one
        `DELETE` row, and a refusal writes nothing at all.
        """
        # 404 for a bad id and the role check, both before any lock is taken.
        pk = self.get_object().pk
        with transaction.atomic():
            unit = self._lock_unit(pk)
            if unit is None:
                # A second DELETE of the same row: the other one committed while this
                # one waited. The row this request named is gone, so it answers the same
                # 404 as a bad id - never the `DoesNotExist` a bare `.get()` raised.
                raise Http404("This selling unit has already been removed.")
            self._refuse_removal(unit)
            # Read the label and code BEFORE the delete: the audit row has to name the
            # unit that went away, and the row cannot be read afterwards.
            description = (
                f"Selling unit {unit.variant.product.base_name} · "
                f"{unit.variant.variant_name} · {unit.uom.code} "
                f"(code {unit.barcode_qr}) removed."
            )
            try:
                unit.delete()
            except ProtectedError as exc:
                # The FK is the real guard (a sale line written between the check and the
                # delete). Same refusal as the check above, because the clerk's answer is
                # the same: this unit is used, leave it alone.
                raise SellingUnitInUse(self._in_use_detail(unit)) from exc
            audit_request(request, AuditLog.ActionType.DELETE, description)
        return Response(status=status.HTTP_204_NO_CONTENT)

    def _lock_unit(self, pk):
        """The row, locked, with the names both the refusal and the audit text need.

        `.first()`, not `.get()`: a deleted row is a 404 the view raises, and a `.get()`
        would turn the second of two clicks into a 500.
        """
        return (
            VariantUOM.objects.select_for_update()
            .select_related("variant__product", "uom")
            .filter(pk=pk)
            .first()
        )

    def _refuse_removal(self, unit):
        """Factor 1 is the base unit; anything referenced by history stays."""
        if unit.conversion_factor == 1:
            raise BaseUnitRequired(
                f"{unit} is the base unit of {unit.variant}: a product is counted in its "
                "base unit, so it cannot be removed. Remove another selling unit, or "
                "archive the product."
            )
        if unit_in_use(unit):
            raise SellingUnitInUse(self._in_use_detail(unit))

    @staticmethod
    def _in_use_detail(unit) -> str:
        return (
            f"{unit} has already been sold, held or requested, so it cannot be removed. "
            "Its price and code stay editable."
        )


# =========================================================================
# Purchasing & Stock ViewSets  (Phase 2)
# =========================================================================


class SupplierViewSet(_AuditedCatalogViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer

    audit_label = "Supplier"

    def audit_detail(self, instance):
        return f"{instance.company_name} (active={instance.is_active})"

    @action(detail=False, methods=["get"])
    def payables(self, request):
        """`GET /suppliers/payables/` — what the shop owes each supplier (decision 18).

        ONE row per supplier that has at least one bill, with the money questions the
        payables screen asks, each summed over that supplier's bills:

            original    SUM(total_amount)      what the bills were for
            paid        original - balance - credited   money that left the till
            balance     SUM(balance_amount)   what is still owed
            overdue     SUM(balance where the due date has passed and money is owed)
            credited    SUM(CREDIT payments)  bills settled with supplier credit
            unapplied   SUM(note remaining)   credit still to spend (own column)
            issued      SUM(ISSUED cheques)   money promised but not yet cleared

        Computed in a handful of grouped queries (never a loop over bills), so a screen
        with twenty suppliers costs a constant number of queries for the whole page.
        Stock Manager / Store Manager / Admin read it; a Cashier and the CPMS account do
        not (supplier money is not till or CPMS data), which `_AuditedCatalogViewSet`'s
        own permission rule already enforces for any action that is not list/retrieve.

        Phase 8 B4 (decision 20 #1): `paid` subtracts `credited` as well as `balance`,
        because a CREDIT payment is not cash that left the till - without the third term
        a 100.00 credit would read as 100.00 of cash. `unapplied_credit` is deliberately
        its own figure and never subtracted from the balance: the note's credit is not
        owed YET, so folding it in would show a supplier the shop owes money to as a
        negative balance.
        """
        from django.db.models import DecimalField, Q, Sum, Value
        from django.db.models.functions import Coalesce

        money_field = DecimalField(max_digits=14, decimal_places=2)

        def sums_by_supplier(queryset, field, key):
            return {
                row[key]: row["total"]
                for row in queryset.values(key).annotate(total=Sum(field))
            }

        credited = sums_by_supplier(
            SupplierPayment.objects.filter(method=SupplierPayment.Method.CREDIT),
            "amount",
            "bill__supplier_id",
        )
        unapplied = sums_by_supplier(
            SupplierCreditNote.objects.all(), "remaining_amount", "supplier_id"
        )
        issued = sums_by_supplier(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CHEQUE,
                status=SupplierPayment.Status.ISSUED,
            ),
            "amount",
            "bill__supplier_id",
        )
        today = timezone.localdate()
        rows = (
            SupplierBill.objects.values("supplier_id", "supplier__company_name")
            .annotate(
                bills=Count("id"),
                original=Coalesce(
                    Sum("total_amount"), Value(0), output_field=money_field
                ),
                balance=Coalesce(
                    Sum("balance_amount"), Value(0), output_field=money_field
                ),
                overdue=Coalesce(
                    Sum(
                        "balance_amount",
                        filter=Q(balance_amount__gt=0, due_date__lt=today),
                    ),
                    Value(0),
                    output_field=money_field,
                ),
            )
            .order_by("supplier__company_name")
        )

        results = [
            {
                "supplier": row["supplier_id"],
                "supplier_name": row["supplier__company_name"],
                "bills": row["bills"],
                "original": f"{row['original']:.2f}",
                "paid": f"{row['original'] - row['balance'] - credited.get(row['supplier_id'], 0):.2f}",
                "balance": f"{row['balance']:.2f}",
                "overdue": f"{row['overdue']:.2f}",
                "credited": f"{credited.get(row['supplier_id'], 0):.2f}",
                "unapplied_credit": f"{unapplied.get(row['supplier_id'], 0):.2f}",
                "issued_cheques": f"{issued.get(row['supplier_id'], 0):.2f}",
            }
            for row in rows
        ]
        return Response({"count": len(results), "results": results})


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

    queryset = (
        PurchaseOrder.objects.select_related(
            "supplier",
            "created_by",
        )
        .prefetch_related("items__variant")
        .all()
    )
    serializer_class = PurchaseOrderSerializer

    def perform_create(self, serializer):
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = serializer.save(created_by=self.request.user)
            audit_request(
                self.request,
                AuditLog.ActionType.CREATE,
                f"Purchase order #{po.pk} created for {po.supplier.company_name} "
                f"with {po.items.count()} line(s).",
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
                f"Purchase order #{po.pk} edited for {po.supplier.company_name} "
                f"({po.items.count()} line(s)).",
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
            po = self._locked(kwargs.get("pk"))
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
        locked = getattr(self, "_locked_instance", None)
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

    @action(detail=True, methods=["post"])
    def place(self, request, pk=None):
        """DRAFT → ORDERED. Anything else is `INVALID_PO_STATE`."""
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            po = self._locked(pk)
            if po.status != PurchaseOrder.Status.DRAFT:
                raise InvalidPurchaseOrderState(
                    f"PO #{po.pk} is {po.status}: only a DRAFT can be placed."
                )
            po.status = PurchaseOrder.Status.ORDERED
            po.save(update_fields=["status", "updated_at"])
            audit_request(
                request,
                AuditLog.ActionType.UPDATE,
                f"Purchase order #{po.pk} placed with {po.supplier.company_name}.",
            )
        return Response(self.get_serializer(po).data)

    @action(detail=True, methods=["post"])
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
                PurchaseOrder.Status.PARTIAL,
                PurchaseOrder.Status.COMPLETE,
            ):
                raise PurchaseOrderHasReceipts(po)
            if (
                po.status != PurchaseOrder.Status.DRAFT
                and po.status != PurchaseOrder.Status.ORDERED
            ):
                raise InvalidPurchaseOrderState(
                    f"PO #{po.pk} is {po.status} and cannot be cancelled."
                )
            if po.receipts.exists() or po.items.filter(received_qty__gt=0).exists():
                raise PurchaseOrderHasReceipts(po)
            po.status = PurchaseOrder.Status.CANCELLED
            po.save(update_fields=["status", "updated_at"])
            audit_request(
                request,
                AuditLog.ActionType.UPDATE,
                f"Purchase order #{po.pk} cancelled ({po.supplier.company_name}).",
            )
        return Response(self.get_serializer(po).data)


def _line_units(base_qty, factor):
    """`base_qty` said in a receipt line's PACKAGE unit, 2dp HALF_UP.

    The returnable report and the return POST speak two units: the clerk enters BAGs,
    stock is kept in base units. Converting back for the report uses the same rounding the
    money columns use, so "0.5 BAG still returnable" is the number the POST will accept.
    """
    from decimal import ROUND_HALF_UP, Decimal

    cent = Decimal("0.01")
    return (base_qty / factor).quantize(cent, rounding=ROUND_HALF_UP)


class _ReceiptRefused(Exception):
    """A receipt the server refuses to record; `str(exc)` is the client's detail.

    Exists so the over-order cap can be raised FROM INSIDE the atomic block — where the
    POItem row is locked and `received_qty` is trustworthy — and still leave as a plain
    400. Returning a Response from inside the block would commit it; raising rolls back
    the receipt row and every accumulated quantity first, and this class is caught one
    line later. Deliberately not a `ValueError`: nothing outside this view catches it.
    """


class GoodsReceiptViewSet(_StockRecordBaseViewSet):
    queryset = (
        GoodsReceipt.objects.select_related(
            "po",
            "received_by",
        )
        .prefetch_related("batches", "lines__po_item__variant", "lines__location")
        .all()
    )
    serializer_class = GoodsReceiptSerializer

    def create(self, request, *args, **kwargs):
        """Record a receipt, optionally carrying received quantities.

        `items: [{po_item, qty}]` does two things, and both matter:

        * adds `qty` to `POItem.received_qty` — the running total across every receipt of
          the PO, and the cap the next delivery is checked against; and
        * writes one `GoodsReceiptItem` per entry WITH a positive `qty`, so `process/`
          can batch THIS delivery instead of the running total (decision 09 item 4).

        `qty` is counted in the PO LINE's selling unit (`POItem.variant_uom`, Phase 5 B1),
        which is the same unit `ordered_qty` and `received_qty` are in. A line with no unit
        (a fixture-written row) is read as the variant's base unit, which is what every
        pre-B1 delivery meant. `process/` converts to stock in base units, and a `qty`
        whose conversion is not a whole hundredth of a base unit is refused here with
        `400 RECEIPT_QUANTITY_UNREPRESENTABLE`: stock is never rounded.

        The two are deliberately not the same field. Before the lines existed, process/
        had only `received_qty` to work from and minted a batch from it on every receipt —
        deliveries of 5 then 2 stocked 12 units for 7 received.

        `received_qty` has no other API write path (Task 6B.2).
        """
        from decimal import Decimal

        from rest_framework import status as drf_status

        from .models import POItem

        data = dict(request.data)
        raw_items = data.pop("items", [])
        if raw_items is None:
            raw_items = []
        if not isinstance(raw_items, list):
            return Response(
                {"detail": "items must be a list of {po_item, qty}."},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        ser = self.get_serializer(data=data)
        ser.is_valid(raise_exception=True)

        po = ser.validated_data["po"]
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
        # (po_item_id, qty, location_id) — one entry per delivered line, in payload order
        parsed = []
        for entry in raw_items:
            if not isinstance(entry, dict):
                return Response(
                    {"detail": "each item must be {po_item, qty, location?}."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            try:
                po_item = POItem.objects.select_related(
                    "po",
                    "variant__base_uom",
                    "variant__product__stored_at",
                    "variant_uom__uom",
                ).get(pk=entry.get("po_item"))
            except (POItem.DoesNotExist, ValueError, TypeError):
                return Response(
                    {"detail": f"unknown po_item: {entry.get('po_item')!r}."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            if po_item.po_id != po.id:
                return Response(
                    {"detail": f"po_item {po_item.pk} is not on this PO."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            try:
                qty = Decimal(str(entry.get("qty", 0)))
            except Exception:
                return Response(
                    {"detail": f"qty for po_item {po_item.pk} is not a number."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            if qty < 0:
                return Response(
                    {"detail": f"qty for po_item {po_item.pk} must not be negative."},
                    status=drf_status.HTTP_400_BAD_REQUEST,
                )
            # Phase 1d Task 2 (decision 16, Q1) + Phase 5 B1 (decision 18): a delivery is
            # counted in the PO LINE's selling unit, and a whole one (a BAG) takes whole
            # counts only while a measured one (the KG base unit) still takes 2.5. Raised
            # outside the atomic block below, so the refusal leaves no receipt row behind;
            # the project's handler turns it into a 400 `WHOLE_UNIT_QUANTITY`.
            unit = po_item.variant_uom
            unit_code = (
                unit.uom.code if unit is not None else po_item.variant.base_uom.code
            )
            refuse_fractional_whole_unit(
                is_whole=(
                    unit.uom.is_whole
                    if unit is not None
                    else po_item.variant.base_uom.is_whole
                ),
                qty=qty,
                what=f"po_item {po_item.pk} ({po_item.variant} in {unit_code})",
            )
            # Phase 5 B1 review fix: the converted stock must FIT the batch column's two
            # decimals, or the delivery is refused here - same place, same reason
            # (nothing written yet, `process/` would round it away). A legit factor-0.01
            # unit receiving 0.01 was stocked as 0.00 and 0.50 x 0.03 as 0.02.
            refuse_unrepresentable_stock(item=po_item, qty=qty)

            # Phase 9 B3 (decision 21, plan Design 7): the receiver may send the line
            # SOMEWHERE. Omitted = the variant's home, which is where every delivery went
            # before this phase. An inactive location is refused outside the atomic block,
            # so the refusal leaves no receipt row and no `received_qty` change.
            location_id = entry.get("location")
            if location_id is None:
                location_id = po_item.variant.product.stored_at_id
            else:
                try:
                    chosen = StorageLocation.objects.get(pk=location_id)
                except (StorageLocation.DoesNotExist, ValueError, TypeError):
                    return Response(
                        {
                            "code": "INVALID_STORAGE_LOCATION",
                            "detail": (
                                f"location for po_item {po_item.pk} is not a storage "
                                f"location: {location_id!r}."
                            ),
                        },
                        status=drf_status.HTTP_400_BAD_REQUEST,
                    )
                if not chosen.is_active:
                    return Response(
                        {
                            "code": "INVALID_STORAGE_LOCATION",
                            "detail": (
                                f"{chosen.name} is deactivated and cannot take "
                                "deliveries: choose an active location for the line, or "
                                "have the location reactivated."
                            ),
                        },
                        status=drf_status.HTTP_400_BAD_REQUEST,
                    )
                location_id = chosen.pk
            parsed.append((po_item.pk, qty, location_id))

        try:
            with transaction.atomic():
                # Phase 9 B3 (plan Design 11/12): the destination shelves are locked
                # FIRST, in PK order, and the active check is repeated under that lock -
                # otherwise an Admin deactivating the Bodega between the check above and
                # the receipt row below would receive into a closed place. A deactivated
                # destination is a 400 with nothing written, like the unlocked check.
                wanted = sorted({entry[2] for entry in parsed})
                destinations = {
                    location.pk: location
                    for location in StorageLocation.objects.select_for_update()
                    .filter(pk__in=wanted)
                    .order_by("pk")
                }
                for location_id in wanted:
                    if not destinations[location_id].is_active:
                        raise InvalidStorageLocation(
                            f"{destinations[location_id].name} is deactivated and "
                            "cannot take deliveries: choose an active location for the "
                            "line, or have the location reactivated."
                        )
                # Locked BEFORE the status is decided, so this receipt and `cancel/`
                # serialize: the cancel either sees this receipt (and refuses with
                # PO_HAS_RECEIPTS) or waits here until the receipt is committed.
                po = PurchaseOrder.objects.select_for_update().get(pk=po_id)
                if po.status == PurchaseOrder.Status.DRAFT:
                    raise PurchaseOrderNotOrdered(po)
                if po.status in (
                    PurchaseOrder.Status.COMPLETE,
                    PurchaseOrder.Status.CANCELLED,
                ):
                    raise PurchaseOrderNotReceivable(
                        f"PO {po.pk} is {po.status} and cannot receive more."
                    )
                receipt = ser.save(received_by=request.user)
                for po_item_pk, qty, location_id in parsed:
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
                            f"qty for po_item {locked.pk} would exceed the "
                            f"ordered {locked.ordered_qty} "
                            f"({locked.received_qty} already received)."
                        )
                    locked.received_qty = total
                    locked.save(update_fields=["received_qty"])
                    if qty > 0:
                        GoodsReceiptItem.objects.create(
                            receipt=receipt,
                            po_item=locked,
                            qty=qty,
                            location_id=location_id,
                        )
        except _ReceiptRefused as exc:
            # Raised inside the atomic block, so the receipt row and every accumulated
            # quantity are rolled back with it — a refused delivery leaves no trace.
            return Response(
                {"detail": str(exc)}, status=drf_status.HTTP_400_BAD_REQUEST
            )
        return Response(
            self.get_serializer(receipt).data, status=drf_status.HTTP_201_CREATED
        )

    @action(detail=True, methods=["post"])
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
                    f"Goods receipt #{receipt.pk} processed into "
                    f"{len(batches)} batch(es) for PO #{receipt.po_id}.",
                )
        except ReceiptAlreadyProcessed as exc:
            # Same 400 and same sentence the view-level guard used to answer with; the
            # added `code` is what lets a client tell this apart from a bad payload.
            return Response(
                {"code": exc.code, "detail": str(exc)},
                status=drf_status.HTTP_400_BAD_REQUEST,
            )
        return Response(InventoryBatchSerializer(batches, many=True).data)

    @action(detail=True, methods=["get"])
    def returnable(self, request, pk=None):
        """`GET /goods-receipts/{id}/returnable/` — what this delivery can still give back.

        One row per receipt LINE, every quantity in THAT line's package unit (a BAG line
        answers in bags, a BOX line in boxes), because the return dialog shows the clerk
        the unit the delivery was recorded in.

            delivered   what the line brought in
            returned    what past returns already took off this line
            returnable  min(delivered - returned, this receipt's batches' current qty)

        The second half of the min is the honest one: a delivery whose bags have since
        been sold (or written off) cannot give back what it no longer has, and the POST
        refuses exactly that with `RETURN_EXCEEDS_RECEIPT`.

        `IsInventoryRole` (via `_InventoryWritePermissions`): an action is a write-side
        route, and supplier stock is not till data - a Cashier and the CPMS account are
        refused.
        """
        from decimal import Decimal

        from django.db.models import Sum

        receipt = self.get_object()
        rows = []
        for line in receipt.lines.select_related(
            "po_item__variant__base_uom", "po_item__variant_uom__uom"
        ).order_by("id"):
            item = line.po_item
            factor = line_factor(item)
            returned_base = SupplierReturnLine.objects.filter(
                receipt_line=line
            ).aggregate(total=Sum("base_qty")).get("total") or Decimal(0)
            on_hand_base = InventoryBatch.objects.filter(
                receipt=receipt, variant=item.variant
            ).aggregate(total=Sum("current_qty")).get("total") or Decimal(0)
            returnable_base = min(
                line.qty * factor - returned_base,
                on_hand_base,
            )
            rows.append(
                {
                    "receipt_line": line.pk,
                    "variant": item.variant_id,
                    "variant_name": str(item.variant),
                    "unit": (
                        item.variant_uom.uom.code
                        if item.variant_uom_id
                        else item.variant.base_uom.code
                    ),
                    "delivered": f"{_line_units(line.qty * factor, factor):.2f}",
                    "returned": f"{_line_units(returned_base, factor):.2f}",
                    "returnable": f"{_line_units(returnable_base, factor):.2f}",
                }
            )
        return Response(rows)


class InventoryBatchViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = InventoryBatch.objects.select_related(
        "variant", "receipt", "location"
    ).all()
    serializer_class = InventoryBatchSerializer
    permission_classes = [IsAuthenticated]


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def stock_on_hand_view(request):
    """`GET /api/v1/stock-on-hand/` — how much of each variant sits at each location.

    Phase 9 B1 (decision 21 §5). Clients used to sum `/batches/` themselves to answer "how
    many do we have"; with stock per shelf that sum is the whole shop's problem, so the
    server answers it in ONE grouped query:

        [{variant, location, location_name, location_active, is_home, qty}, ...]

    `is_home` is `location == variant.product.stored_at` (decision 21 §1: `Stored at` is
    the home shelf), which is what the till needs to take home stock first. `?variant=`
    narrows the read to one variant's shelves. Exhausted batches add no 0.00 row: only
    live stock is counted (`current_qty > 0`), the same filter the valuation uses.

    Readable by ANY authenticated user, the rule `/batches/` follows: the till, the
    low-stock page and the dashboards all need it, and none of them may write.
    """
    rows = InventoryBatch.objects.filter(current_qty__gt=0)
    variant = request.query_params.get("variant")
    if variant:
        try:
            rows = rows.filter(variant_id=int(variant))
        except ValueError:
            return Response(
                {
                    "code": "INVALID_VARIANT",
                    "detail": f"?variant= must be a variant id, got {variant!r}.",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
    grouped = (
        rows.values(
            "variant",
            "location",
            "location__name",
            "location__is_active",
            home=F("variant__product__stored_at_id"),
        )
        .annotate(qty=Sum("current_qty"))
        .order_by("variant", "location")
    )
    return Response(
        [
            {
                "variant": row["variant"],
                "location": row["location"],
                "location_name": row["location__name"],
                "location_active": row["location__is_active"],
                "is_home": row["location"] == row["home"],
                # Text like every other quantity this API emits (DRF serializes a
                # DecimalField to a string); a raw Decimal would reach the client as a
                # float.
                "qty": f"{row['qty']:.2f}",
            }
            for row in grouped
        ]
    )


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

    queryset = StockAdjustment.objects.select_related(
        "variant", "user", "location"
    ).all()
    serializer_class = StockAdjustmentSerializer

    def perform_create(self, serializer):
        # `with` on transaction.atomic() is a verified false positive: pyright cannot pick
        # the context-manager overload without stubs, and the same idiom at 5 pre-existing
        # sites is flagged identically. Ignored at the LINE, so the rule still guards every
        # other line in this file.
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            # Phase 9 B3 (decision 21, plan Design 8/12): the count names a SHELF - the
            # client's optional `location`, else the variant's home, which is what every
            # adjustment meant before this phase. The row is locked FIRST (Design 12 a),
            # so an Admin deactivation racing this write cannot slip between the check and
            # the stock move.
            variant = serializer.validated_data["variant"]
            qty = serializer.validated_data["qty_adjusted"]
            chosen = serializer.validated_data.get("location") or (
                variant.product.stored_at
            )
            location = StorageLocation.objects.select_for_update().get(pk=chosen.pk)
            # An INACTIVE shelf refuses ADDITIONS: nothing may be put into a place the
            # shop has closed. Removals stay allowed - stock that is already there must
            # remain manageable OUT (plan Design 11). Refused before the row is saved, so
            # a refused adjustment leaves no adjustment row and no audit row.
            if qty > 0 and not location.is_active:
                raise InvalidStorageLocation(
                    f"{location.name} is deactivated and cannot take stock: choose an "
                    "active location for this correction."
                )
            adj = serializer.save(user=self.request.user, location=location)
            apply_stock_adjustment(adjustment=adj)
            # Same block, so a refused adjustment (no batch history, negative beyond
            # stock) writes no audit row (decision 07).
            audit_request(
                self.request,
                AuditLog.ActionType.STOCK_ADJUST,
                f"Stock adjustment #{adj.pk} {adj.adjustment_type} "
                f"{adj.qty_adjusted} on {adj.variant}.",
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

    queryset = SystemAlert.objects.select_related("variant", "resolved_by").all()
    serializer_class = SystemAlertSerializer

    def get_permissions(self):
        # `resolve` is the only write on this viewset; everything else it can reach is a
        # read (the viewset itself no longer registers create/update/destroy).
        if self.action == "resolve":
            return [IsInventoryRole()]
        return [IsAuthenticated()]

    @action(detail=True, methods=["post"])
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
            alert = SystemAlert.objects.select_for_update().filter(pk=pk).first()
            if alert is None:
                raise Http404
            if alert.is_resolved:
                return Response(
                    {
                        "code": "ALERT_ALREADY_RESOLVED",
                        "detail": f"Alert {alert.pk} was already resolved.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            alert.is_resolved = True
            alert.resolved_by = request.user
            alert.resolved_at = timezone.now()
            alert.save(update_fields=["is_resolved", "resolved_by", "resolved_at"])
            # Inside the same block as the write (decision 07): the refused second
            # resolve returns above, so it writes no second row.
            audit_request(
                request,
                AuditLog.ActionType.ALERT_RESOLVE,
                f"Alert #{alert.pk} ({alert.alert_type}) resolved.",
            )

        # `dict(...)` copy, not the ReturnDict itself: the serializer's `.data` is typed
        # as index-only by pyright without django-stubs, but a plain dict accepts the
        # legacy `detail` key below.
        data = dict(SystemAlertSerializer(alert).data)
        data["detail"] = "Alert resolved."
        return Response(data)


# =========================================================================
# Supplier payables  (Phase 5 B2, decision 18)
# =========================================================================


class SupplierBillViewSet(viewsets.ReadOnlyModelViewSet):
    """`/supplier-bills/` — what the shop owes, one row per processed receipt.

    **Read-only on purpose.** A bill is written by `process_goods_receipt` inside the
    transaction that stocks the delivery; there is no create, no edit and no delete verb
    for any role, Admin included. `ReadOnlyModelViewSet` does not even map them, so a
    `POST`/`PATCH`/`DELETE` answers **405**, and nothing can rewrite what the shop agreed
    to owe.

    **Who reads it.** `IsInventoryRole` (Stock Manager / Store Manager / Admin): the
    stocker must see what a delivery costs, while a Cashier and the CPMS service account
    are refused - supplier money is not till data and is not part of the CPMS contract.

    Filters: `?supplier=<id>`, `?status=UNPAID|PARTIAL|PAID`, `?overdue=true`. Ordering
    is by due date (oldest first), so a payables screen opens on what is due soonest -
    the overdue rows are the oldest ones.
    """

    queryset = (
        SupplierBill.objects.select_related("supplier", "purchase_order")
        .prefetch_related("payments__paid_by")
        .all()
    )
    serializer_class = SupplierBillSerializer
    permission_classes = [IsInventoryRole]  # noqa: RUF012 - declarative, never mutated

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params

        supplier = params.get("supplier")
        if supplier:
            queryset = queryset.filter(supplier_id=supplier)

        status = (params.get("status") or "").upper()
        if status:
            if status not in SupplierBill.Status.values:
                from rest_framework.exceptions import ValidationError

                raise ValidationError(
                    {
                        "status": (
                            f"status must be one of "
                            f"{', '.join(SupplierBill.Status.values)}."
                        )
                    }
                )
            if status == SupplierBill.Status.PAID:
                queryset = queryset.filter(balance_amount__lte=0)
            elif status == SupplierBill.Status.UNPAID:
                queryset = queryset.filter(balance_amount__gte=F("total_amount"))
            else:
                queryset = queryset.filter(
                    balance_amount__gt=0, balance_amount__lt=F("total_amount")
                )

        overdue = (params.get("overdue") or "").lower()
        if overdue in ("1", "true", "yes"):
            queryset = queryset.filter(
                balance_amount__gt=0, due_date__lt=timezone.localdate()
            )
        return queryset


class SupplierPaymentViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """`/supplier-payments/` — record a payment, read the history, decide a cheque.

    **Store Manager / Admin pay and decide; Stock Manager reads.** The stocker sees what
    is owed and what was paid, but moving money is a manager's act (`IsManagerRole`) - and
    so is deciding whether the bank honoured a supplier cheque (`clear/`, `bounce/`, Phase
    8 B1). A Cashier and the CPMS account are refused entirely.

    **No edit and no delete for any role.** `PUT`/`PATCH`/`DELETE` answer **405**:
    `http_method_names` removes the verbs, so the router keeps the routes and DRF refuses
    before any object lookup. A payment records money that already left the shop;
    correcting one is another business event, not an edit.

    The payment, the bill's new balance and the `PAYMENT` audit row are ONE transaction.
    The service takes the bill's row lock before deciding, so two clerks (or one
    double-clicked button) cannot both spend the same balance - the loser is told
    `BILL_PAID` (or `OVERPAYMENT`), and a failure anywhere rolls all three back.
    """

    queryset = SupplierPayment.objects.select_related(
        "bill__supplier", "paid_by", "decided_by"
    ).all()
    serializer_class = SupplierPaymentSerializer
    http_method_names = ("get", "head", "options", "post")

    def get_permissions(self):
        # Phase 8 B1 (decision 20 #3): deciding a cheque moves the shop's debt, so it is a
        # manager's act exactly as recording the payment was.
        if self.action in ("create", "clear", "bounce"):
            return [IsManagerRole()]
        return [IsInventoryRole()]

    def get_queryset(self):
        queryset = super().get_queryset()
        # `clear/` and `bounce/` are cheque decisions only, so their lookup is confined to
        # cheques: a payment id that is not a cheque is a plain 404, and these actions can
        # never reach into an ordinary tender.
        if self.action in ("clear", "bounce"):
            queryset = queryset.filter(method=SupplierPayment.Method.CHEQUE)
        params = self.request.query_params
        bill = params.get("bill")
        if bill:
            queryset = queryset.filter(bill_id=bill)
        supplier = params.get("supplier")
        if supplier:
            queryset = queryset.filter(bill__supplier_id=supplier)
        # Phase 8 B1: the cheque queue reads `?status=ISSUED`; the bills screen reads the
        # decided ones. An unknown value is a 400, not a silent empty list - a typo must
        # not read as "no cheques waiting".
        status_filter = (params.get("status") or "").upper()
        if status_filter:
            if status_filter not in SupplierPayment.Status.values:
                from rest_framework.exceptions import ValidationError

                raise ValidationError(
                    {
                        "status": (
                            f"status must be one of "
                            f"{', '.join(SupplierPayment.Status.values)}."
                        )
                    }
                )
            queryset = queryset.filter(status=status_filter)
        return queryset

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            if data["method"] == SupplierPayment.Method.CREDIT:
                # Phase 8 B4: applying supplier credit by hand. Its own service because
                # the note's `remaining_amount` moves with the bill's balance, under the
                # note's lock first - the same order the auto rule takes.
                payment = apply_supplier_credit(
                    note=data["credit_note"],
                    bill=data["bill"],
                    amount=data["amount"],
                    user=request.user,
                )
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f"Credit note {payment.credit_note.number} applied {payment.amount} "
                    f"to bill #{payment.bill_id} "
                    f"({payment.bill.supplier.company_name}); "
                    f"{payment.credit_note.remaining_amount} left as supplier credit.",
                )
            else:
                payment = record_supplier_payment(
                    bill=data["bill"],
                    amount=data["amount"],
                    method=data["method"],
                    reference=data.get("reference", ""),
                    cheque_number=data.get("cheque_number", ""),
                    cheque_bank=data.get("cheque_bank", ""),
                    cheque_date=data.get("cheque_date"),
                    user=request.user,
                )
                # Same block as the payment and the moved balance (decision 07): a failed
                # audit row rolls the money back instead of leaving an unaudited payment.
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f"Supplier payment #{payment.pk} of {payment.amount} "
                    f"({payment.method}) against bill #{payment.bill_id} for "
                    f"{payment.bill.supplier.company_name}.",
                )
        return Response(
            self.get_serializer(payment).data, status=status.HTTP_201_CREATED
        )

    @action(detail=True, methods=["post"])
    def clear(self, request, pk=None):
        """POST /supplier-payments/{id}/clear/ -> the bank honoured it; nothing moves."""
        return self._decide(request, SupplierPayment.Status.CLEARED)

    @action(detail=True, methods=["post"])
    def bounce(self, request, pk=None):
        """POST /supplier-payments/{id}/bounce/ {reason} -> the amount goes back on the bill."""
        return self._decide(request, SupplierPayment.Status.BOUNCED)

    def _decide(self, request, decision):
        # Resolved through `self.get_object()`, i.e. the CHEQUE-filtered queryset, so a
        # payment id that is not a cheque is a 404 rather than a decision on cash.
        cheque = self.get_object()
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            cheque = decide_supplier_cheque(
                payment_id=cheque.pk,
                decision=decision,
                user=request.user,
                reason=request.data.get("reason", ""),
            )
            # Decision 07: the decision and its audit row are one transaction, so a failed
            # audit leaves neither a status nor a moved balance. The description names the
            # cheque, the bill, the money and the reason - the trail answers "which cheque,
            # how much, why" without opening the bill.
            audit_request(
                request,
                AuditLog.ActionType.CHEQUE_DECISION,
                f"Supplier cheque {cheque.cheque_number or '(no number)'} for "
                f"{cheque.amount} against bill #{cheque.bill_id} "
                f"({cheque.bill.supplier.company_name}) marked {decision} by "
                f"{request.user.username}"
                + (f" ({cheque.decision_reason})." if cheque.decision_reason else "."),
            )
        return Response(self.get_serializer(cheque).data)


# =========================================================================
# Supplier credit notes  (Phase 8 B4, decision 20 #1)
# =========================================================================


class SupplierCreditNoteViewSet(viewsets.ReadOnlyModelViewSet):
    """`/supplier-credit-notes/` — the numbered credit a supplier owes the shop.

    A note is minted by a supplier return (B3) and spent by a CREDIT payment, either
    automatically on its own bill or by hand (B4). This route set exists so the payables
    screen can offer the notes a manager may still spend: `?open=true` narrows to
    `remaining_amount > 0`, and `?supplier=<id>` to one supplier's notes.

    **Read-only for every role** (`ReadOnlyModelViewSet` maps no write verb, so POST/PUT/
    PATCH/DELETE answer **405**): the credit was priced when the goods went back, and the
    only thing that ever moves is `remaining_amount`, through `apply_supplier_credit`.

    **Who reads it.** `IsInventoryRole` (Stock Manager / Store Manager / Admin), matching
    the returns and bills it belongs to; a Cashier and the CPMS account are refused.
    """

    queryset = SupplierCreditNote.objects.select_related(
        "supplier", "source_bill"
    ).all()
    serializer_class = SupplierCreditNoteSerializer
    permission_classes = [IsInventoryRole]  # noqa: RUF012 - declarative, never mutated

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        supplier = params.get("supplier")
        if supplier:
            queryset = queryset.filter(supplier_id=supplier)
        # `?open=true` is the apply-credit picker: a spent note would offer 0.00.
        if (params.get("open") or "").lower() in ("1", "true", "yes"):
            queryset = queryset.filter(remaining_amount__gt=0)
        return queryset


# =========================================================================
# Supplier returns  (Phase 8 B2, decision 20)
# =========================================================================


class SupplierReturnViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """`/supplier-returns/` — send goods back to a supplier, read the history.

    **Stock Manager / Store Manager / Admin record and read alike** (decision 20 #4): the
    stocker is the person who finds the damaged bags at the gate, and the return is the
    act that takes them off the rack. A Cashier and the CPMS account are refused - a
    supplier return is not till data and not part of the CPMS contract.

    **No edit and no delete for any role** (405): a return is the evidence of stock that
    already moved, so a mistake is corrected by a new business event. The return row, its
    lines, the deductions that name each batch, the moved `current_qty`, the low-stock
    check and the `SUPPLIER_RETURN` audit row are ONE transaction - a refused return
    leaves nothing behind.

    Filters: `?supplier=<id>`, `?receipt=<id>`.
    """

    queryset = (
        SupplierReturn.objects.select_related(
            "receipt", "supplier", "purchase_order", "bill", "created_by"
        )
        .prefetch_related("lines__deductions")
        .all()
    )
    serializer_class = SupplierReturnSerializer
    permission_classes = [IsInventoryRole]  # noqa: RUF012 - declarative, never mutated
    http_method_names = ("get", "head", "options", "post")

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        supplier = params.get("supplier")
        if supplier:
            queryset = queryset.filter(supplier_id=supplier)
        receipt = params.get("receipt")
        if receipt:
            queryset = queryset.filter(receipt_id=receipt)
        return queryset

    def create(self, request, *args, **kwargs):
        """`POST /supplier-returns/` `{receipt, reason, lines:[{receipt_line, qty}]}`.

        The body is validated for SHAPE here; every business rule lives in
        `record_supplier_return`, which is the only writer, so the ORM path cannot skip
        one. The service owns its own `atomic` (the batch row locks need one); this adds
        the audit row to the same block, so a failed audit rolls the return and the moved
        stock back with it (decision 07).
        """
        serializer = SupplierReturnCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # Typing-only cast: `SupplierReturnCreateSerializer` is a plain Serializer,
        # so pyright reads `validated_data` as DRF's untyped `empty`. Runtime is the
        # dict ValidateMixin builds; nothing here changes at run time.
        data = cast(dict, serializer.validated_data)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            supplier_return = record_supplier_return(
                receipt=data["receipt"],
                reason=data.get("reason", ""),
                lines=[(line["receipt_line"], line["qty"]) for line in data["lines"]],
                user=request.user,
            )
            # Phase 8 B3 (decision 20 #1): the stock has moved, so the return is worth a
            # numbered credit note - and that note immediately lowers the bill the goods
            # came in on. Both happen in THIS block, so stock can never go back without
            # the credit that prices it, and a note whose application failed does not
            # survive on its own.
            credit_note = create_credit_note_for_return(supplier_return=supplier_return)
            credit_payment = apply_credit_to_source_bill(
                note=credit_note, user=request.user
            )
            if credit_payment is not None:
                # The note created above is CACHED on the return instance, so reading it
                # again would describe the credit as it was minted, not as the payment
                # just left it. Drop that cache: the response and the two audit sentences
                # must agree with the ledger, or the screen and the trail would both claim
                # credit that has already been spent.
                supplier_return.refresh_from_db()
                credit_note = supplier_return.credit_note
            audit_request(
                request,
                AuditLog.ActionType.SUPPLIER_RETURN,
                f"Supplier return #{supplier_return.pk}: {len(data['lines'])} line(s) "
                f"off goods receipt #{supplier_return.receipt_id} for "
                f"{supplier_return.supplier.company_name} "
                f"({supplier_return.reason}). Credit note {credit_note.number} for "
                f"{credit_note.total_amount}.",
            )
            if credit_payment is not None:
                # Decision 20 #1: applying credit is a PAYMENT event, so the money trail
                # answers "how was this bill settled" in one place.
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f"Credit note {credit_note.number} applied {credit_payment.amount} "
                    f"to bill #{credit_payment.bill_id} "
                    f"({supplier_return.supplier.company_name}); "
                    f"{credit_note.remaining_amount} left as supplier credit.",
                )
        return Response(
            self.get_serializer(supplier_return).data,
            status=status.HTTP_201_CREATED,
        )


# =========================================================================
# Stock transfers  (Phase 9 B4, decision 21 §3)
# =========================================================================


class StockTransferViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    """`/stock-transfers/` — move stock between shelves, read the numbered slips.

    **Stock Manager / Store Manager / Admin record and read alike** (decision 21), the same
    fence as an adjustment: moving goods between shelves is the stocker's act, and a
    Cashier has no business rewriting where stock sits.

    **No edit and no delete for any role** (405): the stock already moved, so the slip is
    the evidence of it. A mistake is corrected by a transfer in the other direction, never
    by editing this one.

    Filters: `?from_location=<id>`, `?to_location=<id>`.
    """

    queryset = StockTransfer.objects.select_related(
        "from_location", "to_location", "user"
    ).prefetch_related("lines__moves", "lines__variant_uom__uom")
    serializer_class = StockTransferSerializer
    permission_classes = [IsInventoryRole]  # noqa: RUF012 - declarative, never mutated
    http_method_names = ("get", "head", "options", "post")

    def get_queryset(self):
        queryset = super().get_queryset()
        params = self.request.query_params
        source = params.get("from_location")
        if source:
            queryset = queryset.filter(from_location_id=source)
        destination = params.get("to_location")
        if destination:
            queryset = queryset.filter(to_location_id=destination)
        return queryset

    def create(self, request, *args, **kwargs):
        """`POST /stock-transfers/` `{from_location, to_location, remarks?, lines:[…]}`.

        The body is validated for SHAPE here; every business rule lives in
        `record_stock_transfer`, the only writer, so the ORM path cannot skip one. The
        service owns the `atomic` block (the destination lock and the batch locks need
        one); this keeps the audit row in the SAME block, so a failed audit rolls the
        moved stock back with it (decision 07).
        """
        serializer = StockTransferCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # Typing-only cast: `StockTransferCreateSerializer` is a plain Serializer, so
        # pyright reads `validated_data` as DRF's untyped `empty`. Runtime is the dict
        # ValidateMixin builds.
        data = cast(dict, serializer.validated_data)
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            transfer = record_stock_transfer(
                from_location=data["from_location"],
                to_location=data["to_location"],
                lines=[(line["variant_uom"], line["qty"]) for line in data["lines"]],
                user=request.user,
                remarks=data.get("remarks", ""),
            )
            audit_request(
                request,
                AuditLog.ActionType.STOCK_TRANSFER,
                f"Stock transfer {transfer.number}: "
                f"{len(data['lines'])} line(s) moved from "
                f"{transfer.from_location.name} to {transfer.to_location.name}"
                + (f" ({transfer.remarks})." if transfer.remarks else "."),
            )
        return Response(
            self.get_serializer(transfer).data, status=status.HTTP_201_CREATED
        )
