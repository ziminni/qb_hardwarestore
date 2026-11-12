# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
#
# Same directives and reasons as apps/inventory/tests_catalog_writes.py: this checker runs
# from a working directory outside the repo, so `Model.objects` is a false positive on
# valid Django, and `**auth` splats HTTP_AUTHORIZATION into the test client, which pyright
# reads as `follow=`.

"""Phase 1d Task 3 — remove a selling unit nothing references (decision 16).

`VariantUOM` had no `DELETE` (405) because five tables hold it through `PROTECT`: a sale
line (a sale or a return), a held-cart line, a project-request line, a quotation line and
a sales-order line. Inventory now needs the exit the Add-product screen implies: a unit
typed by mistake, or a product no longer sold by the bag, must be removable BEFORE a sale
uses it, and impossible to remove once history does.

The rules, all server-side:

* factor 1 is the base unit and can never be removed (`400 BASE_UNIT_REQUIRED`);
* any of the five references refuses with `400 SELLING_UNIT_IN_USE`, and so does a
  `ProtectedError` race, because that is the same answer, not a 500;
* a success is `204` plus ONE `DELETE` audit row written in the same transaction, so a
  refusal leaves no row claiming a removal;
* a unit referenced only by a project request also freezes its variant/uom/factor (Q4)
  while its price and code stay editable;
* the removed unit's `QB` code leaves CPMS `materials/` (its code is what CPMS orders);
* a WRITER that validated a unit before the removal committed refuses with the same 400
  and leaves no parent row, and a removal that arrives after a writer holds the unit
  refuses instead of deleting what the writer just referenced (both orders).
"""

import threading
from decimal import Decimal
from unittest import mock
from uuid import uuid4

from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.db import connections
from django.test import TransactionTestCase
from django.utils.crypto import get_random_string
from rest_framework.test import APIClient

from apps.inventory import serializers as inventory_serializers
from apps.inventory import views as inventory_views
from apps.pos import serializers as pos_serializers
from apps.pos import services as pos_services
from apps.pos.models import (
    Customer,
    HeldCart,
    HeldCartItem,
    Quotation,
    QuotationItem,
    SalesItem,
    SalesOrder,
    SalesOrderItem,
    SalesTransaction,
    Shift,
)
from apps.requisitions import services as requisitions_services
from apps.requisitions.models import Project, Requisition, RequisitionItem
from apps.users.models import AuditLog

