#!/usr/bin/env python
# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/integration/tests.py: this checker
# runs with a working directory outside the repo, so no pyrightconfig.json is found and
# every `Model.objects` access and `self.client.get(...).status_code` is a false positive
# on valid Django. Django's own `manage.py check` and the test run remain the authority.
"""CPMS boundary tests (Phase 1b, Task 4): the store's answer and the expected amount.

Decision 13: a push lands as `WAITING`, it does not arrive accepted. Read-back tells CPMS
what the store decided — the request reason, each line's `available`/`decline_reason`,
and a live `expected_amount` — while the three quantity keys keep their Phase 1 meaning
(`outstanding` stays the TRUE unreleased quantity on a false line and on a CLOSED row).

Decision 11/14: `expected_amount` is a BUDGET, not a debt. It is the known released
total plus the CURRENT selling price of what the store agreed to serve and has not
handed out yet, so a price change moves it, a payment does not, and a historical request
whose released total is unknown reads `null` for ever. Project debt stays on
`projects/{id}/payables/`.

The fixtures are the import fixture from `tests_import` plus the shelf/release helpers
from `tests_close`: every request below is pushed through the real CPMS endpoint, and
every decision is made through the real service, so no test patches a status.
"""

import json
import uuid
from decimal import Decimal

from django.db import connection
from django.test.utils import CaptureQueriesContext

from apps.inventory.models import ProductVariant, UnitOfMeasure, VariantUOM
from apps.pos.models import OfficialReceipt, SalesTransaction
from apps.requisitions.models import (
    MaterialToken,
    Requisition,
    RequisitionItem,
)
from apps.requisitions.services import accept_requisition, decline_requisition
from apps.users.models import AuditLog

from .tests_close import (
    CPMS_REQUEST_ID,
    PAYMENTS_URL,
    CloseTestBase,
)

STAFF_LIST_URL = '/api/v1/requisitions/'

CHANGE_AMOUNT_KEYS = {'cpms_request_id', 'req_number', 'status', 'decline_reason',
                      'expected_amount', 'items'}
CHANGE_AMOUNT_LINE_KEYS = {'code', 'requested', 'released', 'outstanding',
                           'available', 'decline_reason'}


class StoreReviewTestBase(CloseTestBase):
    """The import/release fixture plus the two helpers every money test needs."""

    def set_price(self, vuom, value):
        """Move a selling unit's CURRENT price (decision 13: the estimate is live)."""
        vuom.default_selling_price = Decimal(value)
        vuom.save(update_fields=['default_selling_price'])

    def make_unit(self, variant_name, code, price, conversion='1', uom_code='BAG'):
        """One more sellable unit on the fixture product, at its own price."""
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=uom_code, defaults={'name': uom_code.title()})
        variant = ProductVariant.objects.create(
            product=self.product, variant_name=variant_name, base_uom=uom)
        return VariantUOM.objects.create(
            variant=variant, uom=uom, barcode_qr=code,
            conversion_factor=Decimal(conversion),
            default_selling_price=Decimal(price),
        )

    def push_request(self, items, cpms_request_id=CPMS_REQUEST_ID, token=None):
        """Push one request through the real endpoint and return the stored copy."""
        res = self.push(
            items=items, cpms_request_id=cpms_request_id,
            token=str(token or self.token))
        self.assertEqual(res.status_code, 201, res.content)
        return res.json()

    def accept(self, body, declines=()):
        """Accept through the real service, optionally declining some line pks."""
        requisition = Requisition.objects.get(pk=body['id'])
        lines = list(requisition.items.order_by('pk'))
        accept_requisition(requisition_id=requisition.pk, items=[
            {'id': line.pk, 'available': line.pk not in declines,
             'decline_reason': 'Not stocked' if line.pk in declines else ''}
            for line in lines
        ])
        requisition.refresh_from_db()
        return requisition

    def decline(self, body, reason='Cannot supply this request'):
        decline_requisition(
            requisition_id=body['id'], decline_reason=reason)
        requisition = Requisition.objects.get(pk=body['id'])
        return requisition

    def token_of(self, body):
        return MaterialToken.objects.get(requisition_id=body['id']).token

    def read(self, cpms_request_id=CPMS_REQUEST_ID):
        res = self.read_back(cpms_request_id)
        self.assertEqual(res.status_code, 200, res.content)
        return res.json()

    def expected(self, cpms_request_id=CPMS_REQUEST_ID):
        return self.read(cpms_request_id)['expected_amount']

    def only_line(self, body):
        return Requisition.objects.get(pk=body['id']).items.get()

    def line_ids(self, body):
        return list(
            Requisition.objects.get(pk=body['id']).items.order_by('pk')
            .values_list('pk', flat=True))


