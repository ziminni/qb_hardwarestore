"""The outbound trigger, as a receiver instead of a line inside `pos.services`.

`process_sale` is being edited by another lane, and a sale that took goods from a Bodega
shelf is a fact about the SALE, not about the checkout code. So the trigger watches the
sale row: on a newly created, non-return sale it registers the text for AFTER the
transaction commits (a rolled-back sale texts nobody), and `enqueue_for_sale` re-reads
the claim from the database, which is the only authority on "what may still be
collected".
"""

import logging

from django.db import transaction
from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.pos.models import SalesTransaction

from . import services

logger = logging.getLogger("apps.sms")


def _enqueue_after_commit(sale_id):
    """Text one sale, and fail QUIETLY: this runs after the sale is already committed.

    An exception escaping here reaches the cashier as a 500 on a sale the shop has
    recorded - "the checkout failed" for something that succeeded. So it is caught and
    LOGGED with the one command that recovers it; `requeue_sms_notifications` finds sales
    with Bodega claims and no text, so a lost notification is durably recoverable rather
    than silently gone.
    """
    try:
        services.enqueue_for_sale(sale_id)
    except Exception:  # swallowing IS the requirement here, see the docstring
        logger.exception(
            "SMS enqueue failed for sale %s; recover with "
            "`manage.py requeue_sms_notifications`",
            sale_id,
        )


@receiver(post_save, sender=SalesTransaction, dispatch_uid="sms.sale_committed")
def sms_on_sale_committed(sender, instance, created, **kwargs):
    if not created:
        return
    if instance.source == SalesTransaction.Source.RETURN:
        # A return gives goods back; it never opens a claim to collect.
        return
    sale_id = instance.pk
    # `robust=True` is the second belt: Django's own on_commit runner logs and swallows
    # instead of raising into the request that just committed the sale.
    transaction.on_commit(lambda: _enqueue_after_commit(sale_id), robust=True)
