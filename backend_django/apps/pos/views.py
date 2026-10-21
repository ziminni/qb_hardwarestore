# pyright: reportAttributeAccessIssue=false
#
# Same reason as apps/inventory/views.py and seed_demo.py: the checker resolves its
# config from its WORKING DIRECTORY and does not run inside this repo here, so a
# pyrightconfig.json is not found. This travels with the file. It disables the one
# rule that cannot model Django's `Model.objects` without django-stubs.
from django.db.models import Sum
from decimal import Decimal
from decimal import InvalidOperation
from django.db import IntegrityError
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from apps.users.permissions import IsPOSOrReadOnly, IsManagerRole
from .models import Customer, SalesTransaction, Payment, OfficialReceipt
from .models import Quotation, SalesOrder
from .models import HeldCart
from .models import Shift
from .serializers import CustomerSerializer, SalesTransactionSerializer, PaymentSerializer, OfficialReceiptSerializer
from .serializers import QuotationSerializer, SalesOrderSerializer
from .serializers import HeldCartSerializer
from .serializers import ShiftSerializer
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

    def get_queryset(self):
        qs = super().get_queryset()
        # Decision 15's amendment wires the returns page over
        # GET /transactions/?source=RETURN: the page must isolate returns.
        source = self.request.query_params.get('source')
        if source:
            qs = qs.filter(source=source.upper())
        return qs

    def create(self, request):
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        source = ser.validated_data.get('source','WALK_IN')
        if source == 'RETURN':
            from .services import process_return
            txn = process_return(
                customer_id=ser.validated_data['customer'].id,
                cashier=request.user,
                items_data=request.data.get('items',[]),
                original_transaction_id=request.data.get('original_transaction'),
                payment_method=request.data.get('payment_method','CASH'),
            )
        else:
            txn = process_sale(
                customer_id=ser.validated_data['customer'].id,
                cashier=request.user,
                items_data=request.data.get('items',[]),
                payments_data=request.data.get('payments',[]),
                source=source,
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


class ShiftViewSet(viewsets.ReadOnlyModelViewSet):
    """Cashier shifts and their Z-readings (Phase 4, decision 06).

    ReadOnlyModelViewSet, not ModelViewSet: the router then registers no create/update/
    destroy route at all, so `POST /shifts/` and `DELETE /shifts/{id}/` are 405 by
    construction rather than by a hand-written guard. A shift opens and closes only
    through the two actions below, which is what makes "OPEN never goes back to CLOSED"
    and "exactly one open shift" enforceable in one place.

    `post` is still in `http_method_names` because the ACTION routes are POSTs; the
    collection and detail routes simply do not exist for it.
    """

    queryset = Shift.objects.select_related('cashier').all()
    serializer_class = ShiftSerializer
    permission_classes = [IsPOSOrReadOnly]
    http_method_names = ['get', 'head', 'options', 'post']

    def get_queryset(self):
        """Cashier sees only their own shifts; a manager sees everyone's.

        Decision 06: "Cashier sees their own; manager sees all." Filtering here rather
        than in a permission class keeps it one rule - a cashier CAN read shifts, just
        not other people's - instead of a 403 that leaks whose shift a URL is.
        """
        qs = super().get_queryset()
        user = self.request.user
        if user.is_superuser or user.groups.filter(
                name__in=IsManagerRole.required_roles).exists():
            return qs
        return qs.filter(cashier=user)

    @action(detail=False, methods=['post'], url_path='open')
    def open_shift(self, request):
        """POST /shifts/open/ {opening_float} -> 201 with the new open shift."""
        raw_float = request.data.get('opening_float', '0')
        try:
            opening_float = Decimal(str(raw_float))
        except (InvalidOperation, TypeError, ValueError):
            return Response(
                {'code': 'INVALID_OPENING_FLOAT',
                 'detail': 'opening_float must be a number.'},
                status=status.HTTP_400_BAD_REQUEST)
        if opening_float < 0:
            return Response(
                {'code': 'INVALID_OPENING_FLOAT',
                 'detail': 'opening_float cannot be negative.'},
                status=status.HTTP_400_BAD_REQUEST)

        if Shift.objects.filter(cashier=request.user,
                                status=Shift.Status.OPEN).exists():
            return Response(
                {'code': 'SHIFT_ALREADY_OPEN',
                 'detail': 'You already have an open shift. Close it first.'},
                status=status.HTTP_400_BAD_REQUEST)
        try:
            shift = Shift.objects.create(
                cashier=request.user,
                opening_float=opening_float,
                notes=request.data.get('notes', ''),
            )
        except IntegrityError:
            # The partial unique index is the real guard: two concurrent opens both pass
            # the check above, and only the database can refuse the second. Same 400, so
            # the client sees one answer whichever layer caught it.
            return Response(
                {'code': 'SHIFT_ALREADY_OPEN',
                 'detail': 'You already have an open shift. Close it first.'},
                status=status.HTTP_400_BAD_REQUEST)
        return Response(
            self.get_serializer(shift).data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], url_path='close')
    def close_shift(self, request, pk=None):
        """POST /shifts/{id}/close/ {closing_count} -> the closed shift + Z-reading.

        Ruling 3: a variance is RECORDED, never blocking. Management reviews it later;
        a cashier stuck at a closed till because the drawer is 20 pesos off is a worse
        outcome than a logged discrepancy.
        """
        shift = self.get_object()
        if shift.status == Shift.Status.CLOSED:
            return Response(
                {'code': 'SHIFT_ALREADY_CLOSED',
                 'detail': 'This shift is already closed.'},
                status=status.HTTP_400_BAD_REQUEST)
        raw_count = request.data.get('closing_count')
        if raw_count is None:
            return Response(
                {'code': 'CLOSING_COUNT_REQUIRED',
                 'detail': 'closing_count is required to close a shift.'},
                status=status.HTTP_400_BAD_REQUEST)
        try:
            closing_count = Decimal(str(raw_count))
        except (InvalidOperation, TypeError, ValueError):
            return Response(
                {'code': 'INVALID_CLOSING_COUNT',
                 'detail': 'closing_count must be a number.'},
                status=status.HTTP_400_BAD_REQUEST)
        if closing_count < 0:
            return Response(
                {'code': 'INVALID_CLOSING_COUNT',
                 'detail': 'closing_count cannot be negative.'},
                status=status.HTTP_400_BAD_REQUEST)

        shift.closing_count = closing_count
        shift.status = Shift.Status.CLOSED
        shift.closed_at = timezone.now()
        if request.data.get('notes'):
            shift.notes = request.data['notes']
        shift.save(update_fields=[
            'closing_count', 'status', 'closed_at', 'notes'])
        return Response(self.get_serializer(shift).data)

    @action(detail=False, methods=['get'])
    def current(self, request):
        """GET /shifts/current/ -> the caller's open shift, or 404.

        404 and not 200-with-null: the POS shell gates the till on this call, and "no
        shift" is the absence of the resource it asked for. The client branches on the
        status code it already knows how to read.
        """
        shift = self.get_queryset().filter(
            cashier=request.user, status=Shift.Status.OPEN).first()
        if shift is None:
            raise NotFound('No open shift for this cashier.')
        return Response(self.get_serializer(shift).data)


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


class HeldCartViewSet(BaseViewSet):
    """Held/parked carts — Phase 3 of cashier-workflow."""
    queryset = HeldCart.objects.select_related('cashier', 'customer').prefetch_related('items__variant_uom')
    serializer_class = HeldCartSerializer

    def perform_create(self, serializer):
        serializer.save(cashier=self.request.user)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        instance = self.get_queryset().get(pk=serializer.instance.pk)
        return Response(
            self.get_serializer(instance).data,
            status=status.HTTP_201_CREATED,
        )

    @action(detail=True, methods=['post'])
    def complete(self, request, pk=None):
        cart = self.get_object()
        items_data = [
            {'variant_id': item.variant_uom_id, 'qty': item.qty, 'unit_price': item.unit_price}
            for item in cart.items.all()
        ]
        payments_data = request.data.get('payments', [])
        customer_id = cart.customer_id or request.data.get('customer')
        from django.db import transaction as db_transaction
        with db_transaction.atomic():
            txn = process_sale(
                customer_id=customer_id,
                cashier=request.user,
                items_data=items_data,
                payments_data=payments_data,
            )
            cart.delete()
        return Response(
            SalesTransactionSerializer(txn).data,
            status=status.HTTP_201_CREATED,
        )
