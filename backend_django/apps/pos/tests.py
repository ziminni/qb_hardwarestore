#!/usr/bin/env python
# pyright: reportAttributeAccessIssue=false
#
# The same directive, with the same reason, as apps/inventory/views.py and seed_demo.py:
# this checker is run by a client whose working directory is outside the repo, so it
# resolves no config and cannot be silenced by pyrightconfig.json, and every
# `Model.objects` access and `self.client.post(...).status_code` is a false positive on
# valid Django. Django's own `manage.py check` and the test run remain the authority.

"""POS app tests — process_sale, FIFO deduction, receipts, underpayment."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand, Category, GoodsReceipt, POItem, Product, ProductVariant, PurchaseOrder,
    Supplier, UnitOfMeasure, VariantUOM,
)
from apps.inventory.services import process_goods_receipt

from .models import Customer, OfficialReceipt, Payment, SalesTransaction
from .services import process_sale
# Absolute, not relative: the project imports apps.<app> absolutely everywhere else
# (see the imports above), and a relative import is what this checker cannot resolve
# from a working directory outside the repo. Same module either way.
from apps.pos.exceptions import WalkInCannotOwe

User = get_user_model()


class POSTestBase(TestCase):
    def setUp(self):
        self.cashier = User.objects.create_user(
            # nosemgrep: the hardcoded-password rule fires on a test fixture. This
            # password authenticates nothing: it exists only in the throwaway test
            # database and is posted straight back to the login endpoint below.
            # It appears nowhere in the app, and it is the established fixture in all
            # five test modules. Indirection would only make the login unreadable.
            username='cashier1', email='c@x.com', password='pass12345',
            full_name='Cashy Ir',
        )
        self.customer = Customer.objects.create(name='Juan Dela Cruz')
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        self.vuom = VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        # Two stock batches: 5 @ 40 (oldest) + 5 @ 60
        supplier = Supplier.objects.create(company_name='Acme')
        for cost, qty in (('40.00', '5'), ('60.00', '5')):
            po = PurchaseOrder.objects.create(
                supplier=supplier, created_by=self.cashier)
            POItem.objects.create(
                po=po, variant=self.variant, ordered_qty=Decimal(qty),
                unit_cost=Decimal(cost), received_qty=Decimal(qty))
            receipt = GoodsReceipt.objects.create(po=po, received_by=self.cashier)
            process_goods_receipt(receipt=receipt, user=self.cashier)


class ProcessSaleTests(POSTestBase):
    def test_sale_deducts_stock_fifo_and_creates_receipt(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 7,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('70')}],
        )
        self.assertEqual(txn.grand_total, Decimal('70'))
        self.assertEqual(txn.items.count(), 1)
        self.assertTrue(Payment.objects.filter(transaction=txn).exists())
        self.assertTrue(OfficialReceipt.objects.filter(transaction=txn).exists())
        # FIFO: oldest 5 gone, 3 remain of newest
        qtys = sorted(self.variant.batches.values_list(
            'current_qty', flat=True))
        self.assertEqual(qtys, [Decimal('0'), Decimal('3')])

    def test_underpaid_walk_in_sale_is_refused(self):
        # Decision 14: a walk-in is NOT a customer record, so a balance on the shared
        # Walk-in account is money owed by nobody - the live database already carries
        # 4,900.00 booked exactly that way, and the aging report calls it overdue.
        #
        # This test REPLACES `test_underpaid_walk_in_posts_to_collectibles`, which pinned
        # the opposite behaviour. That test passed for as long as nothing ever consulted
        # the customer's type, which is the point: the rule has teeth only when the SERVER
        # enforces it, since a client-side check is advisory and this one is about money.
        with self.assertRaises(WalkInCannotOwe) as caught:
            process_sale(
                customer_id=self.customer.id,  # the fixture is WALK_IN by default
                cashier=self.cashier,
                items_data=[{'variant_id': self.vuom.id, 'qty': 10,
                             'unit_price': Decimal('10')}],
                payments_data=[{'method': 'CASH',
                                'amount_tendered': Decimal('60')}],  # 40 short
            )
        self.assertEqual(caught.exception.code, 'WALK_IN_CANNOT_OWE')
        self.assertEqual(caught.exception.shortfall, Decimal('40'))

    def test_a_refused_walk_in_sale_leaves_nothing_behind(self):
        # The refusal must roll back WHOLESALE, exactly like a short-stock rejection: no
        # transaction, no ledger, and the stock untouched. A half-written sale would be
        # worse than accepting it, because the utang is the thing we are refusing.
        with self.assertRaises(WalkInCannotOwe):
            process_sale(
                customer_id=self.customer.id,
                cashier=self.cashier,
                items_data=[{'variant_id': self.vuom.id, 'qty': 10,
                             'unit_price': Decimal('10')}],
                payments_data=[{'method': 'CASH',
                                'amount_tendered': Decimal('60')}],
            )
        self.assertFalse(SalesTransaction.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        self.assertEqual(
            sorted(self.variant.batches.values_list('current_qty', flat=True)),
            [Decimal('5'), Decimal('5')])

    def test_an_underpaid_named_customer_still_posts_to_collectibles(self):
        # The rule is about ANONYMITY, not about underpayment. A named customer owing
        # money is the entire purpose of the utang, so this must keep working.
        named = Customer.objects.create(
            name='Maria Santos', customer_type=Customer.Type.REGULAR)
        txn = process_sale(
            customer_id=named.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 10,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('60')}],
        )
        self.assertEqual(txn.grand_total, Decimal('100'))
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('40'))
        self.assertEqual(ledger.customer, named)

    def test_a_fully_paid_walk_in_sale_still_succeeds(self):
        # The guard must not touch the ordinary anonymous sale, which is most of them.
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 2,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('20')}],
        )
        self.assertEqual(txn.grand_total, Decimal('20'))
        self.assertFalse(
            CollectibleLedger.objects.filter(transaction=txn).exists())

    def test_fully_paid_sale_creates_no_ledger(self):
        txn = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': 2,
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('20')}],
        )
        self.assertFalse(
            CollectibleLedger.objects.filter(transaction=txn).exists())



TRANSACTIONS_URL = '/api/v1/transactions/'
LOGIN_URL = '/api/v1/auth/login/'


class CheckoutApiTests(POSTestBase):
    """Phase 3 Task 2 (decision 06, section 3) - the failure contract.

    `process_sale` reaches `allocate_fifo`, which raises ValueError when stock is
    short. Nothing catches it and no DRF EXCEPTION_HANDLER is configured, so the
    most common expected failure - a cashier asking for more than is on the shelf -
    came back as HTTP 500. Decision 06 calls that "an expected outcome, not a
    crash" and requires distinct UI treatment, which a 500 cannot give: the client
    cannot tell it apart from the server being broken.

    Contract under test: HTTP 400 with a stable machine-readable code.
    """

    def setUp(self):
        super().setUp()
        # Roles are Django Groups, not a field on the user (see permissions.ROLE_CASHIER
        # and User.role_names). Without this the endpoint answers 403 before the code
        # under test runs, and the test would "fail" for the wrong reason.
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'cashier1', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200, 'the cashier must be able to log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def test_the_fixture_can_actually_reach_the_view(self):
        # A guard on the harness itself: if this 403s, every other assertion in this
        # class is testing the permission layer rather than the failure contract.
        self.assertNotEqual(self._post(1).status_code, 403)

    def _payload(self, qty):
        # Stock on hand is 10 (two batches of 5). `variant_id` is a VariantUOM id,
        # which is what the API resolves it as - see Task 1.
        return {
            'customer': self.customer.id,
            'source': 'WALK_IN',
            'items': [{'variant_id': self.vuom.id, 'qty': qty,
                       'unit_price': '10.00'}],
            'payments': [{'method': 'CASH', 'amount_tendered': '100.00'}],
        }

    def _post(self, qty):
        return self.client.post(
            TRANSACTIONS_URL, data=self._payload(qty),
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

    def _post_paying(self, qty, amount, customer_id=None):
        """Post with a chosen payment amount, and optionally a chosen customer.

        `_payload` hardcodes 100.00, which within the fixture's 10-unit stock can only
        overpay - so an underpaid sale cannot be built from it.
        """
        payload = self._payload(qty)
        payload['payments'] = [{'method': 'CASH', 'amount_tendered': amount}]
        if customer_id is not None:
            payload['customer'] = customer_id
        return self.client.post(
            TRANSACTIONS_URL, data=payload,
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

    def test_an_underpaid_walk_in_sale_is_a_400_with_a_code(self):
        # Decision 14's rule, seen from the client's side: a stable code it can branch on,
        # not a 500 and not a silently-created debt.
        response = self._post_paying(10, '60.00')  # 100 total, 40 short
        self.assertEqual(response.status_code, 400)
        body = response.json()
        self.assertEqual(body['code'], 'WALK_IN_CANNOT_OWE')
        self.assertEqual(body['shortfall'], '40.00')
        self.assertFalse(SalesTransaction.objects.exists(),
                         'the refused sale must not be recorded')

    def test_an_underpaid_named_customer_sale_still_returns_201(self):
        named = Customer.objects.create(
            name='Maria Santos', customer_type=Customer.Type.REGULAR)
        response = self._post_paying(10, '60.00', customer_id=named.id)
        self.assertEqual(response.status_code, 201)
        self.assertTrue(
            CollectibleLedger.objects.filter(customer=named).exists())

    def test_insufficient_stock_is_a_400_with_a_stable_code(self):
        # 10 on hand; ask for 11.
        response = self._post(11)
        self.assertEqual(
            response.status_code, 400,
            'insufficient stock is an expected outcome and must not be a 500')
        body = response.json()
        self.assertEqual(body['code'], 'INSUFFICIENT_STOCK')
        self.assertIn('shortfall', body, 'the client needs the shortfall to explain it')
        # Decision 06 section 3 requires the client to "identify the offending line".
        # `detail` names the product, but only an id lets the cart point AT the row it
        # must fix, and InsufficientStock already carries one (inventory/services.py
        # raises it with the variant) - the handler simply was not publishing it.
        self.assertEqual(
            body['variant_id'], self.variant.id,
            'without the variant id the client can only print a sentence')

    def test_a_rejected_sale_rolls_back_entirely(self):
        # transaction.atomic() means a failure leaves NOTHING behind: the client is
        # allowed to keep its cart precisely because the server state is unchanged.
        txns_before = SalesTransaction.objects.count()
        self._post(11)
        self.assertEqual(SalesTransaction.objects.count(), txns_before)
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(Payment.objects.exists())
        self.assertEqual(
            sum(self.variant.batches.values_list('current_qty', flat=True)),
            Decimal('10'),
            'a rejected sale must not have moved any stock')

    def test_a_valid_sale_still_returns_201_with_the_finished_transaction(self):
        # Decision 06 section 1: the response IS the finished transaction, so the
        # receipt screen needs no second fetch.
        response = self._post(2)
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertIn('items', body)
        self.assertIn('payments', body)
        self.assertIn('receipt', body)
        self.assertEqual(body['grand_total'], '20.00')


HELD_CARTS_URL = '/api/v1/held-carts/'


class HeldCartTests(POSTestBase):
    """Phase 3: HeldCart CRUD + complete action."""

    def setUp(self):
        super().setUp()
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'cashier1', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200, 'cashier must log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    def _hold(self, customer=None, items=None):
        payload = {
            'notes': 'test hold',
            'items': items or [{'variant_uom': self.vuom.id, 'qty': '2', 'unit_price': '10.00'}],
        }
        if customer is not None:
            payload['customer'] = customer
        return self.client.post(
            HELD_CARTS_URL, payload,
            content_type='application/json', **self.auth)

    def test_hold_creates_cart(self):
        resp = self._hold(customer=self.customer.id)
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data['notes'], 'test hold')
        self.assertEqual(len(resp.data['items']), 1)

    def test_list_shows_held_carts(self):
        self._hold(customer=self.customer.id)
        resp = self.client.get(HELD_CARTS_URL, **self.auth)
        self.assertEqual(resp.status_code, 200)
        self.assertGreaterEqual(resp.data['count'], 1)

    def test_resume_returns_cart_with_items(self):
        hold_resp = self._hold(customer=self.customer.id)
        cart_id = hold_resp.data['id']
        resp = self.client.get(f'{HELD_CARTS_URL}{cart_id}/', **self.auth)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data['items']), 1)
        self.assertEqual(resp.data['items'][0]['qty'], '2.00')

    def test_complete_creates_transaction_and_deletes_cart(self):
        hold_resp = self._hold(customer=self.customer.id)
        cart_id = hold_resp.data['id']
        resp = self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '20.00'}]},
            content_type='application/json', **self.auth,
        )
        self.assertEqual(resp.status_code, 201)
        self.assertTrue(SalesTransaction.objects.filter(id=resp.data['id']).exists())
        from .models import HeldCart
        self.assertFalse(HeldCart.objects.filter(id=cart_id).exists())

    def test_void_deletes_cart(self):
        hold_resp = self._hold(customer=self.customer.id)
        cart_id = hold_resp.data['id']
        resp = self.client.delete(f'{HELD_CARTS_URL}{cart_id}/', **self.auth)
        self.assertEqual(resp.status_code, 204)
        from .models import HeldCart
        self.assertFalse(HeldCart.objects.filter(id=cart_id).exists())

    def test_walk_in_hold_no_customer(self):
        resp = self._hold(customer=None)
        self.assertEqual(resp.status_code, 201)
        self.assertIsNone(resp.data['customer'])

    def test_complete_insufficient_stock_keeps_cart(self):
        hold_resp = self._hold(
            customer=self.customer.id,
            items=[{'variant_uom': self.vuom.id, 'qty': '99999', 'unit_price': '10.00'}],
        )
        cart_id = hold_resp.data['id']
        resp = self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '999990.00'}]},
            content_type='application/json', **self.auth,
        )
        self.assertEqual(resp.status_code, 400)
        from .models import HeldCart
        self.assertTrue(HeldCart.objects.filter(id=cart_id).exists())
