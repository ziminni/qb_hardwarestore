# pyright: reportAttributeAccessIssue=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false
#
# Same reason as apps/requisitions/services.py: the root pyrightconfig.json is not
# found from this checker's working directory, and DRF serializer `validated_data`
# / Django choice enums resolve to `empty`/`None` without django-stubs.
# `reportGeneralTypeIssues` covers the same false positive one level down (the checker
# cannot see that `transaction.atomic()` is a context manager). The test run
# is the authority.
"""Requisitions app — ViewSets for project management and material release."""

from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import NotFound
from rest_framework.response import Response

from apps.pos.exceptions import NoOpenShift
from apps.users.models import AuditLog
from apps.users.permissions import (
    IsForemanOrManager,
    IsForemanOrManagerOrReadOnly,
    IsManagerRole,
    IsPOSRole,
    has_role,
)
from apps.users.services import audit_request

from .exceptions import NoBaseUom, RequisitionLocked
from .models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)
from .serializers import (
    MaterialTokenSerializer,
    ProjectSerializer,
    RequisitionItemSerializer,
    RequisitionSerializer,
    TokenVerifySerializer,
)
from .services import (
    approve_requisition,
    generate_req_number,
    reject_requisition,
    release_materials,
    submit_requisition,
    verify_token,
)


