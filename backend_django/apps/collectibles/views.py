# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same directive and reason as apps/pos/tests.py, apps/inventory/views.py and
# seed_demo.py: the checker runs with a working directory outside the repo, so it resolves
# no config, and `Model.objects` is a false positive on valid Django.
# `reportGeneralTypeIssues` covers the same false positive one level down (the checker
# cannot see that `transaction.atomic()` is a context manager without django-stubs).

"""Collectibles ViewSets — Accounts Receivable / Utang Management."""

from django.db import transaction
from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from apps.pos.models import Payment
from apps.users.models import AuditLog
from apps.users.permissions import (
    IsManagerRole,
    IsReceivablesReader,
    ReceivablesReadPOSWrite,
)
from apps.users.services import audit_request

from .models import CollectibleLedger, CollectiblePayment, ProjectPaymentReceipt
from .serializers import (
    CollectibleLedgerSerializer,
    CollectiblePaymentSerializer,
    ProjectPaymentReceiptSerializer,
)
from .services import (
    Overpayment,
    ReceiptDecisionError,
    apply_payment_to_ledger,
    approve_payment_receipt,
    decline_payment_receipt,
)


class CollectibleLedgerViewSet(viewsets.ReadOnlyModelViewSet):
    """Read outstanding collectible/receivable entries. There are no ledger writes.

    Phase 2 Task 2 (P2 Ruling) made this viewset read-only. `balance_due` is the money a
    customer still owes, and the old `PATCH /ledgers/{id}/` let a Django-`is_staff` user
    set it to anything - which is indistinguishable from a customer paying. A ledger is
    now created and moved only by the code that knows why: `process_sale` and
    `release_materials` open one, and `POST /ledger-payments/` moves it. `ReadOnlyModelViewSet`
    (rather than a hand-written guard) means the router registers no PUT/PATCH/DELETE
    route at all, so those answers are 405 by construction.

    Reads need a RECEIVABLES role (Cashier / Store Manager / Admin): a Stock Manager
    reads sales, but customers' debts are not theirs to see.
    """

    queryset = CollectibleLedger.objects.select_related(
        'customer', 'transaction', 'project',
    ).prefetch_related(
        'payments__processed_by',
        'payments__payment_receipt',
        'payments__collectible__customer',
        'payments__collectible__transaction',
        'payments__collectible__project',
    ).order_by('-due_date')
    serializer_class = CollectibleLedgerSerializer
    permission_classes = [IsReceivablesReader]

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
    """Post and view payments against collectible ledgers.

    A payment row is a receipt of money, so it is **immutable**: `http_method_names`
    drops PUT/PATCH/DELETE, and the router therefore publishes only GET and POST.
    Editing one would erase a debt without any money moving, and deleting one would
    delete the record that the balance was already reduced. A correction is a new
    business event, not an edit of a past one.

    Reads need a RECEIVABLES role; the POST itself is a POS-role action (a cashier takes
    the money).
    """

    queryset = CollectiblePayment.objects.select_related(
        'collectible__customer',
        'collectible__transaction',
        'collectible__project',
        'processed_by',
        'payment_receipt',
    ).order_by('-payment_date', '-id')
    serializer_class = CollectiblePaymentSerializer
    permission_classes = [ReceivablesReadPOSWrite]
    http_method_names = ['get', 'head', 'options', 'post']

    def get_queryset(self):
        qs = super().get_queryset()
        collectible_id = self.request.query_params.get('collectible')
        search = (self.request.query_params.get('search') or '').strip()
        if collectible_id:
            qs = qs.filter(collectible_id=collectible_id)
        if search:
            qs = qs.filter(
                Q(collectible__customer__name__icontains=search)
                | Q(collectible__project__name__icontains=search)
                | Q(collectible__transaction__transaction_no__icontains=search)
                | Q(official_receipt_no__icontains=search)
                | Q(payment_receipt__reference_no__icontains=search),
            )
        return qs

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
            payment = serializer.save(processed_by=self.request.user)
            # The payment, the moved balance and the audit row are ONE transaction
            # (decision 07). The description names the sale by its document number.
            audit_request(
                self.request,
                AuditLog.ActionType.PAYMENT,
                f'Payment of {payment.amount_paid} posted against ledger '
                f'#{ledger.pk} for transaction {ledger.transaction.transaction_no}.',
            )

    def create(self, request, *args, **kwargs):
        """Post a payment - or, for a cheque, RECORD a pending one (B2, decision 18).

        A cheque is not money received: the bank has not honoured it yet. So a CHEQUE
        here does NOT move `balance_due` (that would settle a debt nobody paid), and it
        does not write a `CollectiblePayment` (that row means "money came in"). It writes
        a PENDING `pos.Payment` against this ledger's transaction - the same table the
        till's cheques live in, so ONE queue lists every cheque the shop is waiting on,
        and `POST /api/v1/cheques/{id}/clear/` is the one place a cheque becomes money.

        The 201 body is that cheque row, not a payment row: the client sent a cheque and
        is told what was recorded, including that it is still PENDING.
        """
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if serializer.validated_data['payment_method'] == Payment.Method.CHEQUE:
            from apps.pos.serializers import ChequeSerializer
            from apps.pos.services import record_cheque_against_ledger

            with transaction.atomic():
                cheque = record_cheque_against_ledger(
                    ledger_id=serializer.validated_data['collectible'].pk,
                    amount=serializer.validated_data['amount_paid'],
                    cheque_number=serializer.validated_data['cheque_number'],
                    bank=serializer.validated_data['bank'],
                    cheque_date=serializer.validated_data['cheque_date'],
                    reference_no=serializer.validated_data.get(
                        'official_receipt_no', ''),
                )
                # Decision 07: the cheque and the trail entry are one transaction, so a
                # cancelled request cannot leave a cheque with no reason recorded.
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f'Pending cheque {cheque.cheque_number} for {cheque.amount_tendered} '
                    f'recorded against ledger #{cheque.ledger_id} for transaction '
                    f'{cheque.transaction.transaction_no}.',
                )
            return Response(
                ChequeSerializer(cheque).data,
                status=status.HTTP_201_CREATED,
            )

        return super().create(request, *args, **kwargs)


