# pyright: reportAttributeAccessIssue=false
"""Requisitions tests — approval flow, tokens, material release."""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.test import TestCase
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
from apps.pos.models import Customer, OfficialReceipt, SalesTransaction, Shift

from .models import Project, Requisition, RequisitionItem
from .serializers import RequisitionSerializer
from .services import (
    approve_requisition,
    reject_requisition,
    release_materials,
    submit_requisition,
    verify_token,
)

User = get_user_model()

# The fixture password, generated instead of written as a literal. These accounts exist
# only in the throwaway test database and nothing logs in with it (the security and audit
# modules reset the password to their own before logging in), so a fixed value would only
# be one more literal a scanner has to be taught to ignore.
FIXTURE_PASSWORD = get_random_string(20)


class RequisitionTestBase(TestCase):
    def setUp(self):
        self.manager = User.objects.create_user(
            username='manager1', email='m@x.com', password=FIXTURE_PASSWORD)
        self.foreman = User.objects.create_user(
            username='foreman1', email='f@x.com', password=FIXTURE_PASSWORD)
        self.cashier = User.objects.create_user(
            username='cashier1', email='c@x.com', password=FIXTURE_PASSWORD)
        # Phase 3 (decision 03): a material release now requires the releasing cashier's
        # OPEN shift, exactly like `process_sale`, so every release test needs one. Opened
        # here for the same reason `POSTestBase` opens one: it is a precondition of the
        # action under test, not the subject of these tests. A test that needs the gate to
        # fire deletes it.
        self.shift = Shift.objects.create(
            cashier=self.cashier, opening_float=Decimal('5000'))
        self.customer = Customer.objects.create(name='Builder Corp')
        self.project = Project.objects.create(
            name='House Build', customer=self.customer)
        category = Category.objects.create(name='Cement')
        brand = Brand.objects.create(name='Rhino')
        uom = UnitOfMeasure.objects.create(code='BAG', name='Bag')
        product = Product.objects.create(
            category=category, brand=brand, base_name='Portland Cement')
        self.variant = ProductVariant.objects.create(
            product=product, variant_name='40kg', base_uom=uom)
        VariantUOM.objects.create(
            variant=self.variant, uom=uom, conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        supplier = Supplier.objects.create(company_name='Acme')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=self.variant, ordered_qty=Decimal('100'),
            unit_cost=Decimal('40'), received_qty=Decimal('100'))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)

        self.requisition = Requisition.objects.create(
            project=self.project, requested_by=self.foreman)
        self.req_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant=self.variant,
            quantity=Decimal('10'))


class RequisitionFlowTests(RequisitionTestBase):
    def test_full_flow_submit_approve_release(self):
        submit_requisition(requisition=self.requisition)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.SUBMITTED)

        token = approve_requisition(
            requisition=self.requisition, approver=self.manager)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.APPROVED)
        self.assertEqual(self.requisition.approved_by, self.manager)
        self.assertEqual(token.requisition, self.requisition)

        # Token verify shows remaining qty before release
        info = verify_token(token_value=str(token.token))
        self.assertEqual(info['items'][0]['remaining'], '10.00')

        result = release_materials(
            token_value=str(token.token), cashier=self.cashier)

        # Stock deducted via FIFO
        total = sum(self.variant.batches.values_list(
            'current_qty', flat=True))
        self.assertEqual(total, Decimal('90'))
        # Sales transaction created with requisition source
        txn = SalesTransaction.objects.get(id=result['transaction_id'])
        self.assertEqual(txn.source, SalesTransaction.Source.REQUISITION)
        self.assertEqual(txn.grand_total, Decimal('100'))
        # Ledger posted for the construction firm
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('100'))
        # Token consumed, requisition released
        token.refresh_from_db()
        self.assertTrue(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)

    def test_cannot_approve_draft_requisition(self):
        with self.assertRaises(ValueError):
            approve_requisition(
                requisition=self.requisition, approver=self.manager)

    def test_cannot_submit_twice(self):
        submit_requisition(requisition=self.requisition)
        with self.assertRaises(ValueError):
            submit_requisition(requisition=self.requisition)

    def test_reject_sets_status(self):
        submit_requisition(requisition=self.requisition)
        reject_requisition(requisition=self.requisition, approver=self.manager)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.REJECTED)

    def test_token_cannot_be_used_twice(self):
        submit_requisition(requisition=self.requisition)
        token = approve_requisition(
            requisition=self.requisition, approver=self.manager)
        release_materials(token_value=str(token.token), cashier=self.cashier)
        with self.assertRaises(ValueError):
            release_materials(token_value=str(token.token),
                              cashier=self.cashier)

    def test_invalid_token_rejected(self):
        # A fixture id is not a UUID: the format check must refuse it before any lookup.
        # Built from the fixture rather than written as a token-shaped literal, so the
        # test reads the same and no scanner has to whitelist a fake credential.
        with self.assertRaises(ValueError):
            verify_token(token_value=str(self.variant.pk))



class RequisitionProvenanceTests(RequisitionTestBase):
    """Decision 09 requires the approve queue to show where a requisition came
    from. The list endpoint is the queue's only data source, so these fields are
    the contract it depends on - pinned here rather than discovered in the UI."""

    def test_serializer_carries_all_four_provenance_facts(self):
        # dict() pins the type: Serializer.data is ReturnDict | list, which a checker
        # cannot index by string even though a ModelSerializer always returns one.
        data = dict(RequisitionSerializer(self.requisition).data)
        self.assertEqual(data['req_number'], self.requisition.req_number)
        self.assertEqual(data['project_name'], 'House Build')
        self.assertEqual(data['requested_by_name'], self.foreman.full_name)
        self.assertEqual(data['project_customer_name'], 'Builder Corp')


