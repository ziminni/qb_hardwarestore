#!/usr/bin/env python
# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/integration/tests.py: this checker
# runs with a working directory outside the repo, so no pyrightconfig.json is found and
# every `Model.objects` access and `self.client.get(...).status_code` is a false positive
# on valid Django. Django's own `manage.py check` and the test run remain the authority.
"""CPMS boundary tests (Phase 1, Task 6): closing a remainder, reading back and payables.

Decision 06: CPMS closes an open remainder. The POS copy stays read-only — this is the one
CPMS write after the push — and the request becomes `CLOSED` with its token dead. What was
already released stays released and stays payable; the released UTang is never touched.

Decision 07: CPMS reads, per request, what was requested / released / outstanding, and per
project its total, paid and balance. Read-only, from the ledgers the POS already keeps.

The interesting tests are the ones about what does NOT happen: a repeat close writes
nothing, a close of a finished request is a no-op, and a close racing a cashier release
cannot interleave (`CloseReleaseRaceTests`, a `TransactionTestCase` because the threads
must see each other's committed rows).
"""

import threading
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.collectibles.models import CollectibleLedger, CollectiblePayment
from apps.collectibles.services import apply_payment_to_ledger
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
from apps.pos.models import Customer, SalesTransaction, Shift
from apps.requisitions.models import (
    MaterialToken,
    Project,
    Requisition,
    RequisitionItem,
)
from apps.requisitions.services import accept_requisition, decline_requisition
from apps.users.models import AuditLog

from .tests import CPMS_URL, make_user
from .tests_import import REQUESTS_URL, ImportTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
RELEASE_URL = '/api/v1/tokens/release/'
VERIFY_URL = '/api/v1/tokens/verify/'
PAYMENTS_URL = '/api/v1/ledger-payments/'

CPMS_REQUEST_ID = 'CPMS-REQ-0001'
CPMS_PROJECT_ID = 'CPMS-PRJ-0001'
# The fixture's material: 280.00 a bag, so a 4-bag release is 1120.00 of utang.
BAG_PRICE = Decimal(280)


def request_url(cpms_request_id=CPMS_REQUEST_ID):
    return f'{REQUESTS_URL}{cpms_request_id}/'


def close_url(cpms_request_id=CPMS_REQUEST_ID):
    return f'{request_url(cpms_request_id)}close/'


def payables_url(cpms_project_id=CPMS_PROJECT_ID):
    return f'{CPMS_URL}projects/{cpms_project_id}/payables/'


