# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests.py: the checker resolves its config from
# its WORKING DIRECTORY, so every `Model.objects` access and every
# `self.client.post(..., **self.auth)` is a false positive on valid Django. The test run
# is the authority.
"""Phase 1 task 3 — collision-safe numbering and idempotent checkout.

Decision 09 items 2-3, and the ledger ruling that narrowed item 2 to checkout only:
idempotency covers `POST /transactions/` and `POST /held-carts/{id}/complete/` in this
phase.

Two separate money problems live here:

* **Numbering.** `generate_transaction_no` / `generate_or_number` read the newest
  document and added one. Two tills ringing at the same instant both read `-0007` and
  both write `-0008`; the loser dies on `transaction_no`'s unique constraint as a 500,
  which is a LOST SALE, not a slow one. The sequence now lives in a `DocumentCounter`
  row locked with `select_for_update` inside the sale's own atomic block.
* **Idempotency.** A client that retries a timed-out checkout must not ring the sale
  twice. Same `Idempotency-Key` + same body replays the original transaction (HTTP 200,
  no new writes); the same key with a DIFFERENT body is a 409, because that is a client
  bug that would otherwise silently sell the second cart under the first one's receipt.

The replay is checked BEFORE `get_object()` on the held-cart endpoint: the first
successful completion DELETES the cart, so a retry would otherwise 404 on a cart whose
sale already rang.
"""

import hashlib
import json
from datetime import date
from decimal import Decimal
from unittest import mock

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group

from apps.pos.models import (
    DocumentCounter,
    HeldCart,
    OfficialReceipt,
    Payment,
    SalesTransaction,
    Shift,
)
from apps.pos.services import generate_transaction_no, replayed_transaction
from apps.pos.tests import LOGIN_URL, TRANSACTIONS_URL, POSTestBase

User = get_user_model()

HELD_CARTS_URL = '/api/v1/held-carts/'
IDEMPOTENCY_HEADER = 'Idempotency-Key'

TODAY_STAMP = date.today().strftime('%Y%m%d')


