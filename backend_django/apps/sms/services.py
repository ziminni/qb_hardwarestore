# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportGeneralTypeIssues=false
"""SMS services: the outbound trigger, the composer, the inbound release, the queue.

Read `models.py`'s docstring first. Two rules shape everything here:

* **The backend owns every decision.** The bridge only moves text between a modem and
  these endpoints, so a wrong reply can never move goods.
* **A reply releases what is still uncollected, and only that.** The claim is derived
  (`bodega.services.claim_lines`), the release is written by `record_release`, and the
  caller holds the transaction - the same shape the checker's screen uses.
"""

import hmac
import secrets
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone

from apps.bodega import services as bodega_services
from apps.bodega.exceptions import BodegaRefused
from apps.inventory.models import ProductVariant, StorageLocation
from apps.pos.models import Delivery, SalesItemDeduction, SalesTransaction
from apps.users.models import AuditLog
from apps.users.permissions import BODEGA_ROLES, has_role
from apps.users.services import log_audit

from .exceptions import SmsDisabled, SmsMessageNotFound, SmsRetryRefused
from .models import MAX_FAILED_ATTEMPTS, BodegaSmsTicket, SmsContact, SmsMessage
from .parser import KIND_DONE, KIND_HELP, KIND_INVALID, parse_inbound
from .phone import InvalidPhoneNumber, normalize_phone

#: One SMS. A longer body is billed as several parts and a modem may split it anyway.
SMS_LENGTH = 160
#: How long a claimed outbound message stays claimed before another bridge may take it.
LEASE_MINUTES = 5
#: Attempts before an outbound message is left FAILED for a human.
MAX_SEND_ATTEMPTS = 5

DEFAULT_RECEIVED_BY = "Customer (via SMS)"

HELP_TEXT = (
    "QB Bodega: reply DONE <receipt> <code> to release a pick-up, e.g. "
    "DONE 000123 4821. Add the receiver's name after the code if needed."
)
FORMAT_TEXT = (
    "QB Bodega: that was not a command. Reply DONE <receipt> <code>, "
    "e.g. DONE 000123 4821, or HELP."
)
NOT_AUTHORIZED_TEXT = (
    "QB Bodega: this number is not linked to a Bodega checker. Call the store."
)


# ---------------------------------------------------------------------------
# Text composition (pure)
# ---------------------------------------------------------------------------


def gsm_safe(text):
    """ASCII only: a GSM-7 modem sends a stray `₱` as garbage, and one unicode char
    re-encodes the whole message as UCS-2 (70 characters per part instead of 160)."""
    text = (text or "").replace("₱", "P").replace("–", "-").replace("—", "-")
    return "".join(ch for ch in text if 32 <= ord(ch) < 127)


def _qty(value):
    """`10.00` -> `10`, `2.50` -> `2.5`: what a person types, not a stock column."""
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return text or "0"


def _item_label(variant, qty):
    unit = variant.base_uom.code
    return (
        f"{_qty(qty)} {unit} {variant.product.base_name} {variant.variant_name}".strip()
    )


def compose_message(*, word, reference, code, items):
    """One <=160-character line: the receipt, the goods, the code, the reply format.

    The code and the reply instruction are NEVER truncated - they are what makes the
    message actionable. When the goods do not fit, the tail is cut and `+N more`
    says so; the checker then hands over the whole claim, which is what a reply does
    anyway.
    """
    head = gsm_safe(f"QB {word} {reference}: ")
    tail = gsm_safe(f". Code {code}. Reply: DONE {reference} {code}")
    budget = SMS_LENGTH - len(head) - len(tail)
    if budget <= 0:  # a pathological receipt number; the code still goes out
        head = gsm_safe(f"QB {word}: ")
        budget = SMS_LENGTH - len(head) - len(tail)
    return head + _fit_items([gsm_safe(item) for item in items], budget) + tail


def _fit_items(items, budget):
    kept = []
    for index, item in enumerate(items):
        remaining = len(items) - index - 1
        suffix = f" +{remaining} more" if remaining else ""
        candidate = "; ".join(kept + [item])
        if len(candidate) + len(suffix) > budget:
            if kept:
                break
            # The very first item alone is too long: cut it, but keep room for the count.
            room = max(budget - len(suffix), 0)
            kept.append(item[:room].rstrip())
            break
        kept.append(item)
    missing = len(items) - len(kept)
    text = "; ".join(kept)
    if missing:
        text = f"{text} +{missing} more" if text else f"+{missing} more"
    return text[:budget]