class CloseTestBase(ImportTestBase):
    """The import fixture plus what a release needs: a shelf, a receiver, a cashier login.

    `ImportTestBase` already holds the whole contract in one payload (one sellable
    material, one contractor payer, `self.push()`), so every test below starts by pushing
    a real CPMS request rather than hand-writing a requisition.
    """

    def setUp(self):
        super().setUp()
        self.manager = make_user('close_manager', 'Store Manager')
        # A release is a sale (decision 03), so the cashier needs an open shift.
        Shift.objects.create(cashier=self.cashier, opening_float=Decimal(5000))
        self.receive(Decimal(100))
        self.cashier_auth = self.login(self.cashier.username)

    def receive(self, quantity, variant=None):
        """Stock a fixture variant through the REAL goods-receipt path."""
        variant = variant or self.vuom.variant
        supplier = Supplier.objects.create(
            company_name=f'Supplier {quantity} {variant.pk}')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=variant, ordered_qty=quantity,
            unit_cost=Decimal(1), received_qty=quantity)
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

    def leave_on_shelf(self, quantity, variant=None):
        """Burn the difference through the same FIFO allocator a sale uses."""
        variant = variant or self.vuom.variant
        on_shelf = sum(variant.batches.values_list('current_qty', flat=True))
        allocate_fifo(
            variant_id=variant.pk, qty_needed=on_shelf - Decimal(quantity))

    def pushed(self, quantity='10'):
        """Push one request and return its stored copy (it lands WAITING)."""
        res = self.push(items=[{'code': self.code, 'quantity': quantity}])
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def accepted(self, quantity='10'):
        """Push one request and accept its lines through the real service.

        Decision 13: a push arrives WAITING, so every release/close fixture answers it
        exactly as the manager screen does — no test writes a status by hand.
        """
        body = self.pushed(quantity=quantity)
        accept_requisition(
            requisition_id=body['id'],
            items=[{'id': line.pk, 'available': True, 'decline_reason': ''}
                   for line in RequisitionItem.objects.filter(
                       requisition_id=body['id']).order_by('pk')])
        return body

    def close(self, cpms_request_id=CPMS_REQUEST_ID):
        return self.client.post(
            close_url(cpms_request_id), content_type='application/json',
            HTTP_AUTHORIZATION=self.auth)

    def read_back(self, cpms_request_id=CPMS_REQUEST_ID):
        return self.client.get(
            request_url(cpms_request_id), HTTP_AUTHORIZATION=self.auth)

    def payables(self, cpms_project_id=CPMS_PROJECT_ID):
        return self.client.get(
            payables_url(cpms_project_id), HTTP_AUTHORIZATION=self.auth)

    def release(self, token=None):
        return self.client.post(
            RELEASE_URL, {'token': str(token or self.token)},
            content_type='application/json', HTTP_AUTHORIZATION=self.cashier_auth)

    def verify(self, token=None):
        return self.client.post(
            VERIFY_URL, {'token': str(token or self.token)},
            content_type='application/json', HTTP_AUTHORIZATION=self.cashier_auth)

    def close_rows(self):
        """The audit rows the close wrote (the fixture's own rows are LOGIN/REQ_APPROVE)."""
        return AuditLog.objects.filter(action_type=AuditLog.ActionType.REQ_REJECT)

    def release_ledgers(self):
        return CollectibleLedger.objects.filter(
            transaction__source=SalesTransaction.Source.REQUISITION)

    def requisition(self):
        return Requisition.objects.get(cpms_request_id=CPMS_REQUEST_ID)

    def line(self):
        return self.requisition().items.get()


class CloseFromOpenRequestTests(CloseTestBase):
    """Decision 06: a WAITING, ACCEPTED or PARTIAL request closes, token and all."""

    def test_a_waiting_request_closes_and_its_token_dies(self):
        body = self.pushed()

        res = self.close()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.CLOSED)
        self.assertEqual(res.json()['req_number'], body['req_number'])
        token = MaterialToken.objects.get(requisition=self.requisition())
        self.assertTrue(token.is_used, 'the close must kill the token')
        self.assertIsNotNone(token.used_at)
        self.assertIsNone(
            token.used_by, 'CPMS closed it: no cashier spent this token')

    def test_the_close_answers_the_read_back_body(self):
        self.pushed()

        closed = self.close().json()
        read = self.read_back()

        self.assertEqual(read.status_code, 200, read.content)
        self.assertEqual(closed, read.json())
        self.assertEqual(
            set(closed), {'cpms_request_id', 'req_number', 'status', 'decline_reason',
                          'expected_amount', 'items'})
        self.assertEqual(
            set(closed['items'][0]),
            {'code', 'requested', 'released', 'outstanding',
             'available', 'decline_reason'})

    def test_a_partial_release_closes_its_remainder_and_leaves_the_utang_alone(self):
        self.leave_on_shelf(4)
        self.accepted()
        released = self.release()
        self.assertEqual(released.status_code, 201, released.content)
        self.assertEqual(released.data['status'], Requisition.Status.PARTIAL)
        ledger = self.release_ledgers().get()

        res = self.close()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.CLOSED)
        self.assertEqual(res.json()['items'][0]['released'], '4.00')
        self.assertEqual(res.json()['items'][0]['outstanding'], '6.00')
        # Decision 06: what left the store stays sold and stays owed.
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('1120.00'))
        self.assertEqual(ledger.original_amount, Decimal('1120.00'))
        self.assertEqual(self.release_ledgers().count(), 1)
        self.assertEqual(self.line().released_qty, Decimal(4))

    def test_the_closed_token_is_refused_by_verify_and_by_release(self):
        self.leave_on_shelf(4)
        self.accepted()
        self.assertEqual(self.release().status_code, 201)
        self.assertEqual(self.close().status_code, 200)
        sales_before = SalesTransaction.objects.count()

        verify = self.verify()
        release = self.release()

        self.assertEqual(verify.status_code, 400, verify.content)
        self.assertEqual(release.status_code, 400, release.content)
        self.assertEqual(
            SalesTransaction.objects.count(), sales_before,
            'a closed request cannot ring another sale')
        self.assertEqual(self.line().released_qty, Decimal(4))

    def test_one_audit_row_names_the_request_and_the_cpms_id_never_the_token(self):
        body = self.pushed()

        self.close()

        rows = self.close_rows()
        self.assertEqual(rows.count(), 1)
        row = rows.get()
        self.assertEqual(row.user, self.cpms)
        self.assertIn(body['req_number'], row.description)
        self.assertIn(CPMS_REQUEST_ID, row.description)
        self.assertNotIn(str(self.token), row.description)

    def test_a_waiting_request_can_be_withdrawn_and_its_token_dies(self):
        """Decision 13, edge case 1: CPMS may close what the store never answered.

        The import itself leaves the request WAITING (Task 4), which is exactly the
        state this close has to handle: no answer exists, so nothing is overwritten.
        """
        self.pushed()
        requisition = self.requisition()
        self.assertEqual(requisition.status, Requisition.Status.WAITING)

        res = self.close()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.CLOSED)
        token = MaterialToken.objects.get(requisition=requisition)
        self.assertTrue(token.is_used, 'a withdrawn request cannot leave the store')
        self.assertIsNone(token.used_by, 'CPMS closed it: no cashier spent this token')
        # A withdrawal is not a review: nobody answered the lines.
        self.assertIsNone(self.line().available)
        self.assertEqual(self.line().decline_reason, '')
        self.assertEqual(self.close_rows().count(), 1)


