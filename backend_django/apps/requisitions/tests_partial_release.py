# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
"""Phase 1 Task 5 — release what is there (decision 05).

A release used to be all-or-nothing: `allocate_fifo` raised on the first short line and
the whole request stayed unreleased. Decision 05 releases what the shelf holds NOW, keeps
the short remainder outstanding on the SAME token, and books one sale plus one
project-tagged utang for exactly what left the store.

The numbers are the contract, so the tests read them the way the cashier sees them:
"10 bags were asked for, 4 are on the shelf, 4 leave, 6 stay outstanding". `PARTIAL` keeps
the token alive for a second visit; `RELEASED` consumes it; nothing on any line is a `400
NOTHING_TO_RELEASE` that writes not one row.
"""

import threading
from decimal import Decimal

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
from apps.inventory.services import allocate_fifo, process_goods_receipt
from apps.pos.models import (
    Customer,
    OfficialReceipt,
    SalesItem,
    SalesTransaction,
    Shift,
)
from apps.pos.services import process_sale
from apps.users.models import AuditLog

from .models import MaterialToken, Project, Requisition, RequisitionItem
from .services import verify_token
from .tests import RequisitionTestBase
from .tests_release_shift import ReleaseShiftBase

RELEASE_URL = '/api/v1/tokens/release/'
VERIFY_URL = '/api/v1/tokens/verify/'


class PartialReleaseBase(ReleaseShiftBase):
    """The shared fixture (10 bags at 10.00, 100 on the shelf) plus shelf control.

    `RequisitionTestBase` stocks 100 base units; a short release needs fewer, so
    `_leave_on_shelf` burns the difference through the SAME FIFO allocator a sale uses
    (no test-only stock writes), and `_receive` puts more back through the real goods
    receipt path.
    """

    def _leave_on_shelf(self, qty):
        on_shelf = sum(self.variant.batches.values_list('current_qty', flat=True))
        allocate_fifo(variant_id=self.variant.pk, qty_needed=on_shelf - Decimal(qty))
        self.assertEqual(self._stock(), Decimal(qty))

    def _receive(self, variant, quantity):
        supplier = Supplier.objects.create(company_name=f'Restock {variant.pk}')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=variant, ordered_qty=quantity,
            unit_cost=Decimal(1), received_qty=quantity)
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

    def _boxes_of_twelve(self, on_shelf):
        """A second variant sold only in boxes of 12, with `on_shelf` PIECES in stock."""
        box_uom, _ = UnitOfMeasure.objects.get_or_create(
            code='BOX', defaults={'name': 'Box'})
        product = Product.objects.create(
            category=self.variant.product.category,
            brand=self.variant.product.brand,
            base_name='Premium Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='50kg', base_uom=box_uom)
        vuom = VariantUOM.objects.create(
            variant=variant, uom=box_uom, conversion_factor=Decimal(12),
            default_selling_price=Decimal(120))
        self._receive(variant, Decimal(on_shelf))
        return variant, vuom

    def _ledger_rows(self):
        return CollectibleLedger.objects.filter(transaction__source=SalesTransaction.Source.REQUISITION)


class FullStockReleaseTests(PartialReleaseBase):
    """Everything is on the shelf: one release, one utang, the token is spent."""

    def test_full_stock_releases_everything_and_tags_the_utang_with_the_project(self):
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'RELEASED')
        self.assertEqual(
            response.data['items'],
            [{'code': self.vuom.barcode_qr, 'released_now': '10.00',
              'outstanding': '0.00', 'available': None,
              'decline_reason': ''}])

        ledger = CollectibleLedger.objects.get(
            transaction_id=response.data['transaction_id'])
        self.assertEqual(ledger.project, self.project, 'decision 03: utang carries its project')
        self.assertEqual(ledger.balance_due, Decimal(100))

        token.refresh_from_db()
        self.assertTrue(token.is_used)
        self.assertEqual(token.used_by, self.cashier)
        self.assertIsNotNone(token.used_at)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)

    def test_verify_reports_a_full_line_as_full(self):
        token = self._mint_token()

        info = verify_token(token_value=str(token.token))

        item = info['items'][0]
        self.assertEqual(item['availability'], 'FULL')
        self.assertEqual(item['releasable'], '10.00')
        self.assertEqual(item['remaining'], '10.00')


