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
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response

from apps.inventory.models import GoodsReceipt, InventoryBatch, StockAdjustment
from apps.pos.models import (
    DiscountApproval,
    Payment,
    SalesItem,
    SalesItemDeduction,
    SalesTransaction,
)
from apps.requisitions.models import Requisition
from apps.users.permissions import IsManagerRole

DEFAULT_RANGE_DAYS = 30
_ZERO = Decimal("0.00")
_CENT = Decimal("0.01")


def _q2(value: Decimal) -> Decimal:
    return value.quantize(_CENT)


def _unit_kpis(
    *,
    gross_sales: Decimal,
    transactions: int,
    merchandise_gross: Decimal,
    merchandise_net: Decimal,
    discounts: Decimal,
    qty_base: Decimal,
) -> dict:
    """ABV, ASP and markdown % for one scope; None wherever the denominator is zero.

    A return is a signed row, so it lowers ABV and ASP by itself - nothing filters it.
    ASP divides by BASE units (a selling unit of 2 bags is 2), and a zero denominator
    reports None, never 0: an empty day and a freebie are different facts.
    """
    return {
        "abv": _q2(gross_sales / transactions) if transactions else None,
        "asp": _q2(merchandise_net / qty_base) if qty_base else None,
        "markdown_percent": (
            _q2((discounts / merchandise_gross) * Decimal(100))
            if merchandise_gross
            else None
        ),
    }


def _delivery_fee_ex_vat(tx) -> Decimal:
    fee = tx.delivery_fee or _ZERO
    if fee == _ZERO:
        return _ZERO
    if tx.vat_registered and tx.vat_rate and tx.vat_rate > _ZERO:
        divisor = Decimal(1) + (tx.vat_rate / Decimal(100))
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