from .models import (
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
from .services import process_goods_receipt
from .tests_catalog_writes import CatalogWriteTestBase

User = get_user_model()

LOGIN_URL = "/api/v1/auth/login/"
VARIANT_UOMS_URL = "/api/v1/variant-uoms/"
PURCHASE_ORDERS_URL = "/api/v1/purchase-orders/"
MATERIALS_URL = "/api/v1/integration/cpms/materials/"
QUOTATIONS_URL = "/api/v1/quotations/"
SALES_ORDERS_URL = "/api/v1/sales-orders/"
CPMS_REQUESTS_URL = "/api/v1/integration/cpms/requests/"
CPMS_GROUP = "CPMS Service"


class UnitRemovalTestBase(CatalogWriteTestBase):
    """The fixture plus a SECOND selling unit (a box of 12) that nothing references.

    `self.vuom` is the variant's factor-1 base unit (BAG) and is therefore never
    removable; `self.box` is the unit every refusal test tries to remove.
    """

    def setUp(self):
        super().setUp()
        self.box = self._unit("PC", factor="12", price="120")

    # -- fixture helpers ---------------------------------------------------
    def _unit(self, uom_code, factor="6", price="60"):
        """One extra selling unit on the variant, on its own unit of measure."""
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=uom_code, defaults={"name": uom_code.title()}
        )
        return VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(factor),
            default_selling_price=Decimal(price),
        )

    def _remove(self, unit=None, user=None, client=None):
        return (client or self.client).delete(
            f"{VARIANT_UOMS_URL}{(unit or self.box).pk}/",
            **self._auth(user or self.stocker),
        )

    def _refusal(self, response, code):
        """Assert a project-shaped refusal: 400, the stable code, and a sentence."""
        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data.get("code"), code, response.data)
        self.assertTrue(response.data.get("detail"), response.data)

    def _delete_rows(self):
        return AuditLog.objects.filter(action_type=AuditLog.ActionType.DELETE)

    def _contractor(self):
        return Customer.objects.create(
            name="Reyes Contracting", customer_type=Customer.Type.CONTRACTOR
        )

    def _sell(self, unit, qty="1"):
        """Ring a real sale of `unit` through `process_sale`: history now holds it."""
        from apps.pos.models import Shift
        from apps.pos.services import process_sale

        self._stock("100")
        customer, _ = Customer.objects.get_or_create(
            name="Walk-in Customer", defaults={"customer_type": Customer.Type.WALK_IN}
        )
        Shift.objects.get_or_create(
            cashier=self.cashier,
            status=Shift.Status.OPEN,
            defaults={"opening_float": Decimal(500)},
        )
        return process_sale(
            customer_id=customer.pk,
            cashier=self.cashier,
            items_data=[{"variant_id": unit.pk, "qty": Decimal(qty)}],
            payments_data=[
                {
                    "method": "CASH",
                    "amount_tendered": unit.default_selling_price * Decimal(qty),
                }
            ],
        )

    def _referenced(self, unit, kind):
        """Make ONE of the five PROTECT tables reference `unit`."""
        if kind == "sold":
            self._sell(unit)
        elif kind == "returned":
            # A return is the SAME `SalesItem` table with a negative quantity on a
            # RETURN-typed transaction (decision 15), so it blocks removal identically.
            transaction = SalesTransaction.objects.create(
                customer=self._contractor(),
                cashier=self.cashier,
                transaction_no="RET-0001",
                source=SalesTransaction.Source.RETURN,
                grand_total=Decimal(-120),
            )
            SalesItem.objects.create(
                transaction=transaction,
                variant_uom=unit,
                qty=Decimal(-1),
                unit_price=Decimal(120),
                subtotal=Decimal(-120),
            )
        elif kind == "held":
            cart = HeldCart.objects.create(cashier=self.cashier)
            HeldCartItem.objects.create(
                cart=cart, variant_uom=unit, qty=Decimal(1), unit_price=Decimal(120)
            )
        elif kind == "requested":
            project = Project.objects.create(
                name="House Build", customer=self._contractor()
            )
            requisition = Requisition.objects.create(
                project=project, req_number="REQ-1001"
            )
            RequisitionItem.objects.create(
                requisition=requisition, variant_uom=unit, quantity=Decimal(2)
            )
        elif kind == "quoted":
            quotation = Quotation.objects.create(
                customer=self._contractor(), created_by=self.stocker
            )
            QuotationItem.objects.create(
                quotation=quotation,
                variant_uom=unit,
                qty=Decimal(1),
                unit_price=Decimal(120),
            )
        elif kind == "ordered":
            order = SalesOrder.objects.create(
                customer=self._contractor(), created_by=self.stocker
            )
            SalesOrderItem.objects.create(
                order=order, variant_uom=unit, qty=Decimal(1), unit_price=Decimal(120)
            )
        else:  # pragma: no cover - a typo in a test, not a behaviour
            raise AssertionError(f"unknown reference kind {kind}")