class ImportWaitingTests(StoreReviewTestBase):
    """Decision 13: a push waits for the store; it does not arrive accepted."""

    def test_a_new_push_lands_waiting_with_unanswered_lines_and_no_money(self):
        res = self.push()
        self.assertEqual(res.status_code, 201, res.content)
        body = res.json()
        # Preserve the import body beyond the status: GET owns the new keys.
        self.assertEqual(
            set(body), {'id', 'req_number', 'cpms_request_id', 'status', 'items'})
        self.assertEqual(body['status'], Requisition.Status.WAITING)
        self.assertEqual(body['items'], [{'code': self.code, 'quantity': '10.00'}])

        requisition = Requisition.objects.get(pk=body['id'])
        self.assertEqual(requisition.released_amount, Decimal('0.00'))
        line = requisition.items.get()
        self.assertIsNone(line.available, 'nobody has answered this line yet')
        self.assertEqual(line.decline_reason, '')

    def test_the_line_carries_no_answer_and_no_reason(self):
        body = self.push().json()
        line = self.only_line(body)
        self.assertIsNone(line.available)
        self.assertEqual(line.decline_reason, '')
        token = MaterialToken.objects.get(requisition_id=body['id'])
        self.assertFalse(token.is_used, 'a WAITING request keeps its token unused')

    def test_a_waiting_request_cannot_be_released(self):
        body = self.push().json()
        res = self.release()
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(
            Requisition.objects.get(pk=body['id']).status,
            Requisition.Status.WAITING)


