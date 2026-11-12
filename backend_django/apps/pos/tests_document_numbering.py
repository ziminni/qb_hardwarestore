# pyright: reportAttributeAccessIssue=false
#
# Same directive and reason as apps/pos/tests_idempotency.py: the checker resolves its
# config from its WORKING DIRECTORY, so `Model.objects` reads as an error on valid
# Django. The test run is the authority.
"""Phase 6 B4 (decision 22 item 19) — QT/SO/DEL/REQ numbers are RESERVED, not sniffed.

`generate_document_number` used to read the newest document for the day and add one.
Nothing was written between that read and the caller's insert, so two requests in the
same window both got `-0007` and the loser died on the field's unique constraint as a
500. The same bug `DocumentCounter` already fixed for TRX/OR (decision 09 item 3).

The numbers are now reserved from a `DocumentCounter` row locked with
`select_for_update`, seeded from the highest document already written for that prefix
and day. A reservation that never becomes a document leaves a gap, which is fine;
two documents with one number is not.
"""

import threading
from datetime import date, timedelta
from unittest import mock

from django.contrib.auth import get_user_model
from django.db import connections
from django.test import TestCase, TransactionTestCase

from apps.pos.models import (
    Customer,
    Delivery,
    DocumentCounter,
    Quotation,
    SalesOrder,
)
from apps.requisitions.models import Project, Requisition
from apps.requisitions.services import generate_req_number
from common.numbering import generate_document_number

User = get_user_model()

TODAY_STAMP = date.today().strftime("%Y%m%d")


class FrozenDate(date):
    """A `date` whose `today()` is fixed, so a day boundary is testable."""

    @classmethod
    def today(cls):
        return cls(2026, 1, 2)