class RemoveUnusedUnitTests(UnitRemovalTestBase):
    """The delete: 204 + one audit row, or a coded 400, never a 500."""

    def test_an_unused_selling_unit_is_removed_with_one_delete_audit_row(self):
        code = self.box.barcode_qr
        self.assertTrue(code, "fixture: every selling unit carries a code")

        response = self._remove()

        self.assertEqual(response.status_code, 204, response.data)
        self.assertFalse(VariantUOM.objects.filter(pk=self.box.pk).exists())
        rows = self._delete_rows()
        self.assertEqual(
            rows.count(), 1, list(rows.values_list("description", flat=True))
        )
        description = rows.get().description
        self.assertIn("Portland Cement", description)
        self.assertIn("40kg", description)
        self.assertIn("PC", description)
        self.assertIn(code, description)
        self.assertIn("removed.", description)

    def test_the_base_unit_cannot_be_removed(self):
        # `self.vuom` is the variant's factor-1 unit: the product is counted in it.
        response = self._remove(self.vuom)

        self._refusal(response, "BASE_UNIT_REQUIRED")
        self.assertTrue(VariantUOM.objects.filter(pk=self.vuom.pk).exists())
        self.assertEqual(self._delete_rows().count(), 0)

    def test_each_of_the_five_references_refuses_and_writes_no_audit_row(self):
        # One unit per reference kind, because one unit can only carry one at a time and
        # a refusal must be provable in isolation.
        for kind, uom_code in (
            ("sold", "BOX"),
            ("returned", "PACK"),
            ("held", "ROLL"),
            ("requested", "SHEET"),
            ("quoted", "KG"),
            ("ordered", "M"),
        ):
            with self.subTest(kind=kind):
                unit = self._unit(uom_code, factor="6")
                self._referenced(unit, kind)

                response = self._remove(unit)

                self._refusal(response, "SELLING_UNIT_IN_USE")
                self.assertTrue(VariantUOM.objects.filter(pk=unit.pk).exists())
                self.assertEqual(
                    self._delete_rows().count(),
                    0,
                    list(self._delete_rows().values_list("description", flat=True)),
                )

    def test_a_protected_error_race_is_the_same_400_not_a_500(self):
        """The in-use check reads, the delete writes, and two tills can interleave.

        Simulated by letting the pre-check answer "not in use" while a real sale line
        still holds the row: the FK is the only thing left to refuse, and its
        `ProtectedError` must read as the same refusal, not as a server crash.
        """
        self._sell(self.box)

        with mock.patch("apps.inventory.views.unit_in_use", return_value=False):
            response = self._remove()

        self._refusal(response, "SELLING_UNIT_IN_USE")
        self.assertTrue(VariantUOM.objects.filter(pk=self.box.pk).exists())
        self.assertEqual(self._delete_rows().count(), 0)

    def test_a_cashier_cannot_remove_a_selling_unit(self):
        response = self._remove(user=self.cashier)

        self.assertEqual(response.status_code, 403, response.data)
        self.assertTrue(VariantUOM.objects.filter(pk=self.box.pk).exists())
        self.assertEqual(self._delete_rows().count(), 0)

    def test_the_store_manager_and_an_admin_may_remove_one(self):
        manager_box = self._unit("BOX", factor="6")
        admin_box = self._unit("PACK", factor="4")
        admin = self._make_user("cat_admin", "Admin")

        self.assertEqual(self._remove(manager_box, self.manager).status_code, 204)
        self.assertEqual(self._remove(admin_box, admin).status_code, 204)

    def test_only_selling_units_gained_a_delete(self):
        """Every other catalog row is still archived, never deleted."""
        for path, row in (
            ("products", self.product),
            ("variants", self.variant),
            ("categories", self.category),
            ("uoms", self.uom_pc),
        ):
            with self.subTest(path=path):
                response = self.client.delete(
                    f"/api/v1/{path}/{row.pk}/", **self._auth(self.stocker)
                )

                self.assertEqual(response.status_code, 405, response.data)

    def test_the_removed_code_disappears_from_the_cpms_material_list(self):
        cpms = User.objects.create_user(
            username="cpms_service",
            email="cpms@example.com",
            password=self.password,
            full_name="CPMS",
        )
        cpms.groups.add(Group.objects.get_or_create(name=CPMS_GROUP)[0])
        auth = self._auth(cpms)
        code = self.box.barcode_qr

        before = self.client.get(MATERIALS_URL, **auth)
        self.assertEqual(before.status_code, 200, before.data)
        self.assertIn(code, [row["code"] for row in before.data["results"]])

        self.assertEqual(self._remove().status_code, 204)

        after = self.client.get(MATERIALS_URL, **auth)
        self.assertEqual(after.status_code, 200, after.data)
        self.assertNotIn(code, [row["code"] for row in after.data["results"]])


class RequisitionFreezeTests(UnitRemovalTestBase):
    """Q4: a project-request line freezes the unit, exactly like a sale (decision 16)."""

    def setUp(self):
        super().setUp()
        self.referenced = self._unit("BOX", factor="6")
        self._referenced(self.referenced, "requested")

    def _patch(self, **overrides):
        return self.client.patch(
            f"{VARIANT_UOMS_URL}{self.referenced.pk}/",
            overrides,
            format="json",
            **self._auth(self.stocker),
        )

    def test_the_factor_of_a_requested_unit_is_frozen(self):
        response = self._patch(conversion_factor="2")

        self._refusal(response, "SELLING_UNIT_IN_USE")
        self.referenced.refresh_from_db()
        self.assertEqual(self.referenced.conversion_factor, Decimal(6))

    def test_the_uom_of_a_requested_unit_is_frozen(self):
        # A unit of measure no other selling unit of this variant holds, so the refusal
        # cannot come from the (variant, uom) uniqueness rule instead of the freeze.
        free_uom, _ = UnitOfMeasure.objects.get_or_create(
            code="ML", defaults={"name": "Millilitre"}
        )

        response = self._patch(uom=free_uom.pk)

        self._refusal(response, "SELLING_UNIT_IN_USE")
        self.referenced.refresh_from_db()
        self.assertNotEqual(self.referenced.uom, free_uom)

    def test_the_variant_of_a_requested_unit_is_frozen(self):
        from .models import ProductVariant

        other = ProductVariant.objects.create(
            product=self.product, variant_name="25kg", base_uom=self.uom
        )

        response = self._patch(variant=other.pk)

        self._refusal(response, "SELLING_UNIT_IN_USE")
        self.referenced.refresh_from_db()
        self.assertEqual(self.referenced.variant, self.variant)

    def test_the_price_and_the_code_of_a_requested_unit_stay_editable(self):
        priced = self._patch(default_selling_price="99.00")
        self.assertEqual(priced.status_code, 200, priced.data)
        coded = self._patch(barcode_qr="AB-1")
        self.assertEqual(coded.status_code, 200, coded.data)

        self.referenced.refresh_from_db()
        self.assertEqual(self.referenced.default_selling_price, Decimal("99.00"))
        self.assertEqual(self.referenced.barcode_qr, "AB-1")