def _paged(request, rows, payload):
    """Page a computed row list 50 rows/page (decision 04), totals kept outside it."""
    paginator = PageNumberPagination()
    page = paginator.paginate_queryset(rows, request)
    return Response(
        {
            **payload,
            "count": paginator.page.paginator.count,
            "next": paginator.get_next_link(),
            "previous": paginator.get_previous_link(),
            "results": page,
        }
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

    # KPIs divide by base units, so a selling unit worth 2 bags counts as 2. One grouped
    # query serves the daily and the period scope; totals sum it, so the three scopes
    # cannot drift apart.
    qty_base_expr = ExpressionWrapper(
        F("qty") * F("variant_uom__conversion_factor"),
        output_field=DecimalField(max_digits=16, decimal_places=4),
    )
    qty_base_by_day: dict[date, Decimal] = {
        row["day"]: row["qty_base"] or _ZERO
        for row in SalesItem.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
        )
        .annotate(day=F("transaction__trans_date__date"))
        .values("day")
        .annotate(qty_base=Sum(qty_base_expr))
    }
    total_qty_base = sum(qty_base_by_day.values(), _ZERO)

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
            _q2((gross_profit / merchandise_net_ex_vat) * Decimal(100))
            if merchandise_net_ex_vat > _ZERO
            else None
        )
        effective_markup_percent = (
            _q2((gross_profit / total_cogs) * Decimal(100))
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
            **_unit_kpis(
                gross_sales=gross_sales_val,
                transactions=totals["transactions"],
                merchandise_gross=merchandise_gross,
                merchandise_net=merchandise_net_ex_vat,
                discounts=discounts_val,
                qty_base=total_qty_base,
            ),
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
        day_gross = row["gross_sales"] or _ZERO
        day_discounts = row["discounts"] or _ZERO
        row.update(
            _unit_kpis(
                gross_sales=day_gross,
                transactions=row["transactions"],
                merchandise_gross=_q2(
                    day_gross
                    - (row["delivery_fees"] or _ZERO)
                    - (row["payment_fees"] or _ZERO)
                    + day_discounts
                ),
                merchandise_net=day_net_ex_vat,
                discounts=day_discounts,
                qty_base=qty_base_by_day.get(d, _ZERO),
            )
        )
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
    cat_cogs_rows = deductions.values(
        "sales_item__variant_uom__variant__product__category__id",
    ).annotate(
        cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
        costed=Count("id", filter=Q(unit_cost__isnull=False)),
        missing=Count("id", filter=Q(unit_cost__isnull=True)),
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
        cat_name = (
            row["variant_uom__variant__product__category__name"] or "Uncategorized"
        )
        gross_m = _q2(row["gross_merchandise"] or _ZERO)
        disc_m = _q2(
            (row["item_discounts"] or _ZERO) + (row["cart_discounts"] or _ZERO)
        )
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
    by_period = _group_transactions_by_period(qs, granularity, qty_base_by_day)

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


def _item_wise_rows(frm: date, to: date) -> list[dict]:
    """One row per selling unit sold in the range, COGS merged in from the deductions.

    Returns are negative completed rows, so every Sum already nets them out. COGS is
    deduction qty x snapshotted unit_cost; a unit with only NULL-cost deductions gets
    `cogs`/`gross_profit` None and counts its rows in `missing_cost_deductions`.
    """
    sales_rows = (
        SalesItem.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
        )
        .values(
            "variant_uom_id",
            "variant_uom__variant_id",
            "variant_uom__variant__sku",
            "variant_uom__variant__product__base_name",
            "variant_uom__variant__variant_name",
            "variant_uom__uom__code",
            "variant_uom__conversion_factor",
        )
        .annotate(
            qty_sold=Sum("qty"),
            merchandise_gross=Sum("subtotal"),
            item_discounts=Sum("item_discount_amount"),
            cart_discounts=Sum("cart_discount_amount"),
        )
    )

    cost_expr = ExpressionWrapper(
        F("qty") * F("unit_cost"),
        output_field=DecimalField(max_digits=16, decimal_places=4),
    )
    cogs_rows = (
        SalesItemDeduction.objects.filter(
            sales_item__transaction__status=SalesTransaction.Status.COMPLETED,
            sales_item__transaction__trans_date__date__range=(frm, to),
        )
        .values("sales_item__variant_uom_id")
        .annotate(
            cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
            costed=Count("id", filter=Q(unit_cost__isnull=False)),
            missing=Count("id", filter=Q(unit_cost__isnull=True)),
        )
    )
    cogs_map = {
        row["sales_item__variant_uom_id"]: (
            _q2(row["cogs"]) if row["cogs"] is not None else _ZERO,
            row["costed"] or 0,
            row["missing"] or 0,
        )
        for row in cogs_rows
    }

    rows = []
    for row in sales_rows:
        uom_id = row["variant_uom_id"]
        qty_sold = row["qty_sold"] or _ZERO
        gross = _q2(row["merchandise_gross"] or _ZERO)
        discounts = _q2(
            (row["item_discounts"] or _ZERO) + (row["cart_discounts"] or _ZERO)
        )
        net = _q2(gross - discounts)
        cogs_val, costed, missing = cogs_map.get(uom_id, (_ZERO, 0, 0))
        if (costed + missing) > 0 and costed == 0:
            cogs = None
            profit = None
        else:
            cogs = cogs_val
            profit = _q2(net - cogs)
        rows.append(
            {
                "variant_uom_id": uom_id,
                "variant_id": row["variant_uom__variant_id"],
                "sku": row["variant_uom__variant__sku"],
                "product": row["variant_uom__variant__product__base_name"],
                "variant": row["variant_uom__variant__variant_name"],
                "uom": row["variant_uom__uom__code"],
                "qty_sold": _q2(qty_sold),
                "qty_base": _q2(qty_sold * row["variant_uom__conversion_factor"]),
                "merchandise_gross": gross,
                "discounts": discounts,
                "net_merchandise": net,
                "cogs": cogs,
                "gross_profit": profit,
                "missing_cost_deductions": missing,
            }
        )
    rows.sort(key=lambda r: r["net_merchandise"], reverse=True)
    return rows


@api_view(["GET"])
@permission_classes([IsManagerRole])
def sales_by_item_view(request):
    """Per selling unit (variant + UOM): base-unit qty, net merchandise, COGS, profit.

    GET /api/v1/reports/sales-by-item/?from=&to=
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    rows = _item_wise_rows(frm, to)
    cogs_parts = [r["cogs"] for r in rows if r["cogs"] is not None]
    total_cogs = None if rows and not cogs_parts else _q2(sum(cogs_parts, _ZERO))
    total_net = _q2(sum((r["net_merchandise"] for r in rows), _ZERO))
    totals = {
        "variant_count": len(rows),
        "qty_base": _q2(sum((r["qty_base"] for r in rows), _ZERO)),
        "net_merchandise": total_net,
        "cogs": total_cogs,
        "gross_profit": None if total_cogs is None else _q2(total_net - total_cogs),
        "missing_cost_deductions": sum(r["missing_cost_deductions"] for r in rows),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


@api_view(["GET"])
@permission_classes([IsManagerRole])
def sales_by_hour_view(request):
    """Store-local hours 0-23 in the range: transactions and signed invoice total.

    GET /api/v1/reports/sales-by-hour/?from=&to=

    Every hour is returned, zeros included, so a chart never has to guess a gap. A
    return is a negative row, so it lands in its own hour and nets the total.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    buckets = [
        {"hour": hour, "transactions": 0, "invoice_total": _ZERO} for hour in range(24)
    ]
    for tx in SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED,
        trans_date__date__range=(frm, to),
    ).only("trans_date", "grand_total"):
        bucket = buckets[timezone.localtime(tx.trans_date).hour]
        bucket["transactions"] += 1
        bucket["invoice_total"] += tx.grand_total or _ZERO
    for bucket in buckets:
        bucket["invoice_total"] = _q2(bucket["invoice_total"])

    totals = {
        "transactions": sum(b["transactions"] for b in buckets),
        "invoice_total": _q2(sum((b["invoice_total"] for b in buckets), _ZERO)),
    }
    return _paged(request, buckets, {"from": str(frm), "to": str(to), "totals": totals})


