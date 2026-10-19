# pyright: reportAttributeAccessIssue=false
#
# Same reason as apps/inventory/views.py: the checker resolves its config from its
# WORKING DIRECTORY and does not run inside this repo here, so a pyrightconfig.json is
# not found. This travels with the file. It disables the one rule that cannot model
# Django's `Model.objects`/`BaseCommand.style` without django-stubs.
from datetime import timedelta
from decimal import Decimal

from django.contrib.auth.models import Group
from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.collectibles.models import CollectibleLedger
from apps.inventory.models import (
    Brand, Category, GoodsReceipt, InventoryBatch, Product,
    ProductVariant, PurchaseOrder, POItem, StockAdjustment, Supplier,
    UnitOfMeasure,
)
from apps.inventory.services import (
    allocate_fifo, apply_stock_adjustment, process_goods_receipt,
)
from apps.pos.models import Customer
from apps.pos.services import process_sale
from apps.requisitions.models import Project, Requisition, RequisitionItem
from apps.requisitions.services import generate_req_number
from apps.requisitions.services import (
    approve_requisition, release_materials, submit_requisition,
)
from apps.users.models import User

PASSWORD = 'demo1234'
ROLES = ['System Administrator', 'Store Manager', 'Stock Manager',
         'Cashier', 'Site Foreman']

USERS = [
    # username, full_name, group, is_superuser, is_staff
    ('admin',   'Ada Ministrator', 'System Administrator', True,  True),
    ('manager', 'Mana Ger',        'Store Manager',        False, False),
    ('stocker', 'Stock Er',        'Stock Manager',        False, False),
    ('cashier', 'Cashi Er',        'Cashier',              False, False),
    ('foreman', 'Fore Man',        'Site Foreman',         False, False),
]

# category, brand, product, [(variant_name, unit_cost, selling_price), ...]
CATALOG = [
    ('Cement', 'Rhino', 'Portland Cement', [
        ('40kg', Decimal('215'), Decimal('260')),
        ('50kg', Decimal('265'), Decimal('320')),
    ]),
    ('Steel', 'SteelCore', 'GI Sheet Plain', [
        ('0.9mm x 1.8m', Decimal('480'), Decimal('560')),
    ]),
    ('Plumbing', 'FlowPro', 'PVC Pipe', [
        ('1/2 inch x 3m', Decimal('95'), Decimal('118')),
        ('4 inch x 3m', Decimal('385'), Decimal('450')),
    ]),
    ('Plumbing', 'FlowPro', 'Faucet', [
        ('Standard', Decimal('180'), Decimal('225')),
    ]),
    ('Electrical', 'VoltEdge', 'Electrical Wire', [
        ('2.0mm THHN (roll)', Decimal('1250'), Decimal('1480')),
    ]),
    ('Electrical', 'VoltEdge', 'Circuit Breaker', [
        ('20A 1-pole', Decimal('260'), Decimal('315')),
    ]),
]


