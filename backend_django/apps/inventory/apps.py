from django.apps import AppConfig


class InventoryConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.inventory'
    verbose_name = 'Inventory'

    def ready(self):
        # Sell by measure: 6-decimal quantities keep the API's "10.00" shape.
        from common.serializer_fields import install

        install()
