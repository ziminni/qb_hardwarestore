# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false
"""SMS app tests, part 1: the pure pieces and the outbound trigger.

No hardware and no network: the phone normalizer, the reply parser and the composer are
plain functions, and the trigger is a `post_save` receiver whose `on_commit` callback the
test runs deliberately (`captureOnCommitCallbacks`) - which is also how "a rolled-back
sale texts nobody" is proved.
"""

from decimal import Decimal
from unittest import TestCase as PlainTestCase
from unittest import mock

from django.core.management import call_command
from django.db import transaction
from django.test import override_settings

from apps.bodega.tests import BodegaTestBase
from apps.inventory.models import InventoryBatch, StorageLocation
from apps.pos.models import Delivery, SalesTransaction
from apps.pos.services import process_return

from . import services
from .models import BodegaSmsTicket, SmsContact, SmsMessage
from .parser import KIND_DONE, KIND_HELP, KIND_INVALID, parse_inbound
from .phone import InvalidPhoneNumber, normalize_phone

GOOD_KEY = "0123456789abcdef0123456789abcdef"


class PhoneNormalizationTests(PlainTestCase):
    def test_every_shape_the_checker_could_type_lands_on_one_number(self):
        for raw in (
            "09171234567",
            "9171234567",
            "+639171234567",
            "639171234567",
            "0917 123 4567",
            "+63 917-123-4567",
            " 0917-123-4567 ",
        ):
            with self.subTest(raw=raw):
                self.assertEqual(normalize_phone(raw), "+639171234567")

    def test_a_number_that_is_not_a_mobile_is_refused(self):
        for raw in ("", None, "12345", "0281234567", "09991234567890"):
            with self.subTest(raw=raw):
                self.assertRaises(InvalidPhoneNumber, normalize_phone, raw)


class ParserTests(PlainTestCase):
    def test_the_shapes_a_checker_types_all_read_as_a_release(self):
        for body in (
            "DONE 000123 4821",
            "done 000123 4821",
            "OK 000123 4821",
            "RELEASED 000123 4821",
            "COMPLETE 000123 4821",
            "completed 000123 4821",
            "'000123':'accomplished' 4821",
            "000123:accomplished:4821",
            "DONE: 000123, code 4821",
        ):
            with self.subTest(body=body):
                command = parse_inbound(body)
                self.assertEqual(command.kind, KIND_DONE, body)
                self.assertEqual(command.reference, "000123", body)
                self.assertEqual(command.code, "4821", body)

    def test_a_receiver_name_after_the_code_comes_through(self):
        command = parse_inbound("DONE 000123 4821 Juan Cruz")
        self.assertEqual(command.name, "Juan Cruz")

    def test_a_transaction_number_keeps_its_dashes(self):
        command = parse_inbound("DONE TRX-20261120-0001 4821")
        self.assertEqual(command.kind, KIND_DONE)
        self.assertEqual(command.reference, "TRX-20261120-0001")

    def test_help_is_help(self):
        for body in ("HELP", "help", "?"):
            with self.subTest(body=body):
                self.assertEqual(parse_inbound(body).kind, KIND_HELP)

    def test_a_message_with_no_readable_command_is_invalid(self):
        for body in (
            "",
            "   ",
            "hello there",
            "DONE",
            "DONE 000123",
            "DONE 000123 12345",
        ):
            with self.subTest(body=body):
                self.assertEqual(parse_inbound(body).kind, KIND_INVALID, body)


class ComposerTests(PlainTestCase):
    def _items(self, count, long=False):
        tail = " extra long product description" if long else ""
        return [f"{index + 1} BAG Portland Cement 40kg{tail}" for index in range(count)]

    def test_a_short_pickup_is_one_plain_message(self):
        body = services.compose_message(
            word="PICKUP", reference="000123", code="4821", items=self._items(2)
        )
        self.assertEqual(
            body,
            "QB PICKUP 000123: 1 BAG Portland Cement 40kg; 2 BAG Portland Cement 40kg"
            ". Code 4821. Reply: DONE 000123 4821",
        )
        self.assertLessEqual(len(body), services.SMS_LENGTH)

    def test_a_long_pickup_is_cut_with_a_count_and_keeps_the_code_and_reply(self):
        body = services.compose_message(
            word="DELIVERY",
            reference="TRX-20261120-0001",
            code="4821",
            items=self._items(12, long=True),
        )
        self.assertLessEqual(len(body), services.SMS_LENGTH)
        self.assertIn(" more", body)
        self.assertIn("Code 4821", body)
        self.assertIn("Reply: DONE TRX-20261120-0001 4821", body)

    def test_the_body_is_ascii_only_and_uses_p_for_pesos(self):
        body = services.compose_message(
            word="PICKUP",
            reference="000123",
            code="4821",
            items=["10 BAG Cement ₱250 – 40kg"],
        )
        body.encode("ascii")  # raises if anything non-ASCII survived
        self.assertIn("P250", body)
        self.assertNotIn("₱", body)

    def test_a_single_item_too_long_for_the_message_is_cut_not_dropped(self):
        body = services.compose_message(
            word="DELIVERY",
            reference="TRX-20261120-0001",
            code="4821",
            items=["9 SHEET " + "x" * 400],
        )
        self.assertLessEqual(len(body), services.SMS_LENGTH)
        self.assertIn("Code 4821", body)
        self.assertIn("Reply: DONE TRX-20261120-0001 4821", body)


