# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directive and reason as apps/pos/tests.py: the checker resolves its config from
# its WORKING DIRECTORY and does not run inside this repo here, so every `Model.objects`
# access and every `self.client.post(..., **self.auth)` is a false positive on valid
# Django. The test run is the authority.
"""Phase 1 task 1 — sale integrity: validation, server price, UOM conversion.

Decision 01 (uom-and-price-authority.md) says the server owns both the price and the
stock arithmetic:

* `SalesItem.unit_price` is `VariantUOM.default_selling_price`. A client `unit_price`
  in the payload is IGNORED, not an error, so older clients keep working.
* `base_qty = qty (selling units) x VariantUOM.conversion_factor` is what FIFO deducts;
  `SalesItem.qty` stays the selling quantity so the receipt reads "1 box", not "12 pcs".

Without this a swapped barcode label - or a hand-written request - rings one box of
twelve and deducts one piece, at a price the client picked.

The ledger ruling extends the same rule to RETURNS: `_restock_returned` receives base
units (the `SalesItemDeduction` rows it reconciles against are base units), and the
refund price is the ORIGINAL sale line's price, so a forged return price cannot mint
money. Cost if wrong: a sale deducts 12 and its return restocks 1.

Everything here exercises the contract the client sees: business-rule rejections are
HTTP 400 `{code, detail}`, never 500.
"""

from datetime import date
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    GoodsReceipt,
    POItem,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.exceptions import ReturnError
from apps.pos.models import (
    Customer,
    HeldCart,
    OfficialReceipt,
    SalesItem,
    SalesTransaction,
    Shift,
)
from apps.pos.services import generate_transaction_no, process_return, process_sale
from apps.pos.tests import LOGIN_URL, TRANSACTIONS_URL, POSTestBase

HELD_CARTS_URL = '/api/v1/held-carts/'

# Phase 3 task 2 (decision 05): every return carries a reason.
RETURN_REASON = 'customer brought the box back'

User = get_user_model()


class SaleIntegrityBase(POSTestBase):
    """POSTestBase (CF=1, price 10, stock 5@40 + 5@60) plus an authenticated client."""

    def setUp(self):
        super().setUp()
        # Roles are Django Groups, not a user field - without this the endpoint answers
        # 403 before the code under test runs and every assertion would be about RBAC.
        self.cashier.groups.add(Group.objects.get_or_create(name='Cashier')[0])
        login = self.client.post(
            LOGIN_URL,
            {'username': 'cashier1', 'password': 'pass12345'},
            content_type='application/json',
        )
        self.assertEqual(login.status_code, 200, 'the cashier must be able to log in')
        self.auth = {'HTTP_AUTHORIZATION': f'Bearer {login.json()["access"]}'}

    # -- fixture helpers ---------------------------------------------------
    def _stock_up(self, qty, cost='40.00'):
        """Add `qty` BASE units to the fixture variant, through a real goods receipt."""
        supplier = Supplier.objects.create(company_name=f'Extra {qty}')
        po = PurchaseOrder.objects.create(supplier=supplier, created_by=self.cashier)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal(qty),
            unit_cost=Decimal(cost), received_qty=Decimal(qty))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.cashier)
        process_goods_receipt(receipt=receipt, user=self.cashier)

    def _box_uom(self, *, conversion_factor='12', price='120.00'):
        """A second selling UOM on the fixture variant: one box = 12 base units."""
        box = UnitOfMeasure.objects.create(code='BOX', name='Box')
        return VariantUOM.objects.create(
            variant=self.variant, uom=box,
            conversion_factor=Decimal(conversion_factor),
            default_selling_price=Decimal(price))

    def _total_stock(self):
        return sum(self.variant.batches.values_list('current_qty', flat=True),
                   Decimal('0'))

    def _unlinked_return_manager(self):
        """A Store Manager with an open shift: unlinked returns are theirs alone.

        Both are Phase 3 rules (decision 05): a cashier may not post an unlinked return,
        and no return may be recorded outside an open shift.
        """
        manager = User.objects.create_user(
            username='ret_integrity_mgr', email='m@x.com', password='pass12345')
        manager.groups.add(Group.objects.get_or_create(name='Store Manager')[0])
        Shift.objects.create(cashier=manager, opening_float=Decimal('0'))
        return manager

    # -- HTTP helpers ------------------------------------------------------
    def _post_sale(self, items, payments=None, customer=None):
        payload = {
            'customer': (customer or self.customer).id,
            'source': 'WALK_IN',
            'items': items,
            'payments': payments if payments is not None
            else [{'method': 'CASH', 'amount_tendered': '1000.00'}],
        }
        return self.client.post(
            TRANSACTIONS_URL, data=payload,
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

    def _assert_invalid_sale(self, response):
        self.assertEqual(
            response.status_code, 400,
            f'a bad sale is an expected rejection, not a crash: {response.content!r}')
        body = response.json()
        self.assertEqual(body.get('code'), 'INVALID_SALE', body)
        self.assertIn('detail', body, 'the client needs a sentence for the cashier')
        self.assertFalse(SalesTransaction.objects.exists(),
                         'a refused sale must leave no transaction behind')


class ServerPriceTests(SaleIntegrityBase):
    """Decision 01: the server sets the price; the client's is ignored."""

    def test_a_forged_unit_price_is_ignored(self):
        response = self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '1', 'unit_price': '0.01'}])

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body['grand_total'], '10.00',
                         'the fixture price is 10.00; a forged 0.01 must not stick')
        self.assertEqual(body['items'][0]['unit_price'], '10.00')
        self.assertEqual(body['items'][0]['subtotal'], '10.00')
        self.assertEqual(
            SalesItem.objects.get(transaction_id=body['id']).unit_price,
            Decimal('10.00'))

    def test_a_client_price_above_the_server_price_is_also_ignored(self):
        # Not only fraud: a stale client cache quoting an old price must not become the
        # recorded price either. One rule, both directions.
        response = self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '2', 'unit_price': '999.00'}])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()['grand_total'], '20.00')


