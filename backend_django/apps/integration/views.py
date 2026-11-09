# pyright: reportAttributeAccessIssue=false, reportIndexIssue=false, reportOptionalSubscript=false, reportInvalidTypeArguments=false, reportGeneralTypeIssues=false
#
# Same directives and reason as apps/requisitions/views.py: without django-stubs,
# DRF's `validated_data` resolves to `empty`/`None` and `transaction.atomic()` does not
# read as a context manager, so these are all false positives on valid Django. The test
# run is the authority.
"""CPMS boundary views — the only namespace the service account may reach.

Every view here is gated by `IsCpmsService`; the blanket refusal everywhere else is the
fence in `apps.users.authentication`, not this file.
"""

from django.db import transaction
from rest_framework import status
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.inventory.models import VariantUOM
from apps.pos.models import Customer
from apps.requisitions.exceptions import CpmsRefusal, RequestImportRefused
from apps.requisitions.services import (
    close_requisition,
    import_request,
    project_payables,
    request_read_back,
)
from apps.users.models import AuditLog
from apps.users.permissions import IsCpmsService
from apps.users.services import audit_request

from .serializers import (
    CpmsCustomerSerializer,
    CpmsMaterialSerializer,
    CpmsRequestImportSerializer,
)

# The customers a project may bill — the same set as `Project.customer`'s
# `limit_choices_to`. Two strings, so they are restated here rather than imported: a
# CPMS read endpoint importing the requisitions models would be a coupling for nothing.
# (`apps.requisitions.services.PAYER_CUSTOMER_TYPES` holds the same pair for the import,
# which has to ask the question on writes.)
PAYER_CUSTOMER_TYPES = ('CONTRACTOR', 'CONSTRUCTION_FIRM')


class CpmsCustomerListView(ListAPIView):
    """`GET customers/` — the payers a push may name (P1, decision 02).

    Active contractors and construction firms only. Paginated like every other list in
    this API (DRF's default class and page size), so the body is
    `{count, next, previous, results: [{id, name}]}`.

    Read-only by construction: there is no create/update/delete on the CPMS boundary.
    """

    permission_classes = (IsCpmsService,)  # tuple: ruff's RUF012 on a mutable class attr
    serializer_class = CpmsCustomerSerializer
    queryset = Customer.objects.filter(
        is_active=True,
        customer_type__in=PAYER_CUSTOMER_TYPES,
    ).order_by('name')


class CpmsMaterialListView(ListAPIView):
    """`GET materials/` — the selling units CPMS may order (decision 04).

    A row is `{code, product, unit}`: the unit's own scan code, its product label and the
    unit of measure. Only units CPMS could actually order are listed — an ACTIVE variant
    of an ACTIVE product — which is also exactly what the import accepts, so a code from
    this list never gets an UNKNOWN_MATERIAL back.

    No stock, price, cost or id, by construction (see `CpmsMaterialSerializer`). Ordered
    by product then variant then unit so the list is stable across pages.
    """

    permission_classes = (IsCpmsService,)
    serializer_class = CpmsMaterialSerializer
    queryset = (
        VariantUOM.objects
        .filter(variant__is_active=True, variant__product__is_active=True)
        .select_related('variant__product', 'uom')
        .order_by(
            'variant__product__base_name', 'variant__variant_name', 'uom__code', 'pk')
    )