class DocumentNumberingFixture(TestCase):
    """The rows the four numbered documents need — nothing about stock or money."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="numbering", email="numbering@example.com", password="pass12345"
        )
        self.customer = Customer.objects.create(
            name="Dela Cruz Construction",
            customer_type=Customer.Type.CONTRACTOR,
        )

    def quotation(self, number=None):
        return Quotation.objects.create(
            quotation_no=number, customer=self.customer, created_by=self.user
        )

    def sales_order(self):
        return SalesOrder.objects.create(customer=self.customer, created_by=self.user)

    def delivery(self):
        return Delivery.objects.create(
            sales_order=self.sales_order(),
            address="Mandaue site",
            contact_name="Nena",
            contact_phone="09170000000",
            scheduled_date=date.today() + timedelta(days=1),
            created_by=self.user,
        )


class ReservationTests(DocumentNumberingFixture):
    """The reservation itself: independent of whether the caller ever saves."""

    def test_first_number_of_day_is_0001(self):
        self.assertEqual(
            generate_document_number(Quotation, "quotation_no", "QT"),
            f"QT-{TODAY_STAMP}-0001",
        )

    def test_two_reservations_same_prefix_do_not_collide(self):
        # This is the race with the writes peeled off: no document is written between
        # the two reads, exactly as when two requests are in the same window. Reading
        # the newest document cannot tell them apart; a reserved counter can.
        first = generate_document_number(Quotation, "quotation_no", "QT")
        second = generate_document_number(Quotation, "quotation_no", "QT")
        self.assertNotEqual(first, second)
        self.assertEqual(
            [first, second], [f"QT-{TODAY_STAMP}-0001", f"QT-{TODAY_STAMP}-0002"]
        )

    def test_existing_documents_seed_the_counter(self):
        # Live data predates the counter; seeding from 0 would hand out -0008 twice.
        self.quotation(f"QT-{TODAY_STAMP}-0007")
        self.assertEqual(
            generate_document_number(Quotation, "quotation_no", "QT"),
            f"QT-{TODAY_STAMP}-0008",
        )

    def test_seed_parses_five_digit_sequences_numerically(self):
        # '-10000' sorts BEFORE '-9999' lexically, so a max-by-string seed is too low.
        self.quotation(f"QT-{TODAY_STAMP}-10000")
        self.assertEqual(
            generate_document_number(Quotation, "quotation_no", "QT"),
            f"QT-{TODAY_STAMP}-10001",
        )

    def test_prefixes_are_independent(self):
        quotation_no = generate_document_number(Quotation, "quotation_no", "QT")
        order_no = generate_document_number(SalesOrder, "order_no", "SO")
        self.assertEqual(quotation_no, f"QT-{TODAY_STAMP}-0001")
        self.assertEqual(order_no, f"SO-{TODAY_STAMP}-0001")

    def test_days_are_independent(self):
        today_no = generate_document_number(Quotation, "quotation_no", "QT")
        with mock.patch("common.numbering.date", FrozenDate):
            other_day_no = generate_document_number(Quotation, "quotation_no", "QT")
        self.assertEqual(today_no, f"QT-{TODAY_STAMP}-0001")
        self.assertEqual(other_day_no, "QT-20260102-0001")
        self.assertEqual(DocumentCounter.objects.filter(prefix="QT").count(), 2)

    def test_requisition_numbers_are_reserved_too(self):
        first = generate_req_number()
        second = generate_req_number()
        self.assertNotEqual(first, second)
        self.assertEqual(
            [first, second], [f"REQ-{TODAY_STAMP}-0001", f"REQ-{TODAY_STAMP}-0002"]
        )

    def test_requisition_counter_seeds_from_existing_requests(self):
        project = Project.objects.create(name="Mandaue", customer=self.customer)
        Requisition.objects.create(
            project=project, req_number=f"REQ-{TODAY_STAMP}-0004"
        )
        self.assertEqual(generate_req_number(), f"REQ-{TODAY_STAMP}-0005")


class CallerNumberingTests(DocumentNumberingFixture):
    """Every caller gets a distinct number, through the model/service that mints it."""

    def test_two_quotations_get_distinct_numbers(self):
        first = self.quotation()
        second = self.quotation()
        self.assertNotEqual(first.quotation_no, second.quotation_no)
        self.assertEqual(
            [first.quotation_no, second.quotation_no],
            [f"QT-{TODAY_STAMP}-0001", f"QT-{TODAY_STAMP}-0002"],
        )

    def test_two_sales_orders_get_distinct_numbers(self):
        first = self.sales_order()
        second = self.sales_order()
        self.assertNotEqual(first.order_no, second.order_no)
        self.assertEqual(
            [first.order_no, second.order_no],
            [f"SO-{TODAY_STAMP}-0001", f"SO-{TODAY_STAMP}-0002"],
        )

    def test_two_deliveries_get_distinct_numbers(self):
        first = self.delivery()
        second = self.delivery()
        self.assertNotEqual(first.delivery_no, second.delivery_no)
        self.assertEqual(
            [first.delivery_no, second.delivery_no],
            [f"DEL-{TODAY_STAMP}-0001", f"DEL-{TODAY_STAMP}-0002"],
        )

    def test_requisition_created_from_the_service_number_saves(self):
        project = Project.objects.create(name="Mandaue", customer=self.customer)
        first = Requisition.objects.create(
            project=project, req_number=generate_req_number()
        )
        second = Requisition.objects.create(
            project=project, req_number=generate_req_number()
        )
        self.assertNotEqual(first.req_number, second.req_number)


class ConcurrentReservationTests(TransactionTestCase):
    """Two real connections reserving at once — the production race, not a mock of it.

    `TransactionTestCase` because both workers must reach the database outside one
    wrapped transaction; the barrier is placed AFTER each worker has its number and
    BEFORE either inserts, so with a read-max-then-add helper both workers provably
    read the same newest document and the second insert dies on the unique constraint.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            username="race_numbering",
            email="race_numbering@example.com",
            password="pass12345",
        )
        self.customer = Customer.objects.create(name="Dela Cruz Construction")

    def _reserve_then_create(self, barrier, numbers, errors, lock):
        try:
            number = generate_document_number(Quotation, "quotation_no", "QT")
            barrier.wait()
            Quotation.objects.create(
                quotation_no=number,
                customer_id=self.customer.id,
                created_by_id=self.user.id,
            )
        except Exception as exc:  # noqa: BLE001 - the failure IS the assertion
            with lock:
                errors.append(exc)
        else:
            with lock:
                numbers.append(number)
        finally:
            connections.close_all()

    def test_simultaneous_quotations_both_save_with_distinct_numbers(self):
        numbers, errors = [], []
        lock = threading.Lock()
        # Shared by both workers: each must take its number before either inserts.
        barrier = threading.Barrier(2, timeout=20)
        threads = [
            threading.Thread(
                target=self._reserve_then_create,
                args=(barrier, numbers, errors, lock),
            )
            for _ in range(2)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(errors, [])
        self.assertEqual(Quotation.objects.count(), 2)
        self.assertEqual(
            sorted(numbers), [f"QT-{TODAY_STAMP}-0001", f"QT-{TODAY_STAMP}-0002"]
        )