class UomConversionTests(SaleIntegrityBase):
    """Decision 01: FIFO deducts `qty x conversion_factor` BASE units."""

    def test_one_box_of_twelve_deducts_twelve_base_units(self):
        self._stock_up('24')                      # 10 fixture + 24 = 34 base units
        box = self._box_uom(conversion_factor='12', price='120.00')
        self.assertEqual(self._total_stock(), Decimal('34'))

        response = self._post_sale(
            [{'variant_id': box.id, 'qty': '1', 'unit_price': '0.01'}])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(self._total_stock(), Decimal('22'),
                         'selling 1 box of 12 must remove 12 base units, not 1')
        item = SalesItem.objects.get(transaction_id=response.json()['id'])
        self.assertEqual(item.qty, Decimal('1'),
                         'the receipt keeps the SELLING quantity: "1 box"')
        self.assertEqual(item.unit_price, Decimal('120.00'))
        self.assertEqual(response.json()['grand_total'], '120.00')

    def test_a_fractional_conversion_factor_is_applied(self):
        self._stock_up('10')                      # 20 base units of "metre" stock
        metre = UnitOfMeasure.objects.create(code='M', name='Metre')
        half = VariantUOM.objects.create(
            variant=self.variant, uom=metre,
            conversion_factor=Decimal('0.50'),
            default_selling_price=Decimal('7.50'))

        response = self._post_sale(
            [{'variant_id': half.id, 'qty': '4', 'unit_price': '7.50'}])

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(self._total_stock(), Decimal('18'),
                         '4 x 0.5 = 2 base units')
        self.assertEqual(response.json()['grand_total'], '30.00')

    def test_a_box_sale_is_short_when_the_base_units_run_out(self):
        # 10 base units on hand. One box of 12 LOOKS affordable only because the server
        # used to compare the raw 1 against the stock; the comparison is on base units.
        box = self._box_uom(conversion_factor='12')

        response = self._post_sale([{'variant_id': box.id, 'qty': '1'}])

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'INSUFFICIENT_STOCK')
        self.assertEqual(response.json()['shortfall'], '2.00',
                         '12 needed, 10 on hand: the shortfall is in base units')
        self.assertEqual(self._total_stock(), Decimal('10'),
                         'a rejected sale must not move stock')


