# pyright: reportAttributeAccessIssue=false
"""Requisitions tests — the CPMS copy, its token, and the material release.

Decision 01 removed the POS-side request and approval, so there is no submit/approve
flow to test any more: a requisition arrives ACCEPTED, with its token minted by the same
CPMS push (`services.import_request`, covered in `apps.integration.tests_import`). What is
left here is what the POS still does — show the copy, verify the token, release the goods.
"""

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
from apps.pos.models import (
    Customer,
    OfficialReceipt,
    SalesItem,
    SalesTransaction,
    Shift,
)

from .models import MaterialToken, Project, Requisition, RequisitionItem
from .serializers import RequisitionSerializer
from .services import release_materials, verify_token

User = get_user_model()

# The fixture password, generated instead of written as a literal. These accounts exist
# only in the throwaway test database and nothing logs in with it (the security and audit
# modules reset the password to their own before logging in), so a fixed value would only
# be one more literal a scanner has to be taught to ignore.
FIXTURE_PASSWORD = get_random_string(20)

# Decision 08: the requester is a NAME CPMS reported, not an account that can log in here.
REQUESTER_NAME = 'Rey Quester'


class RequisitionTestBase(TestCase):
    def setUp(self):
        self.manager = User.objects.create_user(
            username='manager1', email='m@x.com', password=FIXTURE_PASSWORD,
            full_name='Mana Ger')
        self.cashier = User.objects.create_user(
            username='cashier1', email='c@x.com', password=FIXTURE_PASSWORD,
            full_name='Cashi Er')
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
        # Decision 04: a requisition line IS a selling unit, so the fixture keeps the row
        # it points at.
        self.vuom = VariantUOM.objects.create(
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

        # Decision 01: the request is ACCEPTED when it lands here, because CPMS approved
        # it. Stored directly, the way `import_request` stores it.
        self.requisition = Requisition.objects.create(
            project=self.project,
            req_number='REQ-TEST-0001',
            status=Requisition.Status.ACCEPTED,
            requester_name=REQUESTER_NAME,
            approver_name=self.manager.full_name,
        )
        self.req_item = RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=self.vuom,
            quantity=Decimal('10'))

    def _mint_token(self, requisition=None):
        """The one-time token a push mints with its request (decision 02)."""
        return MaterialToken.objects.create(
            requisition=requisition or self.requisition)

    def _stock(self):
        return sum(self.variant.batches.values_list('current_qty', flat=True))


class MaterialReleaseTests(RequisitionTestBase):
    def test_a_release_deducts_stock_books_the_utang_and_consumes_the_token(self):
        token = self._mint_token()

        # Token verify shows remaining qty before release
        info = verify_token(token_value=str(token.token))
        self.assertEqual(info['items'][0]['remaining'], '10.00')

        result = release_materials(
            token_value=str(token.token), cashier=self.cashier)

        # Stock deducted via FIFO
        self.assertEqual(self._stock(), Decimal('90'))
        # Sales transaction created with requisition source
        txn = SalesTransaction.objects.get(id=result['transaction_id'])
        self.assertEqual(txn.source, SalesTransaction.Source.REQUISITION)
        self.assertEqual(txn.grand_total, Decimal('100'))
        self.assertTrue(OfficialReceipt.objects.filter(transaction=txn).exists())
        # Ledger posted for the construction firm
        ledger = CollectibleLedger.objects.get(transaction=txn)
        self.assertEqual(ledger.balance_due, Decimal('100'))
        # Token consumed, requisition released
        token.refresh_from_db()
        self.assertTrue(token.is_used)
        self.requisition.refresh_from_db()
        self.assertEqual(self.requisition.status, Requisition.Status.RELEASED)

    def test_token_cannot_be_used_twice(self):
        token = self._mint_token()
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
    """Decision 09 requires the requisition list to show where a request came
    from. The list endpoint is that screen's only data source, so these fields are
    the contract it depends on - pinned here rather than discovered in the UI."""

    def test_serializer_carries_all_four_provenance_facts(self):
        # dict() pins the type: Serializer.data is ReturnDict | list, which a checker
        # cannot index by string even though a ModelSerializer always returns one.
        data = dict(RequisitionSerializer(self.requisition).data)
        self.assertEqual(data['req_number'], self.requisition.req_number)
        self.assertEqual(data['project_name'], 'House Build')
        self.assertEqual(data['requested_by_name'], REQUESTER_NAME)
        self.assertEqual(data['project_customer_name'], 'Builder Corp')


