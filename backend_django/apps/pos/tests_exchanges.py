# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false

"""Phase 3 tests: returns become exchanges (extra pay, even swap, utang/store credit)."""

from decimal import Decimal

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
from apps.pos.models import Payment, SalesTransaction
from apps.pos.tests_discount_vat import TRANSACTIONS_URL, DiscountVATBase

EXCHANGE_URL = "/api/v1/transactions/exchange/"


class ExchangeFlowTests(DiscountVATBase):
    def setUp(self):
        super().setUp()
        self._settings(discount_cap_percent=10, vat_registered=False)

        # Replacement item B: costs 15.00 (more expensive than self.vuom @ 10.00)
        cat = Category.objects.create(name="Tools")
        brand = Brand.objects.create(name="Stanley")
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="PC", defaults={"name": "Piece"}
        )

        prod_hi = Product.objects.create(
            category=cat, brand=brand, base_name="Heavy Hammer"
        )
        var_hi = ProductVariant.objects.create(
            product=prod_hi, variant_name="2lb", base_uom=uom
        )
        self.expensive = VariantUOM.objects.create(
            variant=var_hi,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal("15.00"),
        )

        # Replacement item C: costs 6.00 (cheaper than self.vuom @ 10.00)
        prod_lo = Product.objects.create(
            category=cat, brand=brand, base_name="Small Nails"
        )
        var_lo = ProductVariant.objects.create(
            product=prod_lo, variant_name="Pack", base_uom=uom
        )
        self.cheap = VariantUOM.objects.create(
            variant=var_lo,
            uom=uom,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal("6.00"),
        )

        supplier = Supplier.objects.create(company_name="Hardware Depot")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.cashier,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po, variant=var_hi, ordered_qty=10, unit_cost=8, received_qty=10
        )
        POItem.objects.create(
            po=po, variant=var_lo, ordered_qty=10, unit_cost=3, received_qty=10
        )
        process_goods_receipt(
            receipt=GoodsReceipt.objects.create(po=po, received_by=self.cashier),
            user=self.cashier,
        )

    def _make_sale(self, *, qty=2, paid="20.00"):
        body = self._sale_body()
        body["items"] = [{"variant_id": self.vuom.id, "qty": qty}]
        body["payments"] = [{"method": "CASH", "amount_tendered": paid}]
        res = self.client.post(
            TRANSACTIONS_URL, body, format="json", **self.cashier_auth
        )
        self.assertEqual(res.status_code, 201, res.content)
        return SalesTransaction.objects.get(pk=res.json()["id"])

    def test_more_expensive_exchange_charges_difference_and_gives_change(self):
        orig = self._make_sale(qty=1, paid="10.00")
        res = self.client.post(
            EXCHANGE_URL,
            {
                "original_transaction": orig.id,
                "return_items": [{"variant_id": self.vuom.id, "qty": 1}],
                "replacement_items": [{"variant_id": self.expensive.id, "qty": 1}],
                "payment_method": "CASH",
                "amount_tendered": "10.00",
                "reason": "Customer wants heavier hammer",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 201, res.content)
        data = res.json()
        summary = data["exchange_summary"]
        self.assertEqual(data["source"], "EXCHANGE")
        self.assertEqual(summary["return_credit"], "10.00")
        self.assertEqual(summary["replacement_total"], "15.00")
        self.assertEqual(summary["net_difference"], "5.00")
        self.assertEqual(summary["extra_paid"], "10.00")
        self.assertEqual(summary["change_given"], "5.00")
        self.assertEqual(summary["store_credit_issued"], "0.00")
        self.assertEqual(
            Payment.objects.filter(transaction_id=data["id"]).count(), 1
        )

    def test_cheaper_exchange_without_utang_issues_store_credit_not_cash(self):
        orig = self._make_sale(qty=1, paid="10.00")
        res = self.client.post(
            EXCHANGE_URL,
            {
                "original_transaction": orig.id,
                "return_items": [{"variant_id": self.vuom.id, "qty": 1}],
                "replacement_items": [{"variant_id": self.cheap.id, "qty": 1}],
                "reason": "Swapped to smaller pack",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 201, res.content)
        data = res.json()
        summary = data["exchange_summary"]
        self.assertEqual(summary["net_difference"], "-4.00")
        self.assertEqual(summary["debt_reduced"], "0.00")
        self.assertEqual(summary["store_credit_issued"], "4.00")
        self.assertEqual(summary["customer_store_credit_balance"], "4.00")
        # Zero cash left the drawer!
        self.assertEqual(
            Payment.objects.filter(transaction_id=data["id"]).count(), 0
        )
        self.customer.refresh_from_db()
        self.assertEqual(self.customer.store_credit_balance, Decimal("4.00"))

    def test_cheaper_exchange_with_utang_reduces_debt_first_then_store_credit(self):
        from apps.pos.models import Customer

        self.customer.customer_type = Customer.Type.REGULAR
        self.customer.save(update_fields=["customer_type"])
        # Sale of 2 x 10.00 = 20.00; customer paid 18.00 -> 2.00 utang on ledger.
        orig = self._make_sale(qty=2, paid="18.00")
        ledger = CollectibleLedger.objects.get(transaction=orig)
        self.assertEqual(ledger.balance_due, Decimal("2.00"))

        # Return 1 item (10.00) for 1 cheap item (6.00) -> 4.00 excess:
        # 2.00 clears the utang, remaining 2.00 becomes store credit!
        res = self.client.post(
            EXCHANGE_URL,
            {
                "original_transaction": orig.id,
                "return_items": [{"variant_id": self.vuom.id, "qty": 1}],
                "replacement_items": [{"variant_id": self.cheap.id, "qty": 1}],
                "reason": "Swapped item",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(res.status_code, 201, res.content)
        summary = res.json()["exchange_summary"]
        self.assertEqual(summary["debt_reduced"], "2.00")
        self.assertEqual(summary["store_credit_issued"], "2.00")
        self.assertEqual(summary["customer_store_credit_balance"], "2.00")
        ledger.refresh_from_db()
        self.assertEqual(ledger.balance_due, Decimal("0.00"))

    def test_already_exchanged_qty_cannot_be_exchanged_or_returned_again(self):
        orig = self._make_sale(qty=1, paid="10.00")
        first = self.client.post(
            EXCHANGE_URL,
            {
                "original_transaction": orig.id,
                "return_items": [{"variant_id": self.vuom.id, "qty": 1}],
                "replacement_items": [{"variant_id": self.cheap.id, "qty": 1}],
                "reason": "First swap",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(first.status_code, 201, first.content)

        second = self.client.post(
            EXCHANGE_URL,
            {
                "original_transaction": orig.id,
                "return_items": [{"variant_id": self.vuom.id, "qty": 1}],
                "replacement_items": [{"variant_id": self.cheap.id, "qty": 1}],
                "reason": "Duplicate swap",
            },
            format="json",
            **self.cashier_auth,
        )
        self.assertEqual(second.status_code, 400, second.content)
        self.assertEqual(second.json()["code"], "RETURN_QTY_EXCEEDED")
