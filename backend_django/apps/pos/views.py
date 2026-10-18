# pyright: reportAttributeAccessIssue=false
#
# Same reason as apps/inventory/views.py and seed_demo.py: the checker resolves its
# config from its WORKING DIRECTORY and does not run inside this repo here, so a
# pyrightconfig.json is not found. This travels with the file. It disables the one
# rule that cannot model Django's `Model.objects` without django-stubs.
from django.db.models import Sum
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from apps.users.permissions import IsPOSOrReadOnly
from .models import Customer, SalesTransaction, Payment, OfficialReceipt
from .models import Quotation, SalesOrder
from .serializers import CustomerSerializer, SalesTransactionSerializer, PaymentSerializer, OfficialReceiptSerializer
from .serializers import QuotationSerializer, SalesOrderSerializer
from .services import process_sale


class BaseViewSet(viewsets.ModelViewSet):
    """Read requires auth; write requires POS role (Cashier+)."""

    permission_classes = [IsPOSOrReadOnly]


class CustomerViewSet(BaseViewSet):
    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer


class SalesTransactionViewSet(BaseViewSet):
    queryset = SalesTransaction.objects.select_related('customer','cashier').prefetch_related('items','payments','receipt').all()
    serializer_class = SalesTransactionSerializer

    def create(self, request):
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        txn = process_sale(
            customer_id=ser.validated_data['customer'].id,
            cashier=request.user,
            items_data=request.data.get('items',[]),
            payments_data=request.data.get('payments',[]),
            source=ser.validated_data.get('source','WALK_IN'),
        )
        return Response(self.get_serializer(txn).data, status=status.HTTP_201_CREATED)

    @action(detail=False, methods=['get'])
    def daily_report(self, request):
        from datetime import timedelta

        from django.utils import timezone
        from django.utils.dateparse import parse_date

        date_param = request.query_params.get('date')
        if date_param:
            parsed = parse_date(date_param)
            if not parsed:
                return Response(
                    {'detail': 'Invalid date. Use YYYY-MM-DD.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            report_date = parsed
        else:
            report_date = timezone.localdate()
        qs = self.get_queryset().filter(
            trans_date__date=report_date,
            status=SalesTransaction.Status.COMPLETED,
        )
        total = qs.aggregate(total=Sum('grand_total'))['total'] or 0
        return Response({
            'date': str(report_date),
            'count': qs.count(),
            'total_sales': total,
        })


class PaymentViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Payment.objects.select_related('transaction').all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]


class OfficialReceiptViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = OfficialReceipt.objects.select_related('transaction').all()
    serializer_class = OfficialReceiptSerializer
    permission_classes = [IsAuthenticated]


class QuotationViewSet(BaseViewSet):
    """Decision 05: quotations are a real backend resource.

    Writes need a POS role (BaseViewSet -> IsPOSOrReadOnly); reads are open to any authenticated
    user, which is what lets the sales screens list them for a Cashier.
    """

    queryset = Quotation.objects.select_related('customer').prefetch_related('items__variant_uom')
    serializer_class = QuotationSerializer

    def perform_create(self, serializer):
        # created_by is never taken from the payload: the server records who actually asked.
        serializer.save(created_by=self.request.user)


class SalesOrderViewSet(BaseViewSet):
    """Phase 6 task 6A.2 (decision 05). Reads are open to any authenticated user; writes need a POS role."""

    queryset = SalesOrder.objects.select_related(
        'customer', 'quotation').prefetch_related('items__variant_uom')
    serializer_class = SalesOrderSerializer

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)
