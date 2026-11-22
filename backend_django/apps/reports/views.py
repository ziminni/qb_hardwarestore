# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
"""Reports app — read-only aggregation endpoints for the admin Reports page.

No models: every view aggregates data from the other apps
(pos, inventory, requisitions).  Managerial reports require
Store Manager / Admin (IsManagerRole).

Endpoints (mounted under /api/v1/reports/):
    GET /reports/sales-summary/?from=YYYY-MM-DD&to=YYYY-MM-DD
    GET /reports/inventory-valuation/
    GET /reports/stock-movements/?from=YYYY-MM-DD&to=YYYY-MM-DD
    GET /reports/requisition-history/?status=&from=&to=
"""

from datetime import date, timedelta
from decimal import Decimal

from django.db.models import Count, DecimalField, ExpressionWrapper, F, Q, Sum
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from apps.inventory.models import GoodsReceipt, InventoryBatch, StockAdjustment
from apps.pos.models import Payment, SalesItem, SalesItemDeduction, SalesTransaction
from apps.requisitions.models import Requisition
from apps.users.permissions import IsManagerRole

DEFAULT_RANGE_DAYS = 30
_ZERO = Decimal("0.00")
_CENT = Decimal("0.01")


def _q2(value: Decimal) -> Decimal:
    return value.quantize(_CENT)


def _delivery_fee_ex_vat(tx) -> Decimal:
    fee = tx.delivery_fee or _ZERO
    if fee == _ZERO:
        return _ZERO
    if tx.vat_registered and tx.vat_rate and tx.vat_rate > _ZERO:
        divisor = Decimal("1") + (tx.vat_rate / Decimal("100"))
        return _q2(fee / divisor)
    return _q2(fee)


def _parse_range(request):
    """Return (from_date, to_date) inclusive; defaults to last 30 days."""
    today = date.today()
    to = parse_date(request.query_params.get("to", "")) or today
    frm = parse_date(request.query_params.get("from", "")) or (
        to - timedelta(days=DEFAULT_RANGE_DAYS)
    )
    if frm > to:
        frm, to = to, frm
    return frm, to


def _range_error():
    return Response(
        {"detail": "Invalid date. Use YYYY-MM-DD for from/to."},
        status=status.HTTP_400_BAD_REQUEST,
    )


