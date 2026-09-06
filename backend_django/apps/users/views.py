"""Users app — ViewSets and auth views."""

from django.contrib.auth.models import Group
from django.db.models import Q
from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from .models import AuditLog, User
from .serializers import (
    AuditLogSerializer,
    LoginSerializer,
    RegisterSerializer,
    UserSerializer,
)
from .services import log_audit, update_last_login


# ---------------------------------------------------------------------------
# Auth endpoints (public)
# ---------------------------------------------------------------------------

@api_view(['POST'])
@permission_classes([IsAdminUser])
def register_view(request):
    """Create an account; public registration is intentionally disabled."""
    serializer = RegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    return Response(UserSerializer(user).data, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def me_view(request):
    return Response(UserSerializer(request.user).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def logout_view(request):
    log_audit(
        user=request.user,
        action_type=AuditLog.ActionType.LOGOUT,
        description=f'{request.user.username} logged out.',
        ip_address=request.META.get('REMOTE_ADDR', ''),
    )
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """Login: validate credentials and return JWT pair."""
    serializer = LoginSerializer(
        data=request.data,
        context={'request': request},
    )
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']

    update_last_login(user)
    log_audit(
        user=user,
        action_type=AuditLog.ActionType.LOGIN,
        description=f'{user.username} logged in.',
        ip_address=request.META.get('REMOTE_ADDR', ''),
    )

    refresh = RefreshToken.for_user(user)
    return Response({
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user': UserSerializer(user).data,
    })


# ---------------------------------------------------------------------------
# User ViewSet
# ---------------------------------------------------------------------------

class UserViewSet(viewsets.ModelViewSet):
    """Admin CRUD for user accounts."""
    queryset = User.objects.prefetch_related('groups').all()
    serializer_class = UserSerializer
    permission_classes = [IsAdminUser]

    def get_queryset(self):
        qs = super().get_queryset()
        search = self.request.query_params.get('search')
        if search:
            qs = qs.filter(
                Q(email__icontains=search)
                | Q(full_name__icontains=search)
                | Q(username__icontains=search),
            )
        return qs

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """Account summary for the admin User Management dashboard cards."""
        total = User.objects.count()
        active = User.objects.filter(is_active=True).count()
        roles_assigned = (
            User.objects.exclude(groups=None)
            .values('groups')
            .distinct()
            .count()
        )
        return Response({
            'total': total,
            'active': active,
            'inactive': total - active,
            'roles_assigned': roles_assigned,
        })

    @action(detail=True, methods=['post'])
    def assign_role(self, request, pk=None):
        """POST /api/users/{id}/assign_role/  { "group_name": "Cashier" }"""
        user = self.get_object()
        group_name = request.data.get('group_name')
        if not group_name:
            return Response(
                {'detail': 'group_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            group = Group.objects.get(name=group_name)
        except Group.DoesNotExist:
            return Response(
                {'detail': f'Group "{group_name}" does not exist.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        user.groups.set([group])
        return Response({'detail': f'{user.username} assigned to {group_name}.'})

    @action(detail=True, methods=['post'])
    def remove_role(self, request, pk=None):
        """POST /api/users/{id}/remove_role/  { "group_name": "Cashier" }"""
        user = self.get_object()
        group_name = request.data.get('group_name')
        if not group_name:
            return Response(
                {'detail': 'group_name is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            group = Group.objects.get(name=group_name)
        except Group.DoesNotExist:
            return Response(
                {'detail': f'Group "{group_name}" does not exist.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        user.groups.remove(group)
        return Response({'detail': f'{group_name} removed from {user.username}.'})


# ---------------------------------------------------------------------------
# AuditLog ViewSet (read-only)
# ---------------------------------------------------------------------------

class AuditLogViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = AuditLog.objects.select_related('user').all()
    serializer_class = AuditLogSerializer
    permission_classes = [IsAdminUser]