class RetryEveryStateTests(StoreReviewTestBase):
    """Decision 02: a same-id retry answers the CURRENT stored copy and writes nothing."""

    def snapshot(self, requisition):
        token = MaterialToken.objects.get(requisition=requisition)
        return {
            'status': requisition.status,
            'decline_reason': requisition.decline_reason,
            'released_amount': requisition.released_amount,
            'updated_at': requisition.updated_at,
            'lines': [
                (line.available, line.decline_reason, line.quantity,
                 line.released_qty)
                for line in requisition.items.order_by('pk')],
            'token': (token.is_used, token.used_at, token.used_by_id),
            'import_row': (
                MaterialToken.objects.count(),
                RequisitionItem.objects.count(),
                SalesTransaction.objects.count(),
                OfficialReceipt.objects.count(),
                AuditLog.objects.count()),
        }

    def retry(self, cpms_request_id, token):
        return self.push(
            cpms_request_id=cpms_request_id, token=str(token),
            items=[{'code': self.code, 'quantity': '999'}])

    def assert_retry_is_a_read_only_echo(
            self, cpms_request_id, token, status, quantity):
        requisition = Requisition.objects.get(cpms_request_id=cpms_request_id)
        self.assertEqual(requisition.status, status)
        before = self.snapshot(requisition)
        res = self.retry(cpms_request_id, token)
        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], status)
        self.assertEqual(res.json()['cpms_request_id'], cpms_request_id)
        self.assertEqual(res.json()['id'], requisition.pk)
        self.assertEqual(
            [row['quantity'] for row in res.json()['items']], [quantity],
            'the retry must echo the stored lines, not the payload it carried')
        self.assertEqual(self.snapshot(requisition), before,
                         'a retry mutated something')

    def test_a_retry_of_every_state_echoes_that_state(self):
        waiting = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-WAIT',
            token=uuid.uuid4())
        accepted = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-ACC',
            token=uuid.uuid4())
        self.accept(accepted)
        declined = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-DEC',
            token=uuid.uuid4())
        self.decline(declined)
        closed = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-CLO',
            token=uuid.uuid4())
        self.assertEqual(self.close(cpms_request_id='CPMS-REQ-CLO').status_code, 200)
        released = self.push_request(
            [{'code': self.code, 'quantity': '2'}], 'CPMS-REQ-REL',
            token=uuid.uuid4())
        self.accept(released)
        self.assertEqual(
            self.release(token=self.token_of(released)).status_code, 201)
        self.leave_on_shelf(4)
        partial = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-PAR',
            token=uuid.uuid4())
        self.accept(partial)
        self.assertEqual(
            self.release(token=self.token_of(partial)).status_code, 201)

        for body, cpms_id, status, quantity in (
                (waiting, 'CPMS-REQ-WAIT', Requisition.Status.WAITING, '10.00'),
                (accepted, 'CPMS-REQ-ACC', Requisition.Status.ACCEPTED, '10.00'),
                (declined, 'CPMS-REQ-DEC', Requisition.Status.DECLINED, '10.00'),
                (closed, 'CPMS-REQ-CLO', Requisition.Status.CLOSED, '10.00'),
                (released, 'CPMS-REQ-REL', Requisition.Status.RELEASED, '2.00'),
                (partial, 'CPMS-REQ-PAR', Requisition.Status.PARTIAL, '10.00')):
            with self.subTest(status=status):
                self.assert_retry_is_a_read_only_echo(
                    cpms_id, self.token_of(body), status, quantity)

    def test_retrying_a_declined_push_writes_no_audit_sale_or_token_change(self):
        body = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-DEC')
        self.decline(body)
        requisition = Requisition.objects.get(pk=body['id'])
        token = MaterialToken.objects.get(requisition=requisition)
        before = (AuditLog.objects.count(), SalesTransaction.objects.count(),
                  OfficialReceipt.objects.count(), token.is_used, token.used_at)

        res = self.retry('CPMS-REQ-DEC', token.token)

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.DECLINED)
        token.refresh_from_db()
        self.assertEqual(
            (AuditLog.objects.count(), SalesTransaction.objects.count(),
             OfficialReceipt.objects.count(), token.is_used, token.used_at),
            before)

    def test_retrying_a_closed_push_writes_no_audit_sale_or_token_change(self):
        body = self.push_request(
            [{'code': self.code, 'quantity': '10'}], 'CPMS-REQ-CLO')
        self.assertEqual(self.close(cpms_request_id='CPMS-REQ-CLO').status_code, 200)
        requisition = Requisition.objects.get(pk=body['id'])
        token = MaterialToken.objects.get(requisition=requisition)
        before = (AuditLog.objects.count(), SalesTransaction.objects.count(),
                  OfficialReceipt.objects.count(), token.is_used, token.used_at)

        res = self.retry('CPMS-REQ-CLO', token.token)

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['status'], Requisition.Status.CLOSED)
        token.refresh_from_db()
        self.assertEqual(
            (AuditLog.objects.count(), SalesTransaction.objects.count(),
             OfficialReceipt.objects.count(), token.is_used, token.used_at),
            before)


