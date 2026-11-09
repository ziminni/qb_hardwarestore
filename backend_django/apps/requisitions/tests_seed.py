# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""Phase 1 Task 4/7 and Phase 1b Task 5 — the demo seed shows the store's own flow.

Decision 08: `seed_demo` creates no foreman and no `Site Foreman` group, adds the CPMS
service account, and leaves requests in every state a CPMS push plus a store answer can
produce:

  * `CPMS-R-1001` ACCEPTED with its token still unused (the cashier's demo), on the
    well-stocked variant so a full release really is possible;
  * `CPMS-R-1002` RELEASED (the till's history) and `CPMS-R-1003` PARTIAL (released once
    against a short shelf, token still live — decision 05);
  * `CPMS-R-1004` WAITING (nobody has answered it yet) and `CPMS-R-1005` DECLINED (the
    store refused it with a reason, which spends the token).

Nothing in DRAFT or SUBMITTED, because the POS can no longer produce either.

Every request is pushed through `import_request` and then accepted, declined or released
through the same services the screens call — no fixture writes a status by hand (Phase 1b
Task 5). The command is run once, against the empty database a fresh install has: its
catalog, stock, sales and requisition halves all skip themselves when their rows exist, so
a second run must change nothing.

The tests at the bottom read the two new requests the way a cashier would: their tokens
are refused by name (`REQUISITION_WAITING` / `REQUISITION_DECLINED`) BEFORE the generic
"already used" answer, and the refusal writes nothing.
"""

from decimal import Decimal
from io import StringIO

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.management import call_command
from django.test import TestCase

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import InventoryBatch
from apps.pos.models import (
    OfficialReceipt,
    SalesItem,
    SalesTransaction,
    Shift,
)

from .exceptions import RequisitionNotReleasable
from .models import MaterialToken, Requisition
from .services import (
    expected_amount,
    release_materials,
    verify_token,
)

User = get_user_model()


class SeedDemoTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        call_command('seed_demo', verbosity=0, stdout=StringIO())

    # -- helpers ---------------------------------------------------------

    def _by_cpms_id(self, cpms_request_id):
        return Requisition.objects.select_related('token').get(
            cpms_request_id=cpms_request_id)

    def _requisition_sales(self, requisition):
        """The REQUISITION sales booked against this request's own selling units.

        The demo's shop sales are never `source=REQUISITION`, and each seeded request
        quotes a unit no other seeded request quotes, so the intersection names the
        releases of this one request.
        """
        unit_ids = set(requisition.items.values_list('variant_uom_id', flat=True))
        sales = []
        for sale in SalesTransaction.objects.filter(
                source=SalesTransaction.Source.REQUISITION).prefetch_related('items'):
            if unit_ids & {item.variant_uom_id for item in sale.items.all()}:
                sales.append(sale)
        return sales

    def _snapshot(self):
        """Everything a second run must NOT change: ids, tokens, decisions, money."""
        return {
            'requests': tuple(
                (r.cpms_request_id, r.status, str(r.token.token),
                 r.token.is_used, r.token.used_by_id, r.released_amount,
                 r.decline_reason,
                 tuple((line.quantity, line.released_qty, line.available,
                        line.decline_reason)
                       for line in r.items.order_by('pk')))
                for r in Requisition.objects.order_by('pk').select_related('token')
            ),
            'sales': SalesTransaction.objects.count(),
            'sale_items': SalesItem.objects.count(),
            'receipts': OfficialReceipt.objects.count(),
            'ledgers': tuple(CollectibleLedger.objects.order_by('pk')
                             .values_list('id', 'original_amount', 'balance_due')),
            'batches': tuple(InventoryBatch.objects.order_by('pk')
                             .values_list('id', 'current_qty')),
        }

    # -- roles and catalog -----------------------------------------------

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

    # -- the five requests -----------------------------------------------

    def test_the_requests_cover_every_state_the_store_workflow_leaves(self):
        self.assertEqual(
            sorted(Requisition.objects.values_list('status', flat=True)),
            sorted([Requisition.Status.ACCEPTED, Requisition.Status.RELEASED,
                    Requisition.Status.PARTIAL, Requisition.Status.WAITING,
                    Requisition.Status.DECLINED]))
        self.assertEqual(
            sorted(Requisition.objects.values_list('cpms_request_id', flat=True)),
            [f'CPMS-R-100{i}' for i in range(1, 6)],
            'the demo ids are stable, so the CPMS handoff docs can name them')

    def test_the_approved_request_keeps_a_live_token_and_text_names(self):
        approved = self._by_cpms_id('CPMS-R-1001')

        self.assertFalse(MaterialToken.objects.get(requisition=approved).is_used)
        self.assertTrue(approved.cpms_request_id)
        self.assertTrue(approved.requester_name, 'the requester is a CPMS name')
        self.assertTrue(approved.approver_name, 'the approver is a CPMS name')
        self.assertTrue(approved.items.exists())

    def test_the_approved_request_is_fully_releasable(self):
        # QA 2026-11-07: the demo's "full release" request must not sit on the variant
        # the seed drains for the low-stock demo.
        approved = self._by_cpms_id('CPMS-R-1001')
        items = verify_token(token_value=str(approved.token.token))['items']
        self.assertEqual({item['availability'] for item in items}, {'FULL'})

    def test_r1001_is_accepted_full_with_eight_releasable_and_a_known_budget(self):
        approved = self._by_cpms_id('CPMS-R-1001')
        item = approved.items.get()

        self.assertEqual(approved.status, Requisition.Status.ACCEPTED)
        self.assertEqual(item.quantity, Decimal('8.00'))
        verified = verify_token(token_value=str(approved.token.token))['items']
        self.assertEqual([line['releasable'] for line in verified], ['8.00'])

        # Decision 11/14: a known released baseline (0.00) plus today's price for what is
        # still owed = a budget CPMS can plan against, and no debt was booked.
        self.assertEqual(approved.released_amount, Decimal('0.00'))
        self.assertEqual(
            expected_amount(approved),
            item.variant_uom.default_selling_price * Decimal('8'))
        self.assertEqual(self._requisition_sales(approved), [],
                         'acceptance books no sale and no utang')

    def test_the_released_request_consumed_its_token_and_deducted_stock(self):
        released = self._by_cpms_id('CPMS-R-1002')

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
        for line in released.items.all():
            self.assertEqual(line.released_qty, line.quantity,
                             'a full release leaves nothing outstanding')

    def test_the_partial_request_kept_its_token_live_and_its_remainder_open(self):
        partial = self._by_cpms_id('CPMS-R-1003')
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

    # -- the two requests nobody at the till may touch -------------------

    def test_the_waiting_request_waits_for_the_store_with_an_unspent_token(self):
        waiting = self._by_cpms_id('CPMS-R-1004')

        self.assertEqual(waiting.status, Requisition.Status.WAITING)
        self.assertFalse(waiting.token.is_used,
                         'nobody answered it, so nothing spent the token')
        self.assertIsNone(waiting.token.used_by)
        self.assertEqual(waiting.released_amount, Decimal('0.00'))
        for line in waiting.items.all():
            self.assertIsNone(line.available, 'the store has not answered yet')
            self.assertEqual(line.decline_reason, '')
            self.assertEqual(line.released_qty, 0)
        self.assertEqual(self._requisition_sales(waiting), [],
                         'a push books no sale, no receipt and no utang')

    def test_the_declined_request_spent_its_token_without_a_cashier_or_a_sale(self):
        declined = self._by_cpms_id('CPMS-R-1005')

        self.assertEqual(declined.status, Requisition.Status.DECLINED)
        self.assertTrue(declined.decline_reason.strip(),
                        'a whole Decline always says why')
        self.assertTrue(declined.token.is_used, 'Decline spends the token')
        self.assertIsNotNone(declined.token.used_at)
        self.assertIsNone(declined.token.used_by, 'no cashier handed anything out')
        self.assertEqual(declined.released_amount, Decimal('0.00'))
        for line in declined.items.all():
            self.assertIs(line.available, False)
            self.assertEqual(line.decline_reason, declined.decline_reason)
            self.assertEqual(line.released_qty, 0)
        self.assertEqual(self._requisition_sales(declined), [],
                         'declining moves no stock and books no money')
        self.assertFalse(
            OfficialReceipt.objects.filter(
                transaction__items__variant_uom__in=declined.items.values('variant_uom')
            ).exists(),
            'nothing was handed out, so no receipt was printed')

    def test_a_waiting_or_declined_token_is_refused_before_already_used(self):
        cashier = User.objects.get(username='cashier')
        before = (SalesTransaction.objects.count(),
                  OfficialReceipt.objects.count(),
                  CollectibleLedger.objects.count(),
                  sum(InventoryBatch.objects.values_list('current_qty', flat=True)))

        for cpms_id, code in (('CPMS-R-1004', 'REQUISITION_WAITING'),
                              ('CPMS-R-1005', 'REQUISITION_DECLINED')):
            request = self._by_cpms_id(cpms_id)
            with self.subTest(cpms_request_id=cpms_id):
                with self.assertRaises(RequisitionNotReleasable) as verify_refusal:
                    verify_token(token_value=str(request.token.token))
                self.assertEqual(verify_refusal.exception.code, code)
                self.assertNotIn('already been used',
                                 str(verify_refusal.exception),
                                 'the decision is the fact the cashier needs')
                with self.assertRaises(RequisitionNotReleasable) as release_refusal:
                    release_materials(token_value=str(request.token.token),
                                      cashier=cashier)
                self.assertEqual(release_refusal.exception.code, code)

        self.assertEqual(
            (SalesTransaction.objects.count(),
             OfficialReceipt.objects.count(),
             CollectibleLedger.objects.count(),
             sum(InventoryBatch.objects.values_list('current_qty', flat=True))),
            before,
            'a refused scan writes nothing at all')

    # -- money: what the seed booked is what the demo says it booked ----

    def test_the_released_amounts_add_up_to_the_sales_and_ledgers_they_booked(self):
        totals = {}
        for cpms_id in ('CPMS-R-1002', 'CPMS-R-1003'):
            request = self._by_cpms_id(cpms_id)
            sales = self._requisition_sales(request)
            self.assertEqual(len(sales), 1, 'one visit, one sale')
            booked = sum((sale.grand_total for sale in sales), Decimal('0.00'))
            self.assertEqual(request.released_amount, booked,
                             f'{cpms_id} accumulates the sale it booked')
            ledgers = CollectibleLedger.objects.filter(transaction__in=sales)
            self.assertEqual(
                sum((ledger.original_amount for ledger in ledgers), Decimal('0.00')),
                booked, 'the project utang is exactly what was released')
            for ledger in ledgers:
                self.assertEqual(ledger.project, request.project)
            totals[cpms_id] = booked

        self.assertEqual(
            sum(CollectibleLedger.objects.filter(
                project_id__in={self._by_cpms_id(cpms_id).project_id for cpms_id in totals},
                transaction__source=SalesTransaction.Source.REQUISITION,
            ).values_list('original_amount', flat=True), Decimal('0.00')),
            sum(totals.values(), Decimal('0.00')),
            'in aggregate the demo project owes exactly the two releases')

    def test_the_original_demo_state_is_unchanged(self):
        self.assertEqual(SalesTransaction.objects.count(), 7,
                         'five shop sales plus the two seeded releases')
        self.assertEqual(
            SalesTransaction.objects.filter(
                source=SalesTransaction.Source.REQUISITION).count(), 2)
        self.assertEqual(CollectibleLedger.objects.filter(project__isnull=False).count(), 2)
        self.assertEqual(CollectibleLedger.objects.filter(project__isnull=True).count(), 1,
                         "Maria's underpaid shop sale still carries its utang")
        self.assertEqual(
            Shift.objects.filter(status=Shift.Status.CLOSED).count(), 1,
            "the demo Z-reading is still closed and short")
        self.assertEqual(
            Shift.objects.filter(status=Shift.Status.OPEN).count(), 1,
            'the release shift stays open for the cashier demo')

    # -- re-running the command ------------------------------------------

    def test_seeding_again_keeps_the_same_requests_tokens_decisions_and_money(self):
        before = self._snapshot()

        call_command('seed_demo', verbosity=0, stdout=StringIO())

        self.assertEqual(self._snapshot(), before,
                         'a second run changes no request, token, decision or amount')

    def test_the_seed_prints_the_waiting_and_declined_token_instructions(self):
        out = StringIO()

        # The second run paints nothing (every half skips itself), yet the instructions
        # still have to name the stored tokens: they are read from the rows, not from
        # the seeding branch.
        call_command('seed_demo', verbosity=0, stdout=out)
        text = out.getvalue()

        waiting = self._by_cpms_id('CPMS-R-1004')
        declined = self._by_cpms_id('CPMS-R-1005')
        waiting_line = next(
            (line for line in text.splitlines()
             if str(waiting.token.token) in line), '')
        declined_line = next(
            (line for line in text.splitlines()
             if str(declined.token.token) in line), '')

        self.assertIn('WAITING', waiting_line)
        self.assertIn('cannot be released', waiting_line,
                      'the operator must know the till refuses it until reviewed')
        self.assertIn('DECLINED', declined_line)
        self.assertIn('dead', declined_line,
                      'the operator must know the declined token is spent')
