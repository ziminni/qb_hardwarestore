# pyright: reportAttributeAccessIssue=false, reportGeneralTypeIssues=false
#
# Same reason as apps/inventory/views.py: the checker resolves its config from its
# WORKING DIRECTORY and does not run inside this repo here, so a pyrightconfig.json is
# not found. This travels with the file. It disables the one rule that cannot model
# Django's `Model.objects`/`BaseCommand.style` without django-stubs.
#
# `reportGeneralTypeIssues` covers `with db_txn.atomic():`, which reads as a function
# call rather than a context manager for the same missing-stubs reason.
import uuid
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import Group
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    BODEGA_LOCATION_NAME,
    STORE_LOCATION_NAME,
    Brand,
    Category,
    GoodsReceipt,
    GoodsReceiptItem,
    InventoryBatch,
    POItem,
    Product,
    ProductVariant,
    PurchaseOrder,
    StockAdjustment,
    StockTransfer,
    Supplier,
    UnitOfMeasure,
    storage_location,
)
from apps.inventory.services import (
    allocate_fifo,
    apply_stock_adjustment,
    process_goods_receipt,
)
from apps.inventory.transfers import record_stock_transfer
from apps.pos.models import Customer
from apps.pos.services import process_sale
from apps.requisitions.models import Requisition
from apps.requisitions.services import (
    accept_requisition,
    decline_requisition,
    import_request,
    release_materials,
)
from apps.users.models import User

PASSWORD = "demo1234"
# Decision 09: a demo whole-Decline always carries the reason the staff screen demands.
DECLINE_REASON = "Cannot supply this request: the items are out of season."
ROLES = [
    "System Administrator",
    "Store Manager",
    "Stock Manager",
    "Cashier",
    # Phase 1 (decision 02): the group CPMS's service account lives in. It is not a
    # POS role - the fence in `apps/users/authentication.py` keeps it inside
    # `/api/v1/integration/cpms/` - and the foreman role is gone (decision 01).
    "CPMS Service",
]

USERS = [
    # username, full_name, group, is_superuser, is_staff
    ("admin", "Ada Ministrator", "System Administrator", True, True),
    ("manager", "Mana Ger", "Store Manager", False, False),
    ("stocker", "Stock Er", "Stock Manager", False, False),
    ("cashier", "Cashi Er", "Cashier", False, False),
    # Decision 02: the machine account CPMS logs in as. Not staff, not a superuser.
    ("cpms_service", "CPMS Service", "CPMS Service", False, False),
]

# The ONE seeded product the demo keeps in the Bodega instead of the Store, so the till
# badge, the receipt line and the delivery slip all have a real "Bodega" to show
# (Phase 5 B4, decision 18).
BODEGA_DEMO_PRODUCT = "GI Sheet Plain"

# Phase 9 B5 (decision 21 §3): ONE demo transfer slip, so the transfers screen starts on a
# real `TR-…` document instead of an empty list. The Stocker moves these from the Store
# shelf to the Bodega shelf through `record_stock_transfer` - the same service the screen
# calls - which is also what gives a Store-home product a Bodega on-hand row.
DEMO_TRANSFER_PRODUCT = "Faucet"
DEMO_TRANSFER_VARIANT = "Standard"
DEMO_TRANSFER_QTY = Decimal(10)

# category, brand, product, [(variant_name, unit_cost, selling_price), ...]
CATALOG = [
    (
        "Cement",
        "Rhino",
        "Portland Cement",
        [
            ("40kg", Decimal(215), Decimal(260)),
            ("50kg", Decimal(265), Decimal(320)),
        ],
    ),
    (
        "Steel",
        "SteelCore",
        "GI Sheet Plain",
        [
            ("0.9mm x 1.8m", Decimal(480), Decimal(560)),
        ],
    ),
    (
        "Plumbing",
        "FlowPro",
        "PVC Pipe",
        [
            ("1/2 inch x 3m", Decimal(95), Decimal(118)),
            ("4 inch x 3m", Decimal(385), Decimal(450)),
        ],
    ),
    (
        "Plumbing",
        "FlowPro",
        "Faucet",
        [
            ("Standard", Decimal(180), Decimal(225)),
        ],
    ),
    (
        "Electrical",
        "VoltEdge",
        "Electrical Wire",
        [
            ("2.0mm THHN (roll)", Decimal(1250), Decimal(1480)),
        ],
    ),
    (
        "Electrical",
        "VoltEdge",
        "Circuit Breaker",
        [
            ("20A 1-pole", Decimal(260), Decimal(315)),
        ],
    ),
]