#: Fixed at 4 digits: one field in a text message, guessable only 5 times.
def new_code():
    return f"{secrets.randbelow(10000):04d}".zfill(4)


def sale_reference(sale):
    """The short reference the checker types back: the OR number when there is one."""
    receipt = getattr(sale, "receipt", None)
    return (receipt.or_number if receipt else "") or sale.transaction_no


def is_delivery(sale):
    return Delivery.objects.filter(sale=sale).exists()


def active_contacts():
    """Active numbers whose account is active and may work the Bodega screens."""
    contacts = SmsContact.objects.filter(
        active=True, user__isnull=False
    ).select_related("user")
    return [contact for contact in contacts if bodega_checker_for(contact)]


def holds_bodega_role(user):
    """True when the account may work the Bodega screens (`IsBodegaRole`'s list)."""
    return bool(user) and user.is_active and has_role(user, BODEGA_ROLES)


def bodega_checker_for(contact):
    """The account a contact acts as, or None when it may not release anything.

    The role list is `IsBodegaRole`'s own: whoever may press Release in the app may
    release by text, so a day without the checker does not stop a pick-up.
    """
    user = contact.user
    if user is None or not user.is_active:
        return None
    return user if has_role(user, BODEGA_ROLES) else None


# ---------------------------------------------------------------------------
# Outbound trigger (post_save on SalesTransaction, inside on_commit)
# ---------------------------------------------------------------------------


def enqueue_for_sale(sale_id):
    """Text the checker about a sale that took goods from a Bodega shelf.

    Called from `transaction.on_commit` after the sale is committed, so a rolled-back
    sale never texts anyone. Returns the created messages (empty is the normal case:
    disabled, no Bodega lines, no contact).
    """
    if not getattr(settings, "SMS_ENABLED", False):
        return []
    sale = (
        SalesTransaction.objects.select_related("receipt", "customer")
        .filter(pk=sale_id)
        .first()
    )
    if sale is None or sale.source == SalesTransaction.Source.RETURN:
        return []
    lines = [
        line for line in bodega_services.claim_lines([sale.pk]) if line["remaining"] > 0
    ]
    if not lines:
        return []
    contacts = active_contacts()
    if not contacts:
        return []
    reference = sale_reference(sale)
    variants = ProductVariant.objects.select_related("product", "base_uom").in_bulk(
        {line["variant_id"] for line in lines}
    )
    items = [
        _item_label(variants[line["variant_id"]], line["remaining"])
        for line in sorted(
            lines, key=lambda row: (row["variant_id"], row["location_id"])
        )
    ]
    word = "DELIVERY" if is_delivery(sale) else "PICKUP"
    # One ticket per receipt: a second text about the same sale re-sends the SAME code
    # instead of minting a second one the checker never saw.
    snapshot = [
        {
            "variant_id": line["variant_id"],
            "location_id": line["location_id"],
            "qty": str(line["remaining"]),
        }
        for line in lines
    ]
    ticket, created = BodegaSmsTicket.objects.get_or_create(
        sale=sale, defaults={"code": new_code(), "snapshot": snapshot}
    )
    if not created and ticket.used_at is not None:
        return []
    body = compose_message(
        word=word, reference=reference, code=ticket.code, items=items
    )
    messages = SmsMessage.objects.bulk_create(
        [
            SmsMessage(
                direction=SmsMessage.Direction.OUT,
                phone=contact.phone,
                body=body,
                status=SmsMessage.Status.QUEUED,
                sale=sale,
            )
            for contact in contacts
        ]
    )
    return messages


def sales_awaiting_text(limit=50):
    """Sales that took Bodega goods and never got an outbound text, newest first.

    This is the recovery path behind `requeue_sms_notifications`: without it, an enqueue
    that failed after the sale committed would leave a pick-up nobody is ever told about.
    Bounded by `limit` on purpose - a repair is run by hand, in batches.
    """
    candidates = (
        SalesItemDeduction.objects.filter(
            batch__location__is_bodega=True,
            qty__gt=0,
            sales_item__transaction__status=SalesTransaction.Status.COMPLETED,
        )
        .exclude(sales_item__transaction__source=SalesTransaction.Source.RETURN)
        .order_by("-sales_item__transaction_id")
        .values_list("sales_item__transaction_id", flat=True)
        .distinct()[: max(1, int(limit))]
    )
    return [
        sale_id
        for sale_id in candidates
        if not SmsMessage.objects.filter(
            direction=SmsMessage.Direction.OUT, sale_id=sale_id
        ).exists()
    ]