class CpmsRequestImportView(APIView):
    """`POST requests/` — CPMS pushes one approved request (decisions 02 and 04).

    `201` with the stored copy for a new request, `200` with the FIRST copy when the same
    `cpms_request_id` is pushed again (nothing is updated — a retry must not rewrite what
    the till may already have released against). Refusals carry the project's usual
    `{code, detail}` body: `400 UNKNOWN_PAYER` / `UNKNOWN_MATERIAL` /
    `DUPLICATE_MATERIAL` / serializer validation, and `409 TOKEN_TAKEN`.

    The store, its lines and the token are one transaction, and the audit row is written
    inside the same one — so a refusal leaves nothing behind and a success cannot be
    missing from the trail. The description names the requisition and CPMS's request id,
    never the token: that UUID is the bearer credential the cashier scans (decision 07).
    """

    permission_classes = (IsCpmsService,)

    def post(self, request):
        serializer = CpmsRequestImportSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        try:
            with transaction.atomic():
                result = import_request(
                    cpms_request_id=payload['cpms_request_id'],
                    token=payload['token'],
                    project=payload['project'],
                    requester_name=payload['requester_name'],
                    approver_name=payload['approver_name'],
                    # `notes` is optional on the wire; the column is NOT NULL.
                    notes=str(payload['notes'] or ''),
                    items=payload['items'],
                )
                if result['created']:
                    audit_request(
                        request,
                        AuditLog.ActionType.REQ_APPROVE,
                        f'Requisition {result["request"]["req_number"]} imported from '
                        f'CPMS request {payload["cpms_request_id"]}.',
                    )
        except RequestImportRefused as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=error.status_code,
            )
        return Response(
            result['request'],
            status=status.HTTP_201_CREATED if result['created'] else status.HTTP_200_OK,
        )


class CpmsRequestCloseView(APIView):
    """`POST requests/{cpms_request_id}/close/` — CPMS closes an open remainder (dec. 06).

    `ACCEPTED` / `PARTIAL` -> `CLOSED` with the token spent; already `RELEASED` or
    `CLOSED` -> `200` no-op; `CANCELLED` -> `409 REQUEST_CANCELLED`; an id this POS never
    stored -> `404 REQUEST_NOT_FOUND`. The answer is the read-back body below, so CPMS
    sees exactly what the close left behind.

    Release-side work is untouched — no line, sale or ledger row is written — and the
    audit row is written inside the same transaction, only when the request actually
    closed. It names the requisition and CPMS's request id, never the token.
    """

    permission_classes = (IsCpmsService,)

    def post(self, request, cpms_request_id):
        try:
            with transaction.atomic():
                result = close_requisition(cpms_request_id=cpms_request_id)
                if result['closed']:
                    # No dedicated ActionType for a close (out of scope for this task), so
                    # the trail reuses REQ_REJECT: the remainder was given up rather than
                    # served, which is what that action already records.
                    audit_request(
                        request,
                        AuditLog.ActionType.REQ_REJECT,
                        f'Requisition {result["request"]["req_number"]} closed by CPMS '
                        f'request {cpms_request_id}.',
                    )
        except CpmsRefusal as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=error.status_code,
            )
        return Response(result['request'])


class CpmsRequestReadBackView(APIView):
    """`GET requests/{cpms_request_id}/` — status and each line's three quantities.

    Decision 07: the project manager reads this before deciding to close, so it says what
    was asked for, what left the store and what is still outstanding on each line.
    Read-only; `outstanding` stays the TRUE unreleased quantity even once CLOSED.
    """

    permission_classes = (IsCpmsService,)

    def get(self, request, cpms_request_id):
        try:
            return Response(request_read_back(cpms_request_id=cpms_request_id))
        except CpmsRefusal as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=error.status_code,
            )


class CpmsProjectPayablesView(APIView):
    """`GET projects/{cpms_project_id}/payables/` — what the project owes (decision 07).

    `{total, paid, balance}` as 2dp strings from that project's own `CollectibleLedger`
    rows. No prices per item, no stock, no customer detail: a project sees its utang and
    nothing else. A project with no rows yet reads zeros; an id this POS never stored is
    `404 PROJECT_NOT_FOUND`.
    """

    permission_classes = (IsCpmsService,)

    def get(self, request, cpms_project_id):
        try:
            return Response(project_payables(cpms_project_id=cpms_project_id))
        except CpmsRefusal as error:
            return Response(
                {'code': error.code, 'detail': str(error)},
                status=error.status_code,
            )
