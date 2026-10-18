"""Date-stamped document numbers — the ONE home for this pattern.

Requisitions (REQ-YYYYMMDD-NNNN) and quotations (QT-YYYYMMDD-NNNN) both number documents this way.
The pattern lived only in `apps/requisitions/services.generate_req_number`, which is why reusing it for
quotations first failed: it is hardcoded to the Requisition model. Copying it into `apps/pos` would have
created a second home for one fact — so a fix to the sequence width or the ordering would have to be
made twice, and the second copy is the one that gets forgotten.
"""
from datetime import date


def generate_document_number(model, field: str, prefix: str) -> str:
    """Next ``<prefix>-YYYYMMDD-NNNN`` for ``model``'s ``field``.

    Ordered by the field DESCENDING and parsed from the tail, so the sequence survives a day with
    more than nine documents (a lexical sort would put '-0010' before '-0009').
    """
    today = date.today().strftime('%Y%m%d')
    last = (
        model.objects
        .filter(**{f'{field}__startswith': f'{prefix}-{today}'})
        .order_by(f'-{field}')
        .first()
    )
    sequence = int(getattr(last, field).split('-')[-1]) + 1 if last else 1
    return f'{prefix}-{today}-{sequence:04d}'
