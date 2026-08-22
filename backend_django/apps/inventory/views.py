"""Inventory app — ViewSets for product catalog (Sprint 1)."""

from rest_framework import viewsets
from rest_framework.permissions import IsAdminUser, IsAuthenticated

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    UnitOfMeasure,
    VariantUOM,
)
from .serializers import (
    BrandSerializer,
    CategorySerializer,
    ProductSerializer,
    ProductVariantSerializer,
    UnitOfMeasureSerializer,
    VariantUOMSerializer,
)


class _CatalogBaseViewSet(viewsets.ModelViewSet):
    """Base: write requires admin, read requires auth."""

    def get_permissions(self):
        if self.action in ('list', 'retrieve'):
            return [IsAuthenticated()]
        return [IsAdminUser()]


class CategoryViewSet(_CatalogBaseViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class BrandViewSet(_CatalogBaseViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer


class UnitOfMeasureViewSet(_CatalogBaseViewSet):
    queryset = UnitOfMeasure.objects.all()
    serializer_class = UnitOfMeasureSerializer


class ProductViewSet(_CatalogBaseViewSet):
    queryset = Product.objects.select_related(
        'category', 'brand',
    ).prefetch_related(
        'variants__selling_uoms__uom',
        'variants__base_uom',
    ).all()
    serializer_class = ProductSerializer


class ProductVariantViewSet(_CatalogBaseViewSet):
    queryset = ProductVariant.objects.select_related(
        'product', 'base_uom',
    ).prefetch_related(
        'selling_uoms__uom',
    ).all()
    serializer_class = ProductVariantSerializer


class VariantUOMViewSet(_CatalogBaseViewSet):
    queryset = VariantUOM.objects.select_related('variant', 'uom').all()
    serializer_class = VariantUOMSerializer
