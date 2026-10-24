# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same reason as apps/inventory/views.py and seed_demo.py: the checker resolves its
# config from its WORKING DIRECTORY and does not run inside this repo here, so a
# pyrightconfig.json is not found. This travels with the file. It disables the one
# rule that cannot model Django's `Model.objects` without django-stubs, plus the same
# `transaction.atomic()` context-manager false positive documented in
# apps/collectibles/views.py (Phase 2 task 5 wraps events in explicit atomic blocks).
from django.db.models import Sum
from decimal import Decimal
from decimal import InvalidOperation
from django.db import IntegrityError
from django.db import transaction as db_transaction
from django.db.models.deletion import ProtectedError
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound
from rest_framework.response import Response
from apps.users.models import AuditLog
from apps.users.permissions import (
    IsManagerRole, IsPOSOrReadOnly, IsPOSRole, SalesReadPOSWrite,
    has_role, is_cashier_only,
)
from apps.users.services import audit_request
from .exceptions import CreditLimitForbidden
from .models import Customer, SalesTransaction, Payment, OfficialReceipt
from .models import Quotation, SalesOrder
from .models import HeldCart
from .models import Shift
from .serializers import CustomerSerializer, SalesTransactionSerializer, PaymentSerializer, OfficialReceiptSerializer
from .serializers import QuotationSerializer, SalesOrderSerializer
from .serializers import HeldCartSerializer
from .serializers import ShiftSerializer
from .services import process_sale
from .services import (
    parse_idempotency_key, request_body_hash, replayed_transaction,
)

# Decision 09 item 2: the optional retry token. A client that times out mid-checkout
# resends the SAME key and gets the original sale back instead of ringing a second one.
IDEMPOTENCY_HEADER = 'Idempotency-Key'


def _idempotency_inputs(request, scope):
    """(key, request hash) for this request, or (None, '') when no header was sent.

    Read from `request.headers`, which is case-insensitive - a client sending
    `idempotency-key` is not making an error. The hash is computed over the parsed body
    (not the raw stream) so a pretty-printed re-send still matches its own retry.

    `scope` names WHAT this key was spent on (`transactions.create`, or
    `held-carts.<pk>.complete`) and is hashed alongside the body, because the body alone
    does not identify a request: two different held carts of the same size with the same
    tender POST identical `{"payments": [...]}` bodies, and an unscoped hash made the
    second one replay the first one's receipt - cart B was never sold, and its money was
    never taken. Same reasoning across endpoints: a key spent on checkout must not
    complete a cart. The scope is only folded in when a key IS sent, so an unkeyed
    request stays exactly as cheap as it was.
    """
    key = parse_idempotency_key(request.headers.get(IDEMPOTENCY_HEADER))
    if key is None:
        return None, ''
    return key, request_body_hash({'scope': scope, 'body': request.data})


def _replayed_response(transaction):
    """200, not 201: nothing was created, the client is being shown its own sale."""
    return Response(
        SalesTransactionSerializer(transaction).data,
        status=status.HTTP_200_OK,
    )


class BaseViewSet(viewsets.ModelViewSet):
    """Read needs a SALES role; write needs a POS role (decision 02, Phase 2).

    Reads used to be open to any authenticated user, which handed quotations, customers
    and the whole sales history to a Site Foreman or to a groupless account. `foreman`
    is not a sales role: 403. A Stock Manager IS a sales reader (P2 Ruling - the stocker
    Sales tab reads all sales), it just cannot write one.
    """

    permission_classes = [SalesReadPOSWrite]


class OwnSalesScopeMixin:
    """Row-level scope: a cashier-only user sees the sales THEY rang, nobody else's.

    Manager / Admin / Stock Manager see the whole store. `own_scope_field` is the lookup
    that reaches the cashier who owns the row: `cashier` on a transaction, and
    `transaction__cashier` on a payment or a receipt.

    Filtering the QUERYSET, rather than refusing in a permission class, is what makes a
    non-owner's detail URL a **404**: within this caller's world the row does not exist,
    so the API neither confirms it nor reveals whose till rang it ("hidden ≠ forbidden",
    decision 02). It also scopes `daily_report` for free, because that action already
    aggregates `self.get_queryset()`.
    """

    own_scope_field = 'cashier'

    def get_queryset(self):
        qs = super().get_queryset()
        if is_cashier_only(self.request.user):
            return qs.filter(**{self.own_scope_field: self.request.user})
        return qs