@override_settings(SMS_ENABLED=True, SMS_GATEWAY_KEY=GOOD_KEY)
class EnqueueTests(BodegaTestBase):
    """The `post_save` trigger: one text per Bodega sale, only when the shop asks for it."""

    def setUp(self):
        super().setUp()
        self.contact = SmsContact.objects.create(
            phone="+639171234567", user=self.checker, label="Bodega"
        )

    def _sell_and_commit(self, qty=2):
        """Ring a sale and let `transaction.on_commit` run - the real trigger order."""
        with self.captureOnCommitCallbacks(execute=True):
            return self._sell(qty)

    def _outbound(self):
        return SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT)

    def test_a_bodega_sale_texts_the_checker_with_receipt_items_and_code(self):
        sale = self._sell_and_commit(6)
        (message,) = self._outbound()
        reference = services.sale_reference(sale)
        self.assertEqual(message.phone, "+639171234567")
        self.assertEqual(message.status, SmsMessage.Status.QUEUED)
        self.assertEqual(message.sale_id, sale.pk)
        self.assertIn(f"QB PICKUP {reference}", message.body)
        self.assertIn("6 BAG Portland Cement 40kg", message.body)
        ticket = BodegaSmsTicket.objects.get(sale=sale)
        self.assertEqual(len(ticket.code), 4)
        self.assertIn(f"Code {ticket.code}", message.body)
        self.assertIn(f"Reply: DONE {reference} {ticket.code}", message.body)
        self.assertLessEqual(len(message.body), services.SMS_LENGTH)

    def test_a_delivery_sale_says_delivery_instead_of_pickup(self):
        # The slip is written inside the same transaction as the sale, so the trigger
        # (which runs at commit) sees it - exactly the live order.
        with self.captureOnCommitCallbacks(execute=True):
            sale = self._sell(2)
            Delivery.objects.create(
                sale=sale,
                created_by=self.cashier,
                address="12 Mabini St",
                contact_name="Juan",
                contact_phone="09170000000",
                scheduled_date=sale.trans_date.date(),
                fee=Decimal(0),
            )
        (message,) = self._outbound()
        self.assertTrue(message.body.startswith("QB DELIVERY"), message.body)

    def test_every_active_contact_gets_the_same_code(self):
        SmsContact.objects.create(
            phone="+639200000000", user=self.manager, label="Boss phone"
        )
        sale = self._sell_and_commit(1)
        code = BodegaSmsTicket.objects.get(sale=sale).code
        messages = self._outbound()
        self.assertEqual(messages.count(), 2)
        for message in messages:
            self.assertIn(f"Code {code}", message.body)

    def test_a_sale_from_the_store_shelf_texts_nobody(self):
        InventoryBatch.objects.filter(variant=self.variant).update(
            location=StorageLocation.objects.get(name="Store")
        )
        self._sell_and_commit(1)
        self.assertEqual(self._outbound().count(), 0)
        self.assertEqual(BodegaSmsTicket.objects.count(), 0)

    def test_a_return_texts_nobody(self):
        sale = self._sell_and_commit(3)
        self._outbound().delete()
        with self.captureOnCommitCallbacks(execute=True):
            process_return(
                customer_id=self.customer.id,
                cashier=self.cashier,
                items_data=[{"variant_id": self.vuom.id, "qty": 1}],
                original_transaction_id=sale.id,
                reason="customer changed their mind",
            )
        self.assertEqual(self._outbound().count(), 0)

    @override_settings(SMS_ENABLED=False)
    def test_nothing_is_queued_while_the_shop_has_the_link_off(self):
        self._sell_and_commit(2)
        self.assertEqual(self._outbound().count(), 0)
        self.assertEqual(BodegaSmsTicket.objects.count(), 0)

    def test_no_contact_means_no_text_and_no_ticket(self):
        self.contact.delete()
        self._sell_and_commit(2)
        self.assertEqual(self._outbound().count(), 0)
        self.assertEqual(BodegaSmsTicket.objects.count(), 0)

    def test_an_inactive_contact_is_not_texted(self):
        self.contact.active = False
        self.contact.save(update_fields=["active"])
        self._sell_and_commit(2)
        self.assertEqual(self._outbound().count(), 0)

    def test_a_contact_whose_account_cannot_work_the_bodega_is_not_texted(self):
        self.contact.user = self.cashier
        self.contact.save(update_fields=["user"])
        self._sell_and_commit(2)
        self.assertEqual(self._outbound().count(), 0)

    def test_a_contact_whose_account_was_deactivated_is_not_texted(self):
        self.checker.is_active = False
        self.checker.save(update_fields=["is_active"])
        self._sell_and_commit(2)
        self.assertEqual(self._outbound().count(), 0)


