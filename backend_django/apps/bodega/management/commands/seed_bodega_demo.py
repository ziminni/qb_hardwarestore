# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Demo data for the Bodega module (decision 25). Idempotent; safe on a live dev DB.

Goes through the REAL services - receiving, the till, the Bodega release and count -
so every figure on the checker's screens is one the system computed:

* five bulk products whose home is the Bodega, received onto the Bodega shelf;
* three paid sales that took them from the Bodega (one partly collected, one fully
  collected, one not collected yet);
* one supplier delivery (gravel, hollow blocks) waiting for the checker.

Skipped when the product "Gravel" already exists.
"""

from decimal import ROUND_UP, Decimal

from django.contrib.auth.models import Group
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.bodega.models import BodegaDelivery
from apps.bodega.services import confirm_delivery, record_release
from apps.inventory.models import (
    BODEGA_LOCATION_NAME,
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    Supplier,
    UnitOfMeasure,
    VariantUOM,
    storage_location,
)
from apps.inventory.services import process_goods_receipt
from apps.pos.models import Customer, Shift
from apps.pos.services import process_sale
from apps.users.models import User

PASSWORD = "demo1234"

# product, variant, category, unit, cost, price, received, reorder level
CATALOG = [
    ("Gravel", "3/4 inch", "Aggregates", "CU.M", "950.00", "1350.00", "40", "8"),
    ("Washed Sand", "Fine", "Aggregates", "CU.M", "800.00", "1150.00", "35", "8"),
    (
        "Mixed Aggregates",
        "Sand & gravel",
        "Aggregates",
        "CU.M",
        "850.00",
        "1250.00",
        "25",
        "5",
    ),
    ("Hollow Blocks", "4 inch", "Masonry", "PC", "11.00", "16.00", "2000", "300"),
    ("Hollow Blocks", "6 inch", "Masonry", "PC", "15.00", "22.00", "1200", "200"),
]


class Command(BaseCommand):
    help = "Seed Bodega demo products, sales, releases and a delivery to check (idempotent)."

    def handle(self, *args, **options):
        if Product.objects.filter(base_name="Gravel").exists():
            if BodegaDelivery.objects.exists():
                self.stdout.write("Bodega demo already present - skipped")
                return
            # Seeded before delivery checks existed: add only the truck to check.
            with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
                bodega = storage_location(BODEGA_LOCATION_NAME)
                stocker = User.objects.filter(groups__name="Stock Manager").first()
                units = {
                    (v.variant.product.base_name, v.variant.variant_name): (
                        v,
                        POItem.objects.filter(variant=v.variant).first().unit_cost,
                        None,
                    )
                    for v in VariantUOM.objects.filter(
                        variant__product__base_name__in=["Gravel", "Hollow Blocks"]
                    ).select_related("variant__product")
                }
                self._new_delivery(units, bodega, stocker)
            self.stdout.write(self.style.SUCCESS("Bodega delivery to check added"))
            return
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            bodega = storage_location(BODEGA_LOCATION_NAME)
            if not bodega.is_bodega:
                bodega.is_bodega = True
                bodega.save(update_fields=["is_bodega"])
            checker = self._user("checker", "Bodega Checker", "Bodega Checker")
            stocker = (
                User.objects.filter(groups__name="Stock Manager").first() or checker
            )
            cashier = User.objects.filter(username="cashier").first() or self._user(
                "cashier", "Cashi Er", "Cashier"
            )
            units = self._catalog(bodega)
            self._receive(units, bodega, stocker)
            self._confirm_all_good(checker)
            sales = self._sell(units, cashier)
            self._release(sales, units, bodega, checker)
            self._new_delivery(units, bodega, stocker)
        self.stdout.write(self.style.SUCCESS("Bodega demo seeded"))

    def _user(self, username, full_name, group):
        user, created = User.objects.get_or_create(
            username=username,
            defaults={"full_name": full_name, "email": f"{username}@demo.ph"},
        )
        if created:
            user.set_password(PASSWORD)
            user.save()
        user.groups.add(Group.objects.get_or_create(name=group)[0])
        return user

    def _catalog(self, bodega):
        cubic, _ = UnitOfMeasure.objects.get_or_create(
            code="CU.M", defaults={"name": "Cubic meter", "is_whole": False}
        )
        piece = UnitOfMeasure.objects.get(code="PC")
        brand, _ = Brand.objects.get_or_create(name="Local Supply")
        units = {}
        for name, variant_name, cat, unit, cost, price, qty, reorder in CATALOG:
            category, _ = Category.objects.get_or_create(name=cat)
            product, _ = Product.objects.get_or_create(
                base_name=name,
                defaults={"category": category, "brand": brand, "stored_at": bodega},
            )
            variant = ProductVariant.objects.create(
                product=product,
                variant_name=variant_name,
                base_uom=cubic if unit == "CU.M" else piece,
                min_stock_threshold=Decimal(reorder),
            )
            vuom = VariantUOM.objects.create(
                variant=variant,
                uom=variant.base_uom,
                conversion_factor=Decimal(1),
                default_selling_price=Decimal(price),
            )
            units[(name, variant_name)] = (vuom, Decimal(cost), Decimal(qty))
        return units

    def _receive(self, units, bodega, stocker):
        supplier, _ = Supplier.objects.get_or_create(
            company_name="Mactan Aggregates & CHB Supply",
            defaults={"contact_person": "Nonoy Abella", "phone": "0917-333-4444"},
        )
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=stocker, status=PurchaseOrder.Status.ORDERED
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=stocker)
        for vuom, cost, qty in units.values():
            item = POItem.objects.create(
                po=po,
                variant=vuom.variant,
                variant_uom=vuom,
                ordered_qty=qty,
                unit_cost=cost,
                received_qty=qty,
            )
            GoodsReceiptItem.objects.create(
                receipt=receipt, po_item=item, qty=qty, location=bodega
            )
        process_goods_receipt(receipt=receipt, user=stocker)

    def _sell(self, units, cashier):
        if not Shift.objects.filter(cashier=cashier, status=Shift.Status.OPEN).exists():
            Shift.objects.create(cashier=cashier, opening_float=Decimal(5000))
        walk_in = Customer.objects.filter(name="Walk-in Customer").first()
        contractor = Customer.objects.filter(name="Dela Cruz Construction").first()
        maria = Customer.objects.filter(name="Maria Santos").first()
        default = walk_in or Customer.objects.create(name="Walk-in Customer")
        plan = {
            "contractor": (
                contractor or default,
                [(("Gravel", "3/4 inch"), 6), (("Hollow Blocks", "4 inch"), 400)],
            ),
            "maria": (maria or default, [(("Washed Sand", "Fine"), 2)]),
            "walk_in": (default, [(("Hollow Blocks", "6 inch"), 150)]),
            "waiting": (
                contractor or default,
                [
                    (("Mixed Aggregates", "Sand & gravel"), 4),
                    (("Gravel", "3/4 inch"), 3),
                ],
            ),
        }
        sales = {}
        for key, (customer, lines) in plan.items():
            total = sum(
                units[product][0].default_selling_price * qty for product, qty in lines
            )
            tendered = (total / 1000).quantize(Decimal(1), rounding=ROUND_UP) * 1000
            sales[key] = process_sale(
                customer_id=customer.pk,
                cashier=cashier,
                items_data=[
                    {"variant_id": units[product][0].pk, "qty": qty}
                    for product, qty in lines
                ],
                payments_data=[{"method": "CASH", "amount_tendered": tendered}],
            )
        return sales

    def _release(self, sales, units, bodega, checker):
        gravel = units[("Gravel", "3/4 inch")][0].variant
        blocks4 = units[("Hollow Blocks", "4 inch")][0].variant
        blocks6 = units[("Hollow Blocks", "6 inch")][0].variant
        sand = units[("Washed Sand", "Fine")][0].variant
        # Contractor: first trip took half the gravel and all the blocks.
        record_release(
            sale=sales["contractor"],
            checker=checker,
            received_by="Jun Reyes (driver)",
            plate_no="GAB 4521",
            notes="First trip",
            lines=[(gravel, bodega, Decimal(3)), (blocks4, bodega, Decimal(400))],
        )
        # Walk-in: everything collected at once.
        record_release(
            sale=sales["walk_in"],
            checker=checker,
            received_by="Carlo Mendoza",
            plate_no="",
            notes="",
            lines=[(blocks6, bodega, Decimal(150))],
        )
        # Maria Santos: one of two cubic metres so far.
        record_release(
            sale=sales["maria"],
            checker=checker,
            received_by="Maria Santos",
            plate_no="NBC 1180",
            notes="Will return for the rest",
            lines=[(sand, bodega, Decimal(1))],
        )

    def _confirm_all_good(self, checker):
        """The opening stock arrived whole: the checker confirms it as delivered."""
        for delivery in BodegaDelivery.objects.filter(
            status=BodegaDelivery.Status.PENDING
        ):
            confirm_delivery(
                delivery_id=delivery.pk,
                checker=checker,
                lines={
                    line.pk: (line.delivered_qty, Decimal(0), "")
                    for line in delivery.lines.all()
                },
                notes="Opening stock",
            )

    def _new_delivery(self, units, bodega, stocker):
        """Next truck: gravel and hollow blocks, recorded by the stocker, NOT yet checked."""
        supplier = Supplier.objects.get(company_name="Mactan Aggregates & CHB Supply")
        po = PurchaseOrder.objects.create(
            supplier=supplier, created_by=stocker, status=PurchaseOrder.Status.ORDERED
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=stocker)
        for key, qty in (
            (("Gravel", "3/4 inch"), Decimal(20)),
            (("Hollow Blocks", "4 inch"), Decimal(1000)),
        ):
            vuom, cost, _ = units[key]
            item = POItem.objects.create(
                po=po,
                variant=vuom.variant,
                variant_uom=vuom,
                ordered_qty=qty,
                unit_cost=cost,
                received_qty=qty,
            )
            GoodsReceiptItem.objects.create(
                receipt=receipt, po_item=item, qty=qty, location=bodega
            )
        process_goods_receipt(receipt=receipt, user=stocker)
