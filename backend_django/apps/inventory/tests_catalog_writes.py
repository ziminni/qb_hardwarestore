# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests.py: this checker runs from a
# working directory outside the repo, so `Model.objects` is a false positive on valid
# Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which pyright
# reads as `follow=`.

"""Phase 4 Task 1 — catalog writes are hardened and audited (audit findings R).

Five refusals and one trail, all on the SERVER, because every one of them was
previously reachable with a well-formed request:

* **No DELETE.** Every catalog row is referenced by sales, batches or history through
  `PROTECT`, so `DELETE /products/{id}/` was a 500 or an orphan. Archive instead.
* **Category archive** (`is_active`) replaces the delete a clerk wanted.
* **Selling-unit integrity.** A factor of 0 divided every FIFO deduction by zero, a
  negative price put money the wrong way round, and two factor-1 units on one variant
  made "the base unit" ambiguous. Once a unit has been SOLD its factor/uom/variant are
  frozen: changing them re-writes what the return cap and restock are measured against.
* **Variant integrity.** Negative thresholds made every sale "low", and re-pointing a
  variant at another product rewrote its stock history.
* **One audit row per write**, none per refusal (decision 07).

Real JWT logins (no ``force_authenticate``): the permission classes read GROUP
membership, so the login path is part of what is under test.
"""

from decimal import Decimal

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.users.models import AuditLog

from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
)
from .services import process_goods_receipt
from .tests import InventoryTestBase

User = get_user_model()

LOGIN_URL = '/api/v1/auth/login/'
CATEGORIES_URL = '/api/v1/categories/'
PRODUCTS_URL = '/api/v1/products/'
VARIANTS_URL = '/api/v1/variants/'
VARIANT_UOMS_URL = '/api/v1/variant-uoms/'
SUPPLIERS_URL = '/api/v1/suppliers/'


class CatalogWriteTestBase(InventoryTestBase):
    """One user per role, real logins, and a factor-1 selling unit on the variant."""

    def setUp(self):
        super().setUp()
        self.client = APIClient()
        self.password = get_random_string(16)
        self.stocker = self._make_user('cat_stocker', 'Stock Manager')
        self.manager = self._make_user('cat_manager', 'Store Manager')
        self.cashier = self._make_user('cat_cashier', 'Cashier')
        self.foreman = self._make_user('cat_foreman', 'Site Foreman')
        # A second UOM, so a selling unit can be re-pointed at a DIFFERENT unit.
        self.uom_pc = UnitOfMeasure.objects.create(code='PC', name='Piece')
        self.vuom = VariantUOM.objects.create(
            variant=self.variant, uom=self.uom,
            conversion_factor=Decimal('1'),
            default_selling_price=Decimal('10'),
        )
        self.supplier = Supplier.objects.create(company_name='Acme Supply')
        self.po = PurchaseOrder.objects.create(
            supplier=self.supplier, created_by=self.stocker)

    # -- fixture helpers ---------------------------------------------------
    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username, email=f'{username}@example.com',
            password=self.password, full_name=username)
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _auth(self, user):
        login = APIClient().post(
            LOGIN_URL, {'username': user.username, 'password': self.password},
            format='json')
        self.assertEqual(login.status_code, 200, login.data)
        return {'HTTP_AUTHORIZATION': f'Bearer {login.data["access"]}'}

    def _stock(self, qty='10'):
        """A processed delivery, so the variant has sellable stock."""
        _po, _item, receipt = self._receive(qty)
        process_goods_receipt(receipt=receipt, user=self.stocker)

    def _ring_sale(self, qty=Decimal('1')):
        """Ring a real sale through `process_sale`: the unit becomes REFERENCED."""
        from apps.pos.models import Customer, Shift
        from apps.pos.services import process_sale

        customer, _ = Customer.objects.get_or_create(
            name='Walk-in Customer',
            defaults={'customer_type': Customer.Type.WALK_IN})
        Shift.objects.get_or_create(
            cashier=self.cashier, status=Shift.Status.OPEN,
            defaults={'opening_float': Decimal('500')})
        return process_sale(
            customer_id=customer.pk,
            cashier=self.cashier,
            items_data=[{'variant_id': self.vuom.pk, 'qty': qty}],
            payments_data=[{
                'method': 'CASH',
                'amount_tendered': Decimal('10') * qty,
            }],
        )

    def _writes(self, action_type, contains=None):
        """Audit rows for one action type, optionally filtered by text."""
        rows = AuditLog.objects.filter(action_type=action_type)
        if contains is not None:
            rows = rows.filter(description__contains=contains)
        return rows


