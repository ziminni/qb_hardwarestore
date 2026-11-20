# pyright: reportAttributeAccessIssue=false, reportArgumentType=false
"""Re-queue the pick-up text for sales that never got one.

The outbound trigger runs AFTER a sale commits (a rolled-back sale must text nobody), so
if it fails there is nothing left to retry it - the sale is recorded and the checker is
never told. This command is that retry, run by hand or from a scheduled task:

    python manage.py requeue_sms_notifications --limit 50
    python manage.py requeue_sms_notifications --dry-run

Batches are bounded (`--limit`, newest sales first) because it walks sales with Bodega
lines. It only ever queues a text for a sale that has none, so running it twice is safe.
"""

import logging

from django.conf import settings
from django.core.management.base import BaseCommand

from apps.sms import services

logger = logging.getLogger("apps.sms")


class Command(BaseCommand):
    help = "Queue the Bodega pick-up SMS for sales that never got one (bounded batch)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--limit", type=int, default=50, help="how many sales to inspect (default 50)"
        )
        parser.add_argument(
            "--dry-run", action="store_true", help="report what would be queued, change nothing"
        )

    def handle(self, *args, **options):
        if not getattr(settings, "SMS_ENABLED", False):
            self.stderr.write(
                "SMS_ENABLED is false: nothing can be queued until the link is switched on."
            )
            return
        sale_ids = services.sales_awaiting_text(limit=options["limit"])
        if options["dry_run"]:
            self.stdout.write(
                f"dry run: {len(sale_ids)} sale(s) would be requeued {sale_ids}"
            )
            return
        queued = 0
        failed = 0
        for sale_id in sale_ids:
            try:
                queued += len(services.enqueue_for_sale(sale_id))
            except Exception:  # one bad sale must not stop the batch
                failed += 1
                logger.exception("requeue failed for sale %s", sale_id)
        self.stdout.write(
            f"inspected {len(sale_ids)} sale(s): queued {queued} message(s), {failed} failed"
        )
