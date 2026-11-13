# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Phase 8 B2 (decision 20) — a supplier return takes stock off the receipt it came in on.

What this file pins:

* **Only the chosen receipt's stock leaves.** Two deliveries of one variant are two
  batches; a return from receipt A must not touch receipt B's batch. `allocate_fifo`
  cannot do this (it is variant-wide), which is why `allocate_from_receipt` exists.
* **The cap is what is really still there.** Per line: the DELIVERED base quantity minus
  what that line already returned, and never more than the receipt's batches still hold
  (a sale or a damage adjustment may have emptied them).
* **A refusal writes nothing** — no return, no line, no deduction, no batch change — for
  an over-cap, fractional, unrepresentable, blank-reason, unprocessed-receipt or
  wrong-receipt-line request.
* **The deduction rows are the provenance**: one per batch touched, summing to the line's
  base quantity, each carrying the landed cost it was taken at.
* **Stock going back out re-runs the low-stock check**, and the whole act is audited once
  as `SUPPLIER_RETURN`.
* **Roles**: Stock Manager / Store Manager / Admin record and read returns; a Cashier and
  the CPMS account are refused the route set.
* **Append-only**: a return, its lines and its deductions cannot be edited or deleted.

Phase 8 B3 (decision 20 #1) adds the money side, pinned in the last four classes here:

* **Every return mints ONE numbered credit note** (`CN-YYYYMMDD-NNNN`) whose value is the
  landed cost of what went back, rounded once, with VAT taken from the source bill's
  snapshot (inclusive: the total IS the value, VAT extracted; exclusive: VAT added on).
* **The note lowers the source bill first** and whatever the bill cannot absorb stays as
  supplier credit (`remaining_amount`) - a settled bill, or a receipt that never had one,
  leaves the whole credit unapplied.
* **The application is a real payment**: `method=CREDIT`, linked to the note, CLEARED at
  once, audited as `PAYMENT`.
* **A note cannot be edited or deleted**; only `remaining_amount` ever moves.
"""

from decimal import Decimal
from unittest import mock

from django.db import IntegrityError, transaction

from apps.users.models import AuditLog

from .exceptions import ImmutablePayableRecord
from .models import (
    GoodsReceiptItem,
    InventoryBatch,
    Supplier,
    SupplierBill,
    SupplierCreditNote,
    SupplierPayment,
    SupplierReturn,
    SupplierReturnDeduction,
    SupplierReturnLine,
    SystemAlert,
    UnitOfMeasure,
    VariantUOM,
)
from .services import record_supplier_return
from .tests_supplier_payables import PayablesTestBase

RETURNS_URL = "/api/v1/supplier-returns/"
RECEIPTS_URL = "/api/v1/goods-receipts/"
PAYMENTS_URL = "/api/v1/supplier-payments/"
CREDIT_NOTES_URL = "/api/v1/supplier-credit-notes/"


class ReturnTestBase(PayablesTestBase):
    REASON = "Dented bags refused at the gate"

    def _lines(self, receipt):
        return list(GoodsReceiptItem.objects.filter(receipt=receipt).order_by("id"))

    def _post_return(self, *, receipt, lines, user=None, reason=None):
        payload = {
            "receipt": receipt.pk,
            "reason": self.REASON if reason is None else reason,
            "lines": lines,
        }
        return self._login(user or self.stocker).post(
            RETURNS_URL, payload, format="json"
        )

    def _package_unit(self):
        """A whole unit worth `factor` base units, for the conversion tests."""
        uom, _ = UnitOfMeasure.objects.get_or_create(
            code="BOX", defaults={"name": "Box", "is_whole": True}
        )
        uom.is_whole = True
        uom.save(update_fields=["is_whole"])
        return VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal(10),
            default_selling_price=Decimal(100),
        )

    def _assert_nothing_written(self):
        self.assertFalse(SupplierReturn.objects.exists())
        self.assertFalse(SupplierReturnLine.objects.exists())
        self.assertFalse(SupplierReturnDeduction.objects.exists())
        self.assertFalse(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.SUPPLIER_RETURN
            ).exists()
        )


class SupplierReturnStockTests(ReturnTestBase):
    """Stock leaves ONE receipt's batches, capped by what that line and that rack hold."""

    def setUp(self):
        super().setUp()
        self.po, self.item = self._po(ordered="20", cost="100")
        self.receipt_a = self._receipt(self.po, [(self.item, "5")])
        self.receipt_b = self._receipt(self.po, [(self.item, "5")])
        self._process(self.receipt_a)
        self._process(self.receipt_b)

    def _batch(self, receipt):
        return InventoryBatch.objects.get(receipt=receipt, variant=self.variant)

    def test_returns_take_stock_only_from_the_chosen_receipt(self):
        line = self._lines(self.receipt_a)[0]

        response = self._post_return(
            receipt=self.receipt_a,
            lines=[{"receipt_line": line.pk, "qty": "2"}],
        )

        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(self._batch(self.receipt_a).current_qty, Decimal(3))
        # The other delivery of the SAME variant is untouched: FIFO would have taken it.
        self.assertEqual(self._batch(self.receipt_b).current_qty, Decimal(5))
        self.assertEqual(
            [d.batch_id for d in SupplierReturnDeduction.objects.all()],
            [self._batch(self.receipt_a).pk],
        )

    def test_one_deduction_per_batch_touched_sums_to_the_line_base_qty(self):
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "3"), (item, "4")])
        self._process(receipt)
        first, second = list(
            InventoryBatch.objects.filter(receipt=receipt).order_by("pk")
        )
        # A sale took 2 off the oldest batch, so only 1 is left there.
        first.current_qty = Decimal(1)
        first.save(update_fields=["current_qty"])
        line = self._lines(receipt)[0]  # delivered 3 base units

        response = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "3"}]
        )

        self.assertEqual(response.status_code, 201, response.data)
        body = response.data["lines"][0]
        self.assertEqual(Decimal(body["base_qty"]), Decimal(3))
        deductions = list(
            SupplierReturnDeduction.objects.filter(line_id=body["id"]).order_by("pk")
        )
        self.assertEqual([d.batch_id for d in deductions], [first.pk, second.pk])
        self.assertEqual([d.qty for d in deductions], [Decimal(1), Decimal(2)])
        self.assertEqual(sum(d.qty for d in deductions), Decimal(body["base_qty"]))
        self.assertEqual(
            [d.unit_cost_landed for d in deductions],
            [Decimal("100.00"), Decimal("100.00")],
        )
        # 3 base units at P100.00 landed each, rounded once.
        self.assertEqual(Decimal(body["credit_value"]), Decimal("300.00"))
        first.refresh_from_db()
        second.refresh_from_db()
        self.assertEqual(first.current_qty, Decimal(0))
        self.assertEqual(second.current_qty, Decimal(2))

    def test_the_cap_is_what_the_receipt_still_holds(self):
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "3"), (item, "4")])
        self._process(receipt)
        first, second = list(
            InventoryBatch.objects.filter(receipt=receipt).order_by("pk")
        )
        second.current_qty = Decimal(0)
        second.save(update_fields=["current_qty"])
        line = self._lines(receipt)[1]  # delivered 4, only 3 still on the rack

        refused = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "4"}]
        )

        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "RETURN_EXCEEDS_RECEIPT")
        self._assert_nothing_written()
        first.refresh_from_db()
        self.assertEqual(first.current_qty, Decimal(3))

        accepted = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "3"}]
        )
        self.assertEqual(accepted.status_code, 201, accepted.data)
        first.refresh_from_db()
        self.assertEqual(first.current_qty, Decimal(0))

    def test_the_cap_subtracts_what_the_line_already_returned(self):
        line = self._lines(self.receipt_a)[0]  # delivered 5

        self.assertEqual(
            self._post_return(
                receipt=self.receipt_a,
                lines=[{"receipt_line": line.pk, "qty": "4"}],
            ).status_code,
            201,
        )
        refused = self._post_return(
            receipt=self.receipt_a, lines=[{"receipt_line": line.pk, "qty": "2"}]
        )
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "RETURN_EXCEEDS_RECEIPT")
        self.assertEqual(SupplierReturn.objects.count(), 1)

        accepted = self._post_return(
            receipt=self.receipt_a, lines=[{"receipt_line": line.pk, "qty": "1"}]
        )
        self.assertEqual(accepted.status_code, 201, accepted.data)
        self.assertEqual(
            SupplierReturnLine.objects.order_by("pk").values_list(
                "base_qty", flat=True
            )[1],
            Decimal("1.00"),
        )