class ShortStockReleaseTests(PartialReleaseBase):
    """4 of 10 on the shelf: 4 leave, 6 stay outstanding, the token stays alive."""

    def setUp(self):
        super().setUp()
        self._leave_on_shelf(4)

    def test_verify_shows_the_short_line_with_what_is_there(self):
        token = self._mint_token()

        item = verify_token(token_value=str(token.token))['items'][0]

        self.assertEqual(item['availability'], 'SHORT')
        self.assertEqual(item['releasable'], '4.00')
        self.assertEqual(item['remaining'], '10.00')

    def test_the_first_release_takes_what_is_there_and_keeps_the_token_alive(self):
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'PARTIAL')
        self.assertEqual(Decimal(response.data['grand_total']), Decimal(40))
        self.assertEqual(
            response.data['items'],
            [{'code': self.vuom.barcode_qr, 'released_now': '4.00',
              'outstanding': '6.00', 'available': None,
              'decline_reason': ''}])

        # Exactly what left the store: 4 bags on the sale, 40.00 of utang, 4 off the shelf.
        sale = SalesTransaction.objects.get(pk=response.data['transaction_id'])
        self.assertEqual([i.qty for i in sale.items.all()], [Decimal(4)])
        ledger = CollectibleLedger.objects.get(transaction=sale)
        self.assertEqual(ledger.balance_due, Decimal(40))
        self.assertEqual(ledger.project, self.project)
        self.assertEqual(self._stock(), Decimal(0))

        # The request is still open and the token still works: the cashier comes back.
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal(4))
        token.refresh_from_db()
        self.assertFalse(token.is_used, 'a partial release must not spend the token')
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.PARTIAL)

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.RELEASE)
        self.assertIn('partially released', row.description)
        self.assertNotIn(str(token.token), row.description)

    def test_a_second_release_after_a_restock_finishes_the_request(self):
        token = self._mint_token()
        first = self._release(token)
        self.assertEqual(first.status_code, 201, first.data)
        self._receive(self.variant, Decimal(10))

        second = self._release(token)

        self.assertEqual(second.status_code, 201, second.data)
        self.assertEqual(second.data['status'], 'RELEASED')
        self.assertEqual(Decimal(second.data['grand_total']), Decimal(60))
        self.assertEqual(
            second.data['items'],
            [{'code': self.vuom.barcode_qr, 'released_now': '6.00',
              'outstanding': '0.00', 'available': None,
              'decline_reason': ''}])

        # Two releases, two utang rows, both tagged with the project, 100.00 in total.
        ledgers = self._ledger_rows().order_by('pk')
        self.assertEqual(len(ledgers), 2)
        self.assertEqual({ledger.project for ledger in ledgers}, {self.project})
        self.assertEqual(
            sum(ledger.balance_due for ledger in ledgers), Decimal(100))

        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal(10))
        self.assertEqual(self._stock(), Decimal(4))
        token.refresh_from_db()
        self.assertTrue(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)


