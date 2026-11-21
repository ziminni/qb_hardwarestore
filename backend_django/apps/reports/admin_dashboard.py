# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""`GET /api/v1/reports/admin-dashboard/` — the Admin's own dashboard (owner 2026-11-18).

The five tabs of Admin → Dashboard: System, Sales, Inventory, Bodega and Finance.
`?section=<tab>` answers that one tab only, so each tab loads on its own and one slow
section never holds up the others; no `section` answers all five. Every figure is computed here from the live tables, so the screen needs no
other module's dashboard. Admin / System Administrator only.

Money is returned as strings with two decimals (the API's convention); counts as ints.
"""

from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db.models import Count, DecimalField, ExpressionWrapper, F, Q, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from apps.users.permissions import IsAdminRole

ZERO = Decimal(0)


def _money(value):
    return f"{(value or ZERO):.2f}"


def _sum(queryset, field):
    return queryset.aggregate(total=Sum(field))["total"] or ZERO


def _system(today):
    from apps.inventory.models import StorageLocation
    from apps.pos.models import StoreSettings
    from apps.users.models import AuditLog
    from apps.users.permissions import ROLE_CODE_ORDER, role_codes_for

    users = list(get_user_model().objects.prefetch_related("groups"))
    by_role = dict.fromkeys(ROLE_CODE_ORDER, 0)
    for user in users:
        if not user.is_active:
            continue
        for code in role_codes_for(user):
            by_role[code] = by_role.get(code, 0) + 1
    week_ago = timezone.now() - timedelta(days=7)
    logs = AuditLog.objects.all()
    settings = StoreSettings.objects.first()
    recent = logs.order_by("-timestamp", "-id")[:12]
    return {
        "users_total": len(users),
        "users_active": sum(1 for user in users if user.is_active),
        "users_inactive": sum(1 for user in users if not user.is_active),
        "users_by_role": by_role,
        "logins_today": logs.filter(
            action_type=AuditLog.ActionType.LOGIN, timestamp__date=today
        ).count(),
        "failed_logins_7d": logs.filter(
            action_type=AuditLog.ActionType.LOGIN_FAILED, timestamp__gte=week_ago
        ).count(),
        "events_today": logs.filter(timestamp__date=today).count(),
        "recent_events": [
            {
                "when": row.timestamp,
                "user": row.username_snapshot,
                "action": row.get_action_type_display(),
                "description": row.description[:160],
            }
            for row in recent
        ],
        "locations": [
            {
                "name": row.name,
                "is_bodega": row.is_bodega,
                "is_active": row.is_active,
            }
            for row in StorageLocation.objects.order_by("name")
        ],
        "vat_registered": bool(settings and settings.vat_registered),
        "vat_rate": f"{settings.vat_rate:.2f}" if settings else "0.00",
        "discount_cap_percent": (
            f"{settings.discount_cap_percent:.2f}" if settings else "0.00"
        ),
    }


def _sales(today):
    from apps.pos.models import (
        Payment,
        SalesItem,
        SalesItemDeduction,
        SalesTransaction,
        Shift,
    )

    sales = SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED
    ).exclude(source=SalesTransaction.Source.RETURN)
    completed_all = SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED
    )
    month_start = today.replace(day=1)
    week_start = today - timedelta(days=6)
    daily = {
        row["day"]: row
        for row in sales.filter(trans_date__date__gte=week_start)
        .annotate(day=TruncDate("trans_date"))
        .values("day")
        .annotate(
            total=Sum("grand_total"),
            vatable=Sum("vatable_sales"),
            delivery=Sum("delivery_fee"),
            count=Count("id"),
        )
    }
    cost_expr = ExpressionWrapper(
        F("qty") * F("unit_cost"),
        output_field=DecimalField(max_digits=16, decimal_places=4),
    )
    daily_cogs = {
        row["day"]: row
        for row in SalesItemDeduction.objects.filter(
            sales_item__transaction__status=SalesTransaction.Status.COMPLETED,
            sales_item__transaction__trans_date__date__gte=week_start,
        )
        .annotate(day=TruncDate("sales_item__transaction__trans_date"))
        .values("day")
        .annotate(
            cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
            costed=Count("id", filter=Q(unit_cost__isnull=False)),
            missing=Count("id", filter=Q(unit_cost__isnull=True)),
        )
    }
    last_7_days = []
    for offset in range(7):
        day = week_start + timedelta(days=offset)
        row = daily.get(day, {})
        c_row = daily_cogs.get(day, {})
        costed = c_row.get("costed") or 0
        missing = c_row.get("missing") or 0
        if (costed + missing) > 0 and costed == 0:
            day_cogs = None
            day_profit = None
        elif (costed + missing) == 0:
            day_cogs = None
            day_profit = None
        else:
            cogs_val = c_row.get("cogs") or ZERO
            vatable_val = row.get("vatable") or ZERO
            day_cogs = _money(cogs_val)
            day_profit = _money(vatable_val - cogs_val)
        last_7_days.append(
            {
                "date": day.isoformat(),
                "total": _money(row.get("total")),
                "transactions": row.get("count", 0),
                "cogs": day_cogs,
                "gross_profit": day_profit,
            }
        )
    returns = SalesTransaction.objects.filter(
        source=SalesTransaction.Source.RETURN, trans_date__date__gte=month_start
    )
    top = (
        SalesItem.objects.filter(
            transaction__in=sales.filter(trans_date__date__gte=month_start)
        )
        .values(
            "variant_uom__variant__product__base_name",
            "variant_uom__variant__variant_name",
        )
        .annotate(total=Sum("subtotal"), qty=Sum("qty"))
        .order_by("-total")[:5]
    )
    by_cashier = (
        sales.filter(trans_date__date=today)
        .values("cashier__full_name", "cashier__username")
        .annotate(total=Sum("grand_total"), count=Count("id"))
        .order_by("-total")
    )
    by_method = (
        Payment.objects.filter(
            transaction__in=sales.filter(trans_date__date__gte=month_start),
            status=Payment.Status.CLEARED,
        )
        .values("method")
        .annotate(total=Sum("amount_tendered"), count=Count("id"))
        .order_by("-total")
    )
    today_sales = sales.filter(trans_date__date=today)
    month_sales = sales.filter(trans_date__date__gte=month_start)
    month_all = completed_all.filter(trans_date__date__gte=month_start)
    month_deductions = SalesItemDeduction.objects.filter(
        sales_item__transaction__in=month_all
    ).aggregate(
        cogs=Sum(cost_expr, filter=Q(unit_cost__isnull=False)),
        costed=Count("id", filter=Q(unit_cost__isnull=False)),
        missing=Count("id", filter=Q(unit_cost__isnull=True)),
    )
    m_costed = month_deductions["costed"] or 0
    m_missing = month_deductions["missing"] or 0
    month_vatable = _sum(month_all, "vatable_sales")
    month_discounts = _sum(month_all, "discount_amount")
    if (m_costed + m_missing) > 0 and m_costed == 0:
        month_cogs = None
        month_gross_profit = None
        month_margin_percent = None
    elif (m_costed + m_missing) == 0:
        month_cogs = None
        month_gross_profit = None
        month_margin_percent = None
    else:
        cogs_dec = month_deductions["cogs"] or ZERO
        profit_dec = month_vatable - cogs_dec
        month_cogs = _money(cogs_dec)
        month_gross_profit = _money(profit_dec)
        month_margin_percent = (
            f"{((profit_dec / month_vatable) * Decimal('100')):.1f}"
            if month_vatable > ZERO
            else None
        )
    return {
        "today_total": _money(_sum(today_sales, "grand_total")),
        "today_transactions": today_sales.count(),
        "month_total": _money(_sum(month_sales, "grand_total")),
        "month_transactions": month_sales.count(),
        "month_discounts": _money(month_discounts),
        "month_cogs": month_cogs,
        "month_gross_profit": month_gross_profit,
        "month_margin_percent": month_margin_percent,
        "month_cost_coverage_complete": m_missing == 0,
        "month_returns_total": _money(-_sum(returns, "grand_total")),
        "month_returns_count": returns.count(),
        "open_shifts": Shift.objects.filter(status=Shift.Status.OPEN).count(),
        # A shift still open from an earlier day was never closed out.
        "stale_shifts": [
            {
                "cashier": row.cashier.full_name or row.cashier.username,
                "opened_at": row.opened_at,
            }
            for row in Shift.objects.filter(
                status=Shift.Status.OPEN, opened_at__date__lt=today
            )
            .select_related("cashier")
            .order_by("opened_at")
        ],
        "last_7_days": last_7_days,
        "top_products_month": [
            {
                "name": f"{row['variant_uom__variant__product__base_name']} — "
                f"{row['variant_uom__variant__variant_name']}",
                "qty": f"{row['qty']:.2f}",
                "total": _money(row["total"]),
            }
            for row in top
        ],
        "by_cashier_today": [
            {
                "name": row["cashier__full_name"] or row["cashier__username"] or "",
                "total": _money(row["total"]),
                "transactions": row["count"],
            }
            for row in by_cashier
        ],
        "by_payment_method_month": [
            {
                "method": row["method"],
                "total": _money(row["total"]),
                "count": row["count"],
            }
            for row in by_method
        ],
    }


def _inventory(today):
    from apps.inventory.models import (
        InventoryBatch,
        Product,
        PurchaseOrder,
        StockAdjustment,
        StockTransfer,
        SystemAlert,
    )

    money = DecimalField(max_digits=20, decimal_places=2)
    batches = InventoryBatch.objects.filter(current_qty__gt=0).annotate(
        cost=ExpressionWrapper(F("current_qty") * F("unit_cost_landed"), output_field=money),
        retail=ExpressionWrapper(
            F("current_qty") * F("batch_selling_price"), output_field=money
        ),
    )
    by_location = (
        batches.values("location__name")
        .annotate(cost=Sum("cost"), retail=Sum("retail"))
        .order_by("location__name")
    )
    week_ago = today - timedelta(days=6)
    open_alerts = SystemAlert.objects.filter(is_resolved=False)
    return {
        "products_active": Product.objects.filter(is_active=True).count(),
        "products_archived": Product.objects.filter(is_active=False).count(),
        "stock_cost": _money(_sum(batches, "cost")),
        "stock_retail": _money(_sum(batches, "retail")),
        "by_location": [
            {
                "name": row["location__name"],
                "cost": _money(row["cost"]),
                "retail": _money(row["retail"]),
            }
            for row in by_location
        ],
        "open_alerts": open_alerts.count(),
        "out_of_stock": open_alerts.filter(
            alert_type=SystemAlert.AlertType.OUT_OF_STOCK
        ).count(),
        "low_stock": open_alerts.filter(
            alert_type=SystemAlert.AlertType.LOW_STOCK
        ).count(),
        "expiring": open_alerts.filter(
            alert_type=SystemAlert.AlertType.EXPIRING
        ).count(),
        "alerts": [
            {
                "code": row.alert_type,
                "type": row.get_alert_type_display(),
                "message": row.message[:160],
                "created_at": row.created_at,
            }
            for row in open_alerts.order_by("-id")[:8]
        ],
        "open_purchase_orders": PurchaseOrder.objects.filter(
            status__in=[PurchaseOrder.Status.ORDERED, PurchaseOrder.Status.PARTIAL]
        ).count(),
        "draft_purchase_orders": PurchaseOrder.objects.filter(
            status=PurchaseOrder.Status.DRAFT
        ).count(),
        "adjustments_7d": StockAdjustment.objects.filter(
            timestamp__date__gte=week_ago
        ).count(),
        "transfers_7d": StockTransfer.objects.filter(
            created_at__date__gte=week_ago
        ).count(),
    }


def _bodega(today):
    from apps.bodega.models import BodegaDelivery, BodegaRelease
    from apps.bodega.services import claim_lines
    from apps.inventory.models import StockAdjustment

    lines = claim_lines()
    pending = (
        BodegaDelivery.objects.filter(status=BodegaDelivery.Status.PENDING)
        .select_related("receipt__po__supplier")
        .annotate(line_count=Count("lines"), delivered=Sum("lines__delivered_qty"))
        .order_by("created_at")
    )
    open_sales = {line["sale_id"] for line in lines if line["remaining"] > 0}
    month_start = today.replace(day=1)
    write_offs = StockAdjustment.objects.filter(
        remarks__startswith="Bodega delivery check",
        timestamp__date__gte=month_start,
    )
    return {
        "open_pickups": len(open_sales),
        "pending_deliveries": pending.count(),
        "pending_delivery_list": [
            {
                "number": row.number,
                "supplier": row.receipt.po.supplier.company_name,
                "delivery_receipt_no": row.receipt.delivery_receipt_no,
                "received_at": row.created_at,
                "lines": row.line_count,
                "delivered_qty": f"{(row.delivered or ZERO):.2f}",
            }
            for row in pending[:10]
        ],
        "releases_today": BodegaRelease.objects.filter(
            created_at__date=today
        ).count(),
        "deliveries_checked_month": BodegaDelivery.objects.filter(
            status=BodegaDelivery.Status.CHECKED, checked_at__date__gte=month_start
        ).count(),
        "write_offs_month": write_offs.count(),
        "recent_releases": [
            {
                "number": row.number,
                "receipt": row.sale.transaction_no,
                "received_by": row.received_by,
                "when": row.created_at,
            }
            for row in BodegaRelease.objects.select_related("sale")[:6]
        ],
    }


def _finance(today):
    from apps.collectibles.models import CollectibleLedger, CollectiblePayment
    from apps.inventory.models import SupplierBill, SupplierPayment
    from apps.pos.models import Payment

    open_ledgers = CollectibleLedger.objects.exclude(
        status=CollectibleLedger.Status.PAID
    ).filter(balance_due__gt=0)
    # A bill's status is derived from its balance, so "open" is a balance left.
    open_bills = SupplierBill.objects.filter(balance_amount__gt=0)
    soon = today + timedelta(days=7)
    month_start = today.replace(day=1)
    overdue_ledgers = open_ledgers.filter(due_date__lt=today)
    overdue_bills = open_bills.filter(due_date__lt=today)
    by_supplier = (
        open_bills.values("supplier__company_name")
        .annotate(balance=Sum("balance_amount"), bills=Count("id"))
        .order_by("-balance")[:6]
    )
    return {
        "receivables_total": _money(_sum(open_ledgers, "balance_due")),
        "receivables_count": open_ledgers.count(),
        "receivables_overdue": _money(_sum(overdue_ledgers, "balance_due")),
        "receivables_overdue_count": overdue_ledgers.count(),
        "overdue_receivables": [
            {
                "customer": row.customer.name,
                "due_date": row.due_date,
                "balance": _money(row.balance_due),
            }
            for row in overdue_ledgers.select_related("customer").order_by("due_date")[
                :10
            ]
        ],
        "payables_total": _money(_sum(open_bills, "balance_amount")),
        "payables_count": open_bills.count(),
        "payables_overdue": _money(_sum(overdue_bills, "balance_amount")),
        "payables_overdue_count": overdue_bills.count(),
        "payables_by_supplier": [
            {
                "supplier": row["supplier__company_name"],
                "balance": _money(row["balance"]),
                "bills": row["bills"],
            }
            for row in by_supplier
        ],
        "open_bills": [
            {
                "supplier": row.supplier.company_name,
                "reference": row.receipt.delivery_receipt_no,
                "received_date": row.received_date,
                "due_date": row.due_date,
                "total": _money(row.total_amount),
                "balance": _money(row.balance_amount),
                "overdue": row.due_date < today,
            }
            for row in open_bills.select_related("supplier", "receipt").order_by(
                "due_date", "id"
            )[:10]
        ],
        "payables_due_7d": _money(
            _sum(
                open_bills.filter(due_date__gte=today, due_date__lte=soon),
                "balance_amount",
            )
        ),
        "customer_cheques_pending": Payment.objects.filter(
            status=Payment.Status.PENDING
        ).count(),
        "supplier_cheques_issued": SupplierPayment.objects.filter(
            status=SupplierPayment.Status.ISSUED
        ).count(),
        "collections_month": _money(
            _sum(
                CollectiblePayment.objects.filter(payment_date__date__gte=month_start),
                "amount_paid",
            )
        ),
        "supplier_payments_month": _money(
            _sum(
                SupplierPayment.objects.filter(paid_on__date__gte=month_start).filter(
                    ~Q(status=SupplierPayment.Status.BOUNCED)
                ),
                "amount",
            )
        ),
    }


SECTIONS = {
    "system": _system,
    "sales": _sales,
    "inventory": _inventory,
    "bodega": _bodega,
    "finance": _finance,
}


@api_view(["GET"])
@permission_classes([IsAdminRole])
def admin_dashboard_view(request):
    today = timezone.localdate()
    wanted = request.query_params.get("section")
    if wanted is None:
        names = list(SECTIONS)
    elif wanted in SECTIONS:
        names = [wanted]
    else:
        return Response(
            {
                "detail": f"Unknown section. Use one of: {', '.join(SECTIONS)}.",
                "code": "UNKNOWN_SECTION",
            },
            status=400,
        )
    body = {"as_of": timezone.now()}
    for name in names:
        body[name] = SECTIONS[name](today)
    return Response(body)