class SupplierReturnRefusalTests(ReturnTestBase):
    """Every refusal a clerk can reach leaves the books exactly as they were."""

    def setUp(self):
        super().setUp()
        self.po, self.item = self._po(ordered="10", cost="100")
        self.receipt = self._receipt(self.po, [(self.item, "5")])
        self._process(self.receipt)
        self.line = self._lines(self.receipt)[0]

    def test_a_return_above_the_delivered_quantity_is_refused(self):
        response = self._post_return(
            receipt=self.receipt, lines=[{"receipt_line": self.line.pk, "qty": "6"}]
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "RETURN_EXCEEDS_RECEIPT")
        self._assert_nothing_written()
        self.assertEqual(
            InventoryBatch.objects.get(receipt=self.receipt).current_qty, Decimal(5)
        )

    def test_a_fractional_quantity_on_a_whole_unit_is_refused(self):
        unit = self._package_unit()  # 1 BOX = 10 base units, whole counts only
        po, item = self._po(ordered="10", cost="100", unit=unit)
        receipt = self._receipt(po, [(item, "4")])
        self._process(receipt)
        line = self._lines(receipt)[0]

        response = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "1.5"}]
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "WHOLE_UNIT_QUANTITY")
        self._assert_nothing_written()
        self.assertEqual(
            InventoryBatch.objects.get(receipt=receipt).current_qty, Decimal(40)
        )

    def test_a_quantity_that_is_not_a_whole_hundredth_of_stock_is_refused(self):
        # KG is a MEASURED unit (migration 0008), so 0.5 of it is not itself refused;
        # what is refused is the stock it converts to.
        uom = UnitOfMeasure.objects.get(code="KG")
        unit = VariantUOM.objects.create(
            variant=self.variant,
            uom=uom,
            conversion_factor=Decimal("0.03"),
            default_selling_price=Decimal(10),
        )
        po, item = self._po(ordered="10", cost="10", unit=unit)
        receipt = self._receipt(po, [(item, "1")])  # 0.03 base units, storable
        self._process(receipt)
        line = self._lines(receipt)[0]

        response = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "0.5"}]
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "RECEIPT_QUANTITY_UNREPRESENTABLE")
        self._assert_nothing_written()

    def test_a_blank_reason_is_refused(self):
        for reason in ("", "   "):
            with self.subTest(reason=repr(reason)):
                response = self._post_return(
                    receipt=self.receipt,
                    lines=[{"receipt_line": self.line.pk, "qty": "1"}],
                    reason=reason,
                )

                self.assertEqual(response.status_code, 400, response.data)
                self.assertEqual(response.data["code"], "INVALID_SUPPLIER_RETURN")
                self._assert_nothing_written()

    def test_an_unprocessed_receipt_is_refused(self):
        po, item = self._po(ordered="10", cost="100")
        unprocessed = self._receipt(po, [(item, "5")])
        line = self._lines(unprocessed)[0]

        response = self._post_return(
            receipt=unprocessed, lines=[{"receipt_line": line.pk, "qty": "1"}]
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "RECEIPT_NOT_PROCESSED")
        self.assertFalse(SupplierReturn.objects.exists())

    def test_a_receipt_line_of_another_receipt_is_refused(self):
        po, item = self._po(ordered="10", cost="100")
        other = self._receipt(po, [(item, "5")])
        self._process(other)
        foreign_line = self._lines(other)[0]

        response = self._post_return(
            receipt=self.receipt,
            lines=[{"receipt_line": foreign_line.pk, "qty": "1"}],
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SUPPLIER_RETURN")
        self._assert_nothing_written()


class SupplierReturnUnitTests(ReturnTestBase):
    """The quantity is entered and reported in the receipt LINE's package unit."""

    def test_a_package_quantity_is_stored_as_its_base_quantity(self):
        unit = self._package_unit()  # 1 BOX = 10 base units
        po, item = self._po(ordered="10", cost="100", unit=unit)
        receipt = self._receipt(po, [(item, "4")])  # 4 BOX = 40 base units
        self._process(receipt)
        line = self._lines(receipt)[0]

        response = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "1"}]
        )

        self.assertEqual(response.status_code, 201, response.data)
        body = response.data["lines"][0]
        self.assertEqual(Decimal(body["qty"]), Decimal(1))
        self.assertEqual(Decimal(body["base_qty"]), Decimal("10.00"))
        # landed cost is per BASE unit: P100.00 per BOX / 10 = P10.00 per unit.
        self.assertEqual(Decimal(body["credit_value"]), Decimal("100.00"))
        self.assertEqual(
            InventoryBatch.objects.get(receipt=receipt).current_qty, Decimal(30)
        )


