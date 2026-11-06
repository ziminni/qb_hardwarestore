# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""Phase 1 Task 4/7 — the demo seed shows the CPMS flow, not the foreman flow.

Decision 08: `seed_demo` creates no foreman and no `Site Foreman` group, adds the CPMS
service account, and leaves requests in the three states a CPMS push can produce — one
APPROVED with its token still unused (the cashier's demo), one PARTIAL (released once
against a short shelf, token still live — decision 05) and one RELEASED (the till's
history). Nothing in DRAFT or SUBMITTED, because the POS can no longer produce either.

The command is run once, against the empty database a fresh install has: its catalog,
stock, sales and requisition halves all skip themselves when their rows exist.
"""

from io import StringIO

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.management import call_command
from django.test import TestCase

from apps.collectibles.models import CollectibleLedger
from apps.pos.models import SalesTransaction

from .models import MaterialToken, Requisition

User = get_user_model()


class SeedDemoTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        call_command('seed_demo', verbosity=0, stdout=StringIO())

    def test_no_foreman_account_or_group_is_seeded(self):
        self.assertFalse(
            Group.objects.filter(name='Site Foreman').exists(),
            'the foreman role is gone (decision 01)')
        self.assertFalse(User.objects.filter(username='foreman').exists())

    def test_the_cpms_service_account_is_seeded_into_its_own_group(self):
        account = User.objects.get(username='cpms_service')

        self.assertEqual(
            list(account.groups.values_list('name', flat=True)), ['CPMS Service'])
        self.assertFalse(account.is_staff, 'a machine account is not desk staff')
        self.assertFalse(account.is_superuser)
        self.assertTrue(account.is_active)
        from apps.users.management.commands.seed_demo import PASSWORD
        self.assertTrue(account.check_password(PASSWORD))

    def test_the_requests_are_the_three_states_a_cpms_push_can_leave(self):
        self.assertEqual(
            sorted(Requisition.objects.values_list('status', flat=True)),
            sorted([Requisition.Status.APPROVED, Requisition.Status.PARTIAL,
                    Requisition.Status.RELEASED]))

    def test_the_approved_request_keeps_a_live_token_and_text_names(self):
        approved = Requisition.objects.get(status=Requisition.Status.APPROVED)

        self.assertFalse(MaterialToken.objects.get(requisition=approved).is_used)
        self.assertTrue(approved.cpms_request_id)
        self.assertTrue(approved.requester_name, 'the requester is a CPMS name')
        self.assertTrue(approved.approver_name, 'the approver is a CPMS name')
        self.assertTrue(approved.items.exists())

    def test_the_released_request_consumed_its_token_and_deducted_stock(self):
        released = Requisition.objects.get(status=Requisition.Status.RELEASED)

        self.assertTrue(MaterialToken.objects.get(requisition=released).is_used)
        self.assertTrue(released.items.exists())
        # Stock left through the real release path: a REQUISITION sale holding every line.
        expected = sorted((i.variant_uom_id, i.released_qty)
                          for i in released.items.all())
        matching = [
            sale for sale in SalesTransaction.objects.filter(
                source=SalesTransaction.Source.REQUISITION)
            if sorted((i.variant_uom_id, i.qty) for i in sale.items.all()) == expected
        ]
        self.assertEqual(len(matching), 1, 'one sale for exactly this request')

    def test_the_partial_request_kept_its_token_live_and_its_remainder_open(self):
        partial = Requisition.objects.get(status=Requisition.Status.PARTIAL)
        item = partial.items.get()

        self.assertFalse(MaterialToken.objects.get(requisition=partial).is_used)
        self.assertGreater(item.released_qty, 0, 'the shelf was emptied into this line')
        self.assertLess(item.released_qty, item.quantity,
                        'the line asks for more than the shelf held')
        sale = SalesTransaction.objects.get(
            source=SalesTransaction.Source.REQUISITION,
            items__variant_uom=item.variant_uom)
        self.assertEqual(CollectibleLedger.objects.get(transaction=sale).project,
                         partial.project)
        self.assertEqual(sale.items.get().qty, item.released_qty)