class ProjectPaymentReceiptViewSet(viewsets.ReadOnlyModelViewSet):
    """Staff review queue for CPMS online payment receipts (Phase 1c)."""

    queryset = ProjectPaymentReceipt.objects.select_related(
        'project__customer', 'decided_by'
    ).order_by('-created_at', '-id')
    serializer_class = ProjectPaymentReceiptSerializer
    permission_classes = [ReceivablesReadPOSWrite]

    def get_permissions(self):
        # Approving moves project debt: a manager decision, like clearing a cheque.
        if self.action in ('approve', 'decline'):
            return [IsManagerRole()]
        return super().get_permissions()

    def get_queryset(self):
        qs = super().get_queryset()
        status_filter = self.request.query_params.get('status')
        if status_filter:
            qs = qs.filter(status=status_filter.upper())
        return qs

    @action(detail=True, methods=['post'], url_path='approve')
    def approve(self, request, pk: str):
        """Approve a WAITING CPMS payment receipt (full or partial) and post ledger payments."""
        raw_amount = request.data.get('approved_amount')
        approved_amount = None
        if raw_amount not in (None, ''):
            from decimal import Decimal, InvalidOperation

            try:
                approved_amount = Decimal(str(raw_amount))
            except (InvalidOperation, TypeError, ValueError):
                return Response(
                    {
                        'code': 'INVALID_APPROVED_AMOUNT',
                        'detail': 'Enter a valid approved amount.',
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
        try:
            with transaction.atomic():
                receipt = approve_payment_receipt(
                    receipt_id=int(pk),
                    actor=request.user,
                    approved_amount=approved_amount,
                )
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f'Approved CPMS payment receipt {receipt.reference_no} '
                    f'({receipt.approved_amount:.2f}) for project '
                    f'{receipt.project.cpms_project_id}.',
                )
        except ReceiptDecisionError as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Overpayment as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(ProjectPaymentReceiptSerializer(receipt).data)

    @action(detail=True, methods=['post'], url_path='decline')
    def decline(self, request, pk: str):
        """Decline a WAITING CPMS payment receipt with a required reason."""
        reason = request.data.get('reason', '')
        try:
            with transaction.atomic():
                receipt = decline_payment_receipt(
                    receipt_id=int(pk),
                    actor=request.user,
                    reason=str(reason or ''),
                )
                audit_request(
                    request,
                    AuditLog.ActionType.PAYMENT,
                    f'Declined CPMS payment receipt {receipt.reference_no} for project '
                    f'{receipt.project.cpms_project_id}: {receipt.decline_reason}',
                )
        except ReceiptDecisionError as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(ProjectPaymentReceiptSerializer(receipt).data)