class SupplierReturnSideEffectTests(ReturnTestBase):
    """Stock went out: the low-stock check runs, and the act is audited once."""

    def test_a_return_below_the_threshold_raises_the_low_stock_alert(self):
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "5")])  # threshold is 5, so no alert yet
        self._process(receipt)
        self.assertFalse(SystemAlert.objects.filter(is_resolved=False).exists())
        line = self._lines(receipt)[0]

        response = self._post_return(
            receipt=receipt, lines=[{"receipt_line": line.pk, "qty": "2"}]
        )

        self.assertEqual(response.status_code, 201, response.data)
        alert = SystemAlert.objects.get(variant=self.variant)
        self.assertEqual(alert.alert_type, SystemAlert.AlertType.LOW_STOCK)
        self.assertFalse(alert.is_resolved)

    def test_the_return_is_one_audited_event(self):
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "5")])
        self._process(receipt)
        line = self._lines(receipt)[0]

        response = self._post_return(
            receipt=receipt,
            lines=[{"receipt_line": line.pk, "qty": "2"}],
            user=self.manager,
        )

        self.assertEqual(response.status_code, 201, response.data)
        log = AuditLog.objects.get(action_type=AuditLog.ActionType.SUPPLIER_RETURN)
        self.assertEqual(log.user_id, self.manager.pk)
        self.assertIn(f"#{response.data['id']}", log.description)
        self.assertIn(f"#{receipt.pk}", log.description)

    def test_every_inventory_role_may_record_a_return(self):
        self.po, self.item = self._po(ordered="10", cost="100")
        for user in (self.stocker, self.manager, self.admin):
            with self.subTest(role=user.username):
                receipt = self._receipt(self.po, [(self.item, "1")])
                self._process(receipt)
                line = self._lines(receipt)[0]

                response = self._post_return(
                    receipt=receipt,
                    lines=[{"receipt_line": line.pk, "qty": "1"}],
                    user=user,
                )

                self.assertEqual(response.status_code, 201, response.data)

    def test_a_cashier_and_the_cpms_account_are_refused(self):
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "5")])
        self._process(receipt)
        line = self._lines(receipt)[0]

        for user in (self.cashier, self.cpms):
            with self.subTest(role=user.username):
                posted = self._post_return(
                    receipt=receipt,
                    lines=[{"receipt_line": line.pk, "qty": "1"}],
                    user=user,
                )
                self.assertEqual(posted.status_code, 403, posted.data)
                read = self._login(user).get(RETURNS_URL)
                self.assertEqual(read.status_code, 403, read.data)
        self._assert_nothing_written()


