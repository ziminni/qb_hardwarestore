from django.urls import path

from . import views
from .admin_dashboard import admin_dashboard_view

app_name = "reports"

urlpatterns = [
    path("sales-summary/", views.sales_summary_view, name="sales-summary"),
    # P1 sales detail reports (reports-suite MAP): paginated rows + report totals.
    path("sales-by-item/", views.sales_by_item_view, name="sales-by-item"),
    path("sales-by-hour/", views.sales_by_hour_view, name="sales-by-hour"),
    path("sales-by-cashier/", views.sales_by_cashier_view, name="sales-by-cashier"),
    # P1 sales detail reports, second half: bill-wise, reversals, discounts, voids.
    path("bill-wise/", views.bill_wise_view, name="bill-wise"),
    path(
        "returns-exchanges/",
        views.returns_exchanges_view,
        name="returns-exchanges",
    ),
    path("discounts/", views.discounts_view, name="discounts"),
    path("voids/", views.voids_view, name="voids"),
    path("vat-summary/", views.vat_summary_view, name="vat-summary"),
    # Owner 2026-11-18: Admin → Dashboard, one read for its five tabs.
    path("admin-dashboard/", admin_dashboard_view, name="admin-dashboard"),
    path(
        "inventory-valuation/",
        views.inventory_valuation_view,
        name="inventory-valuation",
    ),
    path("stock-movements/", views.stock_movements_view, name="stock-movements"),
    path(
        "requisition-history/",
        views.requisition_history_view,
        name="requisition-history",
    ),
]
