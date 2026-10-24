"""Requisitions domain exceptions.

Kept separate from `services` so the API layer can import the type without importing the
service module — same layout as `apps.inventory.exceptions` and `apps.pos.exceptions`.
"""


class NoBaseUom(ValueError):
    """A requisition line whose variant has no factor-1 (base unit) selling price.

    `release_materials` prices a release from the variant's base-unit `VariantUOM`
    (`conversion_factor == 1`, `default_selling_price`), because requisition quantities are
    already in base units and the sale line has to point at a real `VariantUOM`.

    When that row is missing there is nothing honest to charge: the old code fell back to
    `unit_price = 0` and still handed `variant_uom=None` to a non-null FK, so the request
    stocked out the materials and then died with an IntegrityError 500 — the cashier saw a
    crash, the sale was half-written inside the block, and a retry could deduct again.

    Raised BEFORE any write (decision 09 item 6), so the refusal leaves the ledger, the
    stock, the receipt and the token exactly as they were.

    A `ValueError` subclass for the same reason as `InsufficientStock`: the token is valid
    and the request well-formed, the shop's catalog just cannot price one of the lines.
    """

    code = 'NO_BASE_UOM'

    def __init__(self, variant, message=None):
        self.variant_id = getattr(variant, 'pk', variant)
        super().__init__(
            message
            or f'Variant {variant} has no base-unit selling price: add a selling unit '
               'with conversion factor 1 before releasing it.')


class SelfApproval(ValueError):
    """The approver is the person who requested the material (decision 04 / NFR).

    Separation of duties: approving is the second signature. A Site Foreman who was also
    promoted to Store Manager could otherwise mint their own material token and release
    goods on credit with nobody's agreement — a superuser included, because the rule is
    about the paperwork, not about rank.

    A `ValueError` subclass for the same reason as `NoBaseUom`: the request is
    well-formed, the shop's rules just refuse it. Raised BEFORE any write, so the
    requisition stays SUBMITTED and no `MaterialToken` row exists afterwards.
    """

    code = 'SELF_APPROVAL'

    def __init__(self, message=None):
        super().__init__(
            message
            or 'You cannot approve a requisition you requested: approval needs a second '
               'person.')


class RequisitionLocked(ValueError):
    """A requisition — or one of its lines — was changed after it left DRAFT.

    P2 ruling (R): once a requisition is submitted for approval it is frozen. Editing the
    lines after approval would change WHAT the material token releases, so the POS would
    hand over goods nobody approved.

    A `ValueError` subclass so the view keeps one refusal path: the client gets
    `{"code": "REQUISITION_LOCKED", "detail": …}` and nothing is written.
    """

    code = 'REQUISITION_LOCKED'

    def __init__(self, status, message=None):
        self.status = status
        super().__init__(
            message
            or f'This requisition is {status}: only a DRAFT requisition can be changed. '
               'Create a new requisition instead.')
