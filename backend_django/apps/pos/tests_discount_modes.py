# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Phase 2 tests: per-product vs whole-sale discount mutual exclusion and per-line inclusion."""

from decimal import Decimal

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
from apps.pos.models import SalesTransaction
from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase


class DiscountModesTest(DiscountVATBase):
    def setUp(self):
        super().setUp()
        # self.vuom is Portland Cement (10.00 each); mark legacy allow_discount=False
        # to prove Phase 2 no longer blocks discounting by product flag.
        product = self.vuom.variant.product
        product.allow_discount = False
        product.save()

        paint = Product.objects.create(
            category=Category.objects.create(name="Paints"),
            brand=Brand.objects.create(name="Boysen"),
            base_name="Latex Paint",
            allow_discount=True,
        )
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece"}
        )
        variant = ProductVariant.objects.create(
            product=paint, variant_name="White", base_uom=uom
        )
        self.paint = VariantUOM.objects.create(
            variant=variant,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal("20.00"),
        )
        po = PurchaseOrder.objects.create(
            supplier=Supplier.objects.create(company_name="Boysen Supply"),
            created_by=self.cashier,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=variant,
            ordered_qty=Decimal(10),
            unit_cost=Decimal(12),
            received_qty=Decimal(10),
        )
        process_goods_receipt(
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.cashier),
            user=self.cashier,
        )
        self._settings(discount_cap_percent=25, vat_registered=False)

    def _checkout(self, items, *, discount=None, paid="30.00"):
        body = self._sale_body(discount=discount)
        body["items"] = items
        body["payments"][0]["amount_tendered"] = paid
        return self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )

    def test_combining_line_and_whole_sale_discount_is_refused(self):
        res = self._checkout(
            [
                {
                    "variant_id": self.paint.id,
                    "qty": 1,
                    "discount": {"kind": "AMOUNT", "value": "2.00", "reason": "Dented can"},
                },
                {"variant_id": self.vuom.id, "qty": 1},
            ],
            discount={"kind": "PERCENT", "value": "5.00", "reason": "Promo"},
        )
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()["code"], "DISCOUNT_MODE_CONFLICT")
        self.assertEqual(SalesTransaction.objects.count(), 0)

    def test_whole_sale_discount_splits_only_over_included_lines(self):
        # Paint = 20.00 (included), Cement = 10.00 (excluded).
        # 10% whole-sale discount -> 2.00 off Paint only, grand_total = 28.00.
        res = self._checkout(
            [
                {"variant_id": self.paint.id, "qty": 1, "include_in_discount": True},
                {"variant_id": self.vuom.id, "qty": 1, "include_in_discount": False},
            ],
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Regular buyer"},
            paid="28.00",
        )
        self.assertEqual(res.status_code, 201, res.content)
        data = res.json()
        self.assertEqual(Decimal(data["discount_amount"]), Decimal("2.00"))
        self.assertEqual(Decimal(data["grand_total"]), Decimal("28.00"))
        txn = SalesTransaction.objects.get(pk=data["id"])
        shares = {item.variant_uom_id: item.cart_discount_amount for item in txn.items.all()}
        self.assertEqual(shares[self.paint.id], Decimal("2.00"))
        self.assertEqual(shares[self.vuom.id], Decimal("0.00"))

    def test_whole_sale_discount_with_all_lines_excluded_is_refused(self):
        res = self._checkout(
            [
                {"variant_id": self.paint.id, "qty": 1, "include_in_discount": False},
                {"variant_id": self.vuom.id, "qty": 1, "include_in_discount": False},
            ],
            discount={"kind": "AMOUNT", "value": "2.00", "reason": "Promo"},
        )
        self.assertEqual(res.status_code, 400, res.content)
        self.assertEqual(res.json()["code"], "INVALID_DISCOUNT")

    def test_whole_sale_discount_defaults_to_all_lines_included_even_if_allow_discount_false(self):
        # Paint = 20.00, Cement (allow_discount=False) = 10.00 -> gross 30.00.
        # 10% whole-sale discount = 3.00 (2.00 on Paint, 1.00 on Cement).
        res = self._checkout(
            [
                {"variant_id": self.paint.id, "qty": 1},
                {"variant_id": self.vuom.id, "qty": 1},
            ],
            discount={"kind": "PERCENT", "value": "10.00", "reason": "Bulk"},
            paid="27.00",
        )
        self.assertEqual(res.status_code, 201, res.content)
        data = res.json()
        self.assertEqual(Decimal(data["discount_amount"]), Decimal("3.00"))
        txn = SalesTransaction.objects.get(pk=data["id"])
        shares = {item.variant_uom_id: item.cart_discount_amount for item in txn.items.all()}
        self.assertEqual(shares[self.paint.id], Decimal("2.00"))
        self.assertEqual(shares[self.vuom.id], Decimal("1.00"))

    def test_line_discount_allowed_even_when_product_allow_discount_is_false(self):
        res = self._checkout(
            [
                {
                    "variant_id": self.vuom.id,
                    "qty": 2,
                    "discount": {"kind": "AMOUNT", "value": "2.00", "reason": "Torn bag"},
                },
            ],
            paid="18.00",
        )
        self.assertEqual(res.status_code, 201, res.content)
        data = res.json()
        self.assertEqual(Decimal(data["discount_amount"]), Decimal("2.00"))
        self.assertEqual(Decimal(data["grand_total"]), Decimal("18.00"))
