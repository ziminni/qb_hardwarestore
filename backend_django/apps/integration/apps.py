from django.apps import AppConfig


class IntegrationConfig(AppConfig):
    # Inline ignore: without django-stubs the checker reads `AppConfig.default_auto_field`
    # as a `cached_property` (same false positive as every sibling apps.py).
    default_auto_field = 'django.db.models.BigAutoField'  # pyright: ignore[reportAssignmentType]
    name = 'apps.integration'
    verbose_name = 'CPMS integration (the service-account boundary)'
