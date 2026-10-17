# pyright: reportAttributeAccessIssue=false
#
# Same directive and reason as apps/pos/tests.py, apps/inventory/views.py and
# seed_demo.py: the checker runs with a working directory outside the repo, so it resolves
# no config, and `Model.objects` is a false positive on valid Django.

"""Collectibles ViewSets — Accounts Receivable / Utang Management."""

from django.db.models import Q
from django.db import transaction
from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.users.permissions import IsPOSOrReadOnly

from .models import CollectibleLedger, CollectiblePayment
from .services import apply_payment_to_ledger
from .serializers import CollectibleLedgerSerializer, CollectiblePaymentSerializer


class IsAdminOrReadOnly(permissions.BasePermission):
    """Allow read for all authenticated users; write only for admins."""

    def has_permission(self, request, view):
        if request.method in permissions.SAFE_METHODS:
            return request.user and request.user.is_authenticated
        return request.user and request.user.is_staff


class CollectibleLedgerViewSet(viewsets.ModelViewSet):
    """Manage outstanding collectible/receivable entries."""

    queryset = CollectibleLedger.objects.select_related(
        'customer', 'transaction',
    ).prefetch_related('payments').order_by('-due_date')
    serializer_class = CollectibleLedgerSerializer
    permission_classes = [IsAdminOrReadOnly]

    def get_queryset(self):
        qs = super().get_queryset()
        status_filter = self.request.query_params.get('status')
        customer_id = self.request.query_params.get('customer')

        if status_filter:
            qs = qs.filter(status=status_filter.upper())
        if customer_id:
            qs = qs.filter(customer_id=customer_id)
        return qs

    @action(detail=False, methods=['get'], url_path='aging')
    def aging_report(self, request):
        """Return overdue / open balances grouped by customer.

        GET /collectibles/ledgers/aging/
        """
        overdue_qs = self.get_queryset().filter(
            Q(status__in=['OPEN', 'PARTIAL', 'OVERDUE']),
        ).select_related('customer')

        # Build per-customer summary
        aging = {}
        for entry in overdue_qs:
            cust_id = entry.customer_id
            if cust_id not in aging:
                aging[cust_id] = {
                    'customer_id': cust_id,
                    'customer_name': entry.customer.name,
                    'total_balance': 0,
                    'open_count': 0,
                    'overdue_count': 0,
                    'entries': [],
                }
            aging[cust_id]['total_balance'] += entry.balance_due
            if entry.is_overdue:
                aging[cust_id]['overdue_count'] += 1
            else:
                aging[cust_id]['open_count'] += 1
            aging[cust_id]['entries'].append(
                CollectibleLedgerSerializer(entry).data,
            )

        return Response({
            'total_customers': len(aging),
            'total_outstanding': sum(
                g['total_balance'] for g in aging.values()
            ),
            'groups': sorted(
                aging.values(),
                key=lambda g: g['total_balance'],
                reverse=True,
            ),
        })


class CollectiblePaymentViewSet(viewsets.ModelViewSet):
    """Post and view payments against collectible ledgers."""

    queryset = CollectiblePayment.objects.select_related(
        'collectible', 'processed_by',
    ).order_by('-payment_date')
    serializer_class = CollectiblePaymentSerializer
    permission_classes = [IsPOSOrReadOnly]

    def perform_create(self, serializer):
        """Record the payment and move the ledger, as ONE transaction.

        Saving the payment without moving `balance_due` was the defect this
        replaces: the receivable kept reporting the full amount owed no matter
        how much had been paid against it. `select_for_update` is taken first so
        two terminals cannot both pay the last peso and have one payment lost.
        """
        with transaction.atomic():
            ledger = CollectibleLedger.objects.select_for_update().get(
                pk=serializer.validated_data['collectible'].pk,
            )
            apply_payment_to_ledger(
                ledger,
                serializer.validated_data['amount_paid'],
            )
            serializer.save(processed_by=self.request.user)