class BoxRoundingTests(PartialReleaseBase):
    """3 boxes of 12 asked for, 30 pieces on the shelf: only 2 whole boxes can go."""

    def setUp(self):
        super().setUp()
        self.box_variant, self.box_vuom = self._boxes_of_twelve(30)
        self.box_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.box_vuom,
            quantity=Decimal(3))
        # Keep the release to the box line alone, so the numbers are unambiguous.
        RequisitionItem.objects.filter(pk=self.req_item.pk).delete()

    def test_boxes_round_down_and_the_remainder_stays_outstanding(self):
        token = self._mint_token()

        item = verify_token(token_value=str(token.token))['items'][0]
        self.assertEqual(item['availability'], 'SHORT')
        self.assertEqual(item['releasable'], '2.00')

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'PARTIAL')
        self.assertEqual(
            response.data['items'],
            [{'code': self.box_vuom.barcode_qr, 'released_now': '2.00',
              'outstanding': '1.00', 'available': None,
              'decline_reason': ''}])
        # FIFO took 2 x 12 pieces; the sale line keeps the SELLING quantity.
        box_stock = sum(self.box_variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(box_stock, Decimal(6))
        line = SalesItem.objects.get(transaction_id=response.data['transaction_id'])
        self.assertEqual(line.qty, Decimal(2))
        self.assertEqual(Decimal(response.data['grand_total']), Decimal(240))
        self.box_item.refresh_from_db()
        self.assertEqual(self.box_item.released_qty, Decimal(2))


class ArchivedLineTests(PartialReleaseBase):
    """An archived line can never leave the store, and it does not block the others."""

    def setUp(self):
        super().setUp()
        self.box_variant, self.box_vuom = self._boxes_of_twelve(50)
        self.box_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.box_vuom,
            quantity=Decimal(2))
        # Decision 04/05: a variant CPMS can no longer be shown is unavailable, even
        # though its batches still hold stock.
        self.variant.is_active = False
        self.variant.save(update_fields=['is_active'])

    def test_an_archived_line_is_unavailable_and_stays_outstanding(self):
        token = self._mint_token()

        items = verify_token(token_value=str(token.token))['items']
        self.assertEqual(items[0]['availability'], 'UNAVAILABLE')
        self.assertEqual(items[0]['releasable'], '0.00')
        self.assertEqual(items[0]['remaining'], '10.00')
        self.assertEqual(items[1]['availability'], 'FULL')

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'PARTIAL')
        self.assertEqual(
            response.data['items'],
            [{'code': self.vuom.barcode_qr, 'released_now': '0.00',
              'outstanding': '10.00', 'available': None,
              'decline_reason': ''},
             {'code': self.box_vuom.barcode_qr, 'released_now': '2.00',
              'outstanding': '0.00', 'available': None,
              'decline_reason': ''}])
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal(0))
        # The archived variant's stock is untouched.
        self.assertEqual(self._stock(), Decimal(100))


class NothingToReleaseTests(PartialReleaseBase):
    """Nothing on any line: a 400 NOTHING_TO_RELEASE and not one row written."""

    def test_an_empty_shelf_refuses_the_release_without_writing_anything(self):
        self._leave_on_shelf(0)
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'NOTHING_TO_RELEASE', response.data)
        self.assertTrue(response.data.get('detail'), response.data)

        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertFalse(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.RELEASE).exists())
        self.assertEqual(self._stock(), Decimal(0))
        token.refresh_from_db()
        self.assertFalse(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.ACCEPTED)
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal(0))


class ClosedRequestRefusalTests(PartialReleaseBase):
    """A request that is closed, cancelled or already released is refused both ways."""

    def setUp(self):
        super().setUp()
        self.token = self._mint_token()

    def _body(self):
        return {'token': str(self.token.token)}

    def _release_at(self, status):
        self.requisition.status = status
        self.requisition.save(update_fields=['status'])
        return self.client.post(
            RELEASE_URL, self._body(), format='json',
            HTTP_AUTHORIZATION=self.bearer)

    def _verify_at(self, status):
        self.requisition.status = status
        self.requisition.save(update_fields=['status'])
        return self.client.post(
            VERIFY_URL, self._body(), format='json',
            HTTP_AUTHORIZATION=self.bearer)

    def test_closed_and_cancelled_are_refused_at_verify(self):
        for status in (Requisition.Status.CLOSED, Requisition.Status.CANCELLED,
                       Requisition.Status.RELEASED):
            with self.subTest(status=status):
                response = self._verify_at(status)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn(status, response.data['detail'])
                # A stable code, so the till never parses the sentence.
                self.assertEqual(response.data['code'], f'REQUISITION_{status}')

    def test_closed_and_cancelled_are_refused_at_release(self):
        for status in (Requisition.Status.CLOSED, Requisition.Status.CANCELLED):
            with self.subTest(status=status):
                response = self._release_at(status)
                self.assertEqual(response.status_code, 400, response.data)
                self.assertIn(status, response.data['detail'])
                # A stable code, so the till never parses the sentence.
                self.assertEqual(response.data['code'], f'REQUISITION_{status}')

        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertEqual(self._stock(), Decimal(100))


