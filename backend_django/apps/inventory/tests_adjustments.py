# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/inventory/tests.py: without django-stubs every
# `Model.objects` is a false positive on valid Django, and the checker does not find this
# repo's pyrightconfig.json from its own working directory, so the directive travels with
# the file. `manage.py test` remains the authority.
"""Phase 1 task 5 — a positive adjustment at zero stock must RESTOCK, never no-op.

The bug this file pins: `apply_stock_adjustment`'s positive branch only looked at
batches with `current_qty > 0`, so a correction booked against an out-of-stock variant
wrote a StockAdjustment row and moved nothing — the ledger asserted stock the shelves
did not have. Decision 09 item 5 said "create a batch"; the ledger ruling replaced that
with "reopen the newest EXISTING batch", because `InventoryBatch.receipt` is non-null
PROTECT and a receipt-less batch would need a schema change.
"""
from decimal import Decimal

from django.contrib.auth.models import Group
from rest_framework.test import APIClient

from .exceptions import NoBatchHistory
from .models import InventoryBatch, StockAdjustment
from .services import apply_stock_adjustment, process_goods_receipt
from .tests import InventoryTestBase


class StockAdjustmentServiceTests(InventoryTestBase):
    def _adjustment(self, qty, adjustment_type=StockAdjustment.AdjustmentType.CORRECTION):
        return StockAdjustment.objects.create(
            variant=self.variant, user=self.user,
            adjustment_type=adjustment_type, qty_adjusted=Decimal(qty),
        )

    def _receive_and_zero(self, qty='10'):
        """One batch of `qty`, then emptied by a sale/shrinkage — stock now 0."""
        _, _, receipt = self._receive(qty)
        process_goods_receipt(receipt=receipt, user=self.user)
        batch = InventoryBatch.objects.get(variant=self.variant)
        batch.current_qty = Decimal('0')
        batch.save(update_fields=['current_qty'])
        return batch

    def test_positive_adjustment_restocks_a_batch_at_zero(self):
        batch = self._receive_and_zero()

        apply_stock_adjustment(adjustment=self._adjustment('5'))

        batch.refresh_from_db()
        self.assertEqual(batch.current_qty, Decimal('5'))

    def test_positive_adjustment_reopens_the_newest_batch(self):
        # Two deliveries, so there are two batches and an order to get wrong.
        for _ in range(2):
            _, _, receipt = self._receive('10')
            process_goods_receipt(receipt=receipt, user=self.user)
        batches = list(
            InventoryBatch.objects.filter(variant=self.variant).order_by('id'))
        self.assertEqual(len(batches), 2)
        oldest, newest = batches
        # Only the OLDEST batch has stock left; the newest is at zero. Before the fix
        # the positive branch picked the oldest (the only one with current_qty > 0);
        # the newest delivery is the one that must be reopened.
        newest_qty_before = newest.current_qty

        apply_stock_adjustment(adjustment=self._adjustment('5'))

        oldest.refresh_from_db()
        newest.refresh_from_db()
        self.assertEqual(newest.current_qty, newest_qty_before + Decimal('5'))
        self.assertEqual(oldest.current_qty, Decimal('10'))

    def test_positive_adjustment_with_no_batch_history_raises(self):
        adjustment = self._adjustment('5')

        with self.assertRaises(NoBatchHistory) as ctx:
            apply_stock_adjustment(adjustment=adjustment)

        self.assertEqual(ctx.exception.code, 'NO_BATCH_HISTORY')


class StockAdjustmentApiTests(InventoryTestBase):
    """The API is where the atomicity is observable: a refused adjustment must leave
    no StockAdjustment row behind."""

    def setUp(self):
        super().setUp()
        group, _ = Group.objects.get_or_create(name='Stock Manager')
        self.user.groups.add(group)
        self.client = APIClient()
        login = self.client.post('/api/v1/auth/login/', {
            'username': 'stocker', 'password': 'pass12345'}, format='json')
        token = login.data.get('access') or login.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def _post(self, qty, adjustment_type='CORRECTION'):
        return self.client.post('/api/v1/adjustments/', {
            'variant': self.variant.id,
            'adjustment_type': adjustment_type,
            'qty_adjusted': qty,
        }, format='json')

    def _receive_and_zero(self, qty='10'):
        _, _, receipt = self._receive(qty)
        process_goods_receipt(receipt=receipt, user=self.user)
        batch = InventoryBatch.objects.get(variant=self.variant)
        batch.current_qty = Decimal('0')
        batch.save(update_fields=['current_qty'])

    def test_positive_adjustment_at_zero_stock_restocks(self):
        self._receive_and_zero()

        response = self._post('5')

        self.assertEqual(response.status_code, 201, response.data)
        total = sum(InventoryBatch.objects.filter(
            variant=self.variant).values_list('current_qty', flat=True))
        self.assertEqual(total, Decimal('5'))

    def test_positive_adjustment_without_batch_history_is_400_and_saves_nothing(self):
        self.assertFalse(InventoryBatch.objects.filter(
            variant=self.variant).exists())

        response = self._post('5')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'NO_BATCH_HISTORY')
        self.assertIn('detail', response.data)
        self.assertEqual(StockAdjustment.objects.count(), 0)

    def test_zero_quantity_is_refused(self):
        self._receive_and_zero()

        response = self._post('0')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(StockAdjustment.objects.count(), 0)

    def test_negative_beyond_stock_is_400_and_saves_nothing(self):
        self._receive_and_zero('10')

        response = self._post('-11', adjustment_type='SHRINKAGE')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data['code'], 'INSUFFICIENT_STOCK')
        self.assertEqual(StockAdjustment.objects.count(), 0)