@api_view(["GET"])
@permission_classes([IsManagerRole])
def sales_summary_view(request):
    """Daily sales totals for the given range (completed transactions).

    GET /api/v1/reports/sales-summary/?from=&to=
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    qs = SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED,
        trans_date__date__range=(frm, to),
    )
    by_day_rows = list(
        qs.annotate(day=F("trans_date__date"))
        .values("day")
        .annotate(
            transactions=Count("id"),
            gross_sales=Sum("grand_total"),
            vatable_sales=Sum("vatable_sales"),
            vat=Sum("vat_amount"),
            discounts=Sum("discount_amount"),
            payment_fees=Sum("payment_fee"),
            delivery_fees=Sum("delivery_fee"),
        )
        .order_by("day")
    )
    totals = qs.aggregate(
        transactions=Count("id"),
        gross_sales=Sum("grand_total"),
        # Phase 4 task B1 (decision 18): the Discounts row is back (D12 superseded), and
        # vatable sales joins it so the report agrees with the receipt: gross - discount
        # = net, and net = vatable + VAT. A return is a negative row, so VAT and discounts
        # net back out of the period they were reversed in.
        vatable_sales=Sum("vatable_sales"),
        vat=Sum("vat_amount"),
        discounts=Sum("discount_amount"),
        # Untaxed GCash/card fees, so gross = vatable + VAT + fees still reconciles.
        payment_fees=Sum("payment_fee"),
        delivery_fees=Sum("delivery_fee"),
    )

    # Delivery fees are VAT-inclusive when the store is VAT-registered; strip their VAT
    # share per transaction so merchandise_net_ex_vat reflects goods only.
    delivery_ex_vat_by_day: dict[date, Decimal] = {}
    total_delivery_ex_vat = _ZERO
    for tx in qs.exclude(delivery_fee=_ZERO).only(
        "trans_date", "delivery_fee", "vat_registered", "vat_rate"
    ):
        ex = _delivery_fee_ex_vat(tx)
        total_delivery_ex_vat += ex
        d = tx.trans_date.date()
        delivery_ex_vat_by_day[d] = delivery_ex_vat_by_day.get(d, _ZERO) + ex

    # Snapshotted landed COGS from SalesItemDeduction (migration pos 0022).
    # Rows with unit_cost=NULL predate cost snapshots and are tracked in cost_coverage
    # rather than silently treated as ₱0 cost.
    deductions = SalesItemDeduction.objects.filter(
        sales_item__transaction__status=SalesTransaction.Status.COMPLETED,
        sales_item__transaction__trans_date__date__range=(frm, to),
    )
    cost_expr = ExpressionWrapper(
        F("qty") * F("unit_cost"),
        output_field=DecimalField(max_digits=16, decimal_places=4),
    )
    coverage_agg = deductions.aggregate(
        costed=Count("id", filter=Q(unit_cost__isnull=False)),
        missing=Count("id", filter=Q(unit_cost__isnull=True)),
        total_cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
    )
    costed_count = coverage_agg["costed"] or 0
    missing_count = coverage_agg["missing"] or 0
    has_any_deductions = (costed_count + missing_count) > 0
    cogs_by_day_rows = (
        deductions.annotate(day=F("sales_item__transaction__trans_date__date"))
        .values("day")
        .annotate(
            cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
            costed=Count("id", filter=Q(unit_cost__isnull=False)),
            missing=Count("id", filter=Q(unit_cost__isnull=True)),
        )
    )
    cogs_by_day = {
        row["day"]: (
            _q2(row["cogs"]) if row["cogs"] is not None else _ZERO,
            row["costed"] or 0,
            row["missing"] or 0,
        )
        for row in cogs_by_day_rows
    }

    gross_sales_val = totals["gross_sales"] or _ZERO
    vatable_val = totals["vatable_sales"] or _ZERO
    discounts_val = totals["discounts"] or _ZERO
    payment_fees_val = totals["payment_fees"] or _ZERO
    delivery_fees_val = totals["delivery_fees"] or _ZERO

    merchandise_gross = _q2(
        gross_sales_val - delivery_fees_val - payment_fees_val + discounts_val
    )
    merchandise_net_ex_vat = _q2(vatable_val - total_delivery_ex_vat)

    if has_any_deductions and costed_count == 0:
        total_cogs = None
        gross_profit = None
        gross_margin_percent = None
        effective_markup_percent = None
    else:
        total_cogs = _q2(coverage_agg["total_cogs"] or _ZERO)
        gross_profit = _q2(merchandise_net_ex_vat - total_cogs)
        gross_margin_percent = (
            _q2((gross_profit / merchandise_net_ex_vat) * Decimal("100"))
            if merchandise_net_ex_vat > _ZERO
            else None
        )
        effective_markup_percent = (
            _q2((gross_profit / total_cogs) * Decimal("100"))
            if total_cogs > _ZERO
            else None
        )

    totals.update(
        {
            "merchandise_gross": merchandise_gross if totals["transactions"] else None,
            "merchandise_net_ex_vat": (
                merchandise_net_ex_vat if totals["transactions"] else None
            ),
            "cogs": total_cogs if totals["transactions"] else None,
            "gross_profit": gross_profit if totals["transactions"] else None,
            "gross_margin_percent": gross_margin_percent,
            "effective_markup_percent": effective_markup_percent,
        }
    )

    by_day = []
    for row in by_day_rows:
        d = row["day"]
        day_vatable = row["vatable_sales"] or _ZERO
        day_net_ex_vat = _q2(day_vatable - delivery_ex_vat_by_day.get(d, _ZERO))
        day_cogs_val, day_costed, day_missing = cogs_by_day.get(d, (_ZERO, 0, 0))
        if (day_costed + day_missing) > 0 and day_costed == 0:
            day_cogs = None
            day_profit = None
        else:
            day_cogs = day_cogs_val
            day_profit = _q2(day_net_ex_vat - day_cogs)
        row["merchandise_net_ex_vat"] = day_net_ex_vat
        row["cogs"] = day_cogs
        row["gross_profit"] = day_profit
        by_day.append(row)

    # Category-level breakdown for analytics charts: merchandise net (incl. discounts)
    # and snapshotted COGS per category.
    cat_sales_rows = (
        SalesItem.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
        )
        .values(
            "variant_uom__variant__product__category__id",
            "variant_uom__variant__product__category__name",
        )
        .annotate(
            gross_merchandise=Sum("subtotal"),
            item_discounts=Sum("item_discount_amount"),
            cart_discounts=Sum("cart_discount_amount"),
        )
    )
    cat_cogs_rows = (
        deductions.values(
            "sales_item__variant_uom__variant__product__category__id",
        )
        .annotate(
            cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
            costed=Count("id", filter=Q(unit_cost__isnull=False)),
            missing=Count("id", filter=Q(unit_cost__isnull=True)),
        )
    )
    cat_cogs_map = {
        row["sales_item__variant_uom__variant__product__category__id"]: (
            _q2(row["cogs"]) if row["cogs"] is not None else _ZERO,
            row["costed"] or 0,
            row["missing"] or 0,
        )
        for row in cat_cogs_rows
    }
    by_category = []
    for row in cat_sales_rows:
        cat_id = row["variant_uom__variant__product__category__id"]
        cat_name = row["variant_uom__variant__product__category__name"] or "Uncategorized"
        gross_m = _q2(row["gross_merchandise"] or _ZERO)
        disc_m = _q2((row["item_discounts"] or _ZERO) + (row["cart_discounts"] or _ZERO))
        net_m = _q2(gross_m - disc_m)
        c_cogs_val, c_costed, c_missing = cat_cogs_map.get(cat_id, (_ZERO, 0, 0))
        if (c_costed + c_missing) > 0 and c_costed == 0:
            c_cogs = None
        else:
            c_cogs = c_cogs_val
        by_category.append(
            {
                "category_id": cat_id,
                "category_name": cat_name,
                "gross_merchandise": gross_m,
                "discounts": disc_m,
                "net_merchandise": net_m,
                "cogs": c_cogs,
                "missing_cost_deductions": c_missing,
            }
        )
    by_category.sort(key=lambda r: r["net_merchandise"], reverse=True)

    # Phase 6 (2026-11-22): OR-backed (BIR invoice tagged) vs untagged OS VAT split,
    # payment-method breakdown, and daily/weekly/monthly period rollup.
    granularity = (request.query_params.get("granularity") or "day").strip().lower()
    if granularity not in ("day", "week", "month"):
        return Response(
            {"detail": "granularity must be day, week, or month."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    or_vat_breakdown = _or_vat_split(qs)
    by_payment_method = [
        {
            "method": row["method"],
            "transactions": row["transactions"],
            "total": _q2(row["total"] or _ZERO),
        }
        for row in (
            Payment.objects.filter(transaction__in=qs)
            .values("method")
            .annotate(
                transactions=Count("transaction_id", distinct=True),
                total=Sum("amount_tendered"),
            )
            .order_by("-total")
        )
    ]
    by_period = _group_transactions_by_period(qs, granularity)

    return Response(
        {
            "from": str(frm),
            "to": str(to),
            "granularity": granularity,
            "totals": totals,
            "or_vat_breakdown": or_vat_breakdown,
            "by_payment_method": by_payment_method,
            "cost_coverage": {
                "costed_deductions": costed_count,
                "missing_cost_deductions": missing_count,
                "complete": missing_count == 0,
            },
            "by_day": by_day,
            "by_period": by_period,
            "by_category": by_category,
        }
    )


def _period_key(day: date, granularity: str) -> str:
    if granularity == "month":
        return f"{day.year:04d}-{day.month:02d}"
    if granularity == "week":
        monday = day - timedelta(days=day.weekday())
        return monday.isoformat()
    return day.isoformat()


def _or_vat_split(qs):
    def _agg(sub):
        a = sub.aggregate(
            transactions=Count("id"),
            gross_sales=Sum("grand_total"),
            vatable_sales=Sum("vatable_sales"),
            vat=Sum("vat_amount"),
        )
        return {
            "transactions": a["transactions"] or 0,
            "gross_sales": _q2(a["gross_sales"] or _ZERO),
            "vatable_sales": _q2(a["vatable_sales"] or _ZERO),
            "vat": _q2(a["vat"] or _ZERO),
        }

    or_qs = qs.exclude(invoice_no="")
    untagged_qs = qs.filter(invoice_no="")
    return {
        "or_backed": _agg(or_qs),
        "untagged_os": _agg(untagged_qs),
        "combined": _agg(qs),
    }


def _group_transactions_by_period(qs, granularity: str):
    buckets: dict[str, dict] = {}
    for tx in qs.select_related(None).only(
        "trans_date",
        "grand_total",
        "vatable_sales",
        "vat_amount",
        "discount_amount",
        "invoice_no",
    ):
        key = _period_key(tx.trans_date.date(), granularity)
        b = buckets.setdefault(
            key,
            {
                "period": key,
                "transactions": 0,
                "gross_sales": _ZERO,
                "vatable_sales": _ZERO,
                "vat": _ZERO,
                "discounts": _ZERO,
                "or_backed_transactions": 0,
                "or_backed_sales": _ZERO,
                "or_backed_vatable": _ZERO,
                "or_backed_vat": _ZERO,
                "untagged_transactions": 0,
                "untagged_sales": _ZERO,
                "untagged_vatable": _ZERO,
                "untagged_vat": _ZERO,
            },
        )
        gross = tx.grand_total or _ZERO
        vatable = tx.vatable_sales or _ZERO
        vat = tx.vat_amount or _ZERO
        disc = tx.discount_amount or _ZERO
        b["transactions"] += 1
        b["gross_sales"] += gross
        b["vatable_sales"] += vatable
        b["vat"] += vat
        b["discounts"] += disc
        if tx.invoice_no:
            b["or_backed_transactions"] += 1
            b["or_backed_sales"] += gross
            b["or_backed_vatable"] += vatable
            b["or_backed_vat"] += vat
        else:
            b["untagged_transactions"] += 1
            b["untagged_sales"] += gross
            b["untagged_vatable"] += vatable
            b["untagged_vat"] += vat

    result = []
    for key in sorted(buckets.keys()):
        b = buckets[key]
        for k, v in list(b.items()):
            if isinstance(v, Decimal):
                b[k] = _q2(v)
        result.append(b)
    return result


@api_view(["GET"])
@permission_classes([IsManagerRole])
def vat_summary_view(request):
    """Daily / weekly / monthly VAT report split into OR-backed vs untagged OS.

    GET /api/v1/reports/vat-summary/?from=YYYY-MM-DD&to=YYYY-MM-DD&granularity=day|week|month
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    granularity = (request.query_params.get("granularity") or "day").strip().lower()
    if granularity not in ("day", "week", "month"):
        return Response(
            {"detail": "granularity must be day, week, or month."},
            status=status.HTTP_400_BAD_REQUEST,
        )
    frm, to = _parse_range(request)
    qs = SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED,
        trans_date__date__range=(frm, to),
    ).select_related("customer", "receipt")

    or_transactions = [
        {
            "id": tx.id,
            "transaction_no": tx.transaction_no,
            "or_number": tx.receipt.or_number if hasattr(tx, "receipt") else "",
            "invoice_no": tx.invoice_no,
            "trans_date": tx.trans_date.isoformat(),
            "customer_name": tx.customer.name if tx.customer_id else "",
            "grand_total": _q2(tx.grand_total or _ZERO),
            "vatable_sales": _q2(tx.vatable_sales or _ZERO),
            "vat_amount": _q2(tx.vat_amount or _ZERO),
        }
        for tx in qs.exclude(invoice_no="").order_by("trans_date", "id")
    ]

    return Response(
        {
            "from": str(frm),
            "to": str(to),
            "granularity": granularity,
            "totals": _or_vat_split(qs),
            "by_period": _group_transactions_by_period(qs, granularity),
            "or_transactions": or_transactions,
        }
    )