class ConcurrentRaceTestBase(TransactionTestCase):
    """One product with sellable stock, real logins, a till shift and both payers.

    `TransactionTestCase` because two workers must see each other's COMMITTED rows: the
    wrapped transaction a `TestCase` uses hides them, and the race would then be decided
    by timing instead of by the row lock.
    """

    def setUp(self):
        self.password = get_random_string(16)
        self.stocker = self._make_user("race_stocker", "Stock Manager")
        self.cashier = self._make_user("race_cashier", "Cashier")
        self.cpms = self._make_user("race_cpms", CPMS_GROUP)
        self.category = Category.objects.create(name="Cement")
        self.brand = Brand.objects.create(name="Rhino")
        self.uom_bag, _ = UnitOfMeasure.objects.get_or_create(
            code="BAG", defaults={"name": "Bag"}
        )
        self.product = Product.objects.create(
            category=self.category, brand=self.brand, base_name="Portland Cement"
        )
        self.variant = ProductVariant.objects.create(
            product=self.product,
            variant_name="40kg",
            base_uom=self.uom_bag,
            min_stock_threshold=Decimal(5),
        )
        VariantUOM.objects.create(
            variant=self.variant,
            uom=self.uom_bag,
            conversion_factor=Decimal(1),
            default_selling_price=Decimal(10),
        )
        self.units = [self._unit(code) for code in ("PC", "BOX", "PACK")]
        self.walk_in, _ = Customer.objects.get_or_create(
            name="Walk-in Customer", defaults={"customer_type": Customer.Type.WALK_IN}
        )
        self.payer = Customer.objects.create(
            name="Reyes Contracting", customer_type=Customer.Type.CONTRACTOR
        )
        # A sale needs an open shift (decision 06), and the till prices it from the
        # unit row, so both are fixture, not what any test here is about.
        Shift.objects.get_or_create(
            cashier=self.cashier,
            status=Shift.Status.OPEN,
            defaults={"opening_float": Decimal(500)},
        )
        self._stock()

    # -- fixture helpers ---------------------------------------------------
    def _unit(self, uom_code):
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code=uom_code, defaults={"name": uom_code.title()}
        )
        return VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(12),
            default_selling_price=Decimal(120),
        )

    def _stock(self, qty="600"):
        """A processed delivery, so the variant has base units a sale can take."""
        supplier = Supplier.objects.create(company_name="Acme Racing")
        po = PurchaseOrder.objects.create(
            supplier=supplier,
            created_by=self.stocker,
            status=PurchaseOrder.Status.ORDERED,
        )
        POItem.objects.create(
            po=po,
            variant=self.variant,
            ordered_qty=Decimal(qty),
            unit_cost=Decimal(5),
            received_qty=Decimal(qty),
        )
        receipt = GoodsReceipt.objects.create(po=po, received_by=self.stocker)
        process_goods_receipt(receipt=receipt, user=self.stocker)

    def _make_user(self, username, *groups):
        user = User.objects.create_user(
            username=username,
            email=f"{username}@example.com",
            password=self.password,
            full_name=username,
        )
        for name in groups:
            user.groups.add(Group.objects.get_or_create(name=name)[0])
        return user

    def _login(self, client, user):
        login = client.post(
            LOGIN_URL,
            {"username": user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(login.status_code, 200, login.data)
        return {"HTTP_AUTHORIZATION": f"Bearer {login.data['access']}"}


class ConcurrentHoldAndRemovalTests(ConcurrentRaceTestBase):
    """A hold and a removal of the same selling unit, at the same moment.

    Both orders are correct, and the test accepts either:

    * the hold wins -> the cart line is committed, so the removal must refuse with
      `400 SELLING_UNIT_IN_USE` and the line stays (nothing is lost);
    * the removal wins -> the unit is gone, so the hold must refuse with a **400**, never
      a 500 from the foreign-key check, and no cart line exists.

    What is never acceptable: a 500, or a `204` next to a cart line that points at the
    removed unit.
    """

    def test_a_hold_and_a_removal_of_one_unit_never_lose_the_cart_line(self):
        for unit in self.units:
            with self.subTest(unit=unit.uom.code):
                self._race(unit)

    def _race(self, unit):
        barrier = threading.Barrier(2, timeout=20)
        results = {}
        lock = threading.Lock()

        def worker(kind):
            client = APIClient()
            user = self.cashier if kind == "hold" else self.stocker
            auth = self._login(client, user)
            try:
                barrier.wait()
                if kind == "hold":
                    response = client.post(
                        "/api/v1/held-carts/",
                        {
                            "items": [
                                {
                                    "variant_uom": unit.pk,
                                    "qty": "1",
                                    "unit_price": "120",
                                }
                            ]
                        },
                        format="json",
                        **auth,
                    )
                else:
                    response = client.delete(f"{VARIANT_UOMS_URL}{unit.pk}/", **auth)
                outcome = response.status_code
            except Exception as exc:  # a 500 escapes the test client as an exception
                outcome = exc
            finally:
                # Each thread owns its connection; leaving one open hangs the
                # truncation this class does when it finishes.
                connections.close_all()
            with lock:
                results[kind] = outcome

        threads = [
            threading.Thread(target=worker, args=(kind,)) for kind in ("hold", "remove")
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(len(results), 2, results)
        for kind, outcome in results.items():
            self.assertNotIsInstance(
                outcome,
                Exception,
                f"the {kind} side crashed instead of being refused: {results!r}",
            )

        hold, remove = results["hold"], results["remove"]
        if remove == 204:
            self.assertEqual(
                hold, 400, f"removal won, so the hold must refuse: {results}"
            )
            self.assertFalse(
                HeldCartItem.objects.filter(variant_uom_id=unit.pk).exists(),
                "a removed unit must not be left holding a cart line",
            )
        else:
            self.assertEqual(
                remove, 400, f"the hold won, so the removal must refuse: {results}"
            )
            self.assertEqual(hold, 201, results)
            self.assertTrue(
                HeldCartItem.objects.filter(variant_uom_id=unit.pk).exists(),
                "the committed cart line must survive the refused removal",
            )


class ConcurrentWriterAndRemovalTests(ConcurrentRaceTestBase):
    """A write that names a selling unit, and a removal of it, with the ORDER FORCED.

    Every writer here resolves its selling units BEFORE it opens a transaction (a refused
    cart, quote, order or push must leave nothing behind), which leaves a window the
    removal can walk through: the writer accepted a unit, `DELETE /variant-uoms/{id}/`
    erases it, and the writer's INSERT then fails on the foreign key - a 500 for a race
    the clerk cannot act on. Both sides take the SAME row lock now, so one of them waits
    and the loser answers a coded 400.

    The order is decided by `threading.Event`s on two seams, never by a sleep:

    * the writer pauses between validation and its transaction, so the removal commits
      first ("the removal won");
    * the writer pauses at its first INSERT, which the fix places AFTER the unit lock, so
      the removal is the side that must wait ("the writer won").

    Never acceptable in either order: a 500, a refused writer that left a parent row
    behind, or a `204` next to a line that points at the removed unit.
    """

    def _race(self, *, unit, removal_first, writer, writer_user):
        """Run `writer` and one DELETE of `unit`; assert both outcomes.

        `writer(client, auth, started, proceed)` pauses itself: it sets `started` on
        arrival and waits for `proceed` before continuing, which is what makes the order
        the test asks for instead of whichever request happened to be scheduled first.
        """
        started = threading.Event()
        proceed = threading.Event()
        removal_started = threading.Event()
        removal_done = threading.Event()
        results = {}

        def writer_worker():
            client = APIClient()
            auth = self._login(client, writer_user)
            try:
                response = writer(client, auth, started, proceed)
                results["write"] = (response.status_code, dict(response.data or {}))
            except Exception as exc:  # a 5xx escapes the test client as an exception
                results["write"] = exc
            finally:
                connections.close_all()

        def removal_worker():
            client = APIClient()
            auth = self._login(client, self.stocker)
            try:
                removal_started.wait(timeout=20)
                response = client.delete(f"{VARIANT_UOMS_URL}{unit.pk}/", **auth)
                results["remove"] = (response.status_code, dict(response.data or {}))
            except Exception as exc:
                results["remove"] = exc
            finally:
                removal_done.set()
                connections.close_all()

        threads = [
            threading.Thread(target=writer_worker, name="writer"),
            threading.Thread(target=removal_worker, name="removal"),
        ]
        for thread in threads:
            thread.start()
        paused = started.wait(timeout=20)
        removal_started.set()
        if paused and removal_first:
            removal_done.wait(timeout=20)
        proceed.set()
        for thread in threads:
            thread.join(timeout=30)

        self.assertTrue(paused, "the writer never reached its seam")
        self.assertEqual(set(results), {"write", "remove"}, results)
        for kind, outcome in results.items():
            self.assertNotIsInstance(
                outcome,
                Exception,
                f"the {kind} side crashed instead of being refused: {results!r}",
            )
        write_status, write_body = results["write"]
        remove_status, remove_body = results["remove"]
        if removal_first:
            self.assertEqual(write_status, 400, results)
            self.assertEqual(write_body.get("code"), "SELLING_UNIT_IN_USE", results)
            self.assertEqual(remove_status, 204, results)
        else:
            self.assertEqual(write_status, 201, results)
            self.assertEqual(remove_status, 400, results)
            self.assertEqual(remove_body.get("code"), "SELLING_UNIT_IN_USE", results)
        self.assertEqual(
            VariantUOM.objects.filter(pk=unit.pk).exists(),
            not removal_first,
            f"the catalogue and the answer disagree: {results!r}",
        )

    def _assert_rows(self, *, before, after, kept, what):
        """A refused writer leaves NO row; a committed one leaves exactly one line."""
        self.assertEqual(
            after[0] - before[0],
            1 if kept else 0,
            f"{what}: wrong number of parent rows ({before} -> {after})",
        )
        self.assertEqual(
            after[1] - before[1],
            1 if kept else 0,
            f"{what}: wrong number of line rows ({before} -> {after})",
        )

    # -- the writers, each paused on its own seam ---------------------------
    def _sale_writer(self, unit, removal_first):
        body = {
            "customer": self.walk_in.pk,
            "items": [{"variant_id": unit.pk, "qty": "1"}],
            "payments": [
                {"method": "CASH", "amount_tendered": str(unit.default_selling_price)}
            ],
        }

        def writer(client, auth, started, proceed):
            def pause():
                started.set()
                if not proceed.wait(timeout=20):
                    raise AssertionError("the sale was never released")

            if removal_first:
                # After the lines are validated and before the transaction: no lock is
                # held yet, so the removal is free to win.
                real = pos_services._validated_payments

                def paused(payments_data):
                    pause()
                    return real(payments_data)

                with mock.patch.object(
                    pos_services, "_validated_payments", side_effect=paused
                ):
                    return client.post(
                        "/api/v1/transactions/", body, format="json", **auth
                    )

            # At the first INSERT: inside the transaction, and - with the fix - already
            # holding the unit lock.
            real_create = SalesTransaction.objects.create

            def paused_create(*args, **kwargs):
                pause()
                return real_create(*args, **kwargs)

            with mock.patch.object(
                SalesTransaction.objects, "create", side_effect=paused_create
            ):
                return client.post("/api/v1/transactions/", body, format="json", **auth)

        return writer

    def _quotation_writer(self, unit, removal_first):
        body = {
            "customer": self.payer.pk,
            "items": [{"variant_uom": unit.pk, "qty": "1", "unit_price": "120"}],
        }

        def writer(client, auth, started, proceed):
            def pause():
                started.set()
                if not proceed.wait(timeout=20):
                    raise AssertionError("the quotation was never released")

            if removal_first:
                real = pos_serializers.QuotationSerializer.create

                def paused(serializer, validated_data):
                    pause()
                    return real(serializer, validated_data)

                with mock.patch.object(
                    pos_serializers.QuotationSerializer, "create", paused
                ):
                    return client.post(QUOTATIONS_URL, body, format="json", **auth)

            real_create = Quotation.objects.create

            def paused_create(*args, **kwargs):
                pause()
                return real_create(*args, **kwargs)

            with mock.patch.object(
                Quotation.objects, "create", side_effect=paused_create
            ):
                return client.post(QUOTATIONS_URL, body, format="json", **auth)

        return writer

    def _sales_order_writer(self, unit, removal_first):
        body = {
            "customer": self.payer.pk,
            "items": [{"variant_uom": unit.pk, "qty": "1", "unit_price": "120"}],
        }

        def writer(client, auth, started, proceed):
            def pause():
                started.set()
                if not proceed.wait(timeout=20):
                    raise AssertionError("the sales order was never released")

            if removal_first:
                real = pos_serializers.SalesOrderSerializer.create

                def paused(serializer, validated_data):
                    pause()
                    return real(serializer, validated_data)

                with mock.patch.object(
                    pos_serializers.SalesOrderSerializer, "create", paused
                ):
                    return client.post(SALES_ORDERS_URL, body, format="json", **auth)

            real_create = SalesOrder.objects.create

            def paused_create(*args, **kwargs):
                pause()
                return real_create(*args, **kwargs)

            with mock.patch.object(
                SalesOrder.objects, "create", side_effect=paused_create
            ):
                return client.post(SALES_ORDERS_URL, body, format="json", **auth)

        return writer

    def _cpms_writer(self, unit, removal_first):
        body = {
            "cpms_request_id": "CPMS-RACE-1",
            "token": str(uuid4()),
            "project": {
                "cpms_project_id": "PRJ-RACE-1",
                "name": "House Build",
                "payer": self.payer.pk,
            },
            "requester_name": "Ree Requester",
            "approver_name": "Ann Approver",
            "items": [{"code": unit.barcode_qr, "quantity": "1"}],
        }

        def writer(client, auth, started, proceed):
            def pause():
                started.set()
                if not proceed.wait(timeout=20):
                    raise AssertionError("the push was never released")

            if removal_first:
                # AFTER the codes are resolved and before the transaction: the lines are
                # already in hand, so this is exactly the window the lock closes.
                real = requisitions_services._resolved_lines

                def paused(items):
                    lines = real(items)
                    pause()
                    return lines

                with mock.patch.object(
                    requisitions_services, "_resolved_lines", side_effect=paused
                ):
                    return client.post(CPMS_REQUESTS_URL, body, format="json", **auth)

            real_create = Requisition.objects.create

            def paused_create(*args, **kwargs):
                pause()
                return real_create(*args, **kwargs)

            with mock.patch.object(
                Requisition.objects, "create", side_effect=paused_create
            ):
                return client.post(CPMS_REQUESTS_URL, body, format="json", **auth)

        return writer

    def _po_writer(self, unit, removal_first, supplier):
        """A purchase order that names `unit`, on the same seams as the other writers.

        Phase 5 B1: the line carries `variant_uom`, so the writer resolves the unit
        before its transaction and then takes the SAME PK-ordered row lock the removal
        takes. Removal-first pauses before that lock (the serializers' `create`);
        writer-first pauses at the first INSERT, which is already after the lock.
        """
        body = {
            "supplier": supplier.pk,
            "items": [
                {
                    "variant": self.variant.pk,
                    "variant_uom": unit.pk,
                    "ordered_qty": "1",
                    "unit_cost": "120",
                }
            ],
        }

        def writer(client, auth, started, proceed):
            def pause():
                started.set()
                if not proceed.wait(timeout=20):
                    raise AssertionError("the purchase order was never released")

            if removal_first:
                real = inventory_serializers.PurchaseOrderSerializer.create

                def paused(serializer, validated_data):
                    pause()
                    return real(serializer, validated_data)

                with mock.patch.object(
                    inventory_serializers.PurchaseOrderSerializer, "create", paused
                ):
                    return client.post(PURCHASE_ORDERS_URL, body, format="json", **auth)

            real_create = PurchaseOrder.objects.create

            def paused_create(*args, **kwargs):
                pause()
                return real_create(*args, **kwargs)

            with mock.patch.object(
                PurchaseOrder.objects, "create", side_effect=paused_create
            ):
                return client.post(PURCHASE_ORDERS_URL, body, format="json", **auth)

        return writer

    # -- one test per writer, both orders ----------------------------------
    def test_a_purchase_order_and_a_removal_of_its_unit_in_either_order(self):
        """Phase 5 B1: the PO writer takes the removal's lock, so neither answers 500."""
        for removal_first in (True, False):
            with self.subTest(removal_first=removal_first):
                unit = self._unit("PO1" if removal_first else "PO2")
                supplier = Supplier.objects.create(company_name=f"PO race {unit.pk}")
                before = (PurchaseOrder.objects.count(), POItem.objects.count())
                self._race(
                    unit=unit,
                    removal_first=removal_first,
                    writer=self._po_writer(unit, removal_first, supplier),
                    writer_user=self.stocker,
                )
                self._assert_rows(
                    before=before,
                    after=(PurchaseOrder.objects.count(), POItem.objects.count()),
                    kept=not removal_first,
                    what="purchase order",
                )

    def test_a_sale_and_a_removal_of_its_unit_in_either_order(self):
        for removal_first in (True, False):
            with self.subTest(removal_first=removal_first):
                unit = self._unit("SA1" if removal_first else "SA2")
                before = (SalesTransaction.objects.count(), SalesItem.objects.count())
                self._race(
                    unit=unit,
                    removal_first=removal_first,
                    writer=self._sale_writer(unit, removal_first),
                    writer_user=self.cashier,
                )
                self._assert_rows(
                    before=before,
                    after=(SalesTransaction.objects.count(), SalesItem.objects.count()),
                    kept=not removal_first,
                    what="sale",
                )

    def test_a_quotation_and_a_removal_of_its_unit_in_either_order(self):
        for removal_first in (True, False):
            with self.subTest(removal_first=removal_first):
                unit = self._unit("QU1" if removal_first else "QU2")
                before = (Quotation.objects.count(), QuotationItem.objects.count())
                self._race(
                    unit=unit,
                    removal_first=removal_first,
                    writer=self._quotation_writer(unit, removal_first),
                    writer_user=self.cashier,
                )
                self._assert_rows(
                    before=before,
                    after=(Quotation.objects.count(), QuotationItem.objects.count()),
                    kept=not removal_first,
                    what="quotation",
                )

    def test_a_sales_order_and_a_removal_of_its_unit_in_either_order(self):
        for removal_first in (True, False):
            with self.subTest(removal_first=removal_first):
                unit = self._unit("SO1" if removal_first else "SO2")
                before = (SalesOrder.objects.count(), SalesOrderItem.objects.count())
                self._race(
                    unit=unit,
                    removal_first=removal_first,
                    writer=self._sales_order_writer(unit, removal_first),
                    writer_user=self.cashier,
                )
                self._assert_rows(
                    before=before,
                    after=(SalesOrder.objects.count(), SalesOrderItem.objects.count()),
                    kept=not removal_first,
                    what="sales order",
                )

    def test_a_cpms_import_and_a_removal_of_its_unit_in_either_order(self):
        for removal_first in (True, False):
            with self.subTest(removal_first=removal_first):
                unit = self._unit("CP1" if removal_first else "CP2")
                before = (
                    Requisition.objects.count(),
                    RequisitionItem.objects.count(),
                    Project.objects.count(),
                )
                self._race(
                    unit=unit,
                    removal_first=removal_first,
                    writer=self._cpms_writer(unit, removal_first),
                    writer_user=self.cpms,
                )
                self._assert_rows(
                    before=before[:2],
                    after=(
                        Requisition.objects.count(),
                        RequisitionItem.objects.count(),
                    ),
                    kept=not removal_first,
                    what="CPMS import",
                )
                self.assertEqual(
                    Project.objects.count() - before[2],
                    1 if not removal_first else 0,
                    "a refused push must leave no project row behind either",
                )

    def test_two_removals_of_one_unit_answer_a_404_not_a_500(self):
        """Both requests read the row, then the second one finds it gone.

        Forced by holding the loser INSIDE `get_object` (after its read returned the
        row) until the winner has committed the delete, so the loser's lock step is the
        only thing left - which is exactly where a bare `.get()` raised `DoesNotExist`
        and turned a harmless double-click into a 500.
        """
        unit = self.units[0]
        read_done = threading.Event()
        removed = threading.Event()
        results = {}
        real_get_object = inventory_views.VariantUOMViewSet.get_object

        def get_object(view):
            row = real_get_object(view)
            if threading.current_thread().name == "delayed":
                read_done.set()
                if not removed.wait(timeout=20):
                    raise AssertionError("the winning removal never finished")
            return row

        def removal(name, delayed):
            client = APIClient()
            auth = self._login(client, self.stocker)
            try:
                if not delayed and not read_done.wait(timeout=20):
                    raise AssertionError("the other removal never read the row")
                if delayed:
                    with mock.patch.object(
                        inventory_views.VariantUOMViewSet, "get_object", get_object
                    ):
                        response = client.delete(
                            f"{VARIANT_UOMS_URL}{unit.pk}/", **auth
                        )
                else:
                    response = client.delete(f"{VARIANT_UOMS_URL}{unit.pk}/", **auth)
                results[name] = (response.status_code, dict(response.data or {}))
            except Exception as exc:  # a 5xx escapes the test client as an exception
                results[name] = exc
            finally:
                if not delayed:
                    removed.set()
                connections.close_all()

        threads = [
            threading.Thread(target=removal, args=("delayed", True), name="delayed"),
            threading.Thread(target=removal, args=("winner", False), name="winner"),
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)

        self.assertEqual(set(results), {"delayed", "winner"}, results)
        for kind, outcome in results.items():
            self.assertNotIsInstance(
                outcome,
                Exception,
                f"the {kind} removal crashed instead of answering 404: {results!r}",
            )
        self.assertEqual(results["winner"][0], 204, results)
        self.assertEqual(results["delayed"][0], 404, results)
        self.assertFalse(VariantUOM.objects.filter(pk=unit.pk).exists())
        self.assertEqual(
            AuditLog.objects.filter(action_type=AuditLog.ActionType.DELETE).count(),
            1,
            "one removal happened, so exactly one DELETE row belongs in the trail",
        )
