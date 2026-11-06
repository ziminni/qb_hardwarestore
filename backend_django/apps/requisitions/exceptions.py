"""Requisitions domain exceptions.

Kept separate from `services` so the API layer can import the type without importing the
service module — same layout as `apps.inventory.exceptions` and `apps.pos.exceptions`.
"""


class CpmsRefusal(ValueError):
    """A CPMS call the POS refuses, with the status code the contract promises.

    `code` and `status_code` ride on the error because the contract distinguishes them —
    `400` says "fix the payload", `404` says "this id means nothing here", `409` says
    "the id is real but its state forbids this". The view turns any of them into the
    `{code, detail}` body the whole API uses.

    A `ValueError` subclass so a caller that only knows the base type still treats it as
    a client error rather than a crash.
    """

    code = 'CPMS_REFUSED'
    status_code = 400

    def __init__(self, message=None):
        super().__init__(message or 'This call cannot be made.')


class RequestImportRefused(CpmsRefusal):
    """A CPMS push the POS refuses (Phase 1, Task 3; decisions 02 and 04).

    `status_code` rides on the error because the contract distinguishes them: a `409` tell
    CPMS "this token is someone else's", a `400` tells it what to fix in the payload. The
    import raises every one of these BEFORE the first write, and the view adds the
    `{code, detail}` body the whole API uses.
    """

    code = 'INVALID_REQUEST_IMPORT'

    def __init__(self, message=None):
        super().__init__(message or 'This request cannot be imported.')


class UnknownPayer(RequestImportRefused):
    """`project.payer` names no active contractor or construction firm (P1).

    The payer is a POS customer id, read from `GET customers/` — the same id CPMS was
    given. Walk-in, regular and deactivated customers are all refused: a project bills a
    contractor, and utang has to land on a payer that exists and may owe.
    """

    code = 'UNKNOWN_PAYER'

    def __init__(self, payer_id, message=None):
        self.payer_id = payer_id
        super().__init__(
            message
            or f'Payer {payer_id} is not an active contractor or construction firm.')


class UnknownMaterial(RequestImportRefused):
    """One or more `items[].code` values are not in the material list (decision 04).

    Every offending code is named at once, so CPMS can fix the whole request in one go
    instead of discovering the misses one retry at a time.
    """

    code = 'UNKNOWN_MATERIAL'

    def __init__(self, codes, message=None):
        self.codes = list(codes)
        super().__init__(
            message
            or 'Unknown material code(s): '
               + ', '.join(self.codes)
               + '. Pick a code from GET materials/.')


class DuplicateMaterial(RequestImportRefused):
    """The same selling unit appears twice in one request.

    Two lines for one unit cannot both be released in one pass, and the second would
    silently double the quantity — so the request is refused, not merged.
    """

    code = 'DUPLICATE_MATERIAL'

    def __init__(self, codes, message=None):
        self.codes = list(codes)
        super().__init__(
            message
            or 'The same material appears more than once: '
               + ', '.join(self.codes)
               + '. Send one line per material.')


class NothingToRelease(ValueError):
    """Nothing on the request can leave the store right now (Phase 1, decision 05).

    Every line is short, out of stock, archived or already released, so a release would
    be a sale for zero. Answers `400 NOTHING_TO_RELEASE` and writes nothing at all — no
    sale, no receipt, no utang, no audit row — so the cashier can try the SAME token
    again after a goods receipt arrives.

    A stable `code` because the till has to say "nothing on this request is in stock"
    rather than show a sentence, the same `{code, detail}` shape every refusal uses.
    """

    code = 'NOTHING_TO_RELEASE'

    def __init__(self, message=None):
        super().__init__(
            message
            or 'Nothing on this request can be released: every line is short, '
               'out of stock or unavailable. The token stays valid.')


class TokenTaken(RequestImportRefused):
    """Another requisition already holds this token (decision 02).

    A token is the bearer credential the cashier scans, and `MaterialToken.token` is
    unique — so this is a `409`, not a `400`: the payload is well-formed, the identifier
    itself is spoken for. CPMS must mint a new one.
    """

    code = 'TOKEN_TAKEN'
    status_code = 409

    def __init__(self, message=None):
        super().__init__(
            message
            or 'This token already belongs to another requisition. '
               'Mint a new token for this request.')


class UnknownRequest(CpmsRefusal):
    """No POS copy is stored for that CPMS request id (Phase 1, decision 07).

    A `404`, not a `400`: the id is well-formed, this POS simply has no such request. The
    same answer for the close and the read-back, so CPMS cannot tell them apart when it
    is looking for a request that never landed here.
    """

    code = 'REQUEST_NOT_FOUND'
    status_code = 404

    def __init__(self, cpms_request_id, message=None):
        self.cpms_request_id = cpms_request_id
        super().__init__(
            message
            or f'No request is stored for CPMS request id {cpms_request_id}.')


class RequestCancelled(CpmsRefusal):
    """The request was cancelled, so its remainder is already dead (decision 06).

    A `409`: the id is real and the payload is fine, but cancelling is a decision already
    made here, and a close must not overwrite it with `CLOSED`.
    """

    code = 'REQUEST_CANCELLED'
    status_code = 409

    def __init__(self, cpms_request_id, message=None):
        self.cpms_request_id = cpms_request_id
        super().__init__(
            message
            or f'Request {cpms_request_id} was CANCELLED; it cannot be closed.')


class UnknownProject(CpmsRefusal):
    """No project is stored for that CPMS project id (Phase 1, decision 07).

    `404` for the same reason as `UnknownRequest`: a project the POS only learns about
    through a push, so "never pushed" and "misspelt id" look identical from here.
    """

    code = 'PROJECT_NOT_FOUND'
    status_code = 404

    def __init__(self, cpms_project_id, message=None):
        self.cpms_project_id = cpms_project_id
        super().__init__(
            message
            or f'No project is stored for CPMS project id {cpms_project_id}.')


class RequisitionNotReleasable(ValueError):
    """The scanned request is CLOSED, RELEASED or CANCELLED (Phase 1, decision 05/06).

    `code` is `REQUISITION_<STATUS>` so the till picks its copy without parsing prose.
    """

    def __init__(self, status, message):
        super().__init__(message)
        self.code = f'REQUISITION_{status}'