def _refuse_credit_limit_from_non_manager(request):
    """403 when a non-manager sends `total_credit_limit` (decision 08, Phase 2).

    The field is only refused when it is actually PRESENT: an older client that posts a
    customer without it keeps working, and a cashier editing a customer's phone number
    is not asked for a manager's permission. Nothing is written, because this runs
    before the serializer sees the payload.
    """
    if 'total_credit_limit' not in request.data:
        return
    if has_role(request.user, IsManagerRole.required_roles):
        return
    raise CreditLimitForbidden()


class CustomerViewSet(BaseViewSet):
    """Customers: sales roles read, POS roles write, managers alone set credit limits."""

    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer

    def get_permissions(self):
        # Deleting a customer erases who owed what, so it is a manager decision - a
        # cashier may not make a debtor's history disappear.
        if self.action == 'destroy':
            return [IsManagerRole()]
        return super().get_permissions()

    def create(self, request, *args, **kwargs):
        _refuse_credit_limit_from_non_manager(request)
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        # `partial_update` delegates here, so PATCH is covered by the same guard.
        _refuse_credit_limit_from_non_manager(request)
        return super().update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        try:
            return super().destroy(request, *args, **kwargs)
        except ProtectedError:
            # Sales, quotations, orders, ledgers and requisitions PROTECT their customer:
            # deleting one would orphan money. 409 with a stable code, never a 500.
            return Response(
                {'code': 'CUSTOMER_IN_USE',
                 'detail': 'This customer has sales or receivables and cannot be '
                           'deleted. Deactivate them instead.'},
                status=status.HTTP_409_CONFLICT,
            )