class CloseNoOpTests(CloseTestBase):

    def test_a_declined_request_is_a_no_op_and_keeps_the_stores_answer(self):
        """Decision 13: a close never overwrites a decision the store already made."""
        self.pushed()
        decline_requisition(
            requisition_id=self.requisition().pk, decline_reason='Cannot supply')
        requisition = self.requisition()
        line = self.line()
        token = MaterialToken.objects.get(requisition=requisition)
        used_at = token.used_at
        self.assertTrue(token.is_used, 'the decline itself spent the token')

        res = self.close()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.DECLINED)
        requisition.refresh_from_db()
        self.assertEqual(requisition.decline_reason, 'Cannot supply')
        line.refresh_from_db()
        self.assertFalse(line.available)
        self.assertEqual(line.decline_reason, 'Cannot supply')
        # Nothing closed, so the token is not re-spent and no close row is written.
        token.refresh_from_db()
        self.assertEqual(token.used_at, used_at)
        self.assertTrue(token.is_used)
        self.assertEqual(self.close_rows().count(), 0)
    """Decision 06: a close for a request that is already finished or closed is a no-op."""

    def test_closing_twice_changes_nothing_and_writes_no_second_row(self):
        self.pushed()
        first = self.close()
        token = MaterialToken.objects.get(requisition=self.requisition())
        used_at = token.used_at

        second = self.close()

        self.assertEqual(second.status_code, 200, second.content)
        self.assertEqual(second.json(), first.json())
        token.refresh_from_db()
        self.assertEqual(token.used_at, used_at, 'a no-op must not re-spend the token')
        self.assertEqual(self.close_rows().count(), 1)

    def test_a_fully_released_request_is_not_touched(self):
        self.accepted()
        released = self.release()
        self.assertEqual(released.data['status'], Requisition.Status.RELEASED)
        ledger = self.release_ledgers().get()
        sales = SalesTransaction.objects.count()

        res = self.close()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.RELEASED)
        token = MaterialToken.objects.get(requisition=self.requisition())
        self.assertEqual(token.used_by, self.cashier,
                         'the cashier who spent it stays the one on the token')
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal('2800.00'))
        self.assertEqual(SalesTransaction.objects.count(), sales)
        self.assertEqual(self.close_rows().count(), 0,
                         'nothing closed, so no close row')