class Command(BaseCommand):
    help = 'Seed realistic demo data (idempotent).'

    def handle(self, *args, **options):
        self._seed_groups()
        users = self._seed_users()
        variants = self._seed_catalog()
        self._seed_stock(users['stocker'], variants)
        self._seed_adjustments(users['stocker'], variants)
        self._seed_customers()
        customers = {c.name: c for c in Customer.objects.all()}
        self._seed_sales(users['cashier'], variants, customers)
        self._seed_requisitions(users, variants, customers)
        self._print_summary(users)

    def _seed_groups(self):
        for name in ROLES:
            Group.objects.get_or_create(name=name)
        self.stdout.write(self.style.MIGRATE_HEADING('Groups ensured'))

    def _seed_users(self):
        users = {}
        for username, full_name, group, is_super, is_staff in USERS:
            user, created = User.objects.get_or_create(
                username=username,
                defaults={'full_name': full_name, 'email': f'{username}@demo.ph',
                          'is_superuser': is_super, 'is_staff': is_staff},
            )
            if created:
                user.set_password(PASSWORD)
                user.save()
                self.stdout.write(f'  + user {username} ({group})')
            group_obj, _ = Group.objects.get_or_create(name=group)
            user.groups.add(group_obj)
            users[username] = user
        return users

    def _seed_catalog(self):
        variants = {}
        if Category.objects.filter(name='Cement').exists():
            self.stdout.write(self.style.WARNING('Catalog already seeded - skipping'))
            for v in ProductVariant.objects.all():
                variants[v.variant_name] = {'variant': v}
            return variants
        uoms = {}
        for code, name in [('BAG', 'Bag'), ('PC', 'Piece'), ('RL', 'Roll')]:
            uoms[code], _ = UnitOfMeasure.objects.get_or_create(
                code=code, defaults={'name': name})
        for cat_name, brand_name, prod_name, vs in CATALOG:
            cat, _ = Category.objects.get_or_create(name=cat_name)
            brand, _ = Brand.objects.get_or_create(name=brand_name)
            product, _ = Product.objects.get_or_create(
                category=cat, brand=brand, base_name=prod_name)
            for v_name, cost, price in vs:
                variant, _ = ProductVariant.objects.get_or_create(
                    product=product, variant_name=v_name,
                    defaults={'base_uom': uoms['PC'],
                              'min_stock_threshold': Decimal('20')},
                )
                variant.selling_uoms.get_or_create(
                    uom=variant.base_uom,
                    defaults={'conversion_factor': Decimal('1'),
                              'default_selling_price': price})
                variants[v_name] = {'variant': variant, 'cost': cost}
        self.stdout.write(self.style.SUCCESS(f'Catalog seeded ({len(variants)} variants)'))
        return variants

    def _seed_stock(self, stocker, variants):
        if PurchaseOrder.objects.exists():
            self.stdout.write(self.style.WARNING('Stock already seeded - skipping'))
            return
        supplier, _ = Supplier.objects.get_or_create(
            company_name='Cebu Building Supply',
            defaults={'contact_person': 'Lito Ramos', 'phone': '0917-111-2222'})
        low_stock_variant = None
        for i, (v_name, info) in enumerate(variants.items()):
            po = PurchaseOrder.objects.create(
                supplier=supplier, created_by=stocker,
                expected_delivery=timezone.localdate() + timedelta(days=7))
            POItem.objects.create(
                po=po, variant=info['variant'], ordered_qty=Decimal('100'),
                unit_cost=info['cost'], received_qty=Decimal('100'))
            receipt = GoodsReceipt.objects.create(po=po, received_by=stocker)
            process_goods_receipt(receipt=receipt, user=stocker)
            if i == 0:
                low_stock_variant = info['variant']
        # Force one low-stock scenario for the dashboard/alerts demo.
        if low_stock_variant:
            from django.db import transaction as db_txn
            with db_txn.atomic():
                allocate_fifo(variant_id=low_stock_variant.pk, qty_needed=Decimal('90'))
        self.stdout.write(self.style.SUCCESS('Stock batches seeded (FIFO)'))

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
                self.style.WARNING('Adjustments already seeded - skipping'))
            return

        # (adjustment_type, qty, remarks) - one of each type the UI filters on,
        # with the first landing on the variant _seed_stock took below threshold.
        plan = [
            ('SHRINKAGE', Decimal('-3'), 'Broken in transit.'),
            ('DAMAGE', Decimal('-2'), 'Water damage in storage.'),
            ('CORRECTION', Decimal('4'), 'Cycle count correction.'),
            ('RETURN', Decimal('-1'), 'Returned to supplier.'),
            ('SHRINKAGE', Decimal('-5'), 'Unaccounted loss.'),
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
            candidate = info['variant']
            live = (
                InventoryBatch.objects
                .filter(variant=candidate, current_qty__gt=0)
                .aggregate(total=Sum('current_qty'))['total'] or 0
            )
            if (candidate.min_stock_threshold > 0
                    and live < candidate.min_stock_threshold):
                below_threshold = candidate
                break

        targets = [info['variant'] for info in variants.values()]
        if below_threshold is not None:
            targets.remove(below_threshold)
            targets.insert(0, below_threshold)

        # `apply_stock_adjustment` routes removals through `allocate_fifo`, which
        # uses `select_for_update` — that raises TransactionManagementError
        # outside a transaction. `_seed_stock` wraps its own call for the same
        # reason. Found by actually running the command, not by reading it.
        from django.db import transaction as db_txn
        with db_txn.atomic():
            for (adjustment_type, qty, remarks), variant in zip(plan, targets):
                adjustment = StockAdjustment.objects.create(
                    variant=variant,
                    user=stocker,
                    adjustment_type=adjustment_type,
                    qty_adjusted=qty,
                    remarks=remarks,
                )
                apply_stock_adjustment(adjustment=adjustment)
                made += 1
        self.stdout.write(
            self.style.SUCCESS(f'{made} stock adjustments seeded'))

    def _seed_customers(self):
        Customer.objects.get_or_create(name='Walk-in Customer')
        Customer.objects.get_or_create(
            name='Maria Santos',
            defaults={'customer_type': 'REGULAR', 'contact_details': '0918-333-4444'})
        Customer.objects.get_or_create(
            name='Dela Cruz Construction',
            defaults={'customer_type': 'CONSTRUCTION_FIRM', 'contact_details': '0917-555-6666'})
        self.stdout.write(self.style.SUCCESS('Customers seeded'))

    def _seed_sales(self, cashier, variants, customers):
        from apps.pos.models import SalesTransaction
        if SalesTransaction.objects.exists():
            self.stdout.write(self.style.WARNING('Sales already seeded - skipping'))
            return
        walk_in = customers.get('Walk-in Customer')
        maria = customers.get('Maria Santos')
        v_names = list(variants.keys())
        # (customer, variant index, method, qty, amount_tendered)
        sales_plan = [
            (walk_in, 0, 'CASH', 4, None),
            (walk_in, 1, 'GCASH', 6, None),
            (maria, 2, 'CASH', 3, None),
            (maria, 3, 'CARD', 8, None),
            (maria, 4, 'CASH', 12, Decimal('500')),  # underpaid -> utang (named customer: walk-ins cannot owe)
        ]
        for customer, idx, method, qty, tendered in sales_plan:
            info = variants[v_names[idx % len(v_names)]]
            vuom = info['variant'].selling_uoms.first()
            payments = [{'method': method,
                         'amount_tendered': tendered or vuom.default_selling_price * qty}]
            process_sale(
                customer_id=customer.id, cashier=cashier,
                items_data=[{'variant_id': vuom.pk, 'qty': qty,
                             'unit_price': vuom.default_selling_price}],
                payments_data=payments)
        self.stdout.write(self.style.SUCCESS(f'{len(sales_plan)} sales seeded'))

    def _seed_requisitions(self, users, variants, customers):
        if Requisition.objects.exists():
            self.stdout.write(self.style.WARNING('Requisitions already seeded - skipping'))
            return
        project, _ = Project.objects.get_or_create(
            name='2-Storey House - Mandaue',
            defaults={'customer': customers['Dela Cruz Construction']})
        v_names = list(variants.keys())

        # DRAFT
        draft = Requisition.objects.create(req_number=generate_req_number(), project=project, requested_by=users['foreman'])
        RequisitionItem.objects.create(
            requisition=draft, variant=variants[v_names[1]]['variant'], quantity=Decimal('10'))

        # SUBMITTED
        submitted = Requisition.objects.create(req_number=generate_req_number(), project=project, requested_by=users['foreman'])
        RequisitionItem.objects.create(
            requisition=submitted, variant=variants[v_names[2]]['variant'], quantity=Decimal('5'))
        submit_requisition(requisition=submitted)

        # APPROVED (token ready for POS release demo)
        approved = Requisition.objects.create(req_number=generate_req_number(), project=project, requested_by=users['foreman'])
        RequisitionItem.objects.create(
            requisition=approved, variant=variants[v_names[0]]['variant'], quantity=Decimal('8'))
        submit_requisition(requisition=approved)
        token = approve_requisition(requisition=approved, approver=users['manager'])

        # RELEASED (full flow - deducts stock, posts ledger)
        released = Requisition.objects.create(req_number=generate_req_number(), project=project, requested_by=users['foreman'])
        RequisitionItem.objects.create(
            requisition=released, variant=variants[v_names[3]]['variant'], quantity=Decimal('4'))
        submit_requisition(requisition=released)
        rel_token = approve_requisition(requisition=released, approver=users['manager'])
        release_materials(token_value=str(rel_token.token), cashier=users['cashier'])

        self.stdout.write(self.style.SUCCESS(
            'Requisitions seeded (DRAFT/SUBMITTED/APPROVED/RELEASED)'))
        self.stdout.write(f'  APPROVED token (ready for POS release): {token.token}')

    def _print_summary(self, users):
        from apps.pos.models import SalesTransaction
        self.stdout.write(self.style.MIGRATE_HEADING(
            f'--- Demo accounts (password: {PASSWORD}) ---'))
        for username in users:
            self.stdout.write(f'  {username:<10} / {PASSWORD}')
        open_ledgers = CollectibleLedger.objects.filter(
            status=CollectibleLedger.Status.OPEN).count()
        self.stdout.write(self.style.MIGRATE_HEADING('--- Quick stats ---'))
        self.stdout.write(
            f'  Users: {User.objects.count()}, '
            f'Batches: {InventoryBatch.objects.count()}, '
            f'Transactions: {SalesTransaction.objects.count()}, '
            f'Open utang ledgers: {open_ledgers}')
        self.stdout.write(self.style.SUCCESS('Done.'))