def _refusal(error):
    """400 with a stable `{code, detail}` body for a domain refusal that carries a code.

    Phase 2: every new refusal answers the same shape so the Flutter client can map a
    readable message without parsing prose. A plain `ValueError` (no `code`) keeps the
    old `{detail}` body.
    """
    code = getattr(error, 'code', None)
    if code:
        return Response(
            {'code': code, 'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)


def _requisition_locked_response(requisition):
    """400 `REQUISITION_LOCKED` unless `requisition` is DRAFT; None when it may change.

    P2 ruling (R): a requisition and its lines are immutable once they leave DRAFT —
    otherwise the lines could be edited after approval and the material token would
    release what nobody approved. `None` (unknown / missing parent) is left to the
    serializer, which already answers 400.
    """
    if requisition is None or requisition.status == Requisition.Status.DRAFT:
        return None
    return _refusal(RequisitionLocked(requisition.status))


def _requisition_from_payload(value, queryset=None):
    """The requisition a payload points at, or None when it is absent/garbage.

    ``queryset`` is the caller's SCOPE (``_visible_requisitions``): passing it is how an
    id outside the caller's world resolves to None (→ 404) instead of leaking the row.
    """
    source = Requisition.objects.all() if queryset is None else queryset
    try:
        return source.filter(pk=value).first()
    except (TypeError, ValueError):
        return None


def _is_manager(user):
    """Managers and admins see every requisition; a foreman only their own."""
    return has_role(user, IsManagerRole.required_roles)


def _visible_requisitions(user):
    """The requisitions ``user`` may see AND write into — one home for that rule.

    A manager/admin sees every row; a Site Foreman sees only ``requested_by=self``;
    anything else sees nothing. `RequisitionViewSet.get_queryset` and the requisition
    LINE writes both resolve the parent through this, so a line cannot be filed onto —
    or moved into — a requisition its author cannot read (review F5).
    """
    qs = Requisition.objects.all()
    if user is None or _is_manager(user):
        return qs
    return qs.filter(requested_by=user)


# ---------------------------------------------------------------------------
# Project ViewSet
# ---------------------------------------------------------------------------

class ProjectViewSet(viewsets.ModelViewSet):
    queryset = Project.objects.select_related('customer').all()
    serializer_class = ProjectSerializer
    permission_classes = [IsForemanOrManagerOrReadOnly]


# ---------------------------------------------------------------------------
# Requisition ViewSet
# ---------------------------------------------------------------------------

class RequisitionViewSet(viewsets.ModelViewSet):
    queryset = (
        Requisition.objects
        # project__customer, not project: the serializer exposes project.customer.name for the
        # approve queue's provenance, and stopping at project makes that a per-row query.
        # token is a REVERSE OneToOne (MaterialToken -> Requisition), so the serializer's
        # token field costs one query per row unless it is joined too.
        .select_related('project__customer', 'requested_by', 'token')
        .prefetch_related('items__variant')
        .all()
    )
    serializer_class = RequisitionSerializer

    def get_permissions(self):
        # Phase 2 (token secrecy): the material token is a BEARER credential — whoever
        # holds the UUID releases the goods on credit. Reads were open to any logged-in
        # account, so a cashier who was never handed a token could read one here. Reads
        # (and ordinary writes) now need Site Foreman / Store Manager / Admin; a
        # cashier, stocker or groupless account gets 403. `approve`/`reject` stay a
        # manager decision.
        if self.action in ('approve', 'reject'):
            return [IsManagerRole()]
        return [IsForemanOrManager()]

    def get_queryset(self):
        qs = super().get_queryset()
        # Decision 02 "hidden ≠ forbidden": a foreman asking for another foreman's
        # requisition gets 404, not 403, because the row is not theirs to know about.
        # The scope itself lives in `_visible_requisitions` so the line endpoints below
        # cannot drift from it.
        user = getattr(getattr(self, 'request', None), 'user', None)
        if user is None or _is_manager(user):
            return qs
        return qs.filter(requested_by=user)

    def perform_create(self, serializer):
        serializer.save(
            requested_by=self.request.user,
            req_number=generate_req_number(),
        )

    # --- Immutability after DRAFT (P2 ruling) ---

    def update(self, request, *args, **kwargs):
        # `partial_update` is overridden too because DRF routes PATCH to it directly.
        locked = _requisition_locked_response(self.get_object())
        if locked:
            return locked
        return super().update(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        locked = _requisition_locked_response(self.get_object())
        if locked:
            return locked
        return super().partial_update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        locked = _requisition_locked_response(self.get_object())
        if locked:
            return locked
        return super().destroy(request, *args, **kwargs)

    # --- Status transitions ---

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        """Submit a DRAFT requisition for approval."""
        req = self.get_object()
        try:
            submit_requisition(requisition=req)
        except ValueError as e:
            return _refusal(e)
        return Response({'detail': f'{req.req_number} submitted.'})

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Approve a SUBMITTED requisition and generate a MaterialToken."""
        req = self.get_object()
        try:
            # Approving, minting the token and recording who approved are ONE
            # transaction (decision 07). `SelfApproval` is raised before the first write,
            # so a refused self-approval writes no audit row either.
            with transaction.atomic():
                token = approve_requisition(requisition=req, approver=request.user)
                audit_request(
                    request,
                    AuditLog.ActionType.REQ_APPROVE,
                    f'Requisition {req.req_number} approved.',
                )
        except ValueError as e:
            # Includes `SelfApproval` (400 SELF_APPROVAL): separation of duties, nothing
            # written and no token minted.
            return _refusal(e)
        return Response({
            'detail': f'{req.req_number} approved.',
            'token': str(token.token),
        })

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Reject a SUBMITTED requisition."""
        req = self.get_object()
        try:
            with transaction.atomic():
                reject_requisition(requisition=req, approver=request.user)
                audit_request(
                    request,
                    AuditLog.ActionType.REQ_REJECT,
                    f'Requisition {req.req_number} rejected.',
                )
        except ValueError as e:
            return _refusal(e)
        return Response({'detail': f'{req.req_number} rejected.'})


# ---------------------------------------------------------------------------
# Token / Material Release endpoints
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsPOSRole])
def token_verify_view(request):
    """Verify a material token (UC-20: Scan/Verify Digital Material Token).

    Phase 2: POS work (Cashier / Store Manager / Admin). Verification describes what a
    token is FOR, so a stocker or a groupless account had no business reading it.
    """
    serializer = TokenVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    token_value = str(serializer.validated_data['token'])
    try:
        info = verify_token(token_value=token_value)
    except ValueError as e:
        return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    return Response(info)


@api_view(['POST'])
@permission_classes([IsPOSRole])
def material_release_view(request):
    """Release materials at POS (UC-21 + UC-22).

    Expects { "token": "<uuid>" }.  FIFO-deducts stock, creates
    SalesTransaction, and posts to CollectiblesLedger.
    """
    serializer = TokenVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    token_value = str(serializer.validated_data['token'])
    try:
        # The release and its audit row are one transaction (decision 07). The
        # description names the requisition and the resulting sale by DOCUMENT NUMBER;
        # the token UUID never appears, because it is a bearer credential that releases
        # goods on credit and an audit trail is readable by admins.
        with transaction.atomic():
            result = release_materials(
                token_value=token_value,
                cashier=request.user,
            )
            audit_request(
                request,
                AuditLog.ActionType.RELEASE,
                f'Materials released for requisition {result["req_number"]} '
                f'on transaction {result["transaction_no"]} '
                f'(total {result["grand_total"]}).',
            )
    except NoBaseUom as e:
        # Decision 09 item 6: a release the catalog cannot price for a base unit is a 400
        # with a stable `code`, not the 500 the IntegrityError used to produce. Raised
        # before the first write, so the token is still usable once the catalog is fixed.
        return _refusal(e)
    except NoOpenShift as e:
        # Decision 03: mirrors `POST /transactions/`, which the POS exception handler
        # already maps to 400 `NO_OPEN_SHIFT`. Named explicitly because NoOpenShift is
        # deliberately NOT a ValueError, so the handler below would let it through as a
        # 500. Raised inside the block, so this refusal leaves no RELEASE audit row.
        return _refusal(e)
    except ValueError as e:
        return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    return Response(result, status=status.HTTP_201_CREATED)


# ---------------------------------------------------------------------------
# MaterialToken ViewSet (read-only)
# ---------------------------------------------------------------------------

class MaterialTokenViewSet(viewsets.ReadOnlyModelViewSet):
    """Material tokens — a bearer credential, so only managers/admins may list them."""

    queryset = MaterialToken.objects.select_related('requisition').all()
    serializer_class = MaterialTokenSerializer
    permission_classes = [IsManagerRole]


# ---------------------------------------------------------------------------
# RequisitionItem ViewSet
# ---------------------------------------------------------------------------

class RequisitionItemViewSet(viewsets.ModelViewSet):
    """Requisition lines.

    Reads follow the parent requisition's rule (a Site Foreman sees only their own lines;
    everyone else 403), and a line can only be created/edited/deleted while its
    requisition is DRAFT (P2 ruling) — otherwise approved quantities could be changed
    after the token was minted.
    """

    # `order_by` matters: the model has no Meta.ordering, and DRF's paginator warns (and
    # can repeat a row across pages) on an unordered queryset.
    queryset = RequisitionItem.objects.select_related(
        'requisition', 'variant').order_by('pk')
    serializer_class = RequisitionItemSerializer
    permission_classes = [IsForemanOrManager]

    def get_queryset(self):
        qs = super().get_queryset()
        user = getattr(getattr(self, 'request', None), 'user', None)
        if user is None or _is_manager(user):
            return qs
        return qs.filter(requisition__requested_by=user)

    def _visible_parent(self, payload_value):
        """The requisition this payload targets, if the caller may write into it.

        Resolved through `_visible_requisitions`, the same scope the requisition list
        uses. An id the caller cannot see is **404** ("hidden ≠ forbidden") and nothing
        is written, instead of the unscoped lookup that let foreman B file a line onto
        foreman A's requisition (review F5). Absent key → None, which the serializer
        reports as its own 400.
        """
        if payload_value is None:
            return None
        parent = _requisition_from_payload(
            payload_value, _visible_requisitions(self.request.user))
        if parent is None:
            raise NotFound('Requisition not found.')
        return parent

    def create(self, request, *args, **kwargs):
        parent = self._visible_parent(request.data.get('requisition'))
        locked = _requisition_locked_response(parent)
        if locked:
            return locked
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, **kwargs):
        # `partial_update` delegates here, so PATCH is covered by the same guard.
        item = self.get_object()
        locked = _requisition_locked_response(item.requisition)
        if locked:
            return locked
        # Moving a line to another requisition is a write to BOTH parents: the new one has
        # to be visible to this caller AND a draft, or an approved line could be smuggled
        # into someone else's requisition.
        target = self._visible_parent(request.data.get('requisition'))
        if target is not None and target.pk != item.requisition_id:
            locked = _requisition_locked_response(target)
            if locked:
                return locked
        return super().update(request, *args, **kwargs)

    def destroy(self, request, *args, **kwargs):
        locked = _requisition_locked_response(self.get_object().requisition)
        if locked:
            return locked
        return super().destroy(request, *args, **kwargs)