class SaleValidationTests(SaleIntegrityBase):
    """Task 1.2: everything the server must refuse BEFORE it writes anything."""

    def test_empty_items_is_a_400_with_no_rows(self):
        self._assert_invalid_sale(self._post_sale([]))

    def test_missing_items_key_is_a_400(self):
        response = self.client.post(
            TRANSACTIONS_URL,
            data={'customer': self.customer.id, 'source': 'WALK_IN',
                  'payments': [{'method': 'CASH',
                                'amount_tendered': '10.00'}]},
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]
        self._assert_invalid_sale(response)

    def test_zero_qty_is_a_400(self):
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': '0'}]))

    def test_negative_qty_is_a_400(self):
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': '-1'}]))

    def test_non_numeric_qty_is_a_400(self):
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': 'abc'}]))

    def test_infinite_qty_is_a_400(self):
        # `Decimal('Infinity')` parses, and `min(stock, Infinity)` would deduct the shelf.
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': 'Infinity'}]))

    def test_unknown_variant_uom_id_is_a_400(self):
        # No fallback to a ProductVariant id any more: 999999 exists as neither, and an
        # ambiguous resolution is what let a swapped id sell the wrong thing.
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': 999999, 'qty': '1'}]))

    def test_inactive_variant_is_a_400(self):
        self.variant.is_active = False
        self.variant.save(update_fields=['is_active'])
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': '1'}]))

    def test_inactive_product_is_a_400(self):
        product = self.variant.product
        product.is_active = False
        product.save(update_fields=['is_active'])
        self._assert_invalid_sale(
            self._post_sale([{'variant_id': self.vuom.id, 'qty': '1'}]))

    def test_a_bogus_payment_method_is_a_400(self):
        self._assert_invalid_sale(self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '1'}],
            payments=[{'method': 'BARTER', 'amount_tendered': '10.00'}]))

    def test_a_negative_amount_tendered_is_a_400(self):
        self._assert_invalid_sale(self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '1'}],
            payments=[{'method': 'CASH', 'amount_tendered': '-10.00'}]))

    def test_more_than_two_hundred_lines_is_a_400(self):
        lines = [{'variant_id': self.vuom.id, 'qty': '0.01'} for _ in range(201)]
        self._assert_invalid_sale(self._post_sale(lines))

    def test_a_rejected_sale_leaves_no_receipt_and_no_payment(self):
        from apps.pos.models import Payment
        self._post_sale([{'variant_id': self.vuom.id, 'qty': 'abc'}],
                        payments=[{'method': 'CASH',
                                   'amount_tendered': '10.00'}])
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(Payment.objects.exists())
        self.assertEqual(self._total_stock(), Decimal('10'))


class ReturnConversionTests(SaleIntegrityBase):
    """Ledger ruling: a return restocks BASE units at the ORIGINAL line's price."""

    def _sell_one_box(self):
        self._stock_up('24')
        box = self._box_uom(conversion_factor='12', price='120.00')
        sale = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': box.id, 'qty': Decimal('1'),
                         'unit_price': Decimal('0.01')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('120')}])
        return box, sale

    def test_returning_one_box_restocks_twelve_base_units(self):
        box, sale = self._sell_one_box()
        self.assertEqual(self._total_stock(), Decimal('22'))

        ret = process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': box.id, 'qty': Decimal('1'),
                         'unit_price': Decimal('0.01')}],
            original_transaction_id=sale.id,
            reason=RETURN_REASON,
        )

        self.assertEqual(self._total_stock(), Decimal('34'),
                         'the sale took 12 base units; the return must give 12 back')
        line = ret.items.get()
        self.assertEqual(line.unit_price, Decimal('120.00'),
                         'the refund price is the original line price')
        self.assertEqual(ret.grand_total, Decimal('-120.00'),
                         'a forged return price must not shrink the refund either')

    def test_returning_a_uom_that_was_not_on_the_original_is_refused(self):
        sale = process_sale(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.id, 'qty': Decimal('2'),
                         'unit_price': Decimal('10')}],
            payments_data=[{'method': 'CASH',
                            'amount_tendered': Decimal('20')}])
        box = self._box_uom()

        with self.assertRaises(ReturnError):
            process_return(
                customer_id=self.customer.id,
                cashier=self.cashier,
                items_data=[{'variant_id': box.id, 'qty': Decimal('1')}],
                original_transaction_id=sale.id,
                reason=RETURN_REASON,
            )
        self.assertEqual(self._total_stock(), Decimal('8'),
                         'a refused return must not restock anything')

    def test_an_unlinked_return_restocks_base_units_at_the_server_price(self):
        self._stock_up('24')
        box = self._box_uom(conversion_factor='12', price='120.00')
        manager = self._unlinked_return_manager()

        ret = process_return(
            customer_id=self.customer.id,
            cashier=manager,
            items_data=[{'variant_id': box.id, 'qty': Decimal('1'),
                         'unit_price': Decimal('0.01')}],
            reason=RETURN_REASON,
        )

        self.assertEqual(self._total_stock(), Decimal('46'),
                         'no original to link to: 34 + 12 base units')
        self.assertEqual(ret.grand_total, Decimal('-120.00'))