class CloseRefusalTests(CloseTestBase):
    """Cancelled is a refusal; an unknown id is a 404 and writes nothing."""

    def test_a_cancelled_request_is_409_and_stays_cancelled(self):
        self.pushed()
        requisition = self.requisition()
        requisition.status = Requisition.Status.CANCELLED
        requisition.save(update_fields=['status'])

        res = self.close()

        self.assertEqual(res.status_code, 409, res.content)
        self.assertEqual(res.json()['code'], 'REQUEST_CANCELLED')
        requisition.refresh_from_db()
        self.assertEqual(requisition.status, Requisition.Status.CANCELLED)
        token = MaterialToken.objects.get(requisition=requisition)
        self.assertFalse(token.is_used)
        self.assertEqual(self.close_rows().count(), 0)

    def test_an_unknown_request_is_404_on_close_and_on_read_back(self):
        for response in (self.close('NOPE-1'), self.read_back('NOPE-1')):
            with self.subTest(status=response.status_code):
                self.assertEqual(response.status_code, 404, response.content)
                self.assertEqual(response.json()['code'], 'REQUEST_NOT_FOUND')
        self.assertEqual(self.close_rows().count(), 0)

    def test_an_unknown_project_payables_is_404(self):
        res = self.payables('NOPE-PRJ')

        self.assertEqual(res.status_code, 404, res.content)
        self.assertEqual(res.json()['code'], 'PROJECT_NOT_FOUND')


class ReadBackTests(CloseTestBase):
    """Decision 07: status plus each line's requested, released and outstanding."""

    def test_the_numbers_after_a_partial_release(self):
        self.leave_on_shelf(4)
        body = self.accepted()
        self.assertEqual(self.release().data['status'], Requisition.Status.PARTIAL)

        res = self.read_back()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json(), {
            'cpms_request_id': CPMS_REQUEST_ID,
            'req_number': body['req_number'],
            'status': Requisition.Status.PARTIAL,
            'decline_reason': '',
            # 4 x 280.00 released, plus the 6 still promised at today's 280.00.
            'expected_amount': '2800.00',
            'items': [{'code': self.code, 'requested': '10.00',
                       'released': '4.00', 'outstanding': '6.00',
                       'available': True, 'decline_reason': ''}],
        })

    def test_an_untouched_request_reports_everything_outstanding(self):
        self.pushed()

        body = self.read_back().json()

        self.assertEqual(body['status'], Requisition.Status.WAITING)
        self.assertIsNone(body['expected_amount'])
        self.assertEqual(body['decline_reason'], '')
        self.assertEqual(
            body['items'],
            [{'code': self.code, 'requested': '10.00', 'released': '0.00',
              'outstanding': '10.00', 'available': None, 'decline_reason': ''}])

    def test_a_closed_request_reports_the_true_outstanding_not_zero(self):
        # The status says it is closed; the quantity still says what never left the
        # store. Zeroing it would hide the shortfall the project manager just accepted.
        self.leave_on_shelf(4)
        self.accepted()
        self.assertEqual(self.release().status_code, 201)
        self.assertEqual(self.close().status_code, 200)

        body = self.read_back().json()

        self.assertEqual(body['status'], Requisition.Status.CLOSED)
        self.assertEqual(body['items'][0]['released'], '4.00')
        self.assertEqual(body['items'][0]['outstanding'], '6.00')
        self.assertEqual(body['expected_amount'], '2800.00',
                         'a close after acceptance keeps the budget formula')