# ---------------------------------------------------------------------------
# The bridge's queue
# ---------------------------------------------------------------------------


def claim_outbox(limit):
    """Lease queued messages; lost acknowledgements can still cause duplicate SMS.

    A message left SENDING by a bridge that died comes back after `LEASE_MINUTES`.
    """
    if not getattr(settings, "SMS_ENABLED", False):
        raise SmsDisabled()
    limit = max(1, min(int(limit), 50))
    now = timezone.now()
    stale = now - timedelta(minutes=LEASE_MINUTES)
    with transaction.atomic():
        ids = list(
            SmsMessage.objects.select_for_update(skip_locked=True)
            .filter(direction=SmsMessage.Direction.OUT)
            .filter(
                Q(status=SmsMessage.Status.QUEUED)
                | Q(status=SmsMessage.Status.SENDING, claimed_at__lt=stale)
            )
            .order_by("created_at", "id")
            .values_list("pk", flat=True)[:limit]
        )
        if not ids:
            return []
        SmsMessage.objects.filter(pk__in=ids).update(
            status=SmsMessage.Status.SENDING, claimed_at=now
        )
        return list(
            SmsMessage.objects.filter(pk__in=ids)
            .order_by("created_at", "id")
            .values("id", "phone", "body")
        )


def report_send_result(message_id, ok, error=""):
    """What the modem said. Failure returns the row to the queue, then gives up."""
    with transaction.atomic():
        message = (
            SmsMessage.objects.select_for_update()
            .filter(pk=message_id, direction=SmsMessage.Direction.OUT)
            .first()
        )
        if message is None:
            raise SmsMessageNotFound(f"SMS {message_id} does not exist.")
        if message.status in (SmsMessage.Status.SENT, SmsMessage.Status.FAILED):
            # Terminal. A second bridge (or the same one after a lost response) reporting
            # late must not push a delivered message back into the queue: that would send
            # the checker a second text for a pick-up already released.
            return message
        message.attempts += 1
        message.last_error = "" if ok else str(error or "send failed")[:2000]
        if ok:
            message.status = SmsMessage.Status.SENT
            message.sent_at = timezone.now()
        elif message.attempts >= MAX_SEND_ATTEMPTS:
            message.status = SmsMessage.Status.FAILED
            message.claimed_at = None
        else:
            message.status = SmsMessage.Status.QUEUED
            message.claimed_at = None
        message.save(
            update_fields=[
                "attempts",
                "last_error",
                "status",
                "sent_at",
                "claimed_at",
            ]
        )
        return message


def retry_message(message_id):
    """A human puts a FAILED message back in the queue with a fresh set of attempts."""
    with transaction.atomic():
        message = SmsMessage.objects.select_for_update().filter(pk=message_id).first()
        if message is None:
            raise SmsMessageNotFound(f"SMS {message_id} does not exist.")
        if (
            message.direction != SmsMessage.Direction.OUT
            or message.status != SmsMessage.Status.FAILED
        ):
            raise SmsRetryRefused("Only a FAILED outbound message can be retried.")
        message.status = SmsMessage.Status.QUEUED
        message.attempts = 0
        message.claimed_at = None
        message.last_error = ""
        message.save(update_fields=["status", "attempts", "claimed_at", "last_error"])
        return message


def heartbeat(info):
    from .models import SmsGatewayHeartbeat

    row, _ = SmsGatewayHeartbeat.objects.get_or_create(
        pk=1, defaults={"last_seen": timezone.now()}
    )
    row.last_seen = timezone.now()
    row.info = info if isinstance(info, dict) else {}
    row.save(update_fields=["last_seen", "info"])
    return row


# ---------------------------------------------------------------------------
# Inbound: the release itself
# ---------------------------------------------------------------------------


def _reply(phone, body, *, sale=None, release=None):
    return SmsMessage.objects.create(
        direction=SmsMessage.Direction.OUT,
        phone=phone,
        body=gsm_safe(body)[:SMS_LENGTH],
        status=SmsMessage.Status.QUEUED,
        sale=sale,
        release=release,
    )