class ReadBackContractTests(StoreReviewTestBase):
    """Decision 13: read-back carries the decisions, and the quantities stay truthful."""

    def test_the_keys_are_exactly_the_contract(self):
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)

        read = self.read()

        self.assertEqual(set(read), CHANGE_AMOUNT_KEYS)
        self.assertEqual(set(read['items'][0]), CHANGE_AMOUNT_LINE_KEYS)
        wire = json.dumps(read)
        for leaked in ('token', 'released_amount', 'unit_price',
                       'default_selling_price', 'stock', 'cost', 'margin'):
            with self.subTest(key=leaked):
                self.assertNotIn(f'"{leaked}"', wire)

    def test_a_waiting_request_reads_no_answer_and_no_amount(self):
        self.push_request([{'code': self.code, 'quantity': '10'}])

        read = self.read()

        self.assertEqual(read['status'], Requisition.Status.WAITING)
        self.assertEqual(read['decline_reason'], '')
        self.assertIsNone(read['expected_amount'])
        self.assertIsNone(read['items'][0]['available'])
        self.assertEqual(read['items'][0]['decline_reason'], '')
        self.assertEqual(read['items'][0]['outstanding'], '10.00')

    def test_a_declined_request_reads_its_reason_and_a_null_amount(self):
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.decline(body, reason='Cannot supply this request')

        read = self.read()

        self.assertEqual(read['status'], Requisition.Status.DECLINED)
        self.assertEqual(read['decline_reason'], 'Cannot supply this request')
        self.assertIsNone(read['expected_amount'])
        line = read['items'][0]
        self.assertFalse(line['available'])
        self.assertEqual(line['decline_reason'], 'Cannot supply this request')
        # The numbers keep their historical meaning on a declined line.
        self.assertEqual(
            (line['requested'], line['released'], line['outstanding']),
            ('10.00', '0.00', '10.00'))

    def test_a_mixed_accept_reads_each_answer_and_it_survives_a_close(self):
        other = self.make_unit('16mm', 'QB-STORE-2', '5.00', uom_code='PC')
        body = self.push_request([
            {'code': self.code, 'quantity': '10'},
            {'code': other.barcode_qr, 'quantity': '2'},
        ])
        requisition = self.accept(body, declines=[self.line_ids(body)[1]])

        read = self.read()
        lines = read['items']
        self.assertEqual([line['available'] for line in lines], [True, False])
        self.assertEqual(lines[1]['decline_reason'], 'Not stocked')
        self.assertEqual(lines[1]['outstanding'], '2.00',
                         'a declined line keeps its true outstanding quantity')
        self.assertEqual(read['expected_amount'], '2800.00',
                         'a declined line is never budgeted')

        self.assertEqual(self.close().status_code, 200)
        closed = self.read()
        self.assertEqual(closed['status'], Requisition.Status.CLOSED)
        self.assertEqual([line['available'] for line in closed['items']],
                         [True, False])
        self.assertEqual(closed['items'][1]['outstanding'], '2.00')
        self.assertEqual(
            Requisition.objects.get(pk=body['id']).status,
            Requisition.Status.CLOSED)


class ExpectedAmountNullStateTests(StoreReviewTestBase):
    """Decision 13/14: no answer and no known baseline both read `null`, never 0.00."""

    def test_closing_a_request_nobody_answered_leaves_the_amount_null(self):
        self.push_request([{'code': self.code, 'quantity': '10'}])

        self.assertEqual(self.close().status_code, 200)

        read = self.read()
        self.assertEqual(read['status'], Requisition.Status.CLOSED)
        self.assertIsNone(read['expected_amount'])
        self.assertIsNone(read['items'][0]['available'])

    def test_closing_an_accepted_request_keeps_the_budget_formula(self):
        self.set_price(self.vuom, '10.00')
        self.leave_on_shelf(4)
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        self.assertEqual(self.release().status_code, 201)
        self.set_price(self.vuom, '12.00')
        self.assertEqual(self.expected(), '112.00')

        self.assertEqual(self.close().status_code, 200)

        read = self.read()
        self.assertEqual(read['status'], Requisition.Status.CLOSED)
        # Decision 13: the abandoned accepted shortfall stays in the BUDGET, while the
        # debt (`payables`) is only what actually left the store.
        self.assertEqual(read['expected_amount'], '112.00')
        self.assertEqual(self.payables().json()['balance'], '40.00')

    def test_legacy_statuses_read_null(self):
        self.push_request([{'code': self.code, 'quantity': '10'}])
        project = Requisition.objects.get(cpms_request_id=CPMS_REQUEST_ID).project
        for index, status in enumerate((
                Requisition.Status.DRAFT, Requisition.Status.SUBMITTED,
                Requisition.Status.REJECTED, Requisition.Status.CANCELLED)):
            with self.subTest(status=status):
                requisition = Requisition.objects.create(
                    project=project, cpms_request_id=f'CPMS-LEGACY-{index}',
                    req_number=f'REQ-LEGACY-{index}', status=status)
                RequisitionItem.objects.create(
                    requisition=requisition, variant_uom=self.vuom,
                    quantity=Decimal('1'), available=None)
                MaterialToken.objects.create(requisition=requisition)

                read = self.read(f'CPMS-LEGACY-{index}')
                self.assertEqual(read['status'], status)
                self.assertIsNone(read['expected_amount'])
                self.assertIsNone(read['items'][0]['available'])


