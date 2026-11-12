"""Date-stamped document numbers — the ONE home for this pattern.

Requisitions (REQ-YYYYMMDD-NNNN) and quotations (QT-YYYYMMDD-NNNN) both number documents this way.
The pattern lived only in `apps/requisitions/services.generate_req_number`, which is why reusing it for
quotations first failed: it is hardcoded to the Requisition model. Copying it into `apps/pos` would have
created a second home for one fact — so a fix to the sequence width or the ordering would have to be
made twice, and the second copy is the one that gets forgotten.

Phase 6 B4 (decision 22 item 19): the sequence is now a `DocumentCounter` row locked with
`select_for_update`, not "read the newest document and add one" — the same fix decision 09 item 3
already made for TRX/OR. Reading the newest document is a race with a live request on either side of
it: two creates read `-0007`, both write `-0008`, and the loser dies on the field's unique constraint
as a 500. The reservation commits independently of the caller's insert, so a failed save leaves a gap
rather than a duplicate. Gaps are fine; duplicates are not.
"""

from datetime import date

from django.db import transaction


def generate_document_number(model, field: str, prefix: str) -> str:
    """Reserve the next ``<prefix>-YYYYMMDD-NNNN`` for ``model``'s ``field``.

    The counter row is created on the first document of the day, SEEDED from the highest
    number already written for that prefix and day (`highest_existing_sequence`, which
    parses the suffix in Python so a five-digit day does not seed too low). Seeding from
    0 would hand out the numbers live documents already hold.

    Imported inside the function because `apps.pos` imports this module, and the counter
    row lives with the other POS document counters rather than in a second table here.
    """
    from apps.pos.models import DocumentCounter
    from apps.pos.services import highest_existing_sequence

    today = date.today()
    stamp = f"{prefix}-{today.strftime('%Y%m%d')}-"
    with transaction.atomic():
        lock = DocumentCounter.objects.select_for_update()
        counter, _ = lock.get_or_create(
            prefix=prefix,
            day=today,
            defaults={"last": highest_existing_sequence(model, field, stamp)},
        )
        counter.last += 1
        counter.save(update_fields=["last"])
    return f"{stamp}{counter.last:04d}"
