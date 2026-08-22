"""Requisitions app — ViewSets for project management and material release."""

from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

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


# ---------------------------------------------------------------------------
# Project ViewSet
# ---------------------------------------------------------------------------

class ProjectViewSet(viewsets.ModelViewSet):
    queryset = Project.objects.select_related('customer').all()
    serializer_class = ProjectSerializer

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAuthenticated()]


# ---------------------------------------------------------------------------
# Requisition ViewSet
# ---------------------------------------------------------------------------

class RequisitionViewSet(viewsets.ModelViewSet):
    queryset = (
        Requisition.objects
        .select_related('project', 'requested_by')
        .prefetch_related('items__variant')
        .all()
    )
    serializer_class = RequisitionSerializer

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAuthenticated()]

    def perform_create(self, serializer):
        serializer.save(
            requested_by=self.request.user,
            req_number=generate_req_number(),
        )

    # --- Status transitions ---

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        """Submit a DRAFT requisition for approval."""
        req = self.get_object()
        try:
            submit_requisition(requisition=req)
        except ValueError as e:
            return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'detail': f'{req.req_number} submitted.'})

    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Approve a SUBMITTED requisition and generate a MaterialToken."""
        req = self.get_object()
        try:
            token = approve_requisition(requisition=req, approver=request.user)
        except ValueError as e:
            return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({
            'detail': f'{req.req_number} approved.',
            'token': str(token.token),
        })

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """Reject a SUBMITTED requisition."""
        req = self.get_object()
        try:
            reject_requisition(requisition=req, approver=request.user)
        except ValueError as e:
            return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'detail': f'{req.req_number} rejected.'})


# ---------------------------------------------------------------------------
# Token / Material Release endpoints
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def token_verify_view(request):
    """Verify a material token (UC-20: Scan/Verify Digital Material Token)."""
    serializer = TokenVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    token_value = str(serializer.validated_data['token'])
    try:
        info = verify_token(token_value=token_value)
    except ValueError as e:
        return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    return Response(info)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def material_release_view(request):
    """Release materials at POS (UC-21 + UC-22).

    Expects { "token": "<uuid>" }.  FIFO-deducts stock, creates
    SalesTransaction, and posts to CollectiblesLedger.
    """
    serializer = TokenVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    token_value = str(serializer.validated_data['token'])
    try:
        result = release_materials(
            token_value=token_value,
            cashier=request.user,
        )
    except ValueError as e:
        return Response({'detail': str(e)}, status=status.HTTP_400_BAD_REQUEST)
    return Response(result, status=status.HTTP_201_CREATED)


# ---------------------------------------------------------------------------
# MaterialToken ViewSet (read-only)
# ---------------------------------------------------------------------------

class MaterialTokenViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = MaterialToken.objects.select_related('requisition').all()
    serializer_class = MaterialTokenSerializer
    permission_classes = [IsAuthenticated]


# ---------------------------------------------------------------------------
# RequisitionItem ViewSet
# ---------------------------------------------------------------------------

class RequisitionItemViewSet(viewsets.ModelViewSet):
    queryset = RequisitionItem.objects.select_related(
        'requisition', 'variant').all()
    serializer_class = RequisitionItemSerializer

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAuthenticated()]
