from django.contrib.auth.models import Group
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Q

from apps.users.models import User


class Command(BaseCommand):
    help = 'Create or refresh the Inventory, Sales, and POS test accounts.'

    accounts = (
        {
            'username': 'inventory',
            'email': 'inventory@test.com',
            'full_name': 'Inventory Test',
            'role': 'Stock Manager',
        },
        {
            'username': 'sales',
            'email': 'sales@test.com',
            'full_name': 'Sales Test',
            'role': 'Store Manager',
        },
        {
            'username': 'pos',
            'email': 'pos@test.com',
            'full_name': 'POS Test',
            'role': 'Cashier',
        },
    )

    @transaction.atomic
    def handle(self, *args, **options):
        roles = {
            account['role']: Group.objects.get_or_create(
                name=account['role'],
            )[0]
            for account in self.accounts
        }

        for account in self.accounts:
            username = account['username']
            email = account['email']
            matches = User.objects.filter(
                Q(username=username) | Q(email=email),
            )

            if matches.count() > 1:
                raise CommandError(
                    f'Conflicting users already use {username!r} or {email!r}.',
                )

            user = matches.first()
            if user is None:
                user = User.objects.create_user(
                    username=username,
                    email=email,
                    password='password',
                    full_name=account['full_name'],
                )
                action = 'Created'
            else:
                if user.username != username or user.email != email:
                    raise CommandError(
                        f'Existing account conflicts with {username!r}/{email!r}.',
                    )
                action = 'Updated'

            user.full_name = account['full_name']
            user.is_active = True
            user.is_staff = False
            user.is_superuser = False
            user.set_password('password')
            user.save()
            user.groups.set([roles[account['role']]])

            self.stdout.write(
                self.style.SUCCESS(
                    f'{action}: {email} ({account["role"]})',
                ),
            )