class PayablesTests(CloseTestBase):
    """Decision 07: a project's utang total, paid and balance, from its ledger rows."""

    def _release_four(self):
        self.leave_on_shelf(4)
        body = self.accepted()
        self.assertEqual(self.release().status_code, 201)
        return body

    def test_payables_after_a_partial_release(self):
        self._release_four()

        res = self.payables()

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json(), {
            'cpms_project_id': CPMS_PROJECT_ID,
            'total': '1120.00',
            'paid': '0.00',
            'balance': '1120.00',
        })

    def test_a_payment_through_the_real_path_moves_paid_and_balance(self):
        self._release_four()
        ledger = self.release_ledgers().get()

        pay = self.client.post(
            PAYMENTS_URL,
            {'collectible': ledger.pk, 'amount_paid': '500', 'payment_method': 'CASH'},
            content_type='application/json', HTTP_AUTHORIZATION=self.cashier_auth)
        self.assertEqual(pay.status_code, 201, pay.content)

        body = self.payables().json()

        self.assertEqual(body['total'], '1120.00', 'a payment never changes what was owed')
        self.assertEqual(body['paid'], '500.00')
        self.assertEqual(body['balance'], '620.00')

    def test_payables_follow_balance_due_whatever_moved_it(self):
        # `paid` is total - balance, so a row that reduced the balance any other way (a
        # return credit is written by `_settle_return_money`, not by the payment
        # endpoint) is reflected the same. Written here because a release cannot be a
        # return's original (`process_return` refuses it), so no live path makes one.
        self._release_four()
        ledger = self.release_ledgers().get()
        apply_payment_to_ledger(ledger, Decimal(120))
        CollectiblePayment.objects.create(
            collectible=ledger, processed_by=self.manager,
            amount_paid=Decimal(120), payment_method='RETURN_CREDIT')

        body = self.payables().json()

        self.assertEqual(body['paid'], '120.00')
        self.assertEqual(body['balance'], '1000.00')

    def test_a_project_with_no_ledger_rows_reads_zeros(self):
        self.pushed()

        self.assertEqual(self.payables().json(), {
            'cpms_project_id': CPMS_PROJECT_ID,
            'total': '0.00', 'paid': '0.00', 'balance': '0.00'})

    def test_only_that_projects_rows_are_counted(self):
        self._release_four()
        # A counter sale carries no project (decision 03), and a second project's utang
        # must not land on this one.
        other = Project.objects.create(
            name='Warehouse', customer=self.contractor,
            cpms_project_id='CPMS-PRJ-0002')
        CollectibleLedger.objects.create(
            customer=self.contractor,
            transaction=SalesTransaction.objects.create(
                customer=self.contractor, cashier=self.cashier,
                transaction_no='TRX-OTHER-0001',
                vatable_sales=Decimal(999), grand_total=Decimal(999)),
            project=other, original_amount=Decimal(999),
            balance_due=Decimal(999), due_date='2030-01-01')

        self.assertEqual(self.payables().json()['total'], '1120.00')
        self.assertEqual(self.payables('CPMS-PRJ-0002').json()['total'], '999.00')


class CloseAccessTests(CloseTestBase):
    """All three endpoints belong to the service account, and to nobody else."""

    def test_staff_roles_are_refused_on_all_three(self):
        self.pushed()
        for role in ('Cashier', 'Stock Manager', 'Store Manager', 'Admin'):
            username = f'c_{role[:4]}'
            auth = self.login(make_user(username, role).username)
            for method, url in (
                    ('post', close_url()), ('get', request_url()),
                    ('get', payables_url())):
                with self.subTest(role=role, url=url):
                    res = getattr(self.client, method)(
                        url, content_type='application/json',
                        HTTP_AUTHORIZATION=auth)
                    self.assertEqual(res.status_code, 403, res.content)
        self.assertEqual(self.requisition().status, Requisition.Status.WAITING)

    def test_all_three_require_a_token(self):
        for method, url in (
                ('post', close_url()), ('get', request_url()),
                ('get', payables_url())):
            with self.subTest(url=url):
                res = getattr(self.client, method)(
                    url, content_type='application/json')
                self.assertEqual(res.status_code, 401, res.content)