@api_view(["GET"])
@permission_classes([IsManagerRole])
def sales_by_cashier_view(request):
    """Per cashier: transactions, signed invoice total and discounts given.

    GET /api/v1/reports/sales-by-cashier/?from=&to=

    Discounts are the lines' `item_discount_amount` + `cart_discount_amount` (the same
    two fields every other report reads), not the header's `discount_amount`.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    sales_rows = (
        SalesTransaction.objects.filter(
            status=SalesTransaction.Status.COMPLETED,
            trans_date__date__range=(frm, to),
        )
        .values("cashier_id", "cashier__full_name", "cashier__username")
        .annotate(transactions=Count("id"), invoice_total=Sum("grand_total"))
    )
    discount_rows = (
        SalesItem.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
        )
        .values("transaction__cashier_id")
        .annotate(
            item_discounts=Sum("item_discount_amount"),
            cart_discounts=Sum("cart_discount_amount"),
        )
    )
    discounts_map = {
        row["transaction__cashier_id"]: _q2(
            (row["item_discounts"] or _ZERO) + (row["cart_discounts"] or _ZERO)
        )
        for row in discount_rows
    }

    rows = [
        {
            "cashier_id": row["cashier_id"],
            "cashier_name": row["cashier__full_name"],
            "username": row["cashier__username"],
            "transactions": row["transactions"],
            "invoice_total": _q2(row["invoice_total"] or _ZERO),
            "discounts": discounts_map.get(row["cashier_id"], _ZERO),
        }
        for row in sales_rows
    ]
    rows.sort(key=lambda r: r["invoice_total"], reverse=True)

    totals = {
        "transactions": sum(r["transactions"] for r in rows),
        "invoice_total": _q2(sum((r["invoice_total"] for r in rows), _ZERO)),
        "discounts": _q2(sum((r["discounts"] for r in rows), _ZERO)),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


def _bill_method_map(frm: date, to: date) -> dict:
    """transaction_id -> {method: tendered pesos} for every bill in the range.

    `Payment.amount_tendered` is the money recorded on the tender itself (covered + fee),
    so the column reconciles with what the customer handed over. A cheque that later
    bounces is the cheques report's business, not this listing's.
    """
    rows = (
        Payment.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
        )
        .values("transaction_id", "method")
        .annotate(total=Sum("amount_tendered"))
    )
    per_tx: dict[int, dict[str, Decimal]] = {}
    for row in rows:
        per_tx.setdefault(row["transaction_id"], {})[row["method"]] = _q2(
            row["total"] or _ZERO
        )
    return per_tx


def _sum_methods(rows) -> dict:
    """Merge the rows' `methods` maps into one report total per tender."""
    merged: dict[str, Decimal] = {}
    for row in rows:
        for method, amount in row["methods"].items():
            merged[method] = merged.get(method, _ZERO) + amount
    return {method: _q2(amount) for method, amount in sorted(merged.items())}


def _bill_methods(tx, method_map: dict) -> dict:
    """The tenders that actually settled THIS bill, change taken back off the cash.

    `Payment.amount_tendered` is what the customer handed over, so an overpaid cash sale
    would read richer than its own `grand_total`. The change comes out of the same
    drawer, so subtracting it makes the tender column add up to the bill.
    """
    methods = dict(method_map.get(tx.id, {}))
    change = _q2(tx.change_given or _ZERO)
    if change:
        methods["CASH"] = methods.get("CASH", _ZERO) - change
    return methods


