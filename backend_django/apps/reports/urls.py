from django.urls import path

from . import views

app_name = 'reports'

urlpatterns = [
    path('sales-summary/', views.sales_summary_view, name='sales-summary'),
    path('inventory-valuation/', views.inventory_valuation_view,
         name='inventory-valuation'),
    path('stock-movements/', views.stock_movements_view,
         name='stock-movements'),
    path('requisition-history/', views.requisition_history_view,
         name='requisition-history'),
]
