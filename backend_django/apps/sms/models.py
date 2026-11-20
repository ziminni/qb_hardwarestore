# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""SMS gateway models: the Bodega checker's phone as a second screen for releases.

The hardware is NOT owned by Django (the backend runs in Docker Desktop on Windows,
which cannot pass a COM port into a container). A thin bridge process on the host moves
messages; everything that decides anything lives here:

* `SmsContact` - which phone belongs to which Bodega account. Only contacts are answered;
  an unknown number costs no reply (load is money).
* `SmsMessage` - the two-way log. OUT rows are the queue the bridge drains; IN rows are
  what arrived, with a `result` sentence so a redelivered part is answered once.
* `BodegaSmsTicket` - the one-time code that protects `DONE <receipt> <code>`: caller ID
  can be spoofed, the code cannot be guessed in five tries.
* `SmsGatewayHeartbeat` - is the bridge alive, and with what signal.
"""

from django.conf import settings
from django.db import models

#: Wrong codes before a receipt's ticket locks. Five guesses at a 4-digit code.
MAX_FAILED_ATTEMPTS = 5


class SmsContact(models.Model):
    """A phone that may drive Bodega releases, and the account it acts as."""

    phone = models.CharField(max_length=20, unique=True, db_index=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="sms_contacts",
    )
    label = models.CharField(max_length=80, blank=True, default="")
    active = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "sms_contact"
        ordering = ("phone",)

    def __str__(self):
        return f"{self.phone} ({self.label or 'unlabelled'})"


class SmsMessage(models.Model):
    """One SMS in or out. OUT rows double as the bridge's work queue."""

    class Direction(models.TextChoices):
        OUT = "OUT", "Outbound"
        IN = "IN", "Inbound"

    class Status(models.TextChoices):
        # OUT, in the order a message travels.
        QUEUED = "QUEUED", "Queued"
        SENDING = "SENDING", "Sending"
        SENT = "SENT", "Sent"
        FAILED = "FAILED", "Failed"
        # IN
        RECEIVED = "RECEIVED", "Received"
        PROCESSED = "PROCESSED", "Processed"
        REJECTED = "REJECTED", "Rejected"

    direction = models.CharField(max_length=3, choices=Direction.choices, db_index=True)
    phone = models.CharField(max_length=32, db_index=True)
    body = models.TextField()
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.QUEUED, db_index=True
    )
    attempts = models.PositiveIntegerField(default=0)
    last_error = models.TextField(blank=True, default="")
    # The lease: a bridge that dies mid-send leaves SENDING behind, and the row comes
    # back to the queue once this is older than the lease window.
    claimed_at = models.DateTimeField(null=True, blank=True)
    sent_at = models.DateTimeField(null=True, blank=True)
    sale = models.ForeignKey(
        "pos.SalesTransaction",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    release = models.ForeignKey(
        "bodega.BodegaRelease",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    # What the bridge sends to make a redelivery answer once. NULL for outbound rows, and
    # Postgres allows many NULLs under a unique index.
    inbound_key = models.CharField(max_length=64, null=True, blank=True, unique=True)
    # The sentence the reply said, kept so a duplicate delivery can be answered with the
    # same words without doing the work twice.
    result = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = "sms_message"
        ordering = ("-created_at", "-id")

    def __str__(self):
        return f"{self.direction} {self.phone} [{self.status}]"


class BodegaSmsTicket(models.Model):
    """The one-time code that authorises one receipt's release from a phone."""

    sale = models.OneToOneField(
        "pos.SalesTransaction",
        on_delete=models.PROTECT,
        related_name="sms_ticket",
    )
    code = models.CharField(max_length=4)
    #: The claim AS NOTIFIED: `[{variant_id, location_id, qty}]`. A reply releases only
    #: when the receipt still looks exactly like the text the checker is holding - if a
    #: return or a counter release changed it, the phone cannot be the authority.
    snapshot = models.JSONField(default=list, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    used_at = models.DateTimeField(null=True, blank=True)
    release = models.ForeignKey(
        "bodega.BodegaRelease",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name="+",
    )
    failed_attempts = models.PositiveIntegerField(default=0)

    class Meta:
        db_table = "bodega_sms_ticket"

    def __str__(self):
        return f"{self.sale_id}: {self.code}"


class SmsGatewayHeartbeat(models.Model):
    """The bridge's last word (one row, pk=1). No row means it never ran."""

    last_seen = models.DateTimeField()
    info = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "sms_gateway_heartbeat"

    def __str__(self):
        return f"{self.last_seen:%Y-%m-%d %H:%M:%S}"
