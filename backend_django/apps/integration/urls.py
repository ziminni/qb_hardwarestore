"""CPMS integration URLs — all of them under `/api/v1/integration/cpms/`."""

from django.urls import path

from .views import (
    CpmsCustomerListView,
    CpmsMaterialListView,
    CpmsProjectPayablesView,
    CpmsRequestCloseView,
    CpmsRequestImportView,
    CpmsRequestReadBackView,
)

urlpatterns = [
    path('customers/', CpmsCustomerListView.as_view(), name='cpms-customers'),
    path('materials/', CpmsMaterialListView.as_view(), name='cpms-materials'),
    path(
        'requests/',
        CpmsRequestImportView.as_view(),
        name='cpms-request-import',
    ),
    path(
        'requests/<str:cpms_request_id>/close/',
        CpmsRequestCloseView.as_view(),
        name='cpms-request-close',
    ),
    path(
        'requests/<str:cpms_request_id>/',
        CpmsRequestReadBackView.as_view(),
        name='cpms-request-read-back',
    ),
    path(
        'projects/<str:cpms_project_id>/payables/',
        CpmsProjectPayablesView.as_view(),
        name='cpms-project-payables',
    ),
]