@api_view(["GET"])
@permission_classes([IsManagerRole])
def inventory_valuation_view(request):
    """Stock value at cost and at retail, grouped by category and by shelf.

    GET /api/v1/reports/inventory-valuation/

    `by_location` (Phase 9 B1, decision 21 §5) is the same stock cut by WHERE it sits: the
    rows add up to `totals`, so a manager can read "how much of my money is in the Bodega"
    without a second endpoint. Transfer-born batches are included on purpose - the goods
    exist and are worth the same, whichever shelf they are on.
    """
    batches = (
        InventoryBatch.objects.filter(current_qty__gt=0)
        .select_related(
            "variant__product__category",
            "location",
        )
        .annotate(
            cost_value=F("current_qty") * F("unit_cost_landed"),
            retail_value=F("current_qty") * F("batch_selling_price"),
        )
    )
    by_category = (
        batches.values(
            "variant__product__category__id", "variant__product__category__name"
        )
        .annotate(
            batch_count=Count("id"),
            total_units=Sum("current_qty"),
            cost_value=Sum("cost_value"),
            retail_value=Sum("retail_value"),
        )
        .order_by("-cost_value")
    )
    by_location = (
        batches.values("location", "location__name")
        .annotate(
            batch_count=Count("id"),
            total_units=Sum("current_qty"),
            cost_value=Sum("cost_value"),
            retail_value=Sum("retail_value"),
        )
        .order_by("-cost_value")
    )
    grand = batches.aggregate(
        batch_count=Count("id"),
        total_units=Sum("current_qty"),
        total_cost_value=Sum("cost_value"),
        total_retail_value=Sum("retail_value"),
    )
    return Response(
        {
            "totals": grand,
            "by_category": list(by_category),
            # Keys are named for the screen, unlike `by_category`'s raw ORM aliases: the
            # per-shelf table shows the location's own name, not its join path.
            "by_location": [
                {
                    "location": row["location"],
                    "location_name": row["location__name"],
                    "batch_count": row["batch_count"],
                    "total_units": row["total_units"],
                    "cost_value": row["cost_value"],
                    "retail_value": row["retail_value"],
                }
                for row in by_location
            ],
        }
    )