class HeldCartPriceTests(SaleIntegrityBase):
    """Task 1.6: a held cart's price is a note, not an authority."""

    def _hold(self, unit_price='0.01'):
        return self.client.post(
            HELD_CARTS_URL,
            {'notes': 'tampered', 'customer': self.customer.id,
             'items': [{'variant_uom': self.vuom.id, 'qty': '2',
                        'unit_price': unit_price}]},
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

    def test_completing_a_tampered_held_cart_records_the_server_price(self):
        hold = self._hold(unit_price='0.01')
        self.assertEqual(hold.status_code, 201, hold.content)
        cart_id = hold.json()['id']

        response = self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '20.00'}]},
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 201, response.content)
        body = response.json()
        self.assertEqual(body['grand_total'], '20.00',
                         'the held price 0.01 must not reach the transaction')
        self.assertEqual(body['items'][0]['unit_price'], '10.00')
        self.assertFalse(HeldCart.objects.filter(id=cart_id).exists())

    def test_completing_a_held_cart_that_is_now_unaffordable_is_a_400(self):
        # The held cart is validated by the same code path, so a stale cart that no
        # longer fits the shelf answers 400 and STAYS held rather than half-selling.
        hold = self._hold(unit_price='10.00')
        cart_id = hold.json()['id']
        cart = HeldCart.objects.get(id=cart_id)
        item = cart.items.get()
        item.qty = Decimal('99999')
        item.save(update_fields=['qty'])

        response = self.client.post(
            f'{HELD_CARTS_URL}{cart_id}/complete/',
            {'payments': [{'method': 'CASH', 'amount_tendered': '999990.00'}]},
            content_type='application/json',
            **self.auth)  # pyright: ignore[reportArgumentType]

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'INSUFFICIENT_STOCK')
        self.assertTrue(HeldCart.objects.filter(id=cart_id).exists())