@api_view(["GET"])
@permission_classes([IsManagerRole])
def bill_wise_view(request):
    """One signed row per COMPLETED bill: OR/invoice no, tenders, discount, total.

    GET /api/v1/reports/bill-wise/?from=&to=

    A RETURN/EXCHANGE is a COMPLETED negative row, so it is listed here with its signed
    `grand_total` exactly as it was stored - the bill listing hides no reversal.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    method_map = _bill_method_map(frm, to)
    rows = [
        {
            "id": tx.id,
            "transaction_no": tx.transaction_no,
            "or_number": tx.receipt.or_number if hasattr(tx, "receipt") else "",
            "invoice_no": tx.invoice_no,
            "date": timezone.localtime(tx.trans_date).isoformat(),
            "source": tx.source,
            "cashier_id": tx.cashier_id,
            "cashier_name": tx.cashier.full_name,
            "original_transaction_id": tx.original_transaction_id,
            "methods": _bill_methods(tx, method_map),
            "discount": _q2(tx.discount_amount or _ZERO),
            "grand_total": _q2(tx.grand_total or _ZERO),
        }
        for tx in SalesTransaction.objects.filter(
            status=SalesTransaction.Status.COMPLETED,
            trans_date__date__range=(frm, to),
        ).select_related("cashier", "receipt")
    ]
    totals = {
        "transactions": len(rows),
        "discount": _q2(sum((r["discount"] for r in rows), _ZERO)),
        "grand_total": _q2(sum((r["grand_total"] for r in rows), _ZERO)),
        "methods": _sum_methods(rows),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


@api_view(["GET"])
@permission_classes([IsManagerRole])
def returns_exchanges_view(request):
    """Only the reversal rows (source RETURN/EXCHANGE): link, refunded money, reason.

    GET /api/v1/reports/returns-exchanges/?from=&to=

    `refunded` is the money handed BACK to the customer, so it is positive for a cash
    return and 0.00 on an exchange (an exchange moves goods; only its balance can move
    money). `grand_total` keeps the row's own signed number.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    rows = []
    for tx in SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED,
        source__in=[SalesTransaction.Source.RETURN, SalesTransaction.Source.EXCHANGE],
        trans_date__date__range=(frm, to),
    ).select_related("cashier", "original_transaction"):
        grand_total = _q2(tx.grand_total or _ZERO)
        is_return = tx.source == SalesTransaction.Source.RETURN
        rows.append(
            {
                "id": tx.id,
                "transaction_no": tx.transaction_no,
                "date": timezone.localtime(tx.trans_date).isoformat(),
                "source": tx.source,
                "cashier_id": tx.cashier_id,
                "cashier_name": tx.cashier.full_name,
                "original_transaction_id": tx.original_transaction_id,
                "original_transaction_no": (
                    tx.original_transaction.transaction_no
                    if tx.original_transaction_id
                    else ""
                ),
                "refunded": _q2(-grand_total) if is_return else _ZERO,
                "grand_total": grand_total,
                "reason": tx.notes,
            }
        )
    totals = {
        "transactions": len(rows),
        "returns": sum(
            1 for r in rows if r["source"] == SalesTransaction.Source.RETURN
        ),
        "exchanges": sum(
            1 for r in rows if r["source"] == SalesTransaction.Source.EXCHANGE
        ),
        "refunded": _q2(sum((r["refunded"] for r in rows), _ZERO)),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


@api_view(["GET"])
@permission_classes([IsManagerRole])
def discounts_view(request):
    """Discount pesos per type: LINE, CART and the APPROVAL behind a sale discount.

    GET /api/v1/reports/discounts/?from=&to=

    A line's discount is stored as PESOS only (`item_discount_amount`), never with the
    AMOUNT/PERCENT kind the till typed, so the LINE row cannot be split further without
    guessing. APPROVAL is not extra money: it is the CART discount on the sales a manager
    signed off, so `totals.total_discount` adds LINE + CART only.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    def _discount_row(kind: str, field: str) -> dict | None:
        agg = SalesItem.objects.filter(
            transaction__status=SalesTransaction.Status.COMPLETED,
            transaction__trans_date__date__range=(frm, to),
            **{f"{field}__gt": 0},
        ).aggregate(
            transactions=Count("transaction_id", distinct=True),
            total=Sum(field),
        )
        if not agg["transactions"]:
            return None
        return {
            "type": kind,
            "transactions": agg["transactions"],
            "total_discount": _q2(agg["total"] or _ZERO),
        }

    line_row = _discount_row("LINE", "item_discount_amount")
    cart_row = _discount_row("CART", "cart_discount_amount")

    approval_qs = DiscountApproval.objects.filter(
        transaction__status=SalesTransaction.Status.COMPLETED,
        transaction__trans_date__date__range=(frm, to),
    )
    approved_ids = list(approval_qs.values_list("transaction_id", flat=True).distinct())
    approval_row = None
    if approved_ids:
        agg = SalesTransaction.objects.filter(id__in=approved_ids).aggregate(
            transactions=Count("id"), total=Sum("discount_amount")
        )
        approval_row = {
            "type": "APPROVAL",
            "transactions": agg["transactions"],
            "total_discount": _q2(agg["total"] or _ZERO),
            "approvals": approval_qs.count(),
        }

    rows = [row for row in (line_row, cart_row, approval_row) if row is not None]
    line_total = line_row["total_discount"] if line_row else _ZERO
    cart_total = cart_row["total_discount"] if cart_row else _ZERO
    totals = {
        "line_discount": line_total,
        "cart_discount": cart_total,
        "approval_discount": approval_row["total_discount"] if approval_row else _ZERO,
        "approvals": approval_row["approvals"] if approval_row else 0,
        "total_discount": _q2(line_total + cart_total),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


@api_view(["GET"])
@permission_classes([IsManagerRole])
def voids_view(request):
    """VOID bills in the range: id, date, cashier, voided total and the reason on file.

    GET /api/v1/reports/voids/?from=&to=

    The reason is the row's `notes` - there is no dedicated void-reason column, so an
    empty note reads as "no reason recorded" rather than inventing one.
    """
    bad = [
        p
        for p in ("from", "to")
        if request.query_params.get(p) and not parse_date(request.query_params[p])
    ]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    rows = [
        {
            "id": tx.id,
            "transaction_no": tx.transaction_no,
            "date": timezone.localtime(tx.trans_date).isoformat(),
            "cashier_id": tx.cashier_id,
            "cashier_name": tx.cashier.full_name,
            "voided_total": _q2(tx.grand_total or _ZERO),
            "reason": tx.notes,
        }
        for tx in SalesTransaction.objects.filter(
            status=SalesTransaction.Status.VOID,
            trans_date__date__range=(frm, to),
        ).select_related("cashier")
    ]
    totals = {
        "transactions": len(rows),
        "voided_total": _q2(sum((r["voided_total"] for r in rows), _ZERO)),
    }
    return _paged(request, rows, {"from": str(frm), "to": str(to), "totals": totals})


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


def _group_transactions_by_period(qs, granularity: str, qty_base_by_day=None):
    """Bucket the range into day/week/month rows.

    `qty_base_by_day` opts the buckets into the ABV/ASP/markdown KPIs; the VAT summary
    passes nothing and gets the plain rollup it has always had.
    """
    with_kpis = qty_base_by_day is not None
    qty_base_by_day = qty_base_by_day or {}
    buckets: dict[str, dict] = {}
    fees_by_period: dict[str, dict] = {}
    qty_base_by_period: dict[str, Decimal] = {}
    for tx in qs.select_related(None).only(
        "trans_date",
        "grand_total",
        "vatable_sales",
        "vat_amount",
        "discount_amount",
        "invoice_no",
        "delivery_fee",
        "payment_fee",
    ):
        day = tx.trans_date.date()
        key = _period_key(day, granularity)
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
        fees = fees_by_period.setdefault(key, {"delivery": _ZERO, "payment": _ZERO})
        fees["delivery"] += tx.delivery_fee or _ZERO
        fees["payment"] += tx.payment_fee or _ZERO
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
    # Base units are already grouped by day, so roll them up once per day - adding them
    # inside the transaction loop would count a day's units once per ticket on that day.
    for day, qty in qty_base_by_day.items():
        key = _period_key(day, granularity)
        if key in buckets:
            qty_base_by_period[key] = qty_base_by_period.get(key, _ZERO) + qty
    for key in sorted(buckets.keys()):
        b = buckets[key]
        for k, v in list(b.items()):
            if isinstance(v, Decimal):
                b[k] = _q2(v)
        if with_kpis:
            fees = fees_by_period[key]
            gross = b["gross_sales"]
            discounts = b["discounts"]
            b.update(
                _unit_kpis(
                    gross_sales=gross,
                    transactions=b["transactions"],
                    merchandise_gross=_q2(
                        gross - fees["delivery"] - fees["payment"] + discounts
                    ),
                    # This scope carries no VAT-split delivery figure, so its merchandise
                    # net is the fee-stripped gross (VAT-inclusive on a VAT sale).
                    merchandise_net=_q2(gross - fees["delivery"] - fees["payment"]),
                    discounts=discounts,
                    qty_base=qty_base_by_period.get(key, _ZERO),
                )
            )
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
