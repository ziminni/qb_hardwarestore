from django.db import migrations


def create_group(apps, schema_editor):
    """Decision 25: the Bodega Checker group must exist for a role write to grant it."""
    Group = apps.get_model("auth", "Group")
    Group.objects.get_or_create(name="Bodega Checker")


class Migration(migrations.Migration):
    dependencies = [
        ("bodega", "0001_initial"),
        ("auth", "0012_alter_user_first_name_max_length"),
    ]

    operations = [
        migrations.RunPython(create_group, migrations.RunPython.noop),
    ]
