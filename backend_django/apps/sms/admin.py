from django.contrib import admin

from .models import BodegaSmsTicket, SmsContact, SmsGatewayHeartbeat, SmsMessage


@admin.register(SmsContact)
class SmsContactAdmin(admin.ModelAdmin):
    list_display = ("phone", "user", "label", "active", "created_at")
    list_filter = ("active",)
    search_fields = ("phone", "label", "user__username", "user__full_name")


@admin.register(SmsMessage)
class SmsMessageAdmin(admin.ModelAdmin):
    list_display = ("created_at", "direction", "phone", "status", "attempts", "sale")
    list_filter = ("direction", "status")
    search_fields = ("phone", "body")
    # The log is evidence: an admin reads it, never rewrites it.
    readonly_fields = tuple(field.name for field in SmsMessage._meta.fields)

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(BodegaSmsTicket)
class BodegaSmsTicketAdmin(admin.ModelAdmin):
    list_display = ("sale", "code", "created_at", "used_at", "failed_attempts")
    search_fields = ("sale__transaction_no", "code")


@admin.register(SmsGatewayHeartbeat)
class SmsGatewayHeartbeatAdmin(admin.ModelAdmin):
    list_display = ("last_seen", "info")
