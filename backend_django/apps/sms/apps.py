# pyright: reportAssignmentType=false
#
# Same directive and reason as the other five `apps.py` files: `default_auto_field =
# "django.db.models.BigAutoField"` is a string in Django and a `cached_property` in the
# stubs, so pyright flags the line in EVERY app in this project. `manage.py check` and
# the test run remain the authority.
from django.apps import AppConfig


class SmsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.sms"
    verbose_name = "SMS Gateway"

    def ready(self):
        # The outbound trigger is a `post_save` receiver on `pos.SalesTransaction`, wired
        # here so `pos.services` (another lane's file) stays untouched.
        from . import signals  # noqa: F401  (importing registers the receiver)