class ExpectedAmountMoneyTests(StoreReviewTestBase):
    """Decision 11/13/14: the amount is a live budget in Decimal, not the project's debt."""

    def test_a_price_change_moves_the_estimate_but_not_the_debt(self):
        self.set_price(self.vuom, '10.00')
        self.leave_on_shelf(4)
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        self.assertEqual(self.release().status_code, 201)

        # 4 x 10.00 already out, plus the 6 still promised at today's 10.00.
        self.assertEqual(self.expected(), '100.00')
        requisition = Requisition.objects.get(pk=body['id'])
        self.assertEqual(requisition.released_amount, Decimal('40.00'))
        payables = self.payables().json()
        self.assertEqual((payables['total'], payables['balance']),
                         ('40.00', '40.00'))

        self.set_price(self.vuom, '12.00')

        # 4 x 10.00 already left; 6 x 12.00 is what the store still promised.
        self.assertEqual(self.expected(), '112.00')
        requisition.refresh_from_db()
        self.assertEqual(requisition.released_amount, Decimal('40.00'),
                         'a price change never reprices what already left')
        payables = self.payables().json()
        self.assertEqual((payables['total'], payables['balance']),
                         ('40.00', '40.00'),
                         'a price change books no money')

    def test_another_request_on_the_same_project_is_not_counted(self):
        self.set_price(self.vuom, '10.00')
        self.leave_on_shelf(4)
        first = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(first)
        self.assertEqual(self.release().status_code, 201)
        self.set_price(self.vuom, '12.00')
        second = self.push_request(
            [{'code': self.code, 'quantity': '2'}], 'CPMS-REQ-0002',
            token=uuid.uuid4())
        self.accept(second)

        self.assertEqual(self.expected('CPMS-REQ-0001'), '112.00')
        self.assertEqual(self.expected('CPMS-REQ-0002'), '24.00')

    def test_a_payment_reduces_the_debt_and_never_the_budget(self):
        self.set_price(self.vuom, '10.00')
        self.leave_on_shelf(4)
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        self.assertEqual(self.release().status_code, 201)
        self.set_price(self.vuom, '12.00')
        ledger = self.release_ledgers().get()

        pay = self.client.post(
            PAYMENTS_URL,
            {'collectible': ledger.pk, 'amount_paid': '40',
             'payment_method': 'CASH'},
            content_type='application/json', HTTP_AUTHORIZATION=self.cashier_auth)
        self.assertEqual(pay.status_code, 201, pay.content)

        payables = self.payables().json()
        self.assertEqual(
            (payables['total'], payables['paid'], payables['balance']),
            ('40.00', '40.00', '0.00'))
        self.assertEqual(self.expected(), '112.00',
                         'paying a debt does not shrink the budget')

    def test_a_declined_line_is_never_budgeted(self):
        other = self.make_unit('16mm', 'QB-STORE-2', '5.00', uom_code='PC')
        body = self.push_request([
            {'code': self.code, 'quantity': '10'},
            {'code': other.barcode_qr, 'quantity': '2'},
        ])
        self.accept(body, declines=[self.line_ids(body)[1]])

        self.assertEqual(self.expected(), '2800.00',
                         '10 x 280.00 only; the declined line adds nothing')

    def test_rounding_happens_once_after_summing_the_outstanding_lines(self):
        first = self.make_unit('Small A', 'QB-STORE-3', '0.05')
        second = self.make_unit('Small B', 'QB-STORE-4', '0.05')
        body = self.push_request([
            {'code': first.barcode_qr, 'quantity': '0.05'},
            {'code': second.barcode_qr, 'quantity': '0.05'},
        ])
        self.accept(body)

        # 0.0025 + 0.0025 = 0.005 -> 0.01. Rounding each line first would give 0.00.
        self.assertEqual(self.expected(), '0.01')

    def test_the_price_is_per_selling_unit_not_per_base_unit(self):
        box = self.make_unit(
            'Boxed', 'QB-STORE-5', '10.00', conversion='12', uom_code='BOX')
        body = self.push_request(
            [{'code': box.barcode_qr, 'quantity': '2'}])
        self.accept(body)

        self.assertEqual(self.expected(), '20.00',
                         'the line counts 2 boxes, not 2 x 12 pieces')

    def test_an_unknown_historical_total_stays_null_after_a_future_release(self):
        self.set_price(self.vuom, '10.00')
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        # What migration 0003 leaves for a request released before Phase 1b.
        Requisition.objects.filter(pk=body['id']).update(released_amount=None)
        self.assertIsNone(self.expected())

        self.leave_on_shelf(4)
        self.assertEqual(self.release().status_code, 201)
        requisition = Requisition.objects.get(pk=body['id'])
        self.assertEqual(requisition.status, Requisition.Status.PARTIAL)
        self.assertIsNone(requisition.released_amount,
                          'an unknown total is never guessed')
        self.assertIsNone(self.expected())
        self.assertEqual(self.payables().json()['balance'], '40.00')

        self.receive(Decimal('10'))
        self.assertEqual(self.release().status_code, 201)
        requisition.refresh_from_db()
        self.assertEqual(requisition.status, Requisition.Status.RELEASED)
        self.assertIsNone(requisition.released_amount)
        self.assertIsNone(self.expected())

    def test_repeated_fractional_releases_equal_the_reloaded_sale_totals(self):
        kg = self.make_unit(
            'Loose', 'QB-STORE-6', '3.33', conversion='1', uom_code='KG')
        body = self.push_request(
            [{'code': kg.barcode_qr, 'quantity': '1.00'}])
        self.accept(body)
        self.receive(Decimal('10'), variant=kg.variant)
        self.leave_on_shelf(Decimal('0.4'), variant=kg.variant)

        self.assertEqual(self.release().status_code, 201)
        self.receive(Decimal('1'), variant=kg.variant)
        self.assertEqual(self.release().status_code, 201)

        requisition = Requisition.objects.get(pk=body['id'])
        sales = SalesTransaction.objects.filter(
            source=SalesTransaction.Source.REQUISITION)
        self.assertEqual(requisition.status, Requisition.Status.RELEASED)
        self.assertEqual(sales.count(), 2)
        self.assertEqual(
            requisition.released_amount,
            sum((sale.grand_total for sale in sales), Decimal('0.00')),
            'the accumulator must equal the persisted sale totals, not 4dp math')
        self.assertEqual(
            requisition.released_amount, Decimal('3.33'))
        self.assertEqual(self.expected(), '3.33')