class SupplierReturnReadTests(ReturnTestBase):
    """The list and detail, and the returnable report a client fills the form from."""

    def setUp(self):
        super().setUp()
        self.unit = self._package_unit()  # 1 BOX = 10 base units
        self.po, self.item = self._po(ordered="10", cost="100", unit=self.unit)
        self.receipt = self._receipt(self.po, [(self.item, "4")])  # 4 BOX
        self._process(self.receipt)
        self.line = self._lines(self.receipt)[0]
        self.created = self._post_return(
            receipt=self.receipt,
            lines=[{"receipt_line": self.line.pk, "qty": "1"}],
        )
        self.assertEqual(self.created.status_code, 201, self.created.data)

    def test_returnable_reports_each_line_in_its_own_unit(self):
        response = self._login(self.stocker).get(
            f"{RECEIPTS_URL}{self.receipt.pk}/returnable/"
        )

        self.assertEqual(response.status_code, 200, response.data)
        row = response.data[0]
        self.assertEqual(row["receipt_line"], self.line.pk)
        self.assertEqual(row["unit"], "BOX")
        self.assertEqual(Decimal(row["delivered"]), Decimal("4.00"))
        self.assertEqual(Decimal(row["returned"]), Decimal("1.00"))
        self.assertEqual(Decimal(row["returnable"]), Decimal("3.00"))

    def test_returnable_never_exceeds_the_stock_on_hand(self):
        batch = InventoryBatch.objects.get(receipt=self.receipt)
        batch.current_qty = Decimal(5)  # 0.5 BOX left on the rack
        batch.save(update_fields=["current_qty"])

        response = self._login(self.stocker).get(
            f"{RECEIPTS_URL}{self.receipt.pk}/returnable/"
        )

        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(Decimal(response.data[0]["returnable"]), Decimal("0.5"))

    def test_returnable_is_inventory_role_only(self):
        for user in (self.cashier, self.cpms):
            with self.subTest(role=user.username):
                response = self._login(user).get(
                    f"{RECEIPTS_URL}{self.receipt.pk}/returnable/"
                )
                self.assertEqual(response.status_code, 403, response.data)

    def test_the_list_filters_by_supplier_and_receipt(self):
        other_supplier = Supplier.objects.create(company_name="Other Hardware")
        po, item = self._po(ordered="10", cost="100", supplier=other_supplier)
        receipt = self._receipt(po, [(item, "2")])
        self._process(receipt)
        self._post_return(
            receipt=receipt,
            lines=[{"receipt_line": self._lines(receipt)[0].pk, "qty": "1"}],
        )
        client = self._login(self.stocker)

        mine = client.get(f"{RETURNS_URL}?supplier={self.supplier.pk}")
        self.assertEqual(mine.status_code, 200, mine.data)
        self.assertEqual(mine.data["count"], 1)
        self.assertEqual(mine.data["results"][0]["receipt"], self.receipt.pk)

        by_receipt = client.get(f"{RETURNS_URL}?receipt={receipt.pk}")
        self.assertEqual(by_receipt.status_code, 200, by_receipt.data)
        self.assertEqual(by_receipt.data["results"][0]["receipt"], receipt.pk)

        detail = client.get(f"{RETURNS_URL}{self.created.data['id']}/")
        self.assertEqual(detail.status_code, 200, detail.data)
        self.assertEqual(len(detail.data["lines"]), 1)
        self.assertEqual(detail.data["reason"], self.REASON)

    def test_a_return_cannot_be_edited_or_deleted_over_the_api(self):
        pk = self.created.data["id"]

        self.assertEqual(
            self._login(self.stocker)
            .patch(f"{RETURNS_URL}{pk}/", {"reason": "changed"}, format="json")
            .status_code,
            405,
        )
        self.assertEqual(
            self._login(self.stocker).delete(f"{RETURNS_URL}{pk}/").status_code, 405
        )


class SupplierReturnImmutableTests(ReturnTestBase):
    """The rows are evidence of stock that moved: they are written once and kept."""

    def setUp(self):
        super().setUp()
        po, item = self._po(ordered="10", cost="100")
        receipt = self._receipt(po, [(item, "4")])
        self._process(receipt)
        line = self._lines(receipt)[0]
        self.returned = record_supplier_return(
            receipt=receipt,
            reason=self.REASON,
            lines=[(line, Decimal(2))],
            user=self.manager,
        )
        self.return_line = self.returned.lines.get()
        self.deduction = self.return_line.deductions.get()

    def test_a_return_cannot_be_reasoned_away(self):
        self.returned.reason = "a different story"
        with self.assertRaises(ImmutablePayableRecord):
            self.returned.save()
        self.returned.refresh_from_db()
        self.assertEqual(self.returned.reason, self.REASON)

    def test_a_return_cannot_be_deleted(self):
        with self.assertRaises(ImmutablePayableRecord):
            self.returned.delete()
        with self.assertRaises(ImmutablePayableRecord):
            self.return_line.delete()
        with self.assertRaises(ImmutablePayableRecord):
            self.deduction.delete()
        self.assertEqual(SupplierReturn.objects.count(), 1)
        self.assertEqual(SupplierReturnLine.objects.count(), 1)
        self.assertEqual(SupplierReturnDeduction.objects.count(), 1)

    def test_a_line_or_deduction_cannot_be_edited(self):
        self.return_line.base_qty = Decimal(99)
        with self.assertRaises(ImmutablePayableRecord):
            self.return_line.save()
        self.deduction.qty = Decimal(99)
        with self.assertRaises(ImmutablePayableRecord):
            self.deduction.save()

    def test_the_return_records_its_supplier_receipt_and_bill(self):
        self.assertEqual(self.returned.receipt_id, self.returned.receipt.pk)
        self.assertEqual(self.returned.supplier_id, self.supplier.pk)
        self.assertEqual(self.returned.purchase_order_id, self.returned.receipt.po_id)
        # A processed receipt has a bill (Phase 5 B2), so the return points at it.
        self.assertEqual(self.returned.bill_id, self.returned.receipt.bill.pk)
        self.assertEqual(self.returned.created_by_id, self.manager.pk)