class IdempotencyBase(POSTestBase):
    """POSTestBase (CF=1, price 10, stock 5@40 + 5@60) plus an authenticated cashier."""

    def setUp(self):
        super().setUp()
        # Roles are Django Groups, not a user field - without this every call here would
        # be a 403 about RBAC instead of an assertion about checkout.
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        self.auth = self._login('cashier1', 'pass12345')

    # -- fixture helpers ---------------------------------------------------
    def _login(self, username, password):
        login = self.client.post(
            LOGIN_URL, {'username': username, 'password': password},
            content_type='application/json')
        self.assertEqual(login.status_code, 200, login.content)
        return {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _second_cashier_auth(self):
        """Another till: its own user, Cashier role and open shift."""
        other = User.objects.create_user(
            # nosemgrep: the hardcoded-password rule fires on a test fixture. This
            # password exists only in the throwaway test database and is posted straight
            # back to the login endpoint below - same fixture as POSTestBase.
            username='cashier2', email='c2@x.com', password='pass12345',
            full_name='Second Cashier')
        other.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        Shift.objects.create(cashier=other, opening_float=Decimal('5000'))
        return self._login('cashier2', 'pass12345')

    def _payload(self, qty='2', tendered='20.00'):
        return {
            'customer': self.customer.id,
            'source': 'WALK_IN',
            'items': [{'variant_id': self.vuom.id, 'qty': qty}],
            'payments': [{'method': 'CASH', 'amount_tendered': tendered}],
        }

    def _post(self, payload, *, key=None, auth=None):
        extra = dict(auth or self.auth)
        if key is not None:
            extra['HTTP_IDEMPOTENCY_KEY'] = key
        return self.client.post(
            TRANSACTIONS_URL, data=payload, content_type='application/json',
            **extra)  # pyright: ignore[reportArgumentType]

    def _total_stock(self):
        return sum(self.variant.batches.values_list('current_qty', flat=True),
                   Decimal('0'))


class IdempotentCheckoutTests(IdempotencyBase):
    """A retried checkout rings ONE sale, not two."""

    def test_the_same_key_twice_rings_one_sale_and_replays_it(self):
        key = 'checkout-0001'

        first = self._post(self._payload(), key=key)
        second = self._post(self._payload(), key=key)

        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 200,
                         f'a replay is not a creation: {second.content!r}')
        self.assertEqual(second.json()['id'], first.json()['id'],
                         'the retry must return the ORIGINAL transaction')
        self.assertEqual(SalesTransaction.objects.count(), 1,
                         'one key, one sale - this is the whole point')
        self.assertEqual(OfficialReceipt.objects.count(), 1)
        self.assertEqual(Payment.objects.count(), 1)
        self.assertEqual(self._total_stock(), Decimal('8'),
                         'a replayed checkout must not deduct stock twice')

    def test_the_same_key_with_a_different_body_is_a_409(self):
        key = 'checkout-0002'
        self._post(self._payload(qty='2'), key=key)

        response = self._post(self._payload(qty='3'), key=key)

        self.assertEqual(response.status_code, 409, response.content)
        body = response.json()
        self.assertEqual(body.get('code'), 'IDEMPOTENCY_KEY_REUSED', body)
        self.assertIn('detail', body)
        self.assertEqual(SalesTransaction.objects.count(), 1,
                         'the second cart must not be rung under the first receipt')
        self.assertEqual(self._total_stock(), Decimal('8'))

    def test_two_cashiers_may_use_the_same_key(self):
        # The key is scoped per cashier: two tills in the same shop can both start a
        # fresh attempt numbered "1" without colliding with each other.
        key = 'shared-attempt-1'
        first = self._post(self._payload(), key=key)
        second = self._post(self._payload(), key=key,
                            auth=self._second_cashier_auth())

        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 201, second.content)
        self.assertNotEqual(first.json()['id'], second.json()['id'])
        self.assertEqual(SalesTransaction.objects.count(), 2)

    def test_without_a_key_each_post_rings_its_own_sale(self):
        # Unchanged behaviour for clients that send no header.
        first = self._post(self._payload())
        second = self._post(self._payload())

        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 201, second.content)
        self.assertNotEqual(first.json()['id'], second.json()['id'])
        self.assertEqual(SalesTransaction.objects.count(), 2)

    def test_a_key_longer_than_64_characters_is_a_400(self):
        response = self._post(self._payload(), key='k' * 65)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json().get('code'), 'INVALID_IDEMPOTENCY_KEY',
                         response.json())
        self.assertFalse(SalesTransaction.objects.exists(),
                         'a bad key refuses the sale, it does not ring it')

    def test_an_empty_key_is_a_400(self):
        # An empty header is a client bug that would otherwise make every retry of every
        # sale look like the same request.
        response = self._post(self._payload(), key='')

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json().get('code'), 'INVALID_IDEMPOTENCY_KEY',
                         response.json())
        self.assertFalse(SalesTransaction.objects.exists())

    def test_a_racing_duplicate_key_replays_instead_of_500ing(self):
        # The pre-check can lose the race: both requests read "no such key", both insert,
        # and only the unique constraint can refuse the second. The view must catch that
        # IntegrityError, re-read, and answer 200 - never a 500.
        key = 'checkout-race'
        first = self._post(self._payload(), key=key)
        self.assertEqual(first.status_code, 201, first.content)

        calls = []

        def check_that_misses_the_first_time(**kwargs):
            """Simulate the race: the pre-check sees nothing, the retry sees the row."""
            calls.append(kwargs)
            if len(calls) == 1:
                return None
            return replayed_transaction(**kwargs)

        with mock.patch('apps.pos.views.replayed_transaction',
                        side_effect=check_that_misses_the_first_time):
            second = self._post(self._payload(), key=key)

        self.assertEqual(len(calls), 2,
                         'the view must re-read after the IntegrityError')
        self.assertEqual(second.status_code, 200, second.content)
        self.assertEqual(second.json()['id'], first.json()['id'])
        self.assertEqual(SalesTransaction.objects.count(), 1)