class StaffExpectedAmountTests(StoreReviewTestBase):
    """The review queue reads the SAME live amount CPMS reads, in the same shape."""

    def staff_get(self, url):
        return self.client.get(
            url, HTTP_AUTHORIZATION=self.login(self.manager.username))

    def test_staff_detail_and_list_match_the_cpms_read_back(self):
        self.set_price(self.vuom, '10.00')
        self.leave_on_shelf(4)
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        self.assertEqual(self.release().status_code, 201)
        self.set_price(self.vuom, '12.00')

        detail = self.staff_get(f'{STAFF_LIST_URL}{body["id"]}/')
        listing = self.staff_get(f'{STAFF_LIST_URL}?status=PARTIAL')

        self.assertEqual(detail.status_code, 200, detail.content)
        self.assertEqual(listing.status_code, 200, listing.content)
        self.assertEqual(detail.json()['expected_amount'], self.expected())
        self.assertEqual(listing.json()['results'][0]['expected_amount'],
                         self.expected())
        self.assertEqual(self.expected(), '112.00')
        self.assertNotIn('released_amount', detail.json())
        for leaked in ('unit_price', 'default_selling_price', 'stock'):
            self.assertNotIn(leaked, detail.json()['items'][0])

    def test_the_accept_action_answers_the_same_amount_cpms_reads(self):
        self.set_price(self.vuom, '10.00')
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        line_id = self.line_ids(body)[0]

        res = self.client.post(
            f'{STAFF_LIST_URL}{body["id"]}/accept/',
            {'items': [{'id': line_id, 'available': True, 'decline_reason': ''}]},
            content_type='application/json',
            HTTP_AUTHORIZATION=self.login(self.manager.username))

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(res.json()['expected_amount'], '100.00')
        self.assertEqual(self.expected(), res.json()['expected_amount'])


