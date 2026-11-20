# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false
"""SMS app tests, part 2: the bridge's endpoints, the inbound release and the staff API.

The bridge is the untrusted half of this feature (a script on a Windows host, no login),
so its key is tested from the outside: missing, short, wrong and right. The inbound path
is tested through `process_inbound` AND through the endpoint, because the release it
writes is the point of the whole feature.
"""

from datetime import timedelta
from decimal import Decimal
from unittest import mock

from django.contrib.auth.models import Group
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from apps.bodega import services as bodega_services
from apps.bodega.tests import BodegaTestBase
from apps.pos.models import SalesTransaction
from apps.pos.services import process_return
from apps.users.models import AuditLog

from . import services
from .models import BodegaSmsTicket, SmsContact, SmsGatewayHeartbeat, SmsMessage

GOOD_KEY = "0123456789abcdef0123456789abcdef"
PHONE = "+639171234567"
OUTBOX = "/api/v1/sms/gateway/outbox/"
INBOUND = "/api/v1/sms/gateway/inbound/"
HEARTBEAT = "/api/v1/sms/gateway/heartbeat/"


@override_settings(SMS_ENABLED=True, SMS_GATEWAY_KEY=GOOD_KEY)
class GatewayBase(BodegaTestBase):
    def setUp(self):
        super().setUp()
        self.contact = SmsContact.objects.create(
            phone=PHONE, user=self.checker, label="Bodega"
        )
        self.gateway = APIClient()
        self.gateway.credentials(HTTP_X_SMS_GATEWAY_KEY=GOOD_KEY)

    def _sell_and_commit(self, qty=3):
        with self.captureOnCommitCallbacks(execute=True):
            return self._sell(qty)

    def _inbound(self, body, *, phone=PHONE, key=None, client=None):
        payload = {"from": phone, "body": body}
        if key is not None:
            payload["key"] = key
        return (client or self.gateway).post(INBOUND, payload, format="json")

    def _ticket(self, sale):
        return BodegaSmsTicket.objects.get(sale=sale)

    def _outbox_bodies(self):
        return list(
            SmsMessage.objects.filter(
                direction=SmsMessage.Direction.OUT,
                status=SmsMessage.Status.QUEUED,
            ).values_list("body", flat=True)
        )


class GatewayKeyTests(GatewayBase):
    def test_a_request_with_no_key_is_unauthenticated(self):
        client = APIClient()
        response = client.get(OUTBOX)
        self.assertEqual(response.status_code, 401, response.data)
        self.assertEqual(response.data["code"], "SMS_GATEWAY_UNAUTHORIZED")

    def test_a_wrong_key_is_refused(self):
        client = APIClient()
        client.credentials(HTTP_X_SMS_GATEWAY_KEY="x" * 32)
        response = client.get(OUTBOX)
        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data["code"], "SMS_GATEWAY_REFUSED")

    @override_settings(SMS_GATEWAY_KEY="")
    def test_an_unconfigured_server_refuses_every_call_even_with_a_key(self):
        response = self.gateway.get(OUTBOX)
        self.assertEqual(response.status_code, 403, response.data)
        self.assertEqual(response.data["code"], "SMS_GATEWAY_REFUSED")

    @override_settings(SMS_GATEWAY_KEY="short-key")
    def test_a_short_configured_key_refuses_every_call(self):
        client = APIClient()
        client.credentials(HTTP_X_SMS_GATEWAY_KEY="short-key")
        response = client.get(OUTBOX)
        self.assertEqual(response.status_code, 403, response.data)

    def test_the_jwt_guard_does_not_block_the_bridge(self):
        # No Authorization header at all: the key alone is the credential.
        self.assertEqual(self.gateway.get(OUTBOX).status_code, 200)