class NoDeleteTests(CatalogWriteTestBase):
    """Every catalog row is `PROTECT`-referenced: DELETE answers 405, not 500."""

    def test_catalog_and_purchase_order_deletes_are_method_not_allowed(self):
        targets = [
            ('categories', self.category, Category),
            ('brands', self.brand, Brand),
            ('uoms', self.uom_pc, UnitOfMeasure),
            ('products', self.product, Product),
            ('variants', self.variant, ProductVariant),
            ('variant-uoms', self.vuom, VariantUOM),
            ('suppliers', self.supplier, Supplier),
            ('purchase-orders', self.po, PurchaseOrder),
        ]
        for path, row, model in targets:
            with self.subTest(path=path):
                response = self.client.delete(
                    f'/api/v1/{path}/{row.pk}/', **self._auth(self.stocker))

                self.assertEqual(
                    response.status_code, 405,
                    f'DELETE /{path}/ must be refused: {response.data}')
                self.assertTrue(
                    model.objects.filter(pk=row.pk).exists(),
                    f'the {path} row must still exist')


class CatalogWritePermissionTests(CatalogWriteTestBase):
    """Catalog writes stay `IsInventoryRole`: a cashier and a foreman get 403."""

    def test_cashier_and_foreman_cannot_create_a_product(self):
        body = {
            'category': self.category.pk,
            'brand': self.brand.pk,
            'base_name': 'Bamboo Pole',
        }
        for user in (self.cashier, self.foreman):
            with self.subTest(user=user.username):
                response = self.client.post(
                    PRODUCTS_URL, body, format='json', **self._auth(user))

                self.assertEqual(response.status_code, 403, response.data)

        self.assertEqual(Product.objects.count(), 1)
        self.assertFalse(Product.objects.filter(base_name='Bamboo Pole').exists())


