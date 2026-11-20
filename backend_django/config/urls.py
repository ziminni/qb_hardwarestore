"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/4.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""

from django.conf import settings
from django.contrib import admin
from django.views.static import serve
from django.http import HttpResponseNotFound
from django.urls import include, path, re_path
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(["GET"])
@permission_classes([AllowAny])
def health_check(request):
    """Health check endpoint used by Flutter to verify API connectivity."""
    return Response(
        {
            "status": "ok",
            "service": "BuildPro API",
        }
    )


urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", health_check, name="health"),
    # App routes  (v1 namespace for future versioning)
    path("api/v1/", include("apps.users.urls")),
    path("api/v1/", include("apps.inventory.urls")),
    path("api/v1/", include("apps.pos.urls")),
    path("api/v1/", include("apps.collectibles.urls")),
    path("api/v1/", include("apps.requisitions.urls")),
    path("api/v1/", include("apps.bodega.urls")),
    path("api/v1/", include("apps.sms.urls")),
    path("api/v1/reports/", include("apps.reports.urls")),
    # Phase 1, Task 2: the CPMS boundary. The account that may call these is refused
    # everywhere else by `apps.users.authentication.CpmsFencedJWTAuthentication`.
    path("api/v1/integration/cpms/", include("apps.integration.urls")),
]


# Block legacy private files even BEFORE an admin first visits the backup page.
# Production media servers must deny these paths too; see the backup runbook.
def private_media_not_found(request, **kwargs):
    return HttpResponseNotFound()


urlpatterns += [
    re_path(r"^media/backups(?:/.*)?$", private_media_not_found),
    path("media/system_security_policy.json", private_media_not_found),
]

# Uploaded photos, served in production too (static() is a no-op with DEBUG off). Only
# these three folders: anything else that lands in MEDIA_ROOT stays private.
# shortcut: Django serves the files itself, fine for one store; front it with nginx or a
# CDN if photo traffic ever grows.
urlpatterns += [
    re_path(
        r"^media/(?P<path>(?:product-images|avatars|bodega-deliveries)/[^/]+)$",
        lambda request, path: serve(request, path, document_root=settings.MEDIA_ROOT),
    ),
]
# Django admin's CSS/JS (collected by `collectstatic` at production start).
if not settings.DEBUG:
    urlpatterns += [
        re_path(
            r"^static/(?P<path>.*)$",
            lambda request, path: serve(request, path, document_root=settings.STATIC_ROOT),
        )
    ]