class OutboxTests(GatewayBase):
    def test_disabling_sms_pauses_existing_queued_messages(self):
        self._sell_and_commit(2)
        with override_settings(SMS_ENABLED=False):
            response = self.gateway.get(OUTBOX)
        self.assertEqual(response.status_code, 503, response.data)
        self.assertEqual(response.data["code"], "SMS_DISABLED")
        self.assertFalse(SmsMessage.objects.filter(status=SmsMessage.Status.SENDING).exists())
        self.assertTrue(SmsMessage.objects.filter(status=SmsMessage.Status.QUEUED).exists())

    def test_claiming_marks_sending_and_hands_back_phone_and_body(self):
        self._sell_and_commit(2)
        response = self.gateway.get(OUTBOX, {"limit": 5})
        self.assertEqual(response.status_code, 200, response.data)
        (claimed,) = response.data
        self.assertEqual(claimed["phone"], PHONE)
        self.assertIn("QB PICKUP", claimed["body"])
        message = SmsMessage.objects.get(pk=claimed["id"])
        self.assertEqual(message.status, SmsMessage.Status.SENDING)
        self.assertIsNotNone(message.claimed_at)

    def test_a_claimed_message_is_not_handed_out_twice_inside_the_lease(self):
        self._sell_and_commit(2)
        self.gateway.get(OUTBOX)
        self.assertEqual(self.gateway.get(OUTBOX).data, [])

    def test_a_lease_older_than_five_minutes_comes_back_to_the_queue(self):
        self._sell_and_commit(2)
        (claimed,) = self.gateway.get(OUTBOX).data
        SmsMessage.objects.filter(pk=claimed["id"]).update(
            claimed_at=timezone.now() - timedelta(minutes=6)
        )
        again = self.gateway.get(OUTBOX).data
        self.assertEqual([row["id"] for row in again], [claimed["id"]])

    def test_a_successful_send_is_marked_sent(self):
        self._sell_and_commit(2)
        (claimed,) = self.gateway.get(OUTBOX).data
        response = self.gateway.post(
            f"{OUTBOX}{claimed['id']}/result/", {"ok": True}, format="json"
        )
        self.assertEqual(response.status_code, 200, response.data)
        message = SmsMessage.objects.get(pk=claimed["id"])
        self.assertEqual(message.status, SmsMessage.Status.SENT)
        self.assertIsNotNone(message.sent_at)
        self.assertEqual(message.attempts, 1)
        self.assertEqual(message.last_error, "")

    def test_a_failed_send_returns_to_the_queue_with_the_error(self):
        self._sell_and_commit(2)
        (claimed,) = self.gateway.get(OUTBOX).data
        self.gateway.post(
            f"{OUTBOX}{claimed['id']}/result/",
            {"ok": False, "error": "no carrier"},
            format="json",
        )
        message = SmsMessage.objects.get(pk=claimed["id"])
        self.assertEqual(message.status, SmsMessage.Status.QUEUED)
        self.assertEqual(message.attempts, 1)
        self.assertEqual(message.last_error, "no carrier")

    def test_five_failed_attempts_leave_the_message_failed(self):
        self._sell_and_commit(2)
        message = SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).first()
        for _ in range(5):
            SmsMessage.objects.filter(pk=message.pk).update(
                status=SmsMessage.Status.SENDING
            )
            services.report_send_result(message.pk, ok=False, error="boom")
        message.refresh_from_db()
        self.assertEqual(message.status, SmsMessage.Status.FAILED)
        self.assertEqual(message.attempts, 5)

    def test_a_late_duplicate_result_cannot_resurrect_a_sent_message(self):
        # A second bridge (or the same one whose response was lost) reporting failure on a
        # message that is already SENT must not requeue it: that would text the checker a
        # second time about a pick-up already released.
        self._sell_and_commit(2)
        (claimed,) = self.gateway.get(OUTBOX).data
        self.gateway.post(
            f"{OUTBOX}{claimed['id']}/result/", {"ok": True}, format="json"
        )
        self.gateway.post(
            f"{OUTBOX}{claimed['id']}/result/",
            {"ok": False, "error": "late duplicate"},
            format="json",
        )
        message = SmsMessage.objects.get(pk=claimed["id"])
        self.assertEqual(message.status, SmsMessage.Status.SENT)
        self.assertEqual(message.attempts, 1)

    def test_an_unknown_message_is_a_404(self):
        response = self.gateway.post(
            f"{OUTBOX}999999/result/", {"ok": True}, format="json"
        )
        self.assertEqual(response.status_code, 404, response.data)
        self.assertEqual(response.data["code"], "SMS_MESSAGE_NOT_FOUND")


