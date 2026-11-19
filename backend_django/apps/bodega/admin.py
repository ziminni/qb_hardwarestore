from django.contrib import admin

from .models import BodegaDelivery, BodegaRelease


@admin.register(BodegaRelease)
class BodegaReleaseAdmin(admin.ModelAdmin):
    list_display = ("number", "sale", "received_by", "plate_no", "created_at")
    search_fields = ("number", "sale__transaction_no", "received_by", "plate_no")


@admin.register(BodegaDelivery)
class BodegaDeliveryAdmin(admin.ModelAdmin):
    list_display = ("number", "receipt", "location", "status", "created_at")
    list_filter = ("status",)