@api_view(["GET"])
@permission_classes([IsManagerRole])
def stock_movements_view(request):
    """Stock IN (goods receipts) vs OUT (adjustments) for the given range.

    GET /api/v1/reports/stock-movements/?from=&to=
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    receipts = (
        GoodsReceipt.objects.filter(receive_date__range=(frm, to))
        .values("receive_date")
        .annotate(
            receipts=Count("id"),
            # Phase 9 B1 (decision 21 §2): what the DELIVERY brought in. A transfer-born
            # batch copies its source's `receipt`, so an unfiltered sum counts moved goods
            # twice; `source_batch` NULL is the "minted by a receipt" marker. The filter
            # sits INSIDE Sum so `receipts=Count('id')` still counts every receipt.
            qty_in=Sum(
                "batches__initial_qty",
                filter=Q(batches__source_batch__isnull=True),
            ),
        )
        .order_by("receive_date")
    )
    adjustments = (
        StockAdjustment.objects.filter(timestamp__date__range=(frm, to))
        .values("adjustment_type")
        .annotate(movements=Count("id"), qty_out=Sum("qty_adjusted"))
        .order_by("-qty_out")
    )
    return Response(
        {
            "from": str(frm),
            "to": str(to),
            "total_qty_in": sum(r["qty_in"] or 0 for r in receipts),
            "total_qty_out": sum(a["qty_out"] or 0 for a in adjustments),
            "receipts_by_day": list(receipts),
            "adjustments_by_type": list(adjustments),
        }
    )


@api_view(["GET"])
@permission_classes([IsManagerRole])
def requisition_history_view(request):
    """Requisition counts per status plus a filtered listing.

    GET /api/v1/reports/requisition-history/?status=&from=&to=
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    qs = Requisition.objects.filter(
        created_at__date__range=(frm, to),
    ).select_related("project")

    status_filter = request.query_params.get("status", "").upper()
    valid_statuses = set(Requisition.Status.values)
    if status_filter:
        if status_filter not in valid_statuses:
            return Response(
                {"detail": f"Invalid status. Choose from {sorted(valid_statuses)}."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        qs = qs.filter(status=status_filter)

    by_status = (
        Requisition.objects.filter(created_at__date__range=(frm, to))
        .values("status")
        .annotate(count=Count("id"))
        .order_by("-count")
    )
    return Response(
        {
            "from": str(frm),
            "to": str(to),
            "status_filter": status_filter or None,
            "count_by_status": list(by_status),
            "requisitions": [
                {
                    "id": r.id,
                    "req_number": r.req_number,
                    "status": r.status,
                    "project": r.project.name,
                    # Same wire keys the reports screen reads; both values are CPMS's
                    # names now (decision 08), so `approved_by` stays null when nobody
                    # approved instead of an empty string.
                    "requested_by": r.requester_name,
                    "approved_by": r.approver_name or None,
                    "created_at": r.created_at,
                }
                for r in qs.order_by("-created_at")[:200]
            ],
        }
    )