class HeartbeatTests(GatewayBase):
    def test_a_heartbeat_is_recorded_for_the_staff_status_page(self):
        response = self.gateway.post(
            HEARTBEAT,
            {"info": {"signal": 21, "operator": "Globe", "port": "COM5"}},
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        beat = SmsGatewayHeartbeat.objects.get(pk=1)
        self.assertEqual(beat.info["operator"], "Globe")
        self.assertIsNotNone(beat.last_seen)


class InboundReleaseTests(GatewayBase):
    def test_a_done_reply_releases_everything_left_and_answers_with_the_number(self):
        sale = self._sell_and_commit(4)
        ticket = self._ticket(sale)
        response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], SmsMessage.Status.PROCESSED)

        release = sale.bodega_releases.get()
        self.assertEqual(release.checker_id, self.checker.pk)
        self.assertEqual(release.received_by, services.DEFAULT_RECEIVED_BY)
        self.assertEqual(release.notes, f"Released by SMS from {PHONE}")
        (line,) = release.lines.all()
        self.assertEqual(line.qty, Decimal(4))
        self.assertEqual(
            response.data["reply"],
            f"OK {release.number} {services.sale_reference(sale)} released",
        )

        ticket.refresh_from_db()
        self.assertIsNotNone(ticket.used_at)
        self.assertEqual(ticket.release_id, release.pk)

        # The reply is queued as an outbound message the bridge will pick up.
        self.assertIn(response.data["reply"], self._outbox_bodies())
        self.assertTrue(
            AuditLog.objects.filter(
                user=self.checker,
                action_type=AuditLog.ActionType.RELEASE,
                description__contains=release.number,
            ).exists()
        )

    def test_the_receivers_name_from_the_text_lands_on_the_release(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        reference = services.sale_reference(sale)
        self._inbound(f"done {reference} {ticket.code} Juan Cruz")
        self.assertEqual(sale.bodega_releases.get().received_by, "Juan Cruz")

    def test_inbound_accepts_gsm_cmgl_service_centre_timestamp(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        reference = services.sale_reference(sale)
        response = self.gateway.post(
            INBOUND,
            {
                "from": PHONE,
                "body": f"DONE {reference} {ticket.code} Bridge Checker",
                "received_at": "26/11/20,14:30:12+32",
                "key": "a" * 64,
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], SmsMessage.Status.PROCESSED)
        self.assertEqual(sale.bodega_releases.get().received_by, "Bridge Checker")

    def test_a_second_release_on_the_same_receipt_is_refused_as_already_released(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        reference = services.sale_reference(sale)
        self._inbound(f"DONE {reference} {ticket.code}")
        again = self._inbound(f"DONE {reference} {ticket.code}")
        self.assertEqual(again.data["status"], SmsMessage.Status.PROCESSED)
        self.assertIn("already released", again.data["reply"])
        self.assertEqual(sale.bodega_releases.count(), 1)

    def test_a_receipt_already_released_in_the_app_marks_the_ticket_used(self):
        sale = self._sell_and_commit(3)
        ticket = self._ticket(sale)
        self.api.force_authenticate(self.checker)
        released = self._release(sale, 3)
        self.assertEqual(released.status_code, 201, released.data)
        response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertIn("already fully released", response.data["reply"])
        ticket.refresh_from_db()
        self.assertIsNotNone(ticket.used_at)
        self.assertEqual(sale.bodega_releases.count(), 1)

    def test_an_unknown_sender_is_stored_and_gets_no_reply(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        before = SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).count()
        response = self._inbound(
            f"DONE {services.sale_reference(sale)} {ticket.code}",
            phone="+639999999999",
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertEqual(response.data["reply"], "")
        self.assertEqual(
            SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).count(),
            before,
        )
        self.assertEqual(sale.bodega_releases.count(), 0)
        self.assertFalse(BodegaSmsTicket.objects.get(sale=sale).used_at)

    def test_an_inactive_contact_is_ignored_without_a_reply(self):
        # Sold while the contact is still active (it is what creates the ticket), then the
        # number is switched off: the SMS it sends afterwards must be ignored.
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        self.contact.active = False
        self.contact.save(update_fields=["active"])
        before = SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).count()
        response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertEqual(
            SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).count(),
            before,
        )

    def test_a_wrong_code_counts_up_and_locks_after_five_tries(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        reference = services.sale_reference(sale)
        wrong = "0000" if ticket.code != "0000" else "1111"
        for attempt in range(1, 5):
            response = self._inbound(f"DONE {reference} {wrong}")
            ticket.refresh_from_db()
            self.assertEqual(ticket.failed_attempts, attempt)
            self.assertIn("wrong code", response.data["reply"])
            self.assertEqual(sale.bodega_releases.count(), 0)
        # The fifth wrong try locks it...
        response = self._inbound(f"DONE {reference} {wrong}")
        ticket.refresh_from_db()
        self.assertEqual(ticket.failed_attempts, 5)
        self.assertIn("locked", response.data["reply"])
        # ...and the RIGHT code no longer works.
        response = self._inbound(f"DONE {reference} {ticket.code}")
        self.assertIn("locked", response.data["reply"])
        self.assertEqual(sale.bodega_releases.count(), 0)

    def test_a_receipt_with_no_ticket_is_refused_and_says_to_use_the_app(self):
        sale = self._sell_and_commit(2)
        BodegaSmsTicket.objects.filter(sale=sale).delete()
        response = self._inbound(f"DONE {services.sale_reference(sale)} 4821")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertIn("no pickup code", response.data["reply"])
        self.assertEqual(sale.bodega_releases.count(), 0)

    def test_an_unknown_receipt_is_refused_politely(self):
        response = self._inbound("DONE 000123 4821")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertIn("no receipt", response.data["reply"])

    def test_help_answers_with_the_format(self):
        response = self._inbound("HELP")
        self.assertEqual(response.data["status"], SmsMessage.Status.PROCESSED)
        self.assertIn("DONE <receipt> <code>", response.data["reply"])

    def test_a_message_that_is_not_a_command_is_refused_with_the_format(self):
        response = self._inbound("hi kuya")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertIn("DONE <receipt> <code>", response.data["reply"])

    def test_the_or_number_finds_the_receipt_too(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        response = self._inbound(f"DONE {sale.receipt.or_number} {ticket.code}")
        self.assertEqual(response.data["status"], SmsMessage.Status.PROCESSED)
        self.assertEqual(sale.bodega_releases.count(), 1)

    def test_a_receipt_that_changed_since_the_text_is_refused(self):
        # The checker's phone shows 4 bags. Someone returned 1 at the counter after the
        # text went out, so "release everything" would hand over a bag the receipt no
        # longer covers. The phone must not be the authority on a stale list.
        sale = self._sell_and_commit(4)
        ticket = self._ticket(sale)
        process_return(
            customer_id=self.customer.id,
            cashier=self.cashier,
            items_data=[{"variant_id": self.vuom.id, "qty": 1}],
            original_transaction_id=sale.id,
            reason="customer changed their mind",
        )
        response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertIn("changed since the text was sent", response.data["reply"])
        self.assertEqual(sale.bodega_releases.count(), 0)
        ticket.refresh_from_db()
        self.assertIsNone(ticket.used_at)

    def test_the_sale_row_is_locked_before_the_claim_is_read(self):
        # Issue 2: the claim comparison must not race a release made at the counter. The
        # fix is an ordering one, so the test asserts the ORDER: lock the sale, then read.
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        order = []
        real_lock = SalesTransaction.objects.select_for_update
        real_claim = bodega_services.claim_lines

        def tracking_lock(*args, **kwargs):
            order.append("sale-lock")
            return real_lock(*args, **kwargs)

        def tracking_claim(sale_ids=None):
            order.append("claim")
            return real_claim(sale_ids)

        with (
            mock.patch.object(
                services.SalesTransaction.objects, "select_for_update", tracking_lock
            ),
            mock.patch.object(
                services.bodega_services, "claim_lines", tracking_claim
            ),
        ):
            response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertEqual(response.data["status"], SmsMessage.Status.PROCESSED)
        self.assertIn("sale-lock", order)
        self.assertIn("claim", order)
        self.assertLess(
            order.index("sale-lock"),
            order.index("claim"),
            "the sale row must be locked before the claim is read",
        )

    def test_inbound_is_refused_while_the_link_is_off(self):
        # Issue 3: with SMS_ENABLED=false nothing may be processed OR consumed. The bridge
        # must get a non-2xx so it keeps the message on the SIM for when the link returns.
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        reference = services.sale_reference(sale)
        with override_settings(SMS_ENABLED=False):
            response = self._inbound(f"DONE {reference} {ticket.code}")
            self.assertEqual(response.status_code, 503, response.data)
            self.assertEqual(response.data["code"], "SMS_DISABLED")
        self.assertEqual(sale.bodega_releases.count(), 0)
        self.assertFalse(SmsMessage.objects.filter(direction=SmsMessage.Direction.IN).exists())
        ticket.refresh_from_db()
        self.assertIsNone(ticket.used_at)

    def test_a_pre_existing_inbound_key_returns_the_stored_answer(self):
        # The path a losing racer takes: the row with this key is already there, so the
        # answer is replayed and nothing is processed again.
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        SmsMessage.objects.create(
            direction=SmsMessage.Direction.IN,
            phone=PHONE,
            body="DONE",
            status=SmsMessage.Status.PROCESSED,
            inbound_key="already-seen",
            result="OK BR-20260101-0001 000123 released",
        )
        response = self._inbound(
            f"DONE {services.sale_reference(sale)} {ticket.code}", key="already-seen"
        )
        self.assertEqual(response.data["reply"], "OK BR-20260101-0001 000123 released")
        self.assertEqual(sale.bodega_releases.count(), 0)
        self.assertEqual(
            SmsMessage.objects.filter(direction=SmsMessage.Direction.IN).count(), 1
        )

    def test_a_duplicate_bridge_delivery_answers_once_and_releases_once(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        body = f"DONE {services.sale_reference(sale)} {ticket.code}"
        first = self._inbound(body, key="abc123")
        second = self._inbound(body, key="abc123")
        self.assertEqual(first.data, second.data)
        self.assertEqual(sale.bodega_releases.count(), 1)
        self.assertEqual(
            SmsMessage.objects.filter(direction=SmsMessage.Direction.IN).count(), 1
        )


class InboundNeedsAnAuthorizedContactTests(GatewayBase):
    def test_a_contact_whose_account_lost_the_role_gets_no_release(self):
        sale = self._sell_and_commit(2)
        ticket = self._ticket(sale)
        self.contact.user = self.cashier
        self.contact.save(update_fields=["user"])
        response = self._inbound(f"DONE {services.sale_reference(sale)} {ticket.code}")
        self.assertEqual(response.data["status"], SmsMessage.Status.REJECTED)
        self.assertIn("not linked to a Bodega checker", response.data["reply"])
        self.assertEqual(sale.bodega_releases.count(), 0)


def _staff(username, group):
    from django.contrib.auth import get_user_model

    user = get_user_model().objects.create_user(
        username=username,
        email=f"{username}@x.com",
        # nosemgrep: the hardcoded-password rule fires on a test fixture. This password
        # authenticates nothing: it exists only in the throwaway test database, and it is
        # the same fixture every other test module in this project uses.
        password="pass12345",
        full_name=username.title(),
    )
    user.groups.add(Group.objects.get_or_create(name=group)[0])
    return user


@override_settings(SMS_ENABLED=True, SMS_GATEWAY_KEY=GOOD_KEY)
class StaffApiTests(GatewayBase):
    def setUp(self):
        super().setUp()
        self.manager = _staff("smsboss", "Store Manager")
        self.admin = _staff("smsadmin", "Admin")

    def test_a_cashier_sees_no_sms_screens(self):
        self.api.force_authenticate(self.cashier)
        for url in ("/api/v1/sms/status/", "/api/v1/sms/messages/"):
            with self.subTest(url=url):
                self.assertEqual(self.api.get(url).status_code, 403)

    def test_a_store_manager_reads_the_status_and_the_log(self):
        self._sell_and_commit(2)
        self.api.force_authenticate(self.manager)
        status = self.api.get("/api/v1/sms/status/")
        self.assertEqual(status.status_code, 200, status.data)
        self.assertTrue(status.data["enabled"])
        self.assertTrue(status.data["gateway_configured"])
        self.assertEqual(status.data["queued"], 1)
        self.assertEqual(status.data["failed"], 0)
        self.assertIsNone(status.data["last_heartbeat"])

        log = self.api.get("/api/v1/sms/messages/")
        self.assertEqual(log.status_code, 200, log.data)
        self.assertEqual(log.data["count"], 1)
        self.assertEqual(log.data["results"][0]["direction"], "OUT")

    def test_the_log_filters_by_direction_and_status_and_is_newest_first(self):
        self._sell_and_commit(2)
        self.gateway.post(HEARTBEAT, {"info": {}}, format="json")
        self._inbound("HELP")
        self.api.force_authenticate(self.manager)
        inbound = self.api.get("/api/v1/sms/messages/", {"direction": "IN"})
        self.assertEqual(inbound.data["count"], 1)
        outbound = self.api.get("/api/v1/sms/messages/", {"direction": "OUT"})
        self.assertEqual(outbound.data["count"], 2)  # the pickup text + the HELP reply
        processed = self.api.get(
            "/api/v1/sms/messages/", {"direction": "IN", "status": "PROCESSED"}
        )
        self.assertEqual(processed.data["count"], 1)
        stamps = [
            row["created_at"]
            for row in self.api.get("/api/v1/sms/messages/").data["results"]
        ]
        self.assertEqual(stamps, sorted(stamps, reverse=True))

    def test_a_manager_can_retry_a_failed_message_but_not_a_queued_one(self):
        self._sell_and_commit(2)
        message = SmsMessage.objects.filter(direction=SmsMessage.Direction.OUT).first()
        self.api.force_authenticate(self.manager)
        refused = self.api.post(f"/api/v1/sms/messages/{message.pk}/retry/")
        self.assertEqual(refused.status_code, 400, refused.data)
        self.assertEqual(refused.data["code"], "SMS_RETRY_REFUSED")

        SmsMessage.objects.filter(pk=message.pk).update(
            status=SmsMessage.Status.FAILED, attempts=5, last_error="no carrier"
        )
        accepted = self.api.post(f"/api/v1/sms/messages/{message.pk}/retry/")
        self.assertEqual(accepted.status_code, 200, accepted.data)
        self.assertEqual(accepted.data["status"], "QUEUED")
        self.assertEqual(accepted.data["attempts"], 0)

    def test_the_staff_log_refuses_writes(self):
        self.api.force_authenticate(self.admin)
        response = self.api.post(
            "/api/v1/sms/messages/", {"phone": PHONE, "body": "x"}, format="json"
        )
        self.assertEqual(response.status_code, 405, response.data)

    def test_only_an_admin_registers_a_number(self):
        self._sell_and_commit(1)
        body = {"phone": PHONE, "user": self.checker.pk, "label": "Bodega"}
        self.api.force_authenticate(self.manager)
        self.assertEqual(
            self.api.post("/api/v1/sms/contacts/", body, format="json").status_code, 403
        )
        self.api.force_authenticate(self.admin)
        created = self.api.post("/api/v1/sms/contacts/", body, format="json")
        self.assertEqual(created.status_code, 400, created.data)  # PHONE is taken
        body["phone"] = "0917 999 8888"
        created = self.api.post("/api/v1/sms/contacts/", body, format="json")
        self.assertEqual(created.status_code, 201, created.data)
        self.assertEqual(created.data["phone"], "+639179998888")

    def test_a_contact_for_an_account_without_the_bodega_role_is_refused(self):
        self.api.force_authenticate(self.admin)
        response = self.api.post(
            "/api/v1/sms/contacts/",
            {"phone": "09171234000", "user": self.cashier.pk},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("user", response.data)

    def test_a_number_that_is_not_a_mobile_is_refused(self):
        self.api.force_authenticate(self.admin)
        response = self.api.post(
            "/api/v1/sms/contacts/",
            {"phone": "12345", "user": self.checker.pk},
            format="json",
        )
        self.assertEqual(response.status_code, 400, response.data)
        self.assertIn("phone", response.data)