# =========================================================================
# Phase 8 B3 (decision 20 #1) — the numbered credit note and its application
# =========================================================================


class CreditNoteTestBase(ReturnTestBase):
    """One helper: post a return and hand back the note it must have minted."""

    def _return(self, *, receipt, qty="1", user=None):
        line = self._lines(receipt)[0]
        response = self._post_return(
            receipt=receipt,
            lines=[{"receipt_line": line.pk, "qty": qty}],
            user=user,
        )
        self.assertEqual(response.status_code, 201, response.data)
        note = SupplierCreditNote.objects.get(supplier_return_id=response.data["id"])
        return response, note

    def _receipt_for(self, *, delivered="2", cost="100", **po_money):
        po, item = self._po(ordered="10", cost=cost, **po_money)
        receipt = self._receipt(po, [(item, delivered)])
        self._process(receipt)
        return receipt


class CreditNoteValueTests(CreditNoteTestBase):
    """Value = landed cost of what went back; VAT follows the bill's own snapshot."""

    def test_an_inclusive_bill_keeps_the_value_as_the_total_and_extracts_vat(self):
        # 2 base units at 100.00 landed each = a 200.00 bill, VAT extracted at 12%.
        receipt = self._receipt_for(vat_inclusive=True, vat_rate="12")

        response, note = self._return(receipt=receipt)

        self.assertEqual(note.value, Decimal("100.00"))
        self.assertEqual(note.vat_rate, Decimal("12.00"))
        self.assertTrue(note.vat_inclusive)
        # 100 / 1.12 = 89.2857 -> 89.29 vatable, so the tax is the 10.71 remainder.
        self.assertEqual(note.vat_amount, Decimal("10.71"))
        self.assertEqual(note.total_amount, Decimal("100.00"))
        self.assertEqual(Decimal(response.data["credit_note_total"]), Decimal("100.00"))
        self.assertEqual(
            Decimal(response.data["credit_note_remaining"]), Decimal("0.00")
        )

    def test_an_exclusive_bill_adds_the_vat_on_top_of_the_value(self):
        receipt = self._receipt_for(vat_inclusive=False, vat_rate="12")

        _, note = self._return(receipt=receipt)

        self.assertEqual(note.value, Decimal("100.00"))
        self.assertFalse(note.vat_inclusive)
        self.assertEqual(note.vat_amount, Decimal("12.00"))  # 100 x 12%
        self.assertEqual(note.total_amount, Decimal("112.00"))
        # The bill was 2 x 100 + VAT = 224.00, so 112.00 is exactly half.
        self.assertEqual(
            SupplierBill.objects.get(receipt=receipt).balance_amount, Decimal("112.00")
        )

    def test_a_non_registered_bill_credits_the_value_with_no_vat(self):
        receipt = self._receipt_for(vat_inclusive=True, vat_rate="0")

        _, note = self._return(receipt=receipt)

        self.assertEqual(note.vat_amount, Decimal("0.00"))
        self.assertEqual(note.total_amount, note.value)

    def test_the_note_number_is_the_day_stamped_sequence(self):
        receipt = self._receipt_for()
        _, first = self._return(receipt=receipt, qty="1")

        self.assertRegex(first.number, r"^CN-\d{8}-0001$")

        _, second = self._return(receipt=receipt, qty="1")

        self.assertRegex(second.number, r"^CN-\d{8}-0002$")
        self.assertNotEqual(first.number, second.number)

    def test_the_note_belongs_to_its_return_supplier_and_bill(self):
        receipt = self._receipt_for()
        response, note = self._return(receipt=receipt)

        self.assertEqual(note.supplier_return_id, response.data["id"])
        self.assertEqual(note.supplier_id, self.supplier.pk)
        self.assertEqual(
            note.source_bill_id, SupplierBill.objects.get(receipt=receipt).pk
        )
        self.assertEqual(response.data["credit_note_number"], note.number)
        self.assertEqual(Decimal(response.data["credit_note_total"]), note.total_amount)