class StaffQueryBudgetTests(StoreReviewTestBase):
    """The new figure reads the prefetched lines: more rows must not mean more queries."""

    def test_a_bigger_queue_costs_the_same_queries(self):
        self.set_price(self.vuom, '10.00')
        for index in range(2):
            body = self.push_request(
                [{'code': self.code, 'quantity': '10'}], f'CPMS-REQ-Q{index}',
                token=uuid.uuid4())
            self.accept(body)

        staff = self.login(self.manager.username)
        with CaptureQueriesContext(connection) as first:
            self.client.get(STAFF_LIST_URL, HTTP_AUTHORIZATION=staff)
        for index in range(2, 4):
            body = self.push_request(
                [{'code': self.code, 'quantity': '10'}], f'CPMS-REQ-Q{index}',
                token=uuid.uuid4())
            self.accept(body)
        with CaptureQueriesContext(connection) as second:
            res = self.client.get(STAFF_LIST_URL, HTTP_AUTHORIZATION=staff)

        def line_queries(context):
            return [
                query for query in context.captured_queries
                if 'FROM "requisitions_item"' in query['sql']]

        self.assertEqual(res.status_code, 200, res.content)
        self.assertEqual(len(res.json()['results']), 4)
        self.assertEqual(
            len(line_queries(second)), len(line_queries(first)),
            'the expected amount read the lines once per page, not once per row')


class ReadBackSideEffectTests(StoreReviewTestBase):
    """Decision 07: reading is free — no audit, sale, receipt or token write."""

    def test_two_reads_answer_the_same_body_and_write_nothing(self):
        self.set_price(self.vuom, '10.00')
        body = self.push_request([{'code': self.code, 'quantity': '10'}])
        self.accept(body)
        requisition = Requisition.objects.get(pk=body['id'])
        token = MaterialToken.objects.get(requisition=requisition)
        before = (AuditLog.objects.count(), SalesTransaction.objects.count(),
                  OfficialReceipt.objects.count(), token.is_used, token.used_at,
                  requisition.updated_at, requisition.released_amount)

        first = self.read()
        second = self.read()

        self.assertEqual(first, second)
        requisition.refresh_from_db()
        token.refresh_from_db()
        self.assertEqual(
            (AuditLog.objects.count(), SalesTransaction.objects.count(),
             OfficialReceipt.objects.count(), token.is_used, token.used_at,
             requisition.updated_at, requisition.released_amount),
            before)
