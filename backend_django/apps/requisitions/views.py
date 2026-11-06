# pyright: reportAttributeAccessIssue=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false
#
# Same reason as apps/requisitions/services.py: the root pyrightconfig.json is not
# found from this checker's working directory, and DRF serializer `validated_data`
# / Django choice enums resolve to `empty`/`None` without django-stubs.
# `reportGeneralTypeIssues` covers the same false positive one level down (the checker
# cannot see that `transaction.atomic()` is a context manager). The test run
# is the authority.
"""Requisitions app — read-only copies of CPMS requests, plus the till's token endpoints.

Decision 01: CPMS creates a material request and its project manager approves it, so the
POS neither requests nor approves anything. The requisition, line and project endpoints
are therefore READ-ONLY (list/retrieve for the manager/admin audience that already read
them); the cashier's two token endpoints — verify and release — are the only writes here.
"""

from django.db import transaction
from rest_framework import status, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from apps.pos.exceptions import NoOpenShift
from apps.users.models import AuditLog
from apps.users.permissions import IsManagerRole, IsPOSRole
from apps.users.services import audit_request

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
from .services import release_materials, verify_token


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


# ---------------------------------------------------------------------------
# Project ViewSet
# ---------------------------------------------------------------------------

class ProjectViewSet(viewsets.ReadOnlyModelViewSet):
    """Projects, read-only: they arrive with a CPMS push (decision 03).

    The read audience is what it was before the writes went: any signed-in account
    (the CPMS service account is fenced out in `apps.users.authentication`).
    """

    queryset = Project.objects.select_related('customer').all()
    serializer_class = ProjectSerializer
    permission_classes = [IsAuthenticated]


# ---------------------------------------------------------------------------
# Requisition ViewSet
# ---------------------------------------------------------------------------

class RequisitionViewSet(viewsets.ReadOnlyModelViewSet):
    """The POS copy of what CPMS approved (decisions 01 and 08).

    Read-only: `POST`/`PATCH`/`DELETE` are methods this route does not allow (405) and
    `submit`/`approve`/`reject` are not routed at all (404). The material token is a
    BEARER credential — whoever holds the UUID releases the goods on credit — so the
    read needs Store Manager / Admin; a cashier, stocker or groupless account gets 403.
    """

    queryset = (
        Requisition.objects
        # project__customer, not project: the serializer exposes project.customer.name, and
        # stopping at project makes that a per-row query.
        # token is a REVERSE OneToOne (MaterialToken -> Requisition), so the serializer's
        # token field costs one query per row unless it is joined too.
        .select_related('project__customer', 'token')
        .prefetch_related('items__variant_uom__variant')
        .all()
    )
    serializer_class = RequisitionSerializer
    permission_classes = [IsManagerRole]


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
        return _refusal(e)
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
            # Decision 05: the row tells a partial release from a finished one, so the
            # trail shows a request was deliberately left open.
            label = (
                'partially released'
                if result['status'] == Requisition.Status.PARTIAL
                else 'fully released'
            )
            audit_request(
                request,
                AuditLog.ActionType.RELEASE,
                f'Materials {label} for requisition {result["req_number"]} '
                f'on transaction {result["transaction_no"]} '
                f'(total {result["grand_total"]}).',
            )
    except NoOpenShift as e:
        # Decision 03: mirrors `POST /transactions/`, which the POS exception handler
        # already maps to 400 `NO_OPEN_SHIFT`. Named explicitly because NoOpenShift is
        # deliberately NOT a ValueError, so the handler below would let it through as a
        # 500. Raised inside the block, so this refusal leaves no RELEASE audit row.
        return _refusal(e)
    except ValueError as e:
        # `_refusal` adds the stable `{code, detail}` body when the error carries a code
        # (`NOTHING_TO_RELEASE`) and keeps the plain `{detail}` answer otherwise.
        return _refusal(e)
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

class RequisitionItemViewSet(viewsets.ReadOnlyModelViewSet):
    """Requisition lines, read-only with the same audience as their requisition.

    A line is written by the CPMS push (`services.import_request`), never by the POS:
    the quantities here are what the till releases.
    """

    # `order_by` matters: the model has no Meta.ordering, and DRF's paginator warns (and
    # can repeat a row across pages) on an unordered queryset.
    queryset = RequisitionItem.objects.select_related(
        'requisition', 'variant_uom__variant').order_by('pk')
    serializer_class = RequisitionItemSerializer
    permission_classes = [IsManagerRole]