# Phase 1d Task 4 (decisions 15/16): ONE demo product sold by a base unit and a real
# package, so the screens can show "1 Bag = 25 kg" without inventing data. Numbers are
# chosen to be readable, not to match a supplier: 25 kg at 11.00/kg inside the bag is
# cheaper than the 12.00/kg loose price, which is why a buyer picks the bag. The
# category and brand are the catalog's own rows - this step adds master data, not a
# second Cement or Rhino.
PACKAGING = {
    "category": "Cement",
    "brand": "Rhino",
    "product": "Tile Adhesive",
    "variant": "Standard",
    "base_unit": ("KG", "Kilogram"),
    "base_price": Decimal("12.00"),  # per kg, loose
    "bag_unit": ("BAG", "Bag"),
    "bag_factor": Decimal(25),  # 1 bag = 25 kg
    "bag_price": Decimal("275.00"),  # 25 x 11.00/kg
    "unit_cost": Decimal("9.00"),  # per kg, what Cebu Building Supply charged
    "stock": Decimal(250),  # kg received in one delivery
}


class Command(BaseCommand):
    help = "Seed realistic demo data (idempotent)."

    def handle(self, *args, **options):
        self._seed_groups()
        users = self._seed_users()
        self._seed_locations()
        variants = self._seed_catalog()
        self._seed_stock(users["stocker"], variants)
        self._seed_transfer(users["stocker"])
        self._seed_adjustments(users["stocker"], variants)
        self._seed_customers()
        customers = {c.name: c for c in Customer.objects.all()}
        self._seed_sales(users["cashier"], variants, customers)
        self._seed_requisitions(users, variants, customers)
        self._seed_packaging(users["stocker"], variants)
        self._print_review_instructions()
        self._print_summary(users)

    def _seed_groups(self):
        for name in ROLES:
            Group.objects.get_or_create(name=name)
        self.stdout.write(self.style.MIGRATE_HEADING("Groups ensured"))

    def _seed_locations(self):
        """Store + Bodega (Phase 5 B4, decision 18), restored after a flush.

        Migration 0011 creates both, and `flush` removes them again - exactly like the
        standard units `_seed_catalog` restores - so the demo puts them back. Idempotent
        and case-insensitive through `storage_location`, the same helper the FK default
        uses, so a re-run cannot invent a second spelling.
        """
        for name in (STORE_LOCATION_NAME, BODEGA_LOCATION_NAME):
            storage_location(name)
        self.stdout.write(self.style.MIGRATE_HEADING("Storage locations ensured"))

    def _seed_users(self):
        users = {}
        for username, full_name, group, is_super, is_staff in USERS:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={
                    "full_name": full_name,
                    "email": f"{username}@demo.ph",
                    "is_superuser": is_super,
                    "is_staff": is_staff,
                },
            )
            if created:
                user.set_password(PASSWORD)
                user.save()
                self.stdout.write(f"  + user {username} ({group})")
            group_obj, _ = Group.objects.get_or_create(name=group)
            user.groups.add(group_obj)
            users[username] = user
        return users

    def _seed_catalog(self):
        variants = {}
        if Category.objects.filter(name="Cement").exists():
            self.stdout.write(self.style.WARNING("Catalog already seeded - skipping"))
            # Keyed by (product, variant name): two products can ship a variant called
            # "Standard" (Phase 6 B6, decision 22 item 17).
            for v in ProductVariant.objects.select_related("product"):
                variants[(v.product.base_name, v.variant_name)] = {"variant": v}
            return variants
        uoms = {}
        # Flush removes migration seed rows; restore the same standard list.
        for code, name, whole in [
            ("PC", "Piece", True),
            ("BAG", "Bag", True),
            ("BOX", "Box", True),
            ("PACK", "Pack", True),
            ("ROLL", "Roll", True),
            ("SHEET", "Sheet", True),
            ("KG", "Kilogram", False),
            ("G", "Gram", False),
            ("M", "Metre", False),
            ("CM", "Centimetre", False),
            ("L", "Litre", False),
            ("ML", "Millilitre", False),
        ]:
            unit = UnitOfMeasure.objects.filter(code__iexact=code).first()
            if unit is None and code == "ROLL":
                unit = UnitOfMeasure.objects.filter(code__iexact="RL").first()
            if unit is None:
                unit = UnitOfMeasure.objects.create(
                    code=code, name=name, is_whole=whole
                )
            uoms[code] = unit
        for cat_name, brand_name, prod_name, vs in CATALOG:
            cat, _ = Category.objects.get_or_create(name=cat_name)
            brand, _ = Brand.objects.get_or_create(name=brand_name)
            product, _ = Product.objects.get_or_create(
                category=cat, brand=brand, base_name=prod_name
            )
            for v_name, cost, price in vs:
                variant, _ = ProductVariant.objects.get_or_create(
                    product=product,
                    variant_name=v_name,
                    defaults={
                        "base_uom": uoms["PC"],
                        "min_stock_threshold": Decimal(20),
                    },
                )
                vuom, _ = variant.selling_uoms.get_or_create(
                    uom=variant.base_uom,
                    defaults={
                        "conversion_factor": Decimal(1),
                        "default_selling_price": price,
                    },
                )
                # Decision 04: a requisition line keys on the selling unit, so the
                # demo requests quote the base unit CPMS would have been shown.
                # (product, variant name) - see the skip branch above.
                variants[(prod_name, v_name)] = {
                    "variant": variant,
                    "vuom": vuom,
                    "cost": cost,
                }
            # Phase 5 B4 (decision 18): ONE seeded product lives in the Bodega; every
            # other product keeps the model default, Store. Only this column is written
            # and the value is constant, so a re-run changes nothing.
            #
            # Saved through the INSTANCE, not `filter().update()` (Phase 9 B5): the
            # queryset update left the in-memory `product` pointing at the Store, and
            # `_seed_adjustments` reads `variant.product.stored_at` off this very object.
            # The Bodega product's count correction therefore landed on a NEW Store
            # batch (a copy of its Bodega delivery) while its deliveries sat in the
            # Bodega - the demo showed the same product on two shelves for no reason.
            if prod_name == BODEGA_DEMO_PRODUCT:
                product.stored_at = storage_location(BODEGA_LOCATION_NAME)
                product.save(update_fields=["stored_at"])
        self.stdout.write(
            self.style.SUCCESS(f"Catalog seeded ({len(variants)} variants)")
        )
        return variants

    @staticmethod
    def _base_unit(variant):
        """The variant's REAL base selling unit (`uom == base_uom`, factor 1)."""
        return variant.selling_uoms.filter(
            uom=variant.base_uom, conversion_factor=1
        ).first()

    def _seed_stock(self, stocker, variants):
        if PurchaseOrder.objects.exists():
            self.stdout.write(self.style.WARNING("Stock already seeded - skipping"))
            return
        supplier, _ = Supplier.objects.get_or_create(
            company_name="Cebu Building Supply",
            defaults={"contact_person": "Lito Ramos", "phone": "0917-111-2222"},
        )
        low_stock_variant = None
        for i, (_v_name, info) in enumerate(variants.items()):
            po = PurchaseOrder.objects.create(
                supplier=supplier,
                created_by=stocker,
                status=PurchaseOrder.Status.ORDERED,
                expected_delivery=timezone.localdate() + timedelta(days=7),
            )
            item = POItem.objects.create(
                po=po,
                variant=info["variant"],
                # Phase 5 B1: the line names its selling unit. The demo buys in the
                # variant's BASE unit (decision 18 keeps base purchasing meaning), so
                # the row is tagged with that same base unit and "100" still means 100
                # base units. A catalog-seeded run may not carry `vuom`; the base row is
                # looked up then, and a missing row is left null (read as the base unit).
                variant_uom=info.get("vuom") or self._base_unit(info["variant"]),
                ordered_qty=Decimal(100),
                unit_cost=info["cost"],
                received_qty=Decimal(100),
            )
            receipt = GoodsReceipt.objects.create(po=po, received_by=stocker)
            if info["variant"].product.base_name == BODEGA_DEMO_PRODUCT:
                # Phase 9 B5 (decision 21 §7, plan Design 7): the Bodega product's
                # delivery NAMES its destination shelf, the way the receiving screen
                # does. That takes the per-line path `process_goods_receipt` already
                # follows for every real delivery, so the Bodega stock in the demo is
                # received stock rather than a batch written by hand. The line's qty is
                # the same 100 base units the legacy no-lines path would have minted,
                # so no seeded number moves.
                GoodsReceiptItem.objects.create(
                    receipt=receipt,
                    po_item=item,
                    qty=Decimal(100),
                    location=storage_location(BODEGA_LOCATION_NAME),
                )
            process_goods_receipt(receipt=receipt, user=stocker)
            if i == 0:
                low_stock_variant = info["variant"]
        # Force one low-stock scenario for the dashboard/alerts demo.
        if low_stock_variant:
            from django.db import transaction as db_txn

            with db_txn.atomic():
                allocate_fifo(variant_id=low_stock_variant.pk, qty_needed=Decimal(90))
        self.stdout.write(self.style.SUCCESS("Stock batches seeded (FIFO)"))

    def _seed_adjustments(self, stocker, variants):
        """Record stock adjustments through the REAL service path.

        Two jobs at once, which is why it goes through the service rather than
        creating rows directly:

        * the movements screen reads `GET /api/v1/adjustments/`, which was empty; and
        * `apply_stock_adjustment` ends by calling `_check_low_stock`, so these
          adjustments also generate the `SystemAlert` rows the low-stock screen reads.

        That second job fixes a gap this command had all along: `_seed_stock`
        deliberately drives variant 1 down to 6 units against a threshold of 20 —
        a genuine low-stock situation — but `allocate_fifo` never checks
        thresholds, so no alert was ever raised for it. The data warranted an
        alert and `/api/v1/alerts/` was empty.
        """
        if StockAdjustment.objects.exists():
            self.stdout.write(
                self.style.WARNING("Adjustments already seeded - skipping")
            )
            return

        # (adjustment_type, qty, remarks) - one of each type the UI filters on,
        # with the first landing on the variant _seed_stock took below threshold.
        plan = [
            ("SHRINKAGE", Decimal(-3), "Broken in transit."),
            ("DAMAGE", Decimal(-2), "Water damage in storage."),
            ("CORRECTION", Decimal(4), "Cycle count correction."),
            ("RETURN", Decimal(-1), "Returned to supplier."),
            ("SHRINKAGE", Decimal(-5), "Unaccounted loss."),
        ]
        from django.db.models import Sum

        made = 0
        # The first adjustment must land on the variant that is ACTUALLY below its
        # threshold, because that is what makes `_check_low_stock` raise the
        # LOW_STOCK alert the low-stock screen reads.
        #
        # Chosen by QUERY, not by dict order. An earlier version paired the plan
        # with `zip(plan, variants.values())` and assumed its first value was the
        # low-stock variant. It was not: the adjustments landed on variants
        # 4, 3, 6, 7 and 8, the one variant genuinely below threshold was never
        # touched, and `/api/v1/adjustments/` filled up while `/api/v1/alerts/`
        # stayed empty. Found by running the command and probing both endpoints -
        # it is not visible by reading the code.
        below_threshold = None
        for info in variants.values():
            candidate = info["variant"]
            live = (
                InventoryBatch.objects.filter(
                    variant=candidate, current_qty__gt=0
                ).aggregate(total=Sum("current_qty"))["total"]
                or 0
            )
            if (
                candidate.min_stock_threshold > 0
                and live < candidate.min_stock_threshold
            ):
                below_threshold = candidate
                break

        targets = [info["variant"] for info in variants.values()]
        if below_threshold is not None:
            targets.remove(below_threshold)
            targets.insert(0, below_threshold)

        # `apply_stock_adjustment` routes removals through `allocate_fifo`, which
        # uses `select_for_update` — that raises TransactionManagementError
        # outside a transaction. `_seed_stock` wraps its own call for the same
        # reason. Found by actually running the command, not by reading it.
        from django.db import transaction as db_txn

        with db_txn.atomic():
            for (adjustment_type, qty, remarks), variant in zip(
                plan, targets, strict=False
            ):
                adjustment = StockAdjustment.objects.create(
                    variant=variant,
                    user=stocker,
                    adjustment_type=adjustment_type,
                    qty_adjusted=qty,
                    remarks=remarks,
                    # Phase 9 B1 (decision 21 §1): a seeded count is booked against the
                    # variant's home shelf, the same rule the adjustment API stamps.
                    location=variant.product.stored_at,
                )
                apply_stock_adjustment(adjustment=adjustment)
                made += 1
        self.stdout.write(self.style.SUCCESS(f"{made} stock adjustments seeded"))

    def _seed_transfer(self, stocker):
        """ONE demo transfer slip: Store -> Bodega through the real service (Phase 9 B5).

        Decision 21 §3 makes a transfer the only way stock changes shelf, so the demo
        needs a real one or the transfers screen starts empty and there is no `TR-…`
        number to show. It goes through `record_stock_transfer` - the same writer the
        screen calls - so the slip, its lines and the batch-to-batch moves are the ones
        a stocker would have produced; a batch written by hand would skip the numbered
        contract and the low-stock re-check.

        Its own guard, like every other half of this command: with a transfer already
        stored, a re-run changes nothing.
        """
        if StockTransfer.objects.exists():
            self.stdout.write(self.style.WARNING("Transfer already seeded - skipping"))
            return
        variant = ProductVariant.objects.get(
            product__base_name=DEMO_TRANSFER_PRODUCT,
            variant_name=DEMO_TRANSFER_VARIANT,
        )
        unit = self._base_unit(variant)
        if unit is None:
            self.stdout.write(
                self.style.WARNING(
                    f"No base selling unit for {variant} - transfer not seeded"
                )
            )
            return
        transfer = record_stock_transfer(
            from_location=storage_location(STORE_LOCATION_NAME),
            to_location=storage_location(BODEGA_LOCATION_NAME),
            lines=[(unit, DEMO_TRANSFER_QTY)],
            user=stocker,
            remarks="Demo slip: the stocker moved these to the Bodega shelf.",
        )
        self.stdout.write(
            self.style.SUCCESS(
                f"Transfer seeded: {transfer.number} "
                f"{DEMO_TRANSFER_QTY} {unit.uom.code} of {variant} "
                f"{transfer.from_location.name} -> {transfer.to_location.name}"
            )
        )

    def _seed_customers(self):
        Customer.objects.get_or_create(name="Walk-in Customer")
        # Decision 08: an explicit limit for the demo debtor, because NULL now means
        # UNLIMITED and 0 means NO credit - the seed has to say which it wants instead
        # of inheriting the old `default=0`. Migration 0008 turned the legacy zeros into
        # NULL, so the update branch below also teaches an EXISTING row its limit,
        # which keeps re-running the seed idempotent rather than a silent no-op.
        maria, _ = Customer.objects.get_or_create(
            name="Maria Santos",
            defaults={
                "customer_type": "REGULAR",
                "contact_details": "0918-333-4444",
                "total_credit_limit": Decimal("10000.00"),
            },
        )
        if maria.total_credit_limit != Decimal("10000.00"):
            maria.total_credit_limit = Decimal("10000.00")
            maria.save(update_fields=["total_credit_limit"])
        Customer.objects.get_or_create(
            name="Dela Cruz Construction",
            defaults={
                "customer_type": "CONSTRUCTION_FIRM",
                "contact_details": "0917-555-6666",
            },
        )
        self.stdout.write(self.style.SUCCESS("Customers seeded"))

    def _seed_sales(self, cashier, variants, customers):
        from django.utils import timezone

        from apps.pos.models import SalesTransaction, Shift
        from apps.pos.services import compute_z_reading

        if SalesTransaction.objects.exists():
            self.stdout.write(self.style.WARNING("Sales already seeded - skipping"))
            return
        # Phase 4 (decision 06, ruling 2): `process_sale` now REFUSES to record a sale
        # unless the cashier has an open shift, so the seed must open one first - the
        # demo is a real cashier workflow, not a shortcut around the gate. Reused if one
        # is already open, so re-running the command cannot trip the unique constraint.
        shift = Shift.objects.filter(cashier=cashier, status=Shift.Status.OPEN).first()
        if shift is None:
            shift = Shift.objects.create(cashier=cashier, opening_float=Decimal(5000))
            self.stdout.write(
                f"  + shift {shift.id} opened for {cashier.username} "
                f"(float {shift.opening_float})"
            )
        walk_in = customers.get("Walk-in Customer")
        maria = customers.get("Maria Santos")
        v_names = list(variants.keys())
        # (customer, variant index, method, qty, amount_tendered)
        sales_plan = [
            (walk_in, 0, "CASH", 4, None),
            (walk_in, 1, "GCASH", 6, None),
            (maria, 2, "CASH", 3, None),
            (maria, 3, "CARD", 8, None),
            (
                maria,
                4,
                "CASH",
                12,
                Decimal(500),
            ),  # underpaid -> utang (named customer: walk-ins cannot owe)
        ]
        for customer, idx, method, qty, tendered in sales_plan:
            info = variants[v_names[idx % len(v_names)]]
            vuom = info["variant"].selling_uoms.first()
            payments = [
                {
                    "method": method,
                    "amount_tendered": tendered or vuom.default_selling_price * qty,
                }
            ]
            process_sale(
                customer_id=customer.id,
                cashier=cashier,
                items_data=[
                    {
                        "variant_id": vuom.pk,
                        "qty": qty,
                        "unit_price": vuom.default_selling_price,
                    }
                ],
                payments_data=payments,
            )
        self.stdout.write(self.style.SUCCESS(f"{len(sales_plan)} sales seeded"))

        # Close the shift, so the demo carries a finished Z-reading instead of an open
        # shift that the end-of-shift screen has to close by hand before it shows
        # anything. The count is deliberately 50.00 SHORT of the expected drawer: with a
        # clean count the variance report would always read 0.00 and prove nothing, the
        # same reason `_seed_stock` forces one variant below its threshold. Ruling 3 says
        # a variance is recorded, never blocking - this is that recorded variance.
        z = compute_z_reading(shift)
        shift.closing_count = Decimal(z["expected_drawer"]) - Decimal(50)
        shift.status = Shift.Status.CLOSED
        shift.closed_at = timezone.now()
        shift.notes = "Seeded demo shift, closed 50.00 short on purpose."
        shift.save(update_fields=["closing_count", "status", "closed_at", "notes"])
        z = compute_z_reading(shift)
        self.stdout.write(
            self.style.SUCCESS(
                f"Shift {shift.id} closed: gross {z['gross_sales']}, "
                f"cash {z['cash_sales']}, expected drawer {z['expected_drawer']}, "
                f"variance {z['variance']}"
            )
        )

    def _seed_requisitions(self, users, variants, customers):
        if Requisition.objects.exists():
            self.stdout.write(
                self.style.WARNING("Requisitions already seeded - skipping")
            )
            return
        v_names = list(variants.keys())
        # Decision 03: CPMS owns the project list, so the demo project is identified by
        # its CPMS id and billed to the contractor customer.
        project = {
            "cpms_project_id": "CPMS-P-1001",
            "name": "2-Storey House - Mandaue",
            "payer": customers["Dela Cruz Construction"].pk,
        }

        def push(cpms_request_id, variant_key, quantity, *, answer):
            """One request exactly as CPMS pushes it, then the STORE's answer.

            The push lands WAITING (decision 13), so every demo request is answered
            through the SAME service the review screen calls: `accept` marks its lines
            Available, `decline` refuses the whole request with a reason and spends the
            token, `wait` leaves it waiting for the store. Nothing here writes a status
            by hand, so the demo cannot show a state the screens cannot produce.
            """
            token = uuid.uuid4()
            result = import_request(
                cpms_request_id=cpms_request_id,
                token=token,
                project=project,
                requester_name="Rey Quester",
                approver_name=users["manager"].full_name,
                items=[
                    {
                        "code": variants[variant_key]["vuom"].barcode_qr,
                        "quantity": Decimal(quantity),
                    }
                ],
            )
            requisition = Requisition.objects.get(pk=result["request"]["id"])
            if answer == "accept":
                accept_requisition(
                    requisition_id=requisition.pk,
                    items=[
                        {"id": line.pk, "available": True, "decline_reason": ""}
                        for line in requisition.items.order_by("pk")
                    ],
                )
            elif answer == "decline":
                decline_requisition(
                    requisition_id=requisition.pk, decline_reason=DECLINE_REASON
                )
            return token

        # ACCEPTED (token ready for the POS release demo)
        # Not v_names[0]: the seed drains that one for the low-stock demo.
        token = push("CPMS-R-1001", v_names[1], "8", answer="accept")

        # RELEASED (the full flow - deducts stock, posts the project's utang)
        rel_token = push("CPMS-R-1002", v_names[3], "4", answer="accept")
        # Phase 3 (decision 03): a release needs the cashier's OPEN shift, and `_seed_sales`
        # already closed the one it sold through. Reopen (or reuse) here and leave it open:
        # the release belongs inside a shift's Z-reading, and an open shift is also what the
        # advertised "token ready for POS release" needs for a live demo.
        from apps.pos.models import Shift

        shift = Shift.objects.filter(
            cashier=users["cashier"], status=Shift.Status.OPEN
        ).first()
        if shift is None:
            shift = Shift.objects.create(
                cashier=users["cashier"], opening_float=Decimal(0)
            )
            self.stdout.write(
                f"  + shift {shift.id} opened for {users['cashier'].username} "
                "(release shift, left open for the demo)"
            )
        release_materials(token_value=str(rel_token), cashier=users["cashier"])

        # PARTIAL (decision 05: the shelf is short, the token survives the visit). The
        # line asks for MORE than the shelf holds, derived from the shelf itself so the
        # demo cannot drift into "everything fit after all".
        partial_variant = variants[v_names[2]]["variant"]
        on_hand = sum(partial_variant.batches.values_list("current_qty", flat=True))
        partial_token = push("CPMS-R-1003", v_names[2], on_hand + 5, answer="accept")
        partial = release_materials(
            token_value=str(partial_token), cashier=users["cashier"]
        )

        # WAITING (decision 13): pushed and not answered yet, so its live token must be
        # refused by the till until a manager accepts or declines it.
        push("CPMS-R-1004", v_names[6], "3", answer="wait")
        # DECLINED (decisions 09/13): the store can serve none of it, the reason is
        # recorded on the request and every line, and the token is spent without a
        # cashier. Nothing left the shelf and nothing was booked.
        push("CPMS-R-1005", v_names[7], "5", answer="decline")

        self.stdout.write(
            self.style.SUCCESS(
                "Requisitions seeded (ACCEPTED/PARTIAL/RELEASED/WAITING/DECLINED, "
                "pushed by CPMS)"
            )
        )
        self.stdout.write(f"  ACCEPTED token (ready for POS release): {token}")
        self.stdout.write(
            f"  PARTIAL token (scan again after a goods receipt): {partial_token} "
            f"({partial['status']}, {partial['items'][0]['outstanding']} outstanding)"
        )

    def _seed_packaging(self, stocker, variants):
        """One product that is really sold two ways (Phase 1d Task 4, decisions 15/16).

        Nothing above this step can produce "Bag = 25 kg at its own price": the catalog
        gives every variant a single factor-1 selling unit, so the packaging screens and
        the till's unit picker had no packaged example to show.

        Three things the seed must NOT fake, so it goes through the same rows and
        services the screens use:

        * the two selling units are ordinary `VariantUOM` rows, so `save()` derives
          their `QB…` codes and the whole-number flag comes from the unit;
        * the 250 kg arrives through a purchase order and Receiving, never as a batch
          written by hand - Add product creates catalogue only; and
        * the KG unit is the MEASURED one, so the product still accepts 2.5 kg, which is
          the contrast the packaged BAG is there to show.

        Its own guard, like every other half of this command: every part is looked up
        before it is written, so re-running changes nothing (ids, codes, prices,
        batches). A HALF-BUILT product is repaired in place - the parts that are missing
        (product, variant, either selling unit, its factor and price) are the only rows
        written, so a reset is never needed (Phase 6 B6, decision 22 item 17).

        Stock is the one thing a repair must not redo: the 250 kg is received only when
        this variant has no batch yet, so a run over existing stock never adds a second
        purchase order, receipt or batch, and never touches an existing one.
        """
        base_code, base_name = PACKAGING["base_unit"]
        bag_code, bag_name = PACKAGING["bag_unit"]

        # Both codes are created by migration 0008 in a fresh database; get_or_create
        # keeps a database seeded before it from inventing a rival spelling.
        base_uom, _ = UnitOfMeasure.objects.get_or_create(
            code=base_code, defaults={"name": base_name}
        )
        bag_uom, _ = UnitOfMeasure.objects.get_or_create(
            code=bag_code, defaults={"name": bag_name, "is_whole": True}
        )
        category, _ = Category.objects.get_or_create(name=PACKAGING["category"])
        brand, _ = Brand.objects.get_or_create(name=PACKAGING["brand"])
        product, _ = Product.objects.get_or_create(
            category=category, brand=brand, base_name=PACKAGING["product"]
        )
        variant, _ = ProductVariant.objects.get_or_create(
            product=product,
            variant_name=PACKAGING["variant"],
            defaults={"base_uom": base_uom, "min_stock_threshold": Decimal(20)},
        )
        restored = []
        for uom, factor, price in (
            (base_uom, Decimal(1), PACKAGING["base_price"]),
            (bag_uom, PACKAGING["bag_factor"], PACKAGING["bag_price"]),
        ):
            _unit, created = variant.selling_uoms.get_or_create(
                uom=uom,
                defaults={"conversion_factor": factor, "default_selling_price": price},
            )
            if created:
                restored.append(f"{uom.code} x{factor} at {price}")
        if restored:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Packaging repaired: {product.base_name} / "
                    f"{variant.variant_name} ({', '.join(restored)})"
                )
            )

        if InventoryBatch.objects.filter(variant=variant).exists():
            self.stdout.write(self.style.WARNING("Packaging already seeded - skipping"))
            return

        # Same purchase -> delivery -> process shape `_seed_stock` uses, with the
        # delivery LINE spelling out the 250 kg this order actually brought in.
        supplier, _ = Supplier.objects.get_or_create(
            company_name="Cebu Building Supply",
            defaults={"contact_person": "Lito Ramos", "phone": "0917-111-2222"},
        )
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=stocker,
            status=PurchaseOrder.Status.ORDERED,
            expected_delivery=timezone.localdate(),
        )
        item = POItem.objects.create(
            po=po,
            variant=variant,
            # The demo buys the base unit: `PACKAGING['stock']` is 250 KG, so the line is
            # counted in KG x1 and receiving stocks exactly 250 base units (Phase 5 B1).
            variant_uom=variant.selling_uoms.get(
                uom=base_uom, conversion_factor=Decimal(1)
            ),
            ordered_qty=PACKAGING["stock"],
            unit_cost=PACKAGING["unit_cost"],
            received_qty=PACKAGING["stock"],
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=stocker)
        GoodsReceiptItem.objects.create(
            receipt=receipt, po_item=item, qty=PACKAGING["stock"]
        )
        process_goods_receipt(receipt=receipt, user=stocker)
        self.stdout.write(
            self.style.SUCCESS(
                f"Packaging seeded: {product.base_name} / {variant.variant_name} "
                f"({base_code} x1 at {PACKAGING['base_price']}, "
                f"{bag_code} x{PACKAGING['bag_factor']} at {PACKAGING['bag_price']}), "
                f"{PACKAGING['stock']} {base_code} received on PO {po.pk}"
            )
        )

    def _print_review_instructions(self):
        """What to do with the two requests that only the review screen can move.

        Printed from the STORED rows, not from the seeding branch above, so a re-run
        (whose seeding half skips itself) still names the same tokens. Never printed for
        the releasable requests: the till's own token stays the thing the cashier scans.
        """
        instructions = (
            (
                "CPMS-R-1004",
                "WAITING token",
                (
                    "the store has not answered it, so it cannot be released at the "
                    "till - accept or decline it in Sales > Requests from projects "
                    "first."
                ),
            ),
            (
                "CPMS-R-1005",
                "DECLINED token",
                (
                    "this token is dead: verify and release answer "
                    "REQUISITION_DECLINED. No cashier was involved and nothing left "
                    "the shelf."
                ),
            ),
        )
        for cpms_request_id, label, advice in instructions:
            request = (
                Requisition.objects.filter(cpms_request_id=cpms_request_id)
                .select_related("token")
                .first()
            )
            if request is None:
                continue
            self.stdout.write(
                f"  {cpms_request_id} {label} {request.token.token}: {advice}"
            )

    def _print_summary(self, users):
        from apps.pos.models import SalesTransaction

        self.stdout.write(
            self.style.MIGRATE_HEADING(f"--- Demo accounts (password: {PASSWORD}) ---")
        )
        for username in users:
            self.stdout.write(f"  {username:<10} / {PASSWORD}")
        open_ledgers = CollectibleLedger.objects.filter(
            status=CollectibleLedger.Status.OPEN
        ).count()
        self.stdout.write(self.style.MIGRATE_HEADING("--- Quick stats ---"))
        self.stdout.write(
            f"  Users: {User.objects.count()}, "
            f"Batches: {InventoryBatch.objects.count()}, "
            f"Transactions: {SalesTransaction.objects.count()}, "
            f"Open utang ledgers: {open_ledgers}"
        )
        self.stdout.write(self.style.SUCCESS("Done."))