class SellingUnitIntegrityTests(CatalogWriteTestBase):
    """A selling unit's numbers must be usable: > 0 factor, >= 0 price, one base."""

    def _post_unit(self, **overrides):
        body = {
            'variant': self.variant.pk,
            'uom': self.uom_pc.pk,
            'conversion_factor': '12',
            'default_selling_price': '120',
        }
        body.update(overrides)
        return self.client.post(
            VARIANT_UOMS_URL, body, format='json', **self._auth(self.stocker))

    def _patch_unit(self, **overrides):
        body = {'conversion_factor': '12', 'default_selling_price': '120'}
        body.update(overrides)
        return self.client.patch(
            f'{VARIANT_UOMS_URL}{self.vuom.pk}/', body, format='json',
            **self._auth(self.stocker))

    def test_a_zero_conversion_factor_is_refused(self):
        response = self._post_unit(conversion_factor='0')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_SELLING_UNIT',
                         response.data)
        self.assertEqual(VariantUOM.objects.count(), 1)

    def test_a_negative_default_selling_price_is_refused(self):
        response = self._post_unit(default_selling_price='-1')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_SELLING_UNIT',
                         response.data)
        self.assertEqual(VariantUOM.objects.count(), 1)

    def test_a_second_factor_one_unit_on_one_variant_is_refused(self):
        # `self.vuom` is the variant's factor-1 (base) unit already.
        response = self._post_unit(conversion_factor='1', default_selling_price='10')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'DUPLICATE_BASE_UNIT',
                         response.data)
        self.assertEqual(
            VariantUOM.objects.filter(
                variant=self.variant, conversion_factor=1).count(), 1)

    def test_the_factor_of_a_sold_unit_is_frozen(self):
        self._stock()
        self._ring_sale()

        response = self._patch_unit(conversion_factor='2')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'SELLING_UNIT_IN_USE',
                         response.data)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.conversion_factor, Decimal('1'))

    def test_the_uom_of_a_sold_unit_is_frozen(self):
        self._stock()
        self._ring_sale()

        response = self.client.patch(
            f'{VARIANT_UOMS_URL}{self.vuom.pk}/', {'uom': self.uom_pc.pk},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'SELLING_UNIT_IN_USE',
                         response.data)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.uom, self.uom)

    def test_the_price_of_a_sold_unit_stays_editable_and_is_audited(self):
        self._stock()
        self._ring_sale()

        response = self.client.patch(
            f'{VARIANT_UOMS_URL}{self.vuom.pk}/',
            {'default_selling_price': '12.50'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.vuom.refresh_from_db()
        self.assertEqual(self.vuom.default_selling_price, Decimal('12.50'))
        row = self._writes('UPDATE', 'Selling unit')
        self.assertEqual(row.count(), 1, list(row.values_list('description', flat=True)))
        self.assertIn('10.00', row.get().description)
        self.assertIn('12.50', row.get().description)


class VariantIntegrityTests(CatalogWriteTestBase):
    """Thresholds are non-negative and the product/base_uom are set once."""

    def _patch_variant(self, **overrides):
        return self.client.patch(
            f'{VARIANTS_URL}{self.variant.pk}/', overrides, format='json',
            **self._auth(self.stocker))

    def test_a_negative_min_stock_threshold_is_refused(self):
        response = self._patch_variant(min_stock_threshold='-1')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_VARIANT', response.data)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.min_stock_threshold, Decimal('5'))

    def test_a_negative_max_stock_level_is_refused(self):
        response = self._patch_variant(max_stock_level='-5')

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_VARIANT', response.data)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.max_stock_level, Decimal('0'))

    def test_the_product_of_a_variant_is_immutable(self):
        other = Product.objects.create(
            category=self.category, brand=self.brand, base_name='Rebar')

        response = self._patch_variant(product=other.pk)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_VARIANT', response.data)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.product, self.product)

    def test_the_base_uom_of_a_variant_is_immutable(self):
        response = self._patch_variant(base_uom=self.uom_pc.pk)

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get('code'), 'INVALID_VARIANT', response.data)
        self.variant.refresh_from_db()
        self.assertEqual(self.variant.base_uom, self.uom)


class CategoryArchiveTests(CatalogWriteTestBase):
    """Archiving a category hides it from the picker; its products still sell."""

    def test_archiving_a_category_keeps_its_products_sellable(self):
        response = self.client.patch(
            f'{CATEGORIES_URL}{self.category.pk}/', {'is_active': False},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.assertFalse(response.data['is_active'])
        self.category.refresh_from_db()
        self.assertFalse(self.category.is_active)

        self._stock()
        sale = self._ring_sale()

        self.assertEqual(sale.grand_total, Decimal('10'))
        self.assertEqual(sale.items.count(), 1)

    def test_a_new_category_is_active_by_default(self):
        response = self.client.post(
            CATEGORIES_URL, {'name': 'Roofing'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 201, response.data)
        self.assertTrue(response.data['is_active'])

    def test_restoring_an_archived_category_is_a_plain_patch(self):
        self.category.is_active = False
        self.category.save(update_fields=['is_active'])

        response = self.client.patch(
            f'{CATEGORIES_URL}{self.category.pk}/', {'is_active': True},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        self.category.refresh_from_db()
        self.assertTrue(self.category.is_active)


class CatalogAuditTests(CatalogWriteTestBase):
    """One CREATE/UPDATE row per catalog write, and none for a refusal."""

    def test_creating_a_product_writes_one_create_row(self):
        response = self.client.post(
            PRODUCTS_URL,
            {'category': self.category.pk, 'brand': self.brand.pk,
             'base_name': 'Bamboo Pole'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 201, response.data)
        rows = self._writes('CREATE', 'Bamboo Pole')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))
        self.assertEqual(rows.get().user, self.stocker)

    def test_editing_a_product_writes_one_update_row(self):
        response = self.client.patch(
            f'{PRODUCTS_URL}{self.product.pk}/',
            {'description': 'Washed sand, bagged.'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        rows = self._writes('UPDATE', 'Portland Cement')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))

    def test_creating_a_variant_writes_one_create_row(self):
        response = self.client.post(
            VARIANTS_URL,
            {'product': self.product.pk, 'variant_name': '25kg',
             'base_uom': self.uom.pk, 'min_stock_threshold': '5'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 201, response.data)
        rows = self._writes('CREATE', '25kg')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))

    def test_creating_a_selling_unit_writes_one_create_row(self):
        response = self.client.post(
            VARIANT_UOMS_URL,
            {'variant': self.variant.pk, 'uom': self.uom_pc.pk,
             'conversion_factor': '12', 'default_selling_price': '120'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 201, response.data)
        rows = self._writes('CREATE', 'Selling unit')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))

    def test_editing_a_category_writes_one_update_row(self):
        response = self.client.patch(
            f'{CATEGORIES_URL}{self.category.pk}/', {'name': 'Cement & Sand'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 200, response.data)
        rows = self._writes('UPDATE', 'Category')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))

    def test_creating_a_supplier_writes_one_create_row(self):
        response = self.client.post(
            SUPPLIERS_URL, {'company_name': 'Visayas Hardware'}, format='json',
            **self._auth(self.stocker))

        self.assertEqual(response.status_code, 201, response.data)
        rows = self._writes('CREATE', 'Visayas Hardware')
        self.assertEqual(rows.count(), 1, list(rows.values_list('description', flat=True)))

    def test_a_refused_write_writes_no_audit_row(self):
        response = self.client.post(
            VARIANT_UOMS_URL,
            {'variant': self.variant.pk, 'uom': self.uom_pc.pk,
             'conversion_factor': '0', 'default_selling_price': '10'},
            format='json', **self._auth(self.stocker))

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(self._writes('CREATE').count(), 0)
        self.assertEqual(self._writes('UPDATE').count(), 0)