def process_inbound(*, phone, body, inbound_key=None, received_at=None):
    """Read one SMS, release the claim it names, and queue the reply.

    Returns `{"status", "reply"}`. The whole decision runs in ONE `atomic()` block with
    the ticket row locked, so two messages with the same code cannot both release (the
    second finds the ticket used), and a refusal writes no release at all.
    """
    if not getattr(settings, "SMS_ENABLED", False):
        # Refused BEFORE anything is written. Storing the message now would consume the
        # bridge's dedupe key, and the retry after the shop turns the link on would then
        # get a stored answer for a DONE that was never processed. The bridge keeps the SMS
        # on the SIM because it only deletes on 2xx.
        raise SmsDisabled()

    raw_phone = (phone or "").strip()[:32]
    if inbound_key:
        stored = SmsMessage.objects.filter(
            direction=SmsMessage.Direction.IN, inbound_key=inbound_key
        ).first()
        if stored is not None:
            return {"status": stored.status, "reply": stored.result}

    contact = None
    checker = None
    try:
        contact = (
            SmsContact.objects.select_related("user")
            .filter(phone=normalize_phone(phone), active=True)
            .first()
        )
    except InvalidPhoneNumber:
        contact = None
    if contact is not None:
        checker = bodega_checker_for(contact)

    with transaction.atomic():
        try:
            # The unique `inbound_key` is the real guard: two bridges posting the same
            # message at the same instant both pass the check above, and the SECOND
            # insert is what fails - inside its own savepoint, so the outer block (and
            # the first bridge's release) survives.
            with transaction.atomic():
                message = SmsMessage.objects.create(
                    direction=SmsMessage.Direction.IN,
                    phone=raw_phone,
                    body=(body or "").strip(),
                    status=SmsMessage.Status.RECEIVED,
                    inbound_key=inbound_key,
                )
        except IntegrityError:
            stored = SmsMessage.objects.filter(
                direction=SmsMessage.Direction.IN, inbound_key=inbound_key
            ).first()
            if stored is None:
                raise
            return {"status": stored.status, "reply": stored.result}
        if contact is None:
            # An unknown (or deactivated) number gets no reply: a reply is load, and a
            # stranger's "DONE" must not even earn a confirmation that the shop exists.
            return _finish(message, SmsMessage.Status.REJECTED, "")

        if checker is None:
            _reply(contact.phone, NOT_AUTHORIZED_TEXT)
            return _finish(message, SmsMessage.Status.REJECTED, NOT_AUTHORIZED_TEXT)

        command = parse_inbound(body)
        if command.kind == KIND_HELP:
            _reply(contact.phone, HELP_TEXT)
            return _finish(message, SmsMessage.Status.PROCESSED, HELP_TEXT)
        if command.kind == KIND_INVALID:
            _reply(contact.phone, FORMAT_TEXT)
            return _finish(message, SmsMessage.Status.REJECTED, FORMAT_TEXT)
        if command.kind != KIND_DONE:
            _reply(contact.phone, FORMAT_TEXT)
            return _finish(message, SmsMessage.Status.REJECTED, FORMAT_TEXT)

        return _release_by_text(
            message=message,
            contact=contact,
            checker=checker,
            command=command,
            received_at=received_at,
        )


def _finish(message, status, text, *, sale=None, release=None):
    """Store what was answered on the inbound row (and what it produced, if anything)."""
    message.status = status
    message.result = text
    message.sale = sale
    message.release = release
    message.save(update_fields=["status", "result", "sale", "release"])
    return {"status": status, "reply": text}


