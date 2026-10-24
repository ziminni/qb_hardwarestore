"""Users app — domain exceptions.

Same shape as the other apps' `exceptions.py`: a stable machine-readable ``code`` plus a
human sentence, so a client can map the refusal to a message without parsing prose.
"""


class ImmutableAuditLog(Exception):
    """Raised when anything tries to change or remove a written audit row.

    An audit trail that can be edited is not evidence of anything. Decision 07 makes the
    refusal structural rather than conventional: ``AuditLog.save()`` on an existing row,
    ``AuditLog.delete()``, and the custom queryset's ``update()`` / ``delete()`` all raise
    this, so no view, script or future refactor can quietly rewrite history.
    """

    code = 'IMMUTABLE_AUDIT_LOG'

    def __init__(self, message='Audit log entries are append-only and cannot be changed.'):
        super().__init__(message)
