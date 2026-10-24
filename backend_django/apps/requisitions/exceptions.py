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