def _release_by_text(*, message, contact, checker, command, received_at):
    """The `DONE <receipt> <code>` path: verify, claim, release, reply."""
    sale = None
    try:
        sale = bodega_services.find_sale(command.reference)
    except bodega_services.NoBodegaClaim:
        text = (
            f"QB Bodega: no receipt {command.reference} found. Check the number and "
            "reply again, or call the store."
        )
        _reply(contact.phone, text)
        return _finish(message, SmsMessage.Status.REJECTED, text)

    # Lock order is SALE then TICKET, always - `record_release` locks the sale row itself,
    # and two paths that take them in opposite orders deadlock under real load. The claim
    # is read only AFTER the sale is locked, so a release made at the counter cannot slip
    # in between the snapshot comparison below and the write that follows it.
    SalesTransaction.objects.select_for_update().get(pk=sale.pk)

    ticket = BodegaSmsTicket.objects.select_for_update().filter(sale=sale).first()
    if ticket is None:
        text = (
            f"QB Bodega: receipt {command.reference} has no pickup code. Release it in "
            "the Bodega app instead."
        )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.REJECTED, text, sale=sale)

    if ticket.used_at is not None:
        text = (
            f"QB Bodega: receipt {command.reference} was already released. "
            "Nothing left to hand over."
        )
        _reply(contact.phone, text, sale=sale, release=ticket.release)
        return _finish(
            message,
            SmsMessage.Status.PROCESSED,
            text,
            sale=sale,
            release=ticket.release,
        )

    if ticket.failed_attempts >= MAX_FAILED_ATTEMPTS:
        text = (
            f"QB Bodega: code for receipt {command.reference} is locked after "
            f"{MAX_FAILED_ATTEMPTS} wrong tries. Use the Bodega app or call the store."
        )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.REJECTED, text, sale=sale)

    if not hmac.compare_digest(str(command.code), str(ticket.code)):
        ticket.failed_attempts += 1
        ticket.save(update_fields=["failed_attempts"])
        if ticket.failed_attempts >= MAX_FAILED_ATTEMPTS:
            text = (
                f"QB Bodega: wrong code. Receipt {command.reference} is now locked. "
                "Use the Bodega app or call the store."
            )
        else:
            left = MAX_FAILED_ATTEMPTS - ticket.failed_attempts
            text = (
                f"QB Bodega: wrong code for receipt {command.reference}. {left} "
                "tries left."
            )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.REJECTED, text, sale=sale)

    lines = [
        line for line in bodega_services.claim_lines([sale.pk]) if line["remaining"] > 0
    ]
    if not lines:
        ticket.used_at = timezone.now()
        ticket.save(update_fields=["used_at"])
        text = (
            f"QB Bodega: receipt {command.reference} is already fully released. "
            "Nothing left to hand over."
        )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.PROCESSED, text, sale=sale)

    notified = {
        (row.get("variant_id"), row.get("location_id")): Decimal(
            str(row.get("qty", "0"))
        )
        for row in ticket.snapshot or []
    }
    current = {
        (line["variant_id"], line["location_id"]): line["remaining"] for line in lines
    }
    if notified and notified != current:
        # A return, or a release made at the counter, moved the claim after the text went
        # out. The phone holds a stale list, and releasing "everything" would then hand
        # over goods the receipt no longer covers - or too few. The app shows the truth.
        text = (
            f"QB Bodega: receipt {command.reference} changed since the text was sent "
            "(a return or a release). Use the Bodega app for this pick-up."
        )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.REJECTED, text, sale=sale)

    variants = ProductVariant.objects.in_bulk({line["variant_id"] for line in lines})
    locations = StorageLocation.objects.in_bulk({line["location_id"] for line in lines})
    try:
        release = bodega_services.record_release(
            sale=sale,
            checker=checker,
            received_by=command.name or DEFAULT_RECEIVED_BY,
            plate_no="",
            notes=f"Released by SMS from {contact.phone}"[:255],
            lines=[
                (
                    variants[line["variant_id"]],
                    locations[line["location_id"]],
                    line["remaining"],
                )
                for line in lines
            ],
        )
    except BodegaRefused as refusal:
        # The Bodega module's own refusal (a claim that moved, a quantity over it). A 500
        # here would leave the bridge retrying a DONE forever; the checker gets a sentence
        # and the answer is stored on the message, so the retry replays it.
        text = (
            f"QB Bodega: receipt {command.reference} could not be released "
            f"({refusal}). Use the Bodega app."
        )
        _reply(contact.phone, text, sale=sale)
        return _finish(message, SmsMessage.Status.REJECTED, text, sale=sale)
    ticket.used_at = timezone.now()
    ticket.release = release
    ticket.save(update_fields=["used_at", "release"])
    log_audit(
        user=checker,
        action_type=AuditLog.ActionType.RELEASE,
        username=checker.username,
        description=(
            f"Bodega release {release.number} against {sale.transaction_no} by SMS from "
            f"{contact.phone}: {len(lines)} line(s) to {release.received_by}."
        ),
    )
    text = f"OK {release.number} {command.reference} released"
    _reply(contact.phone, text, sale=sale, release=release)
    return _finish(
        message, SmsMessage.Status.PROCESSED, text, sale=sale, release=release
    )
