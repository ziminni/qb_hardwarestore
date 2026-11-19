from django.urls import path

from .admin_dashboard import admin_dashboard_view

from . import views

app_name = 'reports'

urlpatterns = [
    path('sales-summary/', views.sales_summary_view, name='sales-summary'),
    # Owner 2026-11-18: Admin → Dashboard, one read for its five tabs.
    path('admin-dashboard/', admin_dashboard_view, name='admin-dashboard'),
    path('inventory-valuation/', views.inventory_valuation_view,
         name='inventory-valuation'),
    path('stock-movements/', views.stock_movements_view,
         name='stock-movements'),
    path('requisition-history/', views.requisition_history_view,
         name='requisition-history'),
]
