"""Django Admin registration for Requisitions models."""

from django.contrib import admin

from .models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)


@admin.register(Project)
class ProjectAdmin(admin.ModelAdmin):
    list_display = ('name', 'customer', 'is_active', 'start_date', 'end_date')
    list_filter = ('is_active',)
    search_fields = ('name', 'customer__name')


class RequisitionItemInline(admin.TabularInline):
    model = RequisitionItem
    extra = 0


@admin.register(Requisition)
class RequisitionAdmin(admin.ModelAdmin):
    list_display = ('req_number', 'project', 'status', 'requested_by', 'created_at')
    list_filter = ('status',)
    search_fields = ('req_number', 'project__name')
    inlines = [RequisitionItemInline]


@admin.register(MaterialToken)
class MaterialTokenAdmin(admin.ModelAdmin):
    list_display = ('token', 'requisition', 'is_used', 'created_at')
    list_filter = ('is_used',)
    readonly_fields = ['token', 'created_at', 'used_at']
