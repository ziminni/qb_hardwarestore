"""Requisitions app URL configuration."""

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import (
    MaterialTokenViewSet,
    ProjectViewSet,
    RequisitionItemViewSet,
    RequisitionViewSet,
    material_release_view,
    token_verify_view,
)

router = DefaultRouter()
router.register(r'projects', ProjectViewSet, basename='project')
router.register(r'requisitions', RequisitionViewSet, basename='requisition')
router.register(r'req-items', RequisitionItemViewSet, basename='reqitem')
router.register(r'tokens', MaterialTokenViewSet, basename='materialtoken')

urlpatterns = [
    path('tokens/verify/', token_verify_view, name='token-verify'),
    path('tokens/release/', material_release_view, name='material-release'),
    path('', include(router.urls)),
]