class HeldCartIdempotencyTests(IdempotencyBase):
    """Completing a held cart twice replays the sale; the cart is already deleted."""

    def _hold(self):
        hold = self.client.post(
            HELD_CARTS_URL,
            {'notes': 'retry me', 'customer': self.customer.id,
             'items': [{'variant_uom': self.vuom.id, 'qty': '2',
                        'unit_price': '10.00'}]},
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]
        self.assertEqual(hold.status_code, 201, hold.content)
        return hold.json()['id']

    def _complete(self, cart_id, *, key=None, tendered='20.00'):
        extra = dict(self.auth)
        if key is not None:
            extra['HTTP_IDEMPOTENCY_KEY'] = key
        return self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': tendered}]},
            content_type='application/json',
            **extra)  # pyright: ignore[reportArgumentType]

    def test_completing_the_same_cart_twice_returns_the_original_sale(self):
        cart_id = self._hold()
        key = 'held-0001'

        first = self._complete(cart_id, key=key)
        second = self._complete(cart_id, key=key)

        self.assertEqual(first.status_code, 201, first.content)
        self.assertEqual(second.status_code, 200,
                         f'the cart is gone after the first success, but the SALE is '
                         f'not: {second.content!r}')
        self.assertEqual(second.json()['id'], first.json()['id'])
        self.assertEqual(SalesTransaction.objects.count(), 1)
        self.assertEqual(self._total_stock(), Decimal('8'))
        self.assertFalse(HeldCart.objects.filter(id=cart_id).exists())

    def test_a_reused_key_with_a_different_body_is_a_409_not_a_404(self):
        cart_id = self._hold()
        key = 'held-0002'
        self._complete(cart_id, key=key, tendered='20.00')

        response = self._complete(cart_id, key=key, tendered='50.00')

        self.assertEqual(response.status_code, 409, response.content)
        self.assertEqual(response.json().get('code'), 'IDEMPOTENCY_KEY_REUSED',
                         response.json())
        self.assertEqual(SalesTransaction.objects.count(), 1)


class DocumentNumberingTests(IdempotencyBase):
    """Decision 09 item 3: the sequence is a locked counter row, not read-latest+1."""

    def test_the_first_sale_of_the_day_seeds_from_the_existing_maximum(self):
        # A row written before this counter existed (live data, or a restore) must not be
        # handed out again: the first `get_or_create` seeds `last` from the real maximum.
        SalesTransaction.objects.create(
            customer=self.customer, cashier=self.cashier,
            transaction_no=f'TRX-{TODAY_STAMP}-0007',
            vatable_sales=Decimal('0'), grand_total=Decimal('0'))

        response = self._post(self._payload())

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()['transaction_no'], f'TRX-{TODAY_STAMP}-0008',
                         'a legacy -0007 must be stepped over, not reused')
        counter = DocumentCounter.objects.get(prefix='TRX', day=date.today())
        self.assertEqual(counter.last, 8)

    def test_two_sequential_sales_get_consecutive_numbers(self):
        first = self._post(self._payload())
        second = self._post(self._payload())

        self.assertEqual(first.json()['transaction_no'], f'TRX-{TODAY_STAMP}-0001')
        self.assertEqual(second.json()['transaction_no'], f'TRX-{TODAY_STAMP}-0002')
        # The receipt sequence is a counter too, and it must not repeat either.
        self.assertEqual(
            list(OfficialReceipt.objects.order_by('id').values_list('or_number', flat=True)),
            [f'OR-{TODAY_STAMP}-0001', f'OR-{TODAY_STAMP}-0002'])

    def test_generate_transaction_no_is_safe_outside_an_atomic_block(self):
        # `apps/requisitions` and the return path call it inside their own atomic block;
        # this asserts the "no outer block" case still works and still advances.
        first = generate_transaction_no()
        second = generate_transaction_no()

        self.assertEqual(first, f'TRX-{TODAY_STAMP}-0001')
        self.assertEqual(second, f'TRX-{TODAY_STAMP}-0002')


class RequestHashTests(IdempotencyBase):
    """The stored hash is what makes "same request" a server decision, not a guess."""

    def test_the_hash_is_recorded_with_the_transaction(self):
        payload = self._payload()
        response = self._post(payload, key='hashed-0001')

        self.assertEqual(response.status_code, 201, response.content)
        txn = SalesTransaction.objects.get(pk=response.json()['id'])
        self.assertEqual(txn.idempotency_key, 'hashed-0001')
        expected = hashlib.sha256(
            json.dumps(payload, sort_keys=True, default=str).encode('utf-8')
        ).hexdigest()
        self.assertEqual(txn.request_hash, expected,
                         'the hash must be the canonical JSON of the body')

    def test_a_key_is_not_stored_when_the_client_sends_none(self):
        response = self._post(self._payload())

        txn = SalesTransaction.objects.get(pk=response.json()['id'])
        self.assertIsNone(txn.idempotency_key)
        self.assertEqual(txn.request_hash, '')