class CloseReleaseRaceTests(TransactionTestCase):
    """A close and a cashier release of the SAME request cannot interleave.

    `TransactionTestCase` because the two worker threads must see each other's COMMITTED
    rows: a `TestCase`'s wrapping transaction would hide them and the test would then pass
    or fail on timing instead of on the row lock `close_requisition` and
    `release_materials` share.

    The shelf holds 4 of the 10 bags asked for, so a release can only ever get to
    PARTIAL - which means every legal outcome ends `CLOSED`: either the release finished
    first and the close closed the remainder, or the close won and the release was
    refused. What must never happen is a sale booked against a request CPMS already
    closed.
    """

    def setUp(self):
        self.password = get_random_string(16)
        self.cpms = self._user('cpms_service', 'CPMS Service')
        self.manager = self._user('manager1', 'Store Manager')
        self.cashier = self._user('cashier1', 'Cashier')
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal(5000))
        self.customer = Customer.objects.create(
            name='Builder Corp', customer_type=Customer.Type.CONTRACTOR)
        self.project = Project.objects.create(
            name='House Build', customer=self.customer,
            cpms_project_id=CPMS_PROJECT_ID)
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
            default_selling_price=BAG_PRICE)
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal(4),
            unit_cost=Decimal(1), received_qty=Decimal(4))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

        self.requisition = Requisition.objects.create(
            project=self.project, cpms_request_id=CPMS_REQUEST_ID,
            req_number='REQ-RACE-0001', requester_name='Rey Quester')
        self.item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal(10))
        self.token = MaterialToken.objects.create(requisition=self.requisition)
        accept_requisition(
            requisition_id=self.requisition.pk,
            items=[{'id': self.item.pk, 'available': True, 'decline_reason': ''}])

    def _user(self, username, group):
        user = User.objects.create_user(
            username=username, email=f'{username}@x.com', password=self.password,
            full_name=username)
        user.groups.add(Group.objects.get_or_create(name=group)[0])
        return user

    def _bearer(self, username):
        client = APIClient()
        login = client.post(
            LOGIN_URL, {'username': username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return f'Bearer {login.data["access"]}'

    def test_a_close_racing_a_release_never_books_a_sale_after_the_close(self):
        bearer_cpms = self._bearer(self.cpms.username)
        bearer_cashier = self._bearer(self.cashier.username)
        barrier = threading.Barrier(2, timeout=20)
        results = {}
        lock = threading.Lock()

        def worker(name, url, body, bearer):
            client = APIClient()
            try:
                barrier.wait()
                response = client.post(
                    url, body, format='json', HTTP_AUTHORIZATION=bearer)
                # `getattr` on `.data`: an unrouted close answers Django's plain
                # HttpResponseNotFound, which has no `.data` (the RED state of Task 6).
                with lock:
                    results[name] = (response.status_code, getattr(response, 'data', None))
            finally:
                # Each thread owns its own connection; leaving it open would hang the
                # truncation this TestCase does when it finishes.
                connections.close_all()

        threads = [
            threading.Thread(
                target=worker, args=('close', close_url(), {}, bearer_cpms)),
            threading.Thread(
                target=worker,
                args=('release', RELEASE_URL, {'token': str(self.token.token)},
                      bearer_cashier)),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(set(results), {'close', 'release'}, results)
        close_status, close_body = results['close']
        release_status, release_body = results['release']
        self.assertEqual(close_status, 200, close_body)

        self.token.refresh_from_db()
        self.requisition.refresh_from_db()
        self.item.refresh_from_db()
        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION)
        ledgers = CollectibleLedger.objects.filter(project=self.project)

        self.assertTrue(self.token.is_used, 'both outcomes leave the token dead')
        self.assertEqual(self.requisition.status, Requisition.Status.CLOSED)
        self.assertEqual(close_body['status'], Requisition.Status.CLOSED)
        if release_status == 201:
            # The release finished first: it took 4, the close closed the other 6.
            self.assertEqual(
                self.item.released_qty, Decimal(release_body['items'][0]['released_now']))
            self.assertEqual(close_body['items'][0]['outstanding'], '6.00')
            self.assertEqual(sales.count(), 1)
            # Decision 14: exactly one sale total was accumulated, not one per attempt.
            self.assertEqual(
                self.requisition.released_amount, sales.get().grand_total)
            self.assertEqual(self.requisition.released_amount, Decimal('1120.00'))
        else:
            # The close won: the release is refused and nothing was written.
            self.assertEqual(release_status, 400, release_body)
            self.assertEqual(self.item.released_qty, Decimal(0),
                             'a refused release must not move a line')
            self.assertEqual(close_body['items'][0]['outstanding'], '10.00')
            self.assertEqual(sales.count(), 0)
            self.assertEqual(
                self.requisition.released_amount, Decimal('0.00'),
                'a refused release must not accumulate money')
        self.assertEqual(ledgers.count(), sales.count(),
                         'utang exists exactly for what was sold')
