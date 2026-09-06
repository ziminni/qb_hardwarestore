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

from django.db.models import Count, F, Sum
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from apps.inventory.models import GoodsReceipt, InventoryBatch, StockAdjustment
from apps.pos.models import SalesTransaction
from apps.requisitions.models import Requisition
from apps.users.permissions import IsManagerRole

DEFAULT_RANGE_DAYS = 30


def _parse_range(request):
    """Return (from_date, to_date) inclusive; defaults to last 30 days."""
    today = date.today()
    to = parse_date(request.query_params.get('to', '')) or today
    frm = parse_date(request.query_params.get('from', '')) or (
        to - timedelta(days=DEFAULT_RANGE_DAYS)
    )
    if frm > to:
        frm, to = to, frm
    return frm, to


def _range_error():
    return Response(
        {'detail': 'Invalid date. Use YYYY-MM-DD for from/to.'},
        status=status.HTTP_400_BAD_REQUEST,
    )


@api_view(['GET'])
@permission_classes([IsManagerRole])
def sales_summary_view(request):
    """Daily sales totals for the given range (completed transactions).

    GET /api/v1/reports/sales-summary/?from=&to=
    """
    bad = [p for p in ('from', 'to') if request.query_params.get(p)
           and not parse_date(request.query_params[p])]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    qs = SalesTransaction.objects.filter(
        status=SalesTransaction.Status.COMPLETED,
        trans_date__date__range=(frm, to),
    )
    by_day = (
        qs.annotate(day=F('trans_date__date'))
        .values('day')
        .annotate(
            transactions=Count('id'),
            gross_sales=Sum('grand_total'),
            vat=Sum('vat_amount'),
            discounts=Sum('discount_amount'),
        )
        .order_by('day')
    )
    totals = qs.aggregate(
        transactions=Count('id'),
        gross_sales=Sum('grand_total'),
        vat=Sum('vat_amount'),
        discounts=Sum('discount_amount'),
    )
    return Response({
        'from': str(frm),
        'to': str(to),
        'totals': totals,
        'by_day': list(by_day),
    })


@api_view(['GET'])
@permission_classes([IsManagerRole])
def inventory_valuation_view(request):
    """Stock value at cost and at retail, grouped by category.

    GET /api/v1/reports/inventory-valuation/
    """
    batches = InventoryBatch.objects.filter(current_qty__gt=0).select_related(
        'variant__product__category',
    ).annotate(
        cost_value=F('current_qty') * F('unit_cost_landed'),
        retail_value=F('current_qty') * F('batch_selling_price'),
    )
    by_category = (
        batches.values('variant__product__category__id',
                       'variant__product__category__name')
        .annotate(
            batch_count=Count('id'),
            total_units=Sum('current_qty'),
            cost_value=Sum('cost_value'),
            retail_value=Sum('retail_value'),
        )
        .order_by('-cost_value')
    )
    grand = batches.aggregate(
        batch_count=Count('id'),
        total_units=Sum('current_qty'),
        total_cost_value=Sum('cost_value'),
        total_retail_value=Sum('retail_value'),
    )
    return Response({
        'totals': grand,
        'by_category': list(by_category),
    })


@api_view(['GET'])
@permission_classes([IsManagerRole])
def stock_movements_view(request):
    """Stock IN (goods receipts) vs OUT (adjustments) for the given range.

    GET /api/v1/reports/stock-movements/?from=&to=
    """
    bad = [p for p in ('from', 'to') if request.query_params.get(p)
           and not parse_date(request.query_params[p])]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    receipts = (
        GoodsReceipt.objects.filter(receive_date__range=(frm, to))
        .values('receive_date')
        .annotate(receipts=Count('id'), qty_in=Sum('batches__initial_qty'))
        .order_by('receive_date')
    )
    adjustments = (
        StockAdjustment.objects.filter(timestamp__date__range=(frm, to))
        .values('adjustment_type')
        .annotate(movements=Count('id'), qty_out=Sum('qty_adjusted'))
        .order_by('-qty_out')
    )
    return Response({
        'from': str(frm),
        'to': str(to),
        'total_qty_in': sum(r['qty_in'] or 0 for r in receipts),
        'total_qty_out': sum(a['qty_out'] or 0 for a in adjustments),
        'receipts_by_day': list(receipts),
        'adjustments_by_type': list(adjustments),
    })


@api_view(['GET'])
@permission_classes([IsManagerRole])
def requisition_history_view(request):
    """Requisition counts per status plus a filtered listing.

    GET /api/v1/reports/requisition-history/?status=&from=&to=
    """
    bad = [p for p in ('from', 'to') if request.query_params.get(p)
           and not parse_date(request.query_params[p])]
    if bad:
        return _range_error()
    frm, to = _parse_range(request)

    qs = Requisition.objects.filter(
        created_at__date__range=(frm, to),
    ).select_related('project', 'requested_by', 'approved_by')

    status_filter = request.query_params.get('status', '').upper()
    valid_statuses = set(Requisition.Status.values)
    if status_filter:
        if status_filter not in valid_statuses:
            return Response(
                {'detail': f'Invalid status. Choose from {sorted(valid_statuses)}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        qs = qs.filter(status=status_filter)

    by_status = (
        Requisition.objects.filter(created_at__date__range=(frm, to))
        .values('status')
        .annotate(count=Count('id'))
        .order_by('-count')
    )
    return Response({
        'from': str(frm),
        'to': str(to),
        'status_filter': status_filter or None,
        'count_by_status': list(by_status),
        'requisitions': [
            {
                'id': r.id,
                'req_number': r.req_number,
                'status': r.status,
                'project': r.project.name,
                'requested_by': r.requested_by.full_name,
                'approved_by': (
                    r.approved_by.full_name if r.approved_by else None),
                'created_at': r.created_at,
            }
            for r in qs.order_by('-created_at')[:200]
        ],
    })
