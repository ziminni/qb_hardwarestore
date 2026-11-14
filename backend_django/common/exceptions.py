"""Refusals shared by more than one app.

A home here rather than in `apps.inventory.exceptions` or `apps.pos.exceptions` because
the rule spans both directions of the dependency graph: the POS validator, the purchasing
serializers, the goods-receipt view, the adjustment serializer and the CPMS import all ask
the same question, and none of those layers may import another's API module to ask it.
"""

from rest_framework.exceptions import APIException


class InactiveSellingUnit(APIException):
    status_code = 400


def refuse_inactive_selling_unit(*, variant_uom, what):
    """Raise `InactiveSellingUnit` when the unit's variant OR its product is archived.

    An archived variant (or a variant whose product was archived) is off the catalogue:
    a document that names it can never be picked, so it is refused BEFORE the first
    write. Same `is_active` flags the till's `_validated_sale_lines` reads.
    """
    if not variant_uom.variant.is_active or not variant_uom.variant.product.is_active:
        raise InactiveSellingUnit(
            {"code": "INACTIVE_SELLING_UNIT", "detail": f"{what} is archived."}
        )


class WholeUnitQuantity(ValueError):
    """A fractional quantity on a unit counted in whole numbers (Phase 1d, decision 16).

    `UnitOfMeasure.is_whole` is what makes a bag, a box or a roll countable in ones only;
    a kilogram, a metre or a litre takes a fraction. The flag lives on the unit row so the
    SERVER decides, not a client's hard-coded code list - a client-side check is advisory,
    and a hand-written request would otherwise sell 1.5 bags.

    One code for every path that carries a quantity (sale, return, held cart, quotation,
    sales order, purchase order, goods receipt, stock adjustment, CPMS import): the
    client's answer is always the same - show the detail and let the clerk fix the line -
    and `detail` names the line, product and unit.

    A `ValueError` subclass, like `InvalidSale`: it is a wrongly built request, and every
    raise site checks it BEFORE the first write, so the 400 also means "nothing changed".
    Published by `apps.pos.exceptions.handler` as `{code, detail}` with HTTP 400.
    """

    code = "WHOLE_UNIT_QUANTITY"


def refuse_fractional_whole_unit(*, is_whole, qty, what):
    """Raise `WholeUnitQuantity` when a whole unit's quantity is not a whole number.

    `what` names the place the quantity came from, in the words of the path that raised
    it ("Line 2 (Portland Cement — 40kg, BAG)" or "po_item 7"), because the clerk's next
    move is to correct THAT line.
    """
    if is_whole and qty % 1 != 0:
        raise WholeUnitQuantity(
            f"{what}: {qty} is not a whole number, and this unit is counted in whole "
            "units only."
        )
