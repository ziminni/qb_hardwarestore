from django.db.models import Sum
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from apps.users.permissions import IsPOSOrReadOnly
from .models import Customer, SalesTransaction, Payment, OfficialReceipt
from .serializers import CustomerSerializer, SalesTransactionSerializer, PaymentSerializer, OfficialReceiptSerializer
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
        from django.utils import timezone
        from datetime import timedelta
        today = timezone.localdate()
        qs = self.get_queryset().filter(trans_date__date=today)
        total = qs.aggregate(total=Sum('grand_total'))['total'] or 0
        return Response({'date': str(today), 'count': qs.count(), 'total_sales': total})


class PaymentViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Payment.objects.select_related('transaction').all()
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]


class OfficialReceiptViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = OfficialReceipt.objects.select_related('transaction').all()
    serializer_class = OfficialReceiptSerializer
    permission_classes = [IsAuthenticated]
