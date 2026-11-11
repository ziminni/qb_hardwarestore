# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""Phase 1b Task 3 — a release serves only the lines the store agreed to (decisions 10/13).

Decision 10: a line the store marked **Not available** never releases. It keeps its
outstanding quantity for ever, so it must not hold the token open either: when every
AVAILABLE line is out, the request is `RELEASED` and the token is spent, even though the
declined lines still read 5.00 outstanding. Decision 13 adds the two coded scan refusals
(`REQUISITION_WAITING`, `REQUISITION_DECLINED`) and the released-amount accumulator
(`Requisition.released_amount`, decision 14).

Everything here goes over HTTP because the contract the till branches on is the status
code, the stable `code` and the exact item body. "Nothing was written" is only provable by
looking at the database afterwards.

The race at the bottom is a `TransactionTestCase`: the two worker threads must see each
other's COMMITTED rows, or the test would pass on timing instead of on the token→request
lock every transition shares.
"""

import threading
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand,
    Category,
    GoodsReceipt,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.models import (
    Customer,
    OfficialReceipt,
    SalesTransaction,
    Shift,
)
from apps.users.models import AuditLog

from .models import MaterialToken, Project, Requisition, RequisitionItem
from .services import decline_requisition
from .tests_partial_release import PartialReleaseBase

RELEASE_URL = '/api/v1/tokens/release/'
VERIFY_URL = '/api/v1/tokens/verify/'

User = get_user_model()


class StoreReviewReleaseBase(PartialReleaseBase):
    """The release fixture plus the two calls the till makes, over HTTP."""

    def _verify(self, token):
        return self.client.post(
            VERIFY_URL, {'token': str(token.token)}, format='json',
            HTTP_AUTHORIZATION=self.bearer)

    def _release_snapshot(self):
        """Everything a refused release must leave exactly as it was."""
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        token = MaterialToken.objects.get(requisition=requisition)
        return {
            'requisition': (requisition.status, requisition.released_amount),
            'released_qty': list(
                requisition.items.order_by('pk')
                .values_list('released_qty', flat=True)),
            'token': (token.is_used, token.used_at, token.used_by_id),
            'stock': self._stock(),
            'sales': SalesTransaction.objects.count(),
            'receipts': OfficialReceipt.objects.count(),
            'ledgers': CollectibleLedger.objects.count(),
            'release_audit': AuditLog.objects.filter(
                action_type=AuditLog.ActionType.RELEASE).count(),
        }


class MixedRequestReleaseTests(StoreReviewReleaseBase):
    """One Available line finishing is enough: the declined line owes for ever."""

    def setUp(self):
        super().setUp()
        # The store said it cannot serve the boxes, though 30 pieces sit on the shelf.
        self.box_variant, self.box_vuom = self._boxes_of_twelve(30)
        self.box_line = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.box_vuom,
            quantity=Decimal(3), available=False,
            decline_reason='Not stocked')
        self.req_item.available = True
        self.req_item.save(update_fields=['available'])
        self.token = self._mint_token()

    def test_the_available_line_finishes_and_the_declined_line_stays_outstanding(self):
        response = self._release(self.token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], Requisition.Status.RELEASED)
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('100.00'))
        # Truthful quantities for BOTH kinds of line, plus the store's answer each way.
        self.assertEqual(response.data['items'], [
            {'code': self.vuom.barcode_qr, 'released_now': '10.00',
             'outstanding': '0.00', 'available': True, 'decline_reason': ''},
            {'code': self.box_vuom.barcode_qr, 'released_now': '0.00',
             'outstanding': '3.00', 'available': False,
             'decline_reason': 'Not stocked'},
        ])

        self.token.refresh_from_db()
        self.assertTrue(self.token.is_used, 'a mixed request finished on its true lines')
        self.assertEqual(self.token.used_by, self.cashier)
        self.assertIsNotNone(self.token.used_at)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)
        self.assertEqual(self.requisition.released_amount, Decimal('100.00'))

        # The declined line's stock and quantities were never touched.
        self.box_line.refresh_from_db()
        self.assertEqual(self.box_line.released_qty, Decimal('0'))
        self.assertEqual(self.box_line.quantity, Decimal('3'))
        box_stock = sum(
            self.box_variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(box_stock, Decimal('30'))
        self.assertEqual(self._stock(), Decimal('90'))

    def test_verify_reports_the_declined_line_as_unavailable_with_its_reason(self):
        items = self._verify(self.token).data['items']

        self.assertEqual(
            [(item['available'], item['decline_reason'], item['availability'],
              item['releasable'], item['remaining']) for item in items],
            [(True, '', 'FULL', '10.00', '10.00'),
             (False, 'Not stocked', 'UNAVAILABLE', '0.00', '3.00')])

    def test_the_finished_mixed_token_is_refused_as_already_released(self):
        self.assertEqual(self._release(self.token).status_code, 201)
        before = self._release_snapshot()

        verify = self._verify(self.token)
        release = self._release(self.token)

        self.assertEqual(verify.status_code, 400, verify.data)
        self.assertEqual(verify.data['code'], 'REQUISITION_RELEASED')
        self.assertEqual(release.status_code, 400, release.data)
        self.assertEqual(release.data['code'], 'REQUISITION_RELEASED')
        self.assertEqual(self._release_snapshot(), before)


class SharedShelfWithDeclinedLineTests(StoreReviewReleaseBase):
    """A declined line on the SAME variant must not reserve the shelf it cannot use."""

    def setUp(self):
        super().setUp()
        # One variant, two selling units: the bag line is declined BEFORE the box line.
        self.box_line = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self._second_unit_of(
                self.variant, 'BOX', Decimal('12'), Decimal('120')),
            quantity=Decimal(1), available=True)
        self.req_item.available = False
        self.req_item.decline_reason = 'Not stocked'
        self.req_item.save(update_fields=['available', 'decline_reason'])
        self.token = self._mint_token()

    def _second_unit_of(self, variant, code, factor, price):
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=code, defaults={'name': code.title()})
        return VariantUOM.objects.create(
            variant=variant, uom=uom, conversion_factor=factor,
            default_selling_price=price)

    def test_the_box_line_sees_the_whole_shelf(self):
        items = self._verify(self.token).data['items']

        # The declined 10 bags of a 100-piece shelf took nothing: the box is FULL.
        self.assertEqual(
            [(item['available'], item['availability'], item['releasable'])
             for item in items],
            [(False, 'UNAVAILABLE', '0.00'), (True, 'FULL', '1.00')])

        response = self._release(self.token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], Requisition.Status.RELEASED)
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('120.00'))
        self.assertEqual(
            [line['released_now'] for line in response.data['items']],
            ['0.00', '1.00'])
        self.assertEqual(self._stock(), Decimal('88'))
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal('0'))
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.released_amount, Decimal('120.00'))


class ShortAvailableLineTests(StoreReviewReleaseBase):
    """A short Available line still keeps the token open, declined lines or not."""

    def setUp(self):
        super().setUp()
        self._leave_on_shelf(4)
        self.box_variant, self.box_vuom = self._boxes_of_twelve(30)
        RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.box_vuom,
            quantity=Decimal(3), available=False, decline_reason='Not stocked')
        self.req_item.available = True
        self.req_item.save(update_fields=['available'])
        self.token = self._mint_token()

    def test_a_short_true_line_leaves_the_request_partial(self):
        response = self._release(self.token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], Requisition.Status.PARTIAL)
        self.assertEqual(
            [(line['released_now'], line['outstanding'])
             for line in response.data['items']],
            [('4.00', '6.00'), ('0.00', '3.00')])
        self.token.refresh_from_db()
        self.assertFalse(self.token.is_used, 'a short true line must not spend the token')
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.released_amount, Decimal('40.00'))


class ScanRefusalTests(StoreReviewReleaseBase):
    """WAITING and DECLINED are named refusals, not "token already used"."""

    def test_waiting_is_refused_by_verify_and_by_release_and_writes_nothing(self):
        self.requisition.status = Requisition.Status.WAITING
        self.requisition.save(update_fields=['status'])
        token = self._mint_token()
        before = self._release_snapshot()

        verify = self._verify(token)
        release = self._release(token)

        for response in (verify, release):
            self.assertEqual(response.status_code, 400, response.data)
            self.assertEqual(response.data['code'], 'REQUISITION_WAITING')
            self.assertIn('WAITING', response.data['detail'])
        self.assertEqual(self._release_snapshot(), before)

    def test_a_declined_token_explains_the_decline_not_a_used_token(self):
        # The Decline itself spends the token, so the status must be read FIRST.
        token = self._mint_token()
        self.requisition.status = Requisition.Status.WAITING
        self.requisition.save(update_fields=['status'])
        decline_requisition(
            requisition_id=self.requisition.pk, decline_reason='Cannot supply')
        token.refresh_from_db()
        self.assertTrue(token.is_used, 'the decline spends the token')
        before = self._release_snapshot()

        verify = self._verify(token)
        release = self._release(token)

        for response in (verify, release):
            self.assertEqual(response.status_code, 400, response.data)
            self.assertEqual(response.data['code'], 'REQUISITION_DECLINED')
            self.assertIn('DECLINED', response.data['detail'])
            self.assertNotIn('already been used', response.data['detail'])
        self.assertEqual(self._release_snapshot(), before)


class ReleasedAmountTests(StoreReviewReleaseBase):
    """Decision 14: accumulate the PERSISTED sale total, never guess an old one."""

    def test_a_known_amount_accumulates_the_persisted_sale_totals(self):
        self._leave_on_shelf(4)
        self.req_item.available = True
        self.req_item.save(update_fields=['available'])
        token = self._mint_token()

        first = self._release(token)
        self.assertEqual(first.status_code, 201, first.data)
        self._receive(self.variant, Decimal(10))
        second = self._release(token)
        self.assertEqual(second.status_code, 201, second.data)

        self.requisition.refresh_from_db()
        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION).order_by('pk')
        self.assertEqual(sales.count(), 2)
        self.assertEqual(
            self.requisition.released_amount,
            sum(sale.grand_total for sale in sales))
        self.assertEqual(self.requisition.released_amount, Decimal('100.00'))
        # What the till was told is the same number that was persisted.
        self.assertEqual(
            [Decimal(first.data['grand_total']), Decimal(second.data['grand_total'])],
            [sale.grand_total for sale in sales])

    def test_repeated_fractional_price_releases_equal_the_reloaded_sales(self):
        # A measured unit at 10.05: 0.33 x 10.05 = 3.3165, which the sale stores as 3.32.
        del self.requisition
        self.requisition = Requisition.objects.create(
            project=self.project, req_number='REQ-TEST-FRACTION',
            status=Requisition.Status.ACCEPTED, requester_name='Rey Quester')
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code='M', defaults={'name': 'Metre'})
        product = Product.objects.create(
            category=Category.objects.get(name='Cement'),
            brand=Brand.objects.get(name='Rhino'), base_name='Cable')
        variant = ProductVariant.objects.create(
            product=product, variant_name='2mm', base_uom=uom)
        self.vuom = VariantUOM.objects.create(
            variant=variant, uom=uom, conversion_factor=Decimal(1),
            default_selling_price=Decimal('10.05'))
        line = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal('0.66'), available=True)
        self._receive(variant, Decimal('0.33'))
        token = self._mint_token()

        first = self._release(token)
        self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(Decimal(first.data['grand_total']), Decimal('3.32'))
        self._receive(variant, Decimal('0.33'))
        second = self._release(token)

        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(second.data['status'], Requisition.Status.RELEASED)
        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION).order_by('pk')
        self.requisition.refresh_from_db()
        self.assertEqual(
            self.requisition.released_amount,
            sum(sale.grand_total for sale in sales))
        self.assertEqual(self.requisition.released_amount, Decimal('6.64'))
        line.refresh_from_db()
        self.assertEqual(line.released_qty, Decimal('0.66'))

    def test_a_historical_unknown_amount_stays_unknown(self):
        self.requisition.released_amount = None
        self.requisition.save(update_fields=['released_amount'])
        self.req_item.available = True
        self.req_item.save(update_fields=['available'])
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.requisition.refresh_from_db()
        self.assertIsNone(
            self.requisition.released_amount,
            'a known amount added to an unknown baseline is still unknown')


class AuditRollbackTests(StoreReviewReleaseBase):
    """The release and its audit row are one transaction (decision 07)."""

    def test_a_failed_audit_rolls_back_stock_money_and_amount(self):
        self.req_item.available = True
        self.req_item.save(update_fields=['available'])
        token = self._mint_token()
        before = self._release_snapshot()

        with mock.patch(
                'apps.requisitions.views.audit_request',
                side_effect=RuntimeError('audit unavailable')):
            response = self._release(token)

        self.assertEqual(response.status_code, 500, getattr(response, 'data', None))
        self.assertEqual(self._release_snapshot(), before)
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())


class ConcurrentMixedReleaseTests(TransactionTestCase):
    """Two tills scanning one mixed token: one deduction, one amount, declined untouched.

    `TransactionTestCase` because the two worker threads must see each other's COMMITTED
    rows — a `TestCase`'s wrapping transaction hides them and the test would then pass or
    fail on timing instead of on the token→request lock. No sleeps: a barrier starts both
    requests at the same moment.
    """

    def setUp(self):
        self.password = get_random_string(16)
        self.manager = self._user('manager1', 'Store Manager')
        self.cashier = self._user('cashier1', 'Cashier')
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal(5000))
        self.customer = Customer.objects.create(
            name='Builder Corp', customer_type=Customer.Type.CONTRACTOR)
        self.project = Project.objects.create(
            name='House Build', customer=self.customer)
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code='BAG', defaults={'name': 'Bag'})
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        self.vuom = VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal(1),
            default_selling_price=Decimal('10'))
        self._receive(5)

        box, _ = UnitOfMeasure.objects.get_or_create(
            code='BOX', defaults={'name': 'Box'})
        box_product = Product.objects.create(
            category=category, brand=brand, base_name='Premium Cement')
        self.box_variant = ProductVariant.objects.create(
            product=box_product, variant_name='50kg', base_uom=box)
        self.box_vuom = VariantUOM.objects.create(
            variant=self.box_variant, uom=box, conversion_factor=Decimal(12),
            default_selling_price=Decimal('120'))
        self._receive(30, variant=self.box_variant, uom=box)

        self.requisition = Requisition.objects.create(
            project=self.project, req_number='REQ-RACE-MIXED',
            status=Requisition.Status.ACCEPTED, requester_name='Rey Quester')
        self.item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal(10), available=True)
        self.box_line = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.box_vuom,
            quantity=Decimal(3), available=False, decline_reason='Not stocked')
        self.token = MaterialToken.objects.create(requisition=self.requisition)

    def _receive(self, quantity, variant=None, uom=None):
        """Stock through the REAL goods-receipt path, one base unit per piece."""
        variant = variant or self.variant
        uom = uom or variant.base_uom
        supplier = Supplier.objects.create(company_name=f'Acme {variant.pk}')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=variant, ordered_qty=quantity,
            unit_cost=Decimal(1), received_qty=quantity)
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)
        self.assertEqual(uom, variant.base_uom)

    def _user(self, username, group):
        user = User.objects.create_user(
            username=username, email=f'{username}@x.com', password=self.password,
            full_name=username)
        user.groups.add(Group.objects.get_or_create(name=group)[0])
        return user

    def test_two_concurrent_releases_deduct_once_and_count_the_amount_once(self):
        barrier = threading.Barrier(2, timeout=20)
        results = []
        lock = threading.Lock()

        def worker():
            client = APIClient()
            login = client.post(
                '/api/v1/auth/login/',
                {'username': self.cashier.username, 'password': self.password},
                format='json')
            self.assertEqual(login.status_code, 200, login.data)
            try:
                barrier.wait()
                response = client.post(
                    RELEASE_URL, {'token': str(self.token.token)}, format='json',
                    HTTP_AUTHORIZATION=f'Bearer {login.data["access"]}')
                with lock:
                    results.append((response.status_code, response.data))
            finally:
                # Each thread owns its own connection; leaving it open would hang the
                # truncation this TestCase does when it finishes.
                connections.close_all()

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(len(results), 2, results)
        statuses = sorted(status for status, _data in results)
        # 5 on the shelf of 10 asked: the winner is PARTIAL, the loser finds nothing.
        self.assertEqual(statuses, [201, 400], results)
        losing = next(data for status, data in results if status == 400)
        self.assertEqual(losing.get('code'), 'NOTHING_TO_RELEASE', losing)

        stock = sum(self.variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(stock, Decimal(0), 'the shelf moved exactly once')
        self.item.refresh_from_db()
        self.assertEqual(self.item.released_qty, Decimal(5))
        box_stock = sum(
            self.box_variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(box_stock, Decimal(30), 'the declined line took no stock')
        self.box_line.refresh_from_db()
        self.assertEqual(self.box_line.released_qty, Decimal(0))

        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION)
        self.assertEqual(sales.count(), 1)
        requisition = Requisition.objects.get(pk=self.requisition.pk)
        self.assertEqual(requisition.released_amount, sales.get().grand_total)
        self.assertEqual(requisition.released_amount, Decimal('50.00'))
        self.assertEqual(requisition.status, Requisition.Status.PARTIAL)