@override_settings(SMS_ENABLED=True)
class EnqueueOnCommitBoundaryTests(BodegaTestBase):
    """A sale that never commits must never text anyone."""

    def test_a_rolled_back_sale_leaves_no_message(self):
        SmsContact.objects.create(phone="+639171234567", user=self.checker)
        # Not one `with a, b:` line: pyright (without django-stubs) reads the context
        # manager that tuple form returns as unusable, and this is a test about rollback.
        with self.captureOnCommitCallbacks(execute=True):  # noqa: SIM117
            with transaction.atomic():
                sale = self._sell(1)
                transaction.set_rollback(True)
        self.assertFalse(SmsMessage.objects.filter(sale_id=sale.pk).exists())
        self.assertFalse(BodegaSmsTicket.objects.filter(sale_id=sale.pk).exists())


class TicketCodeTests(PlainTestCase):
    def test_a_code_is_four_digits(self):
        for _ in range(50):
            code = services.new_code()
            self.assertEqual(len(code), 4)
            self.assertTrue(code.isdigit(), code)


@override_settings(SMS_ENABLED=True)
class EnqueueFailureAndRecoveryTests(BodegaTestBase):
    """Issue 1: a failing text must never break a recorded sale, and must be recoverable."""

    def setUp(self):
        super().setUp()
        self.contact = SmsContact.objects.create(
            phone="+639171234567", user=self.checker, label="Bodega"
        )

    def _outbound(self):
        return SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT)

    @mock.patch.object(services, "enqueue_for_sale", side_effect=RuntimeError("boom"))
    def test_a_failing_enqueue_does_not_propagate_to_the_committed_sale(self, _enqueue):
        # The sale is already committed when the callback runs. A raise here used to turn
        # a successful checkout into a 500 - the cashier sees "failed" on a recorded sale.
        with self.captureOnCommitCallbacks(execute=True):
            sale = self._sell(2)
        self.assertTrue(SalesTransaction.objects.filter(pk=sale.pk).exists())
        self.assertEqual(self._outbound().count(), 0)

    def test_the_requeue_command_recovers_a_sale_whose_text_was_lost(self):
        # An explicit patcher, not the decorator: the repair below must run against the
        # REAL enqueue, so the outage has to end before the command does.
        outage = mock.patch.object(
            services, "enqueue_for_sale", side_effect=RuntimeError("boom")
        )
        outage.start()
        try:
            with self.captureOnCommitCallbacks(execute=True):
                sale = self._sell(3)
        finally:
            outage.stop()
        self.assertEqual(self._outbound().count(), 0)
        call_command("requeue_sms_notifications", "--limit", "10")
        self.assertEqual(self._outbound().filter(sale=sale).count(), 1)
        self.assertTrue(BodegaSmsTicket.objects.filter(sale=sale).exists())

    def test_the_requeue_command_does_not_double_text_a_sale(self):
        with self.captureOnCommitCallbacks(execute=True):
            self._sell(2)
        self.assertEqual(self._outbound().count(), 1)
        call_command("requeue_sms_notifications", "--limit", "10")
        self.assertEqual(self._outbound().count(), 1)

    @mock.patch.object(services, "enqueue_for_sale", side_effect=RuntimeError("boom"))
    def test_a_dry_run_reports_without_queueing_anything(self, _enqueue):
        with self.captureOnCommitCallbacks(execute=True):
            self._sell(2)
        call_command("requeue_sms_notifications", "--dry-run")
        self.assertEqual(self._outbound().count(), 0)

    @mock.patch.object(services, "enqueue_for_sale", side_effect=RuntimeError("boom"))
    def test_a_sale_from_the_store_shelf_is_never_requeued(self, _enqueue):
        with self.captureOnCommitCallbacks(execute=True):
            self._sell(2)
        InventoryBatch.objects.filter(variant=self.variant).update(
            location=StorageLocation.objects.get(name="Store")
        )
        call_command("requeue_sms_notifications", "--limit", "10")
        self.assertEqual(self._outbound().count(), 0)