class CreditNoteApplyTests(CreditNoteTestBase):
    """The note lowers its own bill first; what the bill cannot absorb stays as credit."""

    def _pay(self, bill, amount):
        response = self._login(self.manager).post(
            "/api/v1/supplier-payments/",
            {"bill": bill.pk, "amount": amount, "method": "CASH"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response

    def test_credit_below_the_balance_lowers_the_bill_and_leaves_no_remainder(self):
        receipt = self._receipt_for()  # bill 200.00
        bill = SupplierBill.objects.get(receipt=receipt)

        _, note = self._return(receipt=receipt, qty="1")

        bill.refresh_from_db()
        note.refresh_from_db()
        self.assertEqual(note.total_amount, Decimal("100.00"))
        self.assertEqual(note.remaining_amount, Decimal("0.00"))
        self.assertEqual(bill.balance_amount, Decimal("100.00"))
        payment = SupplierPayment.objects.get(method=SupplierPayment.Method.CREDIT)
        self.assertEqual(payment.credit_note_id, note.pk)
        self.assertEqual(payment.bill_id, bill.pk)
        self.assertEqual(payment.amount, Decimal("100.00"))
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)
        self.assertEqual(payment.paid_by_id, self.stocker.pk)

    def test_credit_above_the_balance_leaves_the_remainder_unapplied(self):
        receipt = self._receipt_for()  # bill 200.00
        bill = SupplierBill.objects.get(receipt=receipt)
        self._pay(bill, "150")  # 50.00 left to pay

        _, note = self._return(receipt=receipt, qty="2")  # worth 200.00

        bill.refresh_from_db()
        note.refresh_from_db()
        self.assertEqual(note.total_amount, Decimal("200.00"))
        self.assertEqual(note.remaining_amount, Decimal("150.00"))
        self.assertEqual(bill.balance_amount, Decimal("0.00"))
        self.assertEqual(bill.status, SupplierBill.Status.PAID)
        payment = SupplierPayment.objects.get(method=SupplierPayment.Method.CREDIT)
        self.assertEqual(payment.amount, Decimal("50.00"))

    def test_a_paid_bill_leaves_the_whole_credit_unapplied(self):
        receipt = self._receipt_for()
        bill = SupplierBill.objects.get(receipt=receipt)
        self._pay(bill, "200")

        _, note = self._return(receipt=receipt, qty="1")

        bill.refresh_from_db()
        self.assertEqual(bill.balance_amount, Decimal("0.00"))
        self.assertEqual(note.remaining_amount, note.total_amount)
        self.assertEqual(note.remaining_amount, Decimal("100.00"))
        self.assertFalse(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CREDIT
            ).exists()
        )

    def test_a_receipt_that_never_had_a_bill_leaves_the_whole_credit_unapplied(self):
        # Production guard: a pre-Phase-5 receipt, or a zero-value delivery, has no bill.
        with mock.patch(
            "apps.inventory.payables.create_bill_for_receipt", return_value=None
        ):
            receipt = self._receipt_for()

        _, note = self._return(receipt=receipt, qty="1")

        self.assertIsNone(note.source_bill_id)
        self.assertEqual(note.total_amount, Decimal("100.00"))
        self.assertEqual(note.remaining_amount, Decimal("100.00"))
        self.assertFalse(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CREDIT
            ).exists()
        )

    def test_the_application_is_audited_as_a_payment(self):
        receipt = self._receipt_for()

        _, note = self._return(receipt=receipt, qty="1", user=self.manager)

        row = AuditLog.objects.get(action_type=AuditLog.ActionType.PAYMENT)
        self.assertEqual(row.user_id, self.manager.pk)
        self.assertIn(note.number, row.description)


class CreditNoteImmutableTests(CreditNoteTestBase):
    """A note is evidence of credit the shop is owed: written once, only its balance moves."""

    def setUp(self):
        super().setUp()
        receipt = self._receipt_for()
        self.response, self.note = self._return(receipt=receipt, qty="2")
        self.returned = SupplierReturn.objects.get(pk=self.response.data["id"])

    def test_a_note_cannot_be_edited(self):
        self.note.value = Decimal("1.00")
        with self.assertRaises(ImmutablePayableRecord):
            self.note.save()
        self.note.refresh_from_db()
        self.assertEqual(self.note.value, Decimal("200.00"))

    def test_a_note_cannot_be_deleted(self):
        with self.assertRaises(ImmutablePayableRecord):
            self.note.delete()
        self.assertEqual(SupplierCreditNote.objects.count(), 1)

    def test_only_the_remaining_amount_may_move(self):
        self.note.remaining_amount = Decimal("50.00")
        self.note.save(update_fields=["remaining_amount"])

        self.note.refresh_from_db()
        self.assertEqual(self.note.remaining_amount, Decimal("50.00"))

    def test_a_note_is_read_only_over_the_api(self):
        pk = self.returned.credit_note.pk
        client = self._login(self.manager)

        self.assertEqual(
            client.patch(
                f"{RETURNS_URL}{self.response.data['id']}/", {}, format="json"
            ).status_code,
            405,
        )
        self.assertEqual(
            client.delete(f"{RETURNS_URL}{self.response.data['id']}/").status_code,
            405,
        )
        self.assertEqual(self.note.pk, pk)

    def test_a_return_cannot_grow_a_second_note(self):
        with self.assertRaises(IntegrityError), transaction.atomic():
            SupplierCreditNote.objects.create(
                number="CN-19990101-0001",
                supplier_return=self.returned,
                supplier=self.supplier,
                value=Decimal("1.00"),
                vat_rate=Decimal(0),
                vat_inclusive=True,
                vat_amount=Decimal("0.00"),
                total_amount=Decimal("1.00"),
                remaining_amount=Decimal("1.00"),
            )
        self.assertEqual(SupplierCreditNote.objects.count(), 1)