class CreditLimitTests(SaleIntegrityBase):
    """Phase 1 task 2 — decision 08: the server enforces the credit limit.

    `Customer.total_credit_limit` is nullable on purpose: **NULL means unlimited**, `0`
    means **no credit at all**. Before this the field defaulted to 0 for every row and
    nothing ever set it, so hard-blocking 0 would have refused utang at the till for
    every existing customer; the data migration turns those legacy zeros into NULL.

    The block runs INSIDE `process_sale`'s atomic block, with the customer row locked,
    so a refused credit sale leaves no transaction, no ledger and no moved stock - and
    two tills cannot both pass on the same stale outstanding balance.
    """

    def _named(self, limit):
        return Customer.objects.create(
            name=f'Named {limit}', customer_type=Customer.Type.REGULAR,
            total_credit_limit=limit)

    def _owed(self, customer, balance, status=CollectibleLedger.Status.OPEN):
        """An existing utang row for the customer, as a real past sale would leave."""
        txn = SalesTransaction.objects.create(
            customer=customer, cashier=self.cashier,
            transaction_no=generate_transaction_no(),
            vatable_sales=Decimal(balance), grand_total=Decimal(balance))
        return CollectibleLedger.objects.create(
            customer=customer, transaction=txn,
            original_amount=Decimal(balance), balance_due=Decimal(balance),
            due_date=date.today(), status=status)

    def _credit_sale(self, customer, tendered='400.00'):
        """60 x 10.00 = 600.00 grand total, 400.00 tendered, 200.00 shortfall."""
        return self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '60'}],
            payments=[{'method': 'CASH', 'amount_tendered': tendered}],
            customer=customer)

    def test_a_sale_over_the_limit_is_a_400_and_writes_nothing(self):
        self._stock_up('100')
        customer = self._named(Decimal('500.00'))
        self._owed(customer, '400.00')
        sales_before = SalesTransaction.objects.count()
        ledgers_before = CollectibleLedger.objects.count()
        receipts_before = OfficialReceipt.objects.count()

        response = self._credit_sale(customer)

        self.assertEqual(
            response.status_code, 400,
            f'a credit limit is a business rule, not a crash: {response.content!r}')
        self.assertEqual(response.json()['code'], 'CREDIT_LIMIT_EXCEEDED')
        self.assertEqual(SalesTransaction.objects.count(), sales_before,
                         'a refused credit sale must leave no transaction')
        self.assertEqual(CollectibleLedger.objects.count(), ledgers_before,
                         'a refused credit sale must leave no ledger')
        self.assertEqual(OfficialReceipt.objects.count(), receipts_before)
        self.assertEqual(self._total_stock(), Decimal('110'),
                         'a refused credit sale must not move stock')

    def test_the_rejection_names_limit_outstanding_and_shortfall(self):
        self._stock_up('100')
        customer = self._named(Decimal('500.00'))
        self._owed(customer, '400.00')

        body = self._credit_sale(customer).json()

        self.assertEqual(body['code'], 'CREDIT_LIMIT_EXCEEDED', body)
        self.assertEqual(body['limit'], '500.00',
                         'money in the payload is a 2-decimal string')
        self.assertEqual(body['outstanding'], '400.00')
        self.assertEqual(body['shortfall'], '200.00')
        self.assertIn('detail', body, 'the cashier needs a sentence')

    def test_exactly_at_the_limit_is_allowed(self):
        # 400 outstanding + this 200 shortfall = 600, the limit exactly. The rule is
        # `> limit`, so the boundary sale is accepted - refusing it would make the
        # number the cashier sees unusable.
        self._stock_up('100')
        customer = self._named(Decimal('600.00'))
        self._owed(customer, '400.00')

        response = self._credit_sale(customer)

        self.assertEqual(response.status_code, 201, response.content)
        self.assertTrue(
            CollectibleLedger.objects.filter(
                customer=customer, balance_due=Decimal('200.00')).exists(),
            'the boundary sale posts its own ledger')

    def test_a_null_limit_means_unlimited(self):
        self._stock_up('100')
        customer = self._named(None)

        response = self._credit_sale(customer)

        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(
            CollectibleLedger.objects.filter(
                customer=customer).get().balance_due, Decimal('200.00'))

    def test_a_zero_limit_refuses_any_shortfall(self):
        self._stock_up('100')
        customer = self._named(Decimal('0.00'))

        response = self._credit_sale(customer)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'CREDIT_LIMIT_EXCEEDED')
        self.assertEqual(response.json()['outstanding'], '0.00')

    def test_a_fully_paid_sale_is_allowed_even_at_a_zero_limit(self):
        # The limit is about CREDIT. A sale paid in full owes nothing, so a customer
        # with no credit at all can still buy over the counter.
        customer = self._named(Decimal('0.00'))
        response = self._post_sale(
            [{'variant_id': self.vuom.id, 'qty': '10'}],
            payments=[{'method': 'CASH', 'amount_tendered': '100.00'}],
            customer=customer)

        self.assertEqual(response.status_code, 201, response.content)
        self.assertFalse(CollectibleLedger.objects.filter(customer=customer).exists())

    def test_a_paid_ledger_is_not_counted_as_outstanding(self):
        self._stock_up('100')
        customer = self._named(Decimal('500.00'))
        self._owed(customer, '400.00', status=CollectibleLedger.Status.PAID)

        response = self._credit_sale(customer)

        self.assertEqual(response.status_code, 201, response.content)

    def test_partial_and_overdue_ledgers_count(self):
        # Outstanding means money still owed, whatever the row's stage: 100 open plus
        # 100 partial plus 200 overdue is 400, and 400 + 200 breaks a 500 limit.
        self._stock_up('100')
        customer = self._named(Decimal('500.00'))
        self._owed(customer, '100.00', status=CollectibleLedger.Status.OPEN)
        self._owed(customer, '100.00', status=CollectibleLedger.Status.PARTIAL)
        self._owed(customer, '200.00', status=CollectibleLedger.Status.OVERDUE)

        response = self._credit_sale(customer)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['outstanding'], '400.00')

    def test_the_walk_in_rule_still_wins_over_a_generous_limit(self):
        # Decision 14 is checked FIRST: the placeholder walk-in cannot owe no matter
        # how much credit headroom it is given, and the client sees that code.
        self._stock_up('100')
        walk_in = Customer.objects.create(
            name='Walk-in Customer', customer_type=Customer.Type.WALK_IN,
            total_credit_limit=Decimal('10000.00'))

        response = self._credit_sale(walk_in)

        self.assertEqual(response.status_code, 400, response.content)
        self.assertEqual(response.json()['code'], 'WALK_IN_CANNOT_OWE')