class RequisitionListQueryTests(RequisitionTestBase):
    """The list endpoint is the requisition screen's data source, so its query count must
    not grow with the number of rows: a manager with 200 open requisitions would otherwise
    wait on 200 extra round trips to render the page."""

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
                project=self.project, requester_name=REQUESTER_NAME,
                req_number=f'REQ-QUERYTEST-{index:04d}')
        four_rows = self._queries_for_list()
        self.assertEqual(
            one_row, four_rows,
            'the project customer lookup is happening per row (N+1)')


class MaterialReleaseApiTests(RequisitionTestBase):
    """Decision 04 — a release is priced and counted in the line's OWN selling unit.

    A line carries a `VariantUOM`, so there is no base-unit lookup to miss any more: the
    price is that unit's `default_selling_price` and FIFO deducts
    `quantity x conversion_factor` base units, exactly as `process_sale` does for a
    counter sale. Exercised over HTTP because the numbers the cashier sees are the
    contract: the receipt says "3 boxes", the shelf loses 36 pieces, the utang is 360.
    """

    def setUp(self):
        super().setUp()
        group, _ = Group.objects.get_or_create(name='Cashier')
        self.cashier.groups.add(group)
        self.client = APIClient()
        login = self.client.post('/api/v1/auth/login/', {
            'username': 'cashier1', 'password': FIXTURE_PASSWORD}, format='json')
        token = login.data.get('access') or login.data.get('token')
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def _box_of_twelve_variant(self):
        """A second variant with stock, sold only in boxes of 12."""
        box = UnitOfMeasure.objects.create(code='BOX', name='Box')
        product = Product.objects.create(
            category=Category.objects.get(name='Cement'),
            brand=Brand.objects.get(name='Rhino'),
            base_name='Premium Cement')
        variant = ProductVariant.objects.create(
            product=product, variant_name='50kg', base_uom=box)
        vuom = VariantUOM.objects.create(
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
        return variant, vuom

    def _release(self, token):
        return self.client.post(
            '/api/v1/tokens/release/', {'token': str(token.token)}, format='json')

    def test_a_line_sold_by_the_box_releases_boxes_and_deducts_pieces(self):
        box_variant, box_vuom = self._box_of_twelve_variant()
        RequisitionItem.objects.create(
            requisition=self.requisition, variant_uom=box_vuom,
            quantity=Decimal('3'))
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        # 3 boxes x 120.00, plus the fixture's 10 bags x 10.00 — each line priced by its
        # OWN selling unit in one and the same release.
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('460'))
        # FIFO took 3 x 12 = 36 pieces off a shelf of 50.
        box_stock = sum(box_variant.batches.values_list('current_qty', flat=True))
        self.assertEqual(box_stock, Decimal('14'))
        # The sale line keeps the SELLING quantity, like a counter sale.
        line = SalesItem.objects.get(transaction_id=response.data['transaction_id'],
                                     variant_uom=box_vuom)
        self.assertEqual(line.qty, Decimal('3'))
        self.assertEqual(line.unit_price, Decimal('120'))
        # Both lines are accounted for: 100 of the base variant, 360 for the boxes.
        self.assertEqual(self._stock(), Decimal('90'))

    def test_a_factor_one_line_is_priced_and_counted_one_for_one(self):
        """Guard on the unchanged happy path: 1 bag of 1 base unit at 10.00 each."""
        token = self._mint_token()

        response = self._release(token)

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Decimal(response.data['grand_total']), Decimal('100'))
        self.assertEqual(self._stock(), Decimal('90'))