class RequisitionListQueryTests(RequisitionTestBase):
    """The list endpoint is the approve queue's data source, so its query count must not grow with
    the number of rows: a manager with 200 open requisitions would otherwise wait on 200 extra
    round trips to render the page."""

    def _queries_for_list(self):
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        from .views import RequisitionViewSet

        with CaptureQueriesContext(connection) as ctx:
            list(RequisitionSerializer(RequisitionViewSet().get_queryset(), many=True).data)
        return len(ctx.captured_queries)

    def test_serializing_the_list_does_not_query_once_per_row(self):
        one_row = self._queries_for_list()
        for index in range(3):
            Requisition.objects.create(
                project=self.project, requested_by=self.foreman,
                req_number=f'REQ-QUERYTEST-{index:04d}')
        four_rows = self._queries_for_list()
        self.assertEqual(
            one_row, four_rows,
            'the project customer lookup is happening per row (N+1)')


class MaterialReleaseApiTests(RequisitionTestBase):
    """Decision 09 item 6 — a release must resolve the base-unit (factor 1) VariantUOM
    for EVERY line BEFORE it writes anything.

    The defect: `release_materials` looked the factor-1 selling unit up per item and, on
    a miss, still deducted stock and created a SalesTransaction, then passed
    `variant_uom=None` into a non-null FK — an IntegrityError 500 with the stock already
    moving inside the same block. Retrying the token after the 500 could then deduct a
    second time in the worst case, and the cashier saw a crash instead of a reason.

    Exercised over HTTP because the contract that matters to the client is the 400 with a
    stable `code`, and because "nothing was written" is only provable by leaving the
    request and looking.
    """

    def setUp(self):
        super().setUp()
        group, _ = Group.objects.get_or_create(name='Cashier')
        self.cashier.groups.add(group)
        self.client = APIClient()
        # A 500 must be inspected, not re-raised: before the fix this request CRASHES in
        # the view, and a test that dies with IntegrityError proves the crash but not the
        # status code the client would see.
        self.client.raise_request_exception = False
        login = self.client.post('/api/v1/auth/login/', {
            'username': 'cashier1', 'password': FIXTURE_PASSWORD}, format='json')
        token = login.data.get('access') or login.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def _second_variant_without_base_uom(self):
        """A variant that HAS stock and HAS a selling unit — but only a factor-12 one."""
        box = UnitOfMeasure.objects.create(code='BOX', name='Box')
        product = Product.objects.create(
            category=Category.objects.get(name='Cement'),
            brand=Brand.objects.get(name='Rhino'),
            base_name='Premium Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='50kg', base_uom=box)
        VariantUOM.objects.create(
            variant=variant, uom=box, conversion_factor=Decimal('12'),
            default_selling_price=Decimal('120'),
        )
        supplier = Supplier.objects.create(company_name='Acme Second')
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=self.manager,
            status=PurchaseOrder.Status.ORDERED)
        POItem.objects.create(
            po=po, variant=variant, ordered_qty=Decimal('50'),
            unit_cost=Decimal('90'), received_qty=Decimal('50'))
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.manager)
        process_goods_receipt(receipt=receipt, user=self.manager)
        return variant

    def _approved_token(self):
        submit_requisition(requisition=self.requisition)
        return approve_requisition(
            requisition=self.requisition, approver=self.manager)

    def _release(self, token):
        return self.client.post(
            '/api/v1/tokens/release/', {'token': str(token.token)}, format='json')

    def test_line_without_base_uom_is_400_and_writes_nothing(self):
        box_variant = self._second_variant_without_base_uom()
        RequisitionItem.objects.create(
            requisition=self.requisition, variant=box_variant,
            quantity=Decimal('3'))
        token = self._approved_token()
        transactions_before = SalesTransaction.objects.count()

        response = self._release(token)

        self.assertEqual(
            response.status_code, 400, getattr(response, 'data', None))
        self.assertEqual(response.data['code'], 'NO_BASE_UOM')
        self.assertIn('detail', response.data)
        # Nothing written: no sale, no receipt, no ledger, no deduction, token unused.
        self.assertEqual(SalesTransaction.objects.count(), transactions_before)
        self.assertFalse(OfficialReceipt.objects.exists())
        self.assertFalse(CollectibleLedger.objects.exists())
        token.refresh_from_db()
        self.assertFalse(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.APPROVED)
        self.req_item.refresh_from_db()
        self.assertEqual(self.req_item.released_qty, Decimal('0'))
        base_stock = sum(self.variant.batches.values_list('current_qty', flat=True))
        box_stock = sum(box_variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(base_stock, Decimal('100'))
        self.assertEqual(box_stock, Decimal('50'))

    def test_successful_release_still_uses_base_unit_price(self):
        """Guard on the unchanged happy path: quantities stay in BASE units and the
        price comes from the factor-1 selling unit (server-priced since task 1)."""
        token = self._approved_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        # 10 base units at the factor-1 unit price of 10.00.
        self.assertEqual(
            Decimal(response.data['grand_total']), Decimal('100'))
        base_stock = sum(self.variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(base_stock, Decimal('90'))
