# pyright: reportAttributeAccessIssue=false
"""Phase 3 Task 1 — a material release requires, and attaches, the cashier's open shift.

Decision 03: `release_materials` is a POS sale (it deducts stock and posts a receivable),
so it belongs inside a Z-reading like every other sale. Before this task it was the one
money-and-stock event that could be rung outside a shift: the goods left the warehouse on
credit and the end-of-shift close never asked about them.

Everything here goes over HTTP, because the contract the client branches on is a status
code plus a stable `code`, and "nothing was written" is only provable by leaving the
request and looking at the database afterwards.
"""

from decimal import Decimal

from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.pos.models import OfficialReceipt, SalesTransaction, Shift
from apps.pos.services import compute_z_reading
from apps.users.models import AuditLog

from .models import Requisition
from .services import approve_requisition, submit_requisition
from .tests import RequisitionTestBase

LOGIN_URL = '/api/v1/auth/login/'
RELEASE_URL = '/api/v1/tokens/release/'


class ReleaseShiftBase(RequisitionTestBase):
    """The Phase 1 release fixture plus a real Cashier login and an open shift.

    `RequisitionTestBase` already opens an open shift for this cashier (the shared
    fixture change Task 1 forced on every release test). A test that needs the gate to
    fire deletes it.
    """

    def setUp(self):
        super().setUp()
        self.password = get_random_string(12)
        self.cashier.set_password(self.password)
        self.cashier.save(update_fields=['password'])
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.client = APIClient()
        # A refused release must be inspected, not re-raised: before the fix there is no
        # NoOpenShift call site in the release path at all, so a 500 has to be readable
        # rather than a traceback out of the test client.
        self.client.raise_request_exception = False
        login = self.client.post(
            LOGIN_URL,
            {'username': self.cashier.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, 'the cashier must be able to log in')
        # Explicit keyword, not a `**dict`: the client's own `follow` parameter is typed
        # bool, so unpacking a header dict reads as a type error to a checker.
        self.bearer = f'Bearer {login.data["access"]}'

    def _approved_token(self):
        submit_requisition(requisition=self.requisition)
        return approve_requisition(
            requisition=self.requisition, approver=self.manager)

    def _release(self, token):
        return self.client.post(
            RELEASE_URL, {'token': str(token.token)}, format='json',
            HTTP_AUTHORIZATION=self.bearer)

    def _stock(self):
        return sum(self.variant.batches.values_list('current_qty', flat=True))


class ReleaseRequiresOpenShiftTests(ReleaseShiftBase):
    """Decision 03 — no open shift, no release, and not a single row written."""

    def test_release_without_an_open_shift_is_400_and_writes_nothing(self):
        Shift.objects.all().delete()
        token = self._approved_token()
        transactions_before = SalesTransaction.objects.count()

        response = self._release(token)

        self.assertEqual(
            response.status_code, 400, getattr(response, 'data', None))
        self.assertEqual(response.data['code'], 'NO_OPEN_SHIFT')
        self.assertIn('detail', response.data)

        # Nothing written: no sale, no receipt, no ledger, no stock move, no audit row.
        self.assertEqual(SalesTransaction.objects.count(), transactions_before)
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertFalse(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.RELEASE).exists(),
            'a refused release must not write a RELEASE audit row')
        self.assertEqual(self._stock(), Decimal('100'))
        token.refresh_from_db()
        self.assertFalse(token.is_used, 'the token must survive a refused release')
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.APPROVED)
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal('0'))


class ReleaseAttachesTheShiftTests(ReleaseShiftBase):
    """Decision 03 — a successful release lands inside the cashier's shift."""

    def test_release_records_the_open_shift_and_counts_in_the_z_reading(self):
        before = compute_z_reading(self.shift)
        token = self._approved_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        txn = SalesTransaction.objects.get(pk=response.data['transaction_id'])
        self.assertEqual(txn.shift, self.shift)

        after = compute_z_reading(self.shift)
        self.assertEqual(after['transaction_count'],
                         before['transaction_count'] + 1)
        self.assertEqual(
            Decimal(after['gross_sales']),
            Decimal(before['gross_sales']) + Decimal(response.data['grand_total']))
        # A release books a collectible, not cash: the drawer is untouched.
        self.assertEqual(after['expected_drawer'], before['expected_drawer'])
        self.assertEqual(after['cash_sales'], before['cash_sales'])

        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.RELEASE).count(),
            1, 'the release and its audit row succeed together, exactly once')

    def test_a_second_release_of_the_same_token_is_400_and_stock_moves_once(self):
        token = self._approved_token()
        first = self._release(token)
        self.assertEqual(first.status_code, 201, first.data)

        second = self._release(token)

        self.assertEqual(second.status_code, 400, second.data)
        self.assertEqual(self._stock(), Decimal('90'), 'stock moved exactly once')
        self.assertEqual(
            SalesTransaction.objects.filter(
                source=SalesTransaction.Source.REQUISITION).count(), 1)
        self.assertEqual(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.RELEASE).count(), 1)