class SharedStockTests(PartialReleaseBase):
    """Two lines on one variant share ONE shelf: the second sees what the first takes."""

    def setUp(self):
        super().setUp()
        self._leave_on_shelf(12)
        self.second_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal(5))

    def test_the_second_line_on_the_same_variant_sees_the_leftovers(self):
        token = self._mint_token()

        items = verify_token(token_value=str(token.token))['items']
        self.assertEqual(
            [(item['availability'], item['releasable']) for item in items],
            [('FULL', '10.00'), ('SHORT', '2.00')])

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(response.data['status'], 'PARTIAL')
        self.assertEqual(
            [(line['released_now'], line['outstanding'])
             for line in response.data['items']],
            [('10.00', '0.00'), ('2.00', '3.00')])
        self.assertEqual(self._stock(), Decimal(0))
        self.second_item.refresh_from_db()
        self.assertEqual(self.second_item.released_qty, Decimal(2))

    def test_a_rescan_shows_the_finished_line_as_done_not_full(self):
        token = self._mint_token()
        self._release(token)

        items = verify_token(token_value=str(token.token))['items']
        # Line 1 is out; line 2 has 3 outstanding and an empty shelf.
        self.assertEqual(
            [(item['availability'], item['releasable']) for item in items],
            [('DONE', '0.00'), ('UNAVAILABLE', '0.00')])


class CounterSaleLedgerTests(RequisitionTestBase):
    """Decision 03: only a release carries a project; a counter sale's utang carries none."""

    def test_a_counter_sale_ledger_has_no_project(self):
        contractor = Customer.objects.create(
            name='Builder Corp', customer_type=Customer.Type.CONTRACTOR)

        process_sale(
            customer_id=contractor.pk,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.pk, 'qty': Decimal(2)}],
            payments_data=[{'method': 'CASH', 'amount_tendered': Decimal(5)}],
        )

        ledger = CollectibleLedger.objects.get(customer=contractor)
        self.assertIsNone(ledger.project)
        self.assertEqual(ledger.balance_due, Decimal(15))


class ConcurrentReleaseTests(TransactionTestCase):
    """Two tills scanning the same PARTIAL token at once: the shelf is not overdrawn.

    `TransactionTestCase` because the two worker threads must see each other's COMMITTED
    rows — a `TestCase`'s wrapping transaction hides them and the test would then pass or
    fail on timing instead of on the token row lock.
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
            default_selling_price=Decimal(10))
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal(10),
            unit_cost=Decimal(40), received_qty=Decimal(10))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

        self.requisition = Requisition.objects.create(
            project=self.project, req_number='REQ-RACE-0001',
            status=Requisition.Status.ACCEPTED, requester_name='Rey Quester')
        self.item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal(15))
        self.token = MaterialToken.objects.create(requisition=self.requisition)

    def _user(self, username, group):
        from django.contrib.auth import get_user_model

        user = get_user_model().objects.create_user(
            username=username, email=f'{username}@x.com', password=self.password,
            full_name=username)
        user.groups.add(Group.objects.get_or_create(name=group)[0])
        return user

    def test_two_concurrent_releases_never_overdraw_the_shelf(self):
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
        self.assertEqual(statuses, [201, 400], results)
        losing = next(
            data for status, data in results if status == 400)
        self.assertEqual(losing.get('code'), 'NOTHING_TO_RELEASE', losing)

        # 10 on the shelf, 15 asked for: exactly 10 left, never 15 and never a re-release
        # of the same line.
        stock = sum(self.variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(stock, Decimal(0))
        self.item.refresh_from_db()
        self.assertEqual(self.item.released_qty, Decimal(10))
        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION)
        self.assertEqual(sales.count(), 1)
        ledger = CollectibleLedger.objects.get(transaction=sales.get())
        self.assertEqual(ledger.balance_due, Decimal(100))
        self.assertEqual(ledger.project, self.project)
        # Decision 14: the amount was accumulated ONCE, from the persisted sale total.
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.released_amount, Decimal('100.00'))
        self.assertEqual(self.requisition.released_amount, sales.get().grand_total)