class SalesTransactionViewSet(OwnSalesScopeMixin, BaseViewSet):
    queryset = SalesTransaction.objects.select_related('customer','cashier').prefetch_related('items','payments','receipt').all()
    serializer_class = SalesTransactionSerializer

    def get_queryset(self):
        # `super()` reaches `OwnSalesScopeMixin.get_queryset`, so the cashier-only scope
        # is applied BEFORE the source filter below (both apply, in either order).
        qs = super().get_queryset()
        # Decision 15's amendment wires the returns page over
        # GET /transactions/?source=RETURN: the page must isolate returns.
        source = self.request.query_params.get('source')
        if source:
            qs = qs.filter(source=source.upper())
        return qs

    def create(self, request):
        idempotency_key, body_hash = _idempotency_inputs(request, 'transactions.create')
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        source = ser.validated_data.get('source','WALK_IN')
        if source == 'RETURN':
            # Ledger ruling: this phase protects CHECKOUT with idempotency, not returns.
            # A refund is already re-checkable against the original sale it reverses.
            from .services import process_return
            # Phase 2 task 5 (decision 07): the return and its audit row are one
            # transaction. `process_return` owns its own atomic block, so this is a
            # savepoint nested in the outer one - the row commits or rolls back with the
            # refund it describes.
            with db_transaction.atomic():
                txn = process_return(
                    customer_id=ser.validated_data['customer'].id,
                    cashier=request.user,
                    items_data=request.data.get('items',[]),
                    original_transaction_id=request.data.get('original_transaction'),
                    payment_method=request.data.get('payment_method','CASH'),
                )
                audit_request(
                    request,
                    AuditLog.ActionType.RETURN,
                    f'Return {txn.transaction_no} posted for '
                    f'{txn.grand_total} by {request.user.username}.',
                )
            return Response(self.get_serializer(txn).data, status=status.HTTP_201_CREATED)

        # Decision 09 item 2: replay BEFORE ringing anything. The common retry is a
        # client that never saw the 201, and answering it from the recorded row is what
        # makes "one key, one sale" true even when the first response was lost.
        if idempotency_key:
            replayed = replayed_transaction(
                cashier=request.user, idempotency_key=idempotency_key,
                request_hash=body_hash)
            if replayed is not None:
                return _replayed_response(replayed)

        try:
            # The sale and its audit row are ONE transaction (decision 07). The replay
            # branch above returns before this block, so an idempotent 200 writes no row;
            # the `except IntegrityError` below deliberately sits OUTSIDE it, because
            # that handler has to re-read the database after the block rolled back.
            with db_transaction.atomic():
                txn = process_sale(
                    customer_id=ser.validated_data['customer'].id,
                    cashier=request.user,
                    items_data=request.data.get('items',[]),
                    payments_data=request.data.get('payments',[]),
                    source=source,
                    idempotency_key=idempotency_key,
                    request_hash=body_hash,
                )
                audit_request(
                    request,
                    AuditLog.ActionType.SALE,
                    f'Sale {txn.transaction_no} rung for {txn.grand_total} '
                    f'({source}) by {request.user.username}.',
                )
        except IntegrityError:
            # The race the pre-check cannot win: two retries both read "no such key" and
            # both insert, and only the unique constraint on (cashier, idempotency_key)
            # can refuse the second. `process_sale`'s own atomic block has already rolled
            # back to its savepoint, so the connection is clean and re-reading here is
            # legal - this except clause must stay OUTSIDE that block for exactly that
            # reason. A different payload is a 409; the same one is a replay.
            if not idempotency_key:
                raise
            replayed = replayed_transaction(
                cashier=request.user, idempotency_key=idempotency_key,
                request_hash=body_hash)
            if replayed is None:
                raise
            return _replayed_response(replayed)
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
            # The shift and its audit row are one transaction (decision 07): the
            # IntegrityError handler below has to sit outside it, because it re-reads
            # the state the block just rolled back.
            with db_transaction.atomic():
                shift = Shift.objects.create(
                    cashier=request.user,
                    opening_float=opening_float,
                    notes=request.data.get('notes', ''),
                )
                audit_request(
                    request,
                    AuditLog.ActionType.SHIFT_OPEN,
                    f'Shift #{shift.pk} opened with float {opening_float}.',
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
        # The close and its audit row are one transaction (decision 07).
        with db_transaction.atomic():
            shift.save(update_fields=[
                'closing_count', 'status', 'closed_at', 'notes'])
            audit_request(
                request,
                AuditLog.ActionType.SHIFT_CLOSE,
                f'Shift #{shift.pk} closed with count {closing_count} '
                f'(float {shift.opening_float}).',
            )
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


class PaymentViewSet(OwnSalesScopeMixin, viewsets.ReadOnlyModelViewSet):
    """Read-only POS payments, scoped to the caller's own sales for a cashier-only user.

    A payment row carries the till's money, so it follows its transaction: a cashier sees
    their own, a manager / stocker / admin sees the store (P2 Ruling - the stocker Sales
    tab sums every sale).
    """

    # `order_by('id')` is not cosmetic: paginated results from an unordered queryset can
    # repeat or skip a row between pages (UnorderedObjectListWarning), and a payment list
    # that skips a row is money missing from a screen.
    queryset = Payment.objects.select_related('transaction').order_by('id')
    serializer_class = PaymentSerializer
    permission_classes = [SalesReadPOSWrite]
    own_scope_field = 'transaction__cashier'


class OfficialReceiptViewSet(OwnSalesScopeMixin, viewsets.ReadOnlyModelViewSet):
    """Read-only official receipts, scoped exactly like the payments they record."""

    queryset = OfficialReceipt.objects.select_related('transaction').all()
    serializer_class = OfficialReceiptSerializer
    permission_classes = [SalesReadPOSWrite]
    own_scope_field = 'transaction__cashier'


class QuotationViewSet(BaseViewSet):
    """Decision 05: quotations are a real backend resource.

    Reads need a SALES role and writes a POS role (BaseViewSet -> SalesReadPOSWrite), which is
    what lets every sales screen list them while keeping a Site Foreman or a groupless account out.
    """

    queryset = Quotation.objects.select_related('customer').prefetch_related('items__variant_uom')
    serializer_class = QuotationSerializer

    def perform_create(self, serializer):
        # created_by is never taken from the payload: the server records who actually asked.
        serializer.save(created_by=self.request.user)


class SalesOrderViewSet(BaseViewSet):
    """Phase 6 task 6A.2 (decision 05). Reads need a SALES role; writes need a POS role."""

    queryset = SalesOrder.objects.select_related(
        'customer', 'quotation').prefetch_related('items__variant_uom')
    serializer_class = SalesOrderSerializer

    def perform_create(self, serializer):
        serializer.save(created_by=self.request.user)


class HeldCartViewSet(BaseViewSet):
    """Held/parked carts — Phase 3 of cashier-workflow.

    EVERY method requires a POS role (decision 02): a parked cart is live till work, so a
    Stock Manager or Site Foreman gets 403 even on GET. Among POS roles the carts stay
    store-wide - decision 05's "any cashier may resume" is unchanged, so the queryset is
    NOT scoped to `cashier=request.user`.
    """

    queryset = HeldCart.objects.select_related('cashier', 'customer').prefetch_related('items__variant_uom')
    serializer_class = HeldCartSerializer
    permission_classes = [IsPOSRole]

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

    def destroy(self, request, *args, **kwargs):
        """DELETE /held-carts/{id}/ — voiding a parked cart is a business event.

        A cart is thrown away for a reason (customer walked out, rang it at another
        till), so the removal is recorded with its id and line count. The row and the
        delete are one transaction: a refused delete writes nothing.
        """
        cart = self.get_object()
        cart_pk = cart.pk
        line_count = cart.items.count()
        with db_transaction.atomic():
            cart.delete()
            audit_request(
                request,
                AuditLog.ActionType.CART_VOID,
                f'Held cart #{cart_pk} voided ({line_count} line(s)).',
            )
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=True, methods=['post'])
    def complete(self, request, pk=None):
        # Scope names THIS cart: completing cart B with cart A's key is a 409, not a
        # replay of A (a body-only hash cannot tell the two carts apart).
        idempotency_key, body_hash = _idempotency_inputs(
            request, f'held-carts.{pk}.complete')
        # Decision 09 item 4, and the ruling that made it necessary: the first successful
        # completion DELETES the cart, so this check must run BEFORE `get_object()`.
        # Otherwise a retry of a sale that already rang answers 404 about a cart whose
        # money is in the drawer - the cashier would take payment twice or lose the sale.
        if idempotency_key:
            replayed = replayed_transaction(
                cashier=request.user, idempotency_key=idempotency_key,
                request_hash=body_hash)
            if replayed is not None:
                return _replayed_response(replayed)

        cart = self.get_object()
        # Phase 1 task 1 (decision 01): the cart on the shelf stores a price, but that
        # price is a NOTE, not an authority - a cart parked yesterday, or tampered with,
        # must not set today's price. So it is not forwarded: `process_sale` prices every
        # line from `VariantUOM.default_selling_price` and converts selling units to base
        # units, exactly as the checkout screen does. One price authority, both entry
        # points.
        items_data = [
            {'variant_id': item.variant_uom_id, 'qty': item.qty}
            for item in cart.items.all()
        ]
        payments_data = request.data.get('payments', [])
        customer_id = cart.customer_id or request.data.get('customer')
        if not customer_id:
            from apps.pos.models import Customer
            customer_id = Customer.objects.filter(
                customer_type=Customer.Type.WALK_IN).values_list('id', flat=True).first()
        from django.db import transaction as db_transaction
        try:
            with db_transaction.atomic():
                txn = process_sale(
                    customer_id=customer_id,
                    cashier=request.user,
                    items_data=items_data,
                    payments_data=payments_data,
                    idempotency_key=idempotency_key,
                    request_hash=body_hash,
                )
                cart.delete()
                # Inside THIS block (decision 07): the sale, the deleted cart and the
                # audit row commit together. A refused completion (insufficient stock)
                # rolls back and leaves no row claiming a sale happened.
                audit_request(
                    request,
                    AuditLog.ActionType.SALE,
                    f'Sale {txn.transaction_no} rung for {txn.grand_total} from held '
                    f'cart #{cart.pk} by {request.user.username}.',
                )
        except IntegrityError:
            # Same race as `SalesTransactionViewSet.create`, and handled the same way:
            # the atomic block above has rolled back (cart still held), so re-reading is
            # legal and the answer is the already-recorded sale (200) or a 409.
            if not idempotency_key:
                raise
            replayed = replayed_transaction(
                cashier=request.user, idempotency_key=idempotency_key,
                request_hash=body_hash)
            if replayed is None:
                raise
            return _replayed_response(replayed)
        return Response(
            SalesTransactionSerializer(txn).data,
            status=status.HTTP_201_CREATED,
        )