# =========================================================================
# Phase 8 B4 - applying supplier credit by hand
# =========================================================================


class ManualCreditApplicationTests(CreditNoteTestBase):
    """A manager spends a note on ANY bill of the same supplier, by hand (B4).

    The auto rule (B3) only ever reaches the note's own bill. What a bill could not
    absorb stays on the note as supplier credit, and this is the endpoint that spends it:
    `POST /supplier-payments/ {bill, amount, method: CREDIT, credit_note}`, capped at
    `min(note remaining, bill balance)` and refused when the note belongs to another
    supplier.
    """

    def setUp(self):
        super().setUp()
        # Receipt A: 2 x 100.00 -> a 200.00 bill, PAID IN FULL, so the return's credit has
        # nothing to lower and stays on the note as supplier credit (200.00 open).
        self.receipt_a = self._receipt_for()
        self.bill_a = SupplierBill.objects.get(receipt=self.receipt_a)
        self._pay(self.bill_a, "200")
        _, self.note = self._return(receipt=self.receipt_a, qty="2")
        # Receipt B: 3 x 100.00 -> a 300.00 bill of the SAME supplier, still owed.
        po_b, item_b = self._po(ordered="10", cost="100")
        self.bill_b = self._bill(self._receipt(po_b, [(item_b, "3")]))

    def _pay(self, bill, amount, user=None):
        response = self._login(user or self.manager).post(
            PAYMENTS_URL,
            {"bill": bill.pk, "amount": amount, "method": "CASH"},
            format="json",
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response

    def _apply(self, *, amount="100", bill=None, note=None, user=None, **extra):
        payload = {
            "bill": (bill or self.bill_b).pk,
            "amount": amount,
            "method": "CREDIT",
            "credit_note": (note or self.note).pk,
        }
        payload.update(extra)
        return self._login(user or self.manager).post(
            PAYMENTS_URL, payload, format="json"
        )

    def _foreign_note(self):
        other = Supplier.objects.create(company_name="Other Supply")
        po, item = self._po(ordered="10", cost="100", supplier=other)
        receipt = self._receipt(po, [(item, "1")])
        self._pay(self._bill(receipt), "100")  # settle it, so the note stays open
        _, note = self._return(receipt=receipt, qty="1")
        return note

    def _assert_nothing_moved(self):
        self.bill_b.refresh_from_db()
        self.note.refresh_from_db()
        self.assertEqual(self.bill_b.balance_amount, Decimal("300.00"))
        self.assertEqual(self.note.remaining_amount, Decimal("200.00"))
        self.assertFalse(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CREDIT
            ).exists()
        )
        # setUp paid one bill in cash, which audits as PAYMENT - so the question is
        # whether THIS note was applied, not whether any payment was ever audited.
        self.assertFalse(
            AuditLog.objects.filter(
                action_type=AuditLog.ActionType.PAYMENT,
                description__contains=self.note.number,
            ).exists()
        )

    def test_a_manager_applies_part_of_the_note_to_another_bill(self):
        response = self._apply(amount="120")

        self.assertEqual(response.status_code, 201, response.data)
        payment = SupplierPayment.objects.get(method=SupplierPayment.Method.CREDIT)
        self.assertEqual(payment.bill_id, self.bill_b.pk)
        self.assertEqual(payment.credit_note_id, self.note.pk)
        self.assertEqual(payment.amount, Decimal("120.00"))
        self.assertEqual(payment.status, SupplierPayment.Status.CLEARED)
        self.assertEqual(payment.paid_by_id, self.manager.pk)
        self.assertEqual(response.data["credit_note"], self.note.pk)
        self.bill_b.refresh_from_db()
        self.note.refresh_from_db()
        self.assertEqual(self.bill_b.balance_amount, Decimal("180.00"))
        self.assertEqual(self.note.remaining_amount, Decimal("80.00"))
        # Money is only MOVED, never made: bill + note is 500.00 before and after.
        self.assertEqual(
            self.bill_b.balance_amount + self.note.remaining_amount, Decimal("260.00")
        )
        self.bill_a.refresh_from_db()
        self.assertEqual(self.bill_a.balance_amount, Decimal("0.00"))

    def test_the_note_can_be_spent_down_to_zero_and_no_further(self):
        self.assertEqual(self._apply(amount="200").status_code, 201)

        second = self._apply(amount="10")

        self.assertEqual(second.status_code, 400, second.data)
        self.assertEqual(second.data["code"], "CREDIT_EXCEEDS_REMAINING")
        self.note.refresh_from_db()
        self.bill_b.refresh_from_db()
        self.assertEqual(self.note.remaining_amount, Decimal("0.00"))
        self.assertEqual(self.bill_b.balance_amount, Decimal("100.00"))

    def test_another_suppliers_note_is_refused(self):
        foreign = self._foreign_note()

        response = self._apply(note=foreign, amount="50")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "CREDIT_NOTE_SUPPLIER_MISMATCH")
        foreign.refresh_from_db()
        self.assertEqual(foreign.remaining_amount, Decimal("100.00"))
        self._assert_nothing_moved()

    def test_an_amount_above_the_note_remaining_is_refused(self):
        response = self._apply(amount="200.01")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "CREDIT_EXCEEDS_REMAINING")
        self._assert_nothing_moved()

    def test_an_amount_above_the_bill_balance_is_refused(self):
        self._pay(self.bill_b, "250")  # 50.00 left to pay

        response = self._apply(amount="80")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "OVERPAYMENT")
        self.bill_b.refresh_from_db()
        self.assertEqual(self.bill_b.balance_amount, Decimal("50.00"))
        self.note.refresh_from_db()
        self.assertEqual(self.note.remaining_amount, Decimal("200.00"))

    def test_a_settled_bill_is_refused(self):
        self._pay(self.bill_b, "300")

        response = self._apply(amount="50")

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "BILL_PAID")
        self.note.refresh_from_db()
        self.assertEqual(self.note.remaining_amount, Decimal("200.00"))

    def test_credit_without_a_note_is_refused(self):
        response = self._login(self.manager).post(
            PAYMENTS_URL,
            {"bill": self.bill_b.pk, "amount": "50", "method": "CREDIT"},
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SUPPLIER_PAYMENT")

    def test_an_ordinary_payment_cannot_carry_a_credit_note(self):
        response = self._login(self.manager).post(
            PAYMENTS_URL,
            {
                "bill": self.bill_b.pk,
                "amount": "50",
                "method": "CASH",
                "credit_note": self.note.pk,
            },
            format="json",
        )

        self.assertEqual(response.status_code, 400, response.data)
        self.assertEqual(response.data["code"], "INVALID_SUPPLIER_PAYMENT")

    def test_only_a_manager_may_apply_credit(self):
        self.assertEqual(self._apply(user=self.stocker).status_code, 403)
        self.assertEqual(self._apply(user=self.cashier).status_code, 403)
        self.assertFalse(
            SupplierPayment.objects.filter(
                method=SupplierPayment.Method.CREDIT
            ).exists()
        )

        self.assertEqual(self._apply(user=self.admin, amount="10").status_code, 201)

    def test_applying_credit_is_audited_as_a_payment(self):
        self._apply(amount="120")

        row = AuditLog.objects.get(
            action_type=AuditLog.ActionType.PAYMENT,
            description__contains=self.note.number,
        )
        self.assertEqual(row.user_id, self.manager.pk)
        self.assertIn("120.00", row.description)


class CreditNoteListTests(CreditNoteTestBase):
    """`GET /supplier-credit-notes/?supplier=&open=true` - the notes a manager may spend."""

    def setUp(self):
        super().setUp()
        # One note with credit left (its bill was settled before the return) ...
        receipt = self._receipt_for()
        bill = SupplierBill.objects.get(receipt=receipt)
        self._login(self.manager).post(
            PAYMENTS_URL,
            {"bill": bill.pk, "amount": "200", "method": "CASH"},
            format="json",
        )
        _, self.open_note = self._return(receipt=receipt, qty="2")
        # ... and one already spent on its own bill.
        spent_receipt = self._receipt_for()
        _, self.spent_note = self._return(receipt=spent_receipt, qty="1")

    @staticmethod
    def _rows(response):
        data = response.data
        return data["results"] if isinstance(data, dict) and "results" in data else data

    def _list(self, user=None, **params):
        return self._login(user or self.stocker).get(CREDIT_NOTES_URL, params)

    def test_open_lists_only_notes_with_credit_left(self):
        response = self._list(open="true")

        self.assertEqual(response.status_code, 200, response.data)
        rows = self._rows(response)
        self.assertEqual([row["number"] for row in rows], [self.open_note.number])
        self.assertEqual(Decimal(rows[0]["remaining_amount"]), Decimal("200.00"))
        self.assertEqual(Decimal(rows[0]["total_amount"]), Decimal("200.00"))
        self.assertEqual(Decimal(rows[0]["applied_amount"]), Decimal("0.00"))
        self.assertEqual(rows[0]["supplier"], self.supplier.pk)

    def test_without_the_open_filter_every_note_is_readable(self):
        rows = self._rows(self._list())

        self.assertEqual(
            {row["number"] for row in rows},
            {self.open_note.number, self.spent_note.number},
        )

    def test_the_list_filters_by_supplier(self):
        other = Supplier.objects.create(company_name="Other Supply")
        self._return(receipt=self._receipt_for(), qty="1")  # same supplier, 2nd note

        rows = self._rows(self._list(supplier=other.pk))

        self.assertEqual(rows, [])

    def test_credit_notes_are_inventory_role_only(self):
        self.assertEqual(self._list(user=self.stocker).status_code, 200)
        self.assertEqual(self._list(user=self.manager).status_code, 200)
        self.assertEqual(self._list(user=self.cashier).status_code, 403)
        self.assertEqual(self._list(user=self.cpms).status_code, 403)

    def test_a_credit_note_has_no_write_verbs_over_the_api(self):
        client = self._login(self.manager)
        detail = f"{CREDIT_NOTES_URL}{self.open_note.pk}/"

        self.assertEqual(client.get(detail).status_code, 200)
        self.assertEqual(client.patch(detail, {}, format="json").status_code, 405)
        self.assertEqual(client.delete(detail).status_code, 405)
        self.assertEqual(
            client.post(CREDIT_NOTES_URL, {}, format="json").status_code, 405
        )
