# pyright: reportAttributeAccessIssue=false, reportArgumentType=false, reportMissingImports=false
#
# Same directive and reason as apps/inventory/transfers.py: the checker resolves its
# config from its WORKING DIRECTORY and does not find this repo's pyrightconfig.json, so
# without django-stubs every `Model.objects`, every FK read and every `DecimalField` read
# as a `Decimal` is a false positive on valid Django. `manage.py test` is the authority.

"""Phase 3 B1 (decision 23) — the catalogue import PREVIEW: validate, write nothing.

The Flutter app reads the edited `.xlsx` and posts its rows here; this module answers
what the import WOULD do, so the clerk sees creates, changes, unchanged rows and every
row error before anything is written. Apply (B2) posts the same rows back with the
fingerprint and only then writes.

One sheet row is one SELLING UNIT, carrying its product and variant columns with it
(decision 23). The rules are not re-implemented here: a row whose ids exist is diffed
against the stored rows and the DIFFERENCE is handed to the existing
`ProductSerializer` / `ProductVariantSerializer` / `VariantUOMSerializer` with
`partial=True`, so barcode normalisation, GS1 check digits, code uniqueness, the
one-base-unit rule, the in-use freeze, thresholds >= 0 and the active-location rule fire
exactly as they do on the per-row endpoints. A row with blank ids is a create, grouped
with its siblings by product name (and by variant name inside that product).

What this module adds is only what a FILE knows and a row endpoint cannot see:

* a row's ids must exist and must belong to each other (a Unit ID under its Variant ID
  under its Product ID);
* exactly one row per variant carries `Units per base = 1`, and that row's unit code is a
  NEW variant's `base_uom`;
* the same barcode cannot appear on two rows of one file;
* rows of one product cannot disagree on Active, Category, Product name, Stored at or
  Brand (decision 23's ruling: Active is product-level, so it cannot vary by unit);
* more than 2,000 rows is refused as a whole request, not row by row.

Every message names the sheet column and what to type instead, in sentence case with no
em dashes, because it is read in a dialog next to the row it belongs to.

**Nothing here writes.** Serializer `is_valid()` is the only thing run, no `save()` is
called, and a test pins that against row counts, batch quantities and the audit trail.
"""

import hashlib
import json
from decimal import Decimal, InvalidOperation

from django.db import OperationalError, connection, transaction
from rest_framework.validators import UniqueTogetherValidator

from apps.users.models import AuditLog
from apps.users.services import audit_request

from .exceptions import (
    CatalogueImportBusy,
    CatalogueImportRefused,
    CatalogueImportRowsRefused,
    CatalogueImportTooLarge,
    CataloguePreviewStale,
    CatalogWriteRefused,
)
from .models import (
    Brand,
    Category,
    Product,
    ProductVariant,
    StorageLocation,
    UnitOfMeasure,
    VariantUOM,
    normalise_barcode,
)
from .serializers import (
    ProductSerializer,
    ProductVariantSerializer,
    VariantUOMSerializer,
)

# Decision 23: up to 2,000 rows per file.
MAX_ROWS = 2000

# The sheet's column order (decision 23's delegated default + the Brand ruling of
# 2026-11-12) and the row key the client sends for it. This mapping is the ONE place the
# wire names live, so the preview, the change list and the error list always point at the
# same header the clerk is looking at in Excel.
COLUMNS = {
    "product_id": "Product ID",
    "variant_id": "Variant ID",
    "unit_id": "Unit ID",
    "category": "Category",
    "product_name": "Product name",
    "variant": "Variant",
    "unit_code": "Unit code",
    "units_per_base": "Units per base",
    "price": "Price",
    "barcode": "Barcode",
    "low_stock_threshold": "Low-stock threshold",
    "stored_at": "Stored at",
    "active": "Active",
    "brand": "Brand",
}

# Serializer field -> the row key whose column reports it. A change or a field refusal is
# shown against the column the clerk can actually edit.
FIELD_KEYS = {
    "product": "variant_id",
    "category": "category",
    "brand": "brand",
    "base_name": "product_name",
    "description": "product_name",
    "image_url": "product_name",
    "stored_at": "stored_at",
    "is_active": "active",
    "variant_name": "variant",
    "base_uom": "unit_code",
    "min_stock_threshold": "low_stock_threshold",
    "max_stock_level": "low_stock_threshold",
    "variant": "unit_id",
    "uom": "unit_code",
    "conversion_factor": "units_per_base",
    "default_selling_price": "price",
    "barcode_qr": "barcode",
}

# The one product-level fact decision 23 rules cannot vary between the rows of a product.
DISAGREE_FIELDS = ("active", "category", "product_name", "stored_at", "brand")

# What an Active cell may say. Excel hands a boolean back as TRUE/FALSE and a clerk types
# Yes/No, so both spellings mean the same thing and anything else is refused.
ACTIVE_WORDS = {
    "yes": True,
    "no": False,
    "true": True,
    "false": False,
    "1": True,
    "0": False,
}

_COLUMN_ORDER = {label: index for index, label in enumerate(COLUMNS.values())}


# ---------------------------------------------------------------------------
# The preview
# ---------------------------------------------------------------------------


def preview_catalogue_import(rows):
    """Validate the sheet `rows` and describe what an apply would do. Writes nothing."""
    body, _ = _plan_catalogue_import(rows)
    return body


def _plan_catalogue_import(rows):
    """The preview BODY plus the WRITES behind it, as validated serializers.

    The plan is what makes preview and apply one rule set: `_preview_products` /
    `_preview_variants` / `_preview_units` hand the validated serializer to the caller, so
    the apply saves exactly the rows the clerk's dialog described - no second reading of
    the sheet, and no second copy of the rules.
    """
    rows = _checked_rows(rows)
    names = _Names()

    errors = []
    parsed = []
    for number, cells in enumerate(rows, start=1):
        if not isinstance(cells, dict):
            errors.append(
                {
                    "row": number,
                    "column": "Row",
                    "code": "INVALID_ROW",
                    "message": "This row is not a row of cells: export the catalogue "
                    "again and edit the file the export gave you.",
                }
            )
            continue
        row = _Row(number, cells)
        _read_cells(row)
        if not row.errors:
            _resolve_names(row, names)
        if row.errors:
            errors.extend(row.errors)
        else:
            parsed.append(row)

    rows_by_id = _rows_by_id(parsed)
    for row in parsed:
        _resolve_ids(row, rows_by_id)
        if not row.errors:
            _require_create_cells(row)
        errors.extend(row.errors)
    parsed = [row for row in parsed if not row.errors]

    product_groups = _group(parsed, "product_key")
    variant_groups = _group(parsed, "variant_key")
    for rows_of_product in product_groups.values():
        _check_rows_agree(rows_of_product)
    _check_thresholds_agree(variant_groups)
    base_unit_ok = {
        key: _check_base_unit(rows_of_variant)
        for key, rows_of_variant in variant_groups.items()
    }
    _check_barcodes(parsed)
    _check_unit_rows(parsed)

    creates = {"products": 0, "variants": 0, "units": 0}
    changes = []
    changed_rows = set()
    plan = []

    _preview_products(product_groups, creates, changes, changed_rows, plan)
    _preview_variants(
        variant_groups, base_unit_ok, creates, changes, changed_rows, plan
    )
    _preview_units(parsed, creates, changes, changed_rows, plan)

    changes.sort(key=lambda change: (change["row"], _COLUMN_ORDER[change["field"]]))
    errors.extend(error for row in parsed for error in row.errors)
    errors.sort(
        key=lambda error: (error["row"], _COLUMN_ORDER.get(error["column"], -1))
    )

    body = {
        "creates": creates,
        "changes": changes,
        "unchanged": sum(
            1 for row in parsed if not row.errors and row.number not in changed_rows
        ),
        "errors": errors,
        "fingerprint": _fingerprint(parsed, rows),
    }
    return body, plan


# ---------------------------------------------------------------------------
# The request and the row's cells
# ---------------------------------------------------------------------------


def _checked_rows(rows):
    """The row list, or a whole-request refusal. Never a partly-read file."""
    if not isinstance(rows, list):
        raise CatalogueImportRefused(
            "The import needs its sheet rows: send {rows: [...]} with one entry per "
            "selling unit."
        )
    if len(rows) > MAX_ROWS:
        raise CatalogueImportTooLarge(
            f"{len(rows):,} rows is more than the {MAX_ROWS:,} rows one import accepts: "
            "split the sheet into files of at most 2,000 rows and import them one at a "
            "time."
        )
    return rows


def _text(cells, field):
    """One cell as trimmed text. A blank, missing or `None` cell is the empty string."""
    value = cells.get(field)
    if value is None:
        return ""
    return str(value).strip()


class _Row:
    """One sheet row: the cells it carries and the records it resolved to."""

    def __init__(self, number, cells):
        self.number = number
        self.cells = cells
        self.errors = []
        self.product_id = None
        self.variant_id = None
        self.unit_id = None
        self.product = None
        self.variant = None
        self.unit = None
        self.category = None
        self.brand = None
        self.location = None
        self.uom = None
        self.units_per_base = None
        self.price = None
        self.threshold = None
        self.active = None
        self.barcode = ""

    def error(self, field, code, message):
        self.error_at(COLUMNS[field], code, message)

    def error_at(self, column, code, message):
        self.errors.append(
            {
                "row": self.number,
                "column": column,
                "code": code,
                "message": message,
            }
        )


def _read_cells(row):
    """The cell SHAPES: ids and numbers must parse, Active must say yes or no."""
    row.product_id = _id_cell(row, "product_id")
    row.variant_id = _id_cell(row, "variant_id")
    row.unit_id = _id_cell(row, "unit_id")
    row.units_per_base = _decimal_cell(row, "units_per_base")
    row.price = _decimal_cell(row, "price")
    row.threshold = _decimal_cell(row, "low_stock_threshold")
    row.barcode = _text(row.cells, "barcode")

    active = _text(row.cells, "active")
    if active:
        row.active = ACTIVE_WORDS.get(active.casefold())
        if row.active is None:
            row.error(
                "active",
                "INVALID_BOOLEAN",
                f'Active "{active}" is not Yes or No: type Yes to sell this product or '
                "No to archive it.",
            )


def _id_cell(row, field):
    text = _text(row.cells, field)
    if not text:
        return None
    try:
        return int(text)
    except ValueError:
        row.error(
            field,
            "INVALID_NUMBER",
            f'{COLUMNS[field]} "{text}" is not a whole number: type the id the export '
            "wrote for this record, or leave the cell blank to create a new one.",
        )
        return None


def _decimal_cell(row, field):
    text = _text(row.cells, field)
    if not text:
        return None
    try:
        return Decimal(text)
    except InvalidOperation:
        row.error(
            field,
            "INVALID_NUMBER",
            f'{COLUMNS[field]} "{text}" is not a number: type a number, for example 12 '
            "or 12.50.",
        )
        return None


class _Names:
    """The Lists sheet's values, matched case-insensitively, one query each."""

    def __init__(self):
        self.categories = {row.name.casefold(): row for row in Category.objects.all()}
        self.brands = {row.name.casefold(): row for row in Brand.objects.all()}
        self.locations = {
            row.name.casefold(): row for row in StorageLocation.objects.all()
        }
        self.units = {row.code.casefold(): row for row in UnitOfMeasure.objects.all()}


def _example(mapping, attribute):
    """`, for example "Cement"` — what the clerk can type instead, when there is one."""
    names = sorted(getattr(row, attribute) for row in mapping.values())
    return f', for example "{names[0]}"' if names else ""


def _resolve_names(row, names):
    """Category, Brand, Stored at and Unit code exist; a typo is a row error, not a create."""
    text = _text(row.cells, "category")
    if text:
        row.category = names.categories.get(text.casefold())
        if row.category is None:
            row.error(
                "category",
                "UNKNOWN_CATEGORY",
                f'Category "{text}" is not on the list: type a category from the Lists '
                f"sheet{_example(names.categories, 'name')}.",
            )

    text = _text(row.cells, "brand")
    if text:
        row.brand = names.brands.get(text.casefold())
        if row.brand is None:
            row.error(
                "brand",
                "UNKNOWN_BRAND",
                f'Brand "{text}" is not on the list: type a brand from the Lists '
                f"sheet{_example(names.brands, 'name')}.",
            )

    text = _text(row.cells, "stored_at")
    if text:
        row.location = names.locations.get(text.casefold())
        if row.location is None:
            row.error(
                "stored_at",
                "UNKNOWN_STORED_AT",
                f'Stored at "{text}" is not on the list: type a storage location from '
                f"the Lists sheet{_example(names.locations, 'name')}.",
            )

    text = _text(row.cells, "unit_code")
    if text:
        row.uom = names.units.get(text.casefold())
        if row.uom is None:
            row.error(
                "unit_code",
                "UNKNOWN_UNIT_CODE",
                f'Unit code "{text}" is not on the list: type a unit code from the Lists '
                f"sheet{_example(names.units, 'code')}.",
            )


def _rows_by_id(parsed):
    """The rows the file references, in three queries rather than three per row."""
    return {
        "products": Product.objects.select_related(
            "category", "brand", "stored_at"
        ).in_bulk([row.product_id for row in parsed if row.product_id is not None]),
        "variants": ProductVariant.objects.select_related("product").in_bulk(
            [row.variant_id for row in parsed if row.variant_id is not None]
        ),
        "units": VariantUOM.objects.select_related("variant__product", "uom").in_bulk(
            [row.unit_id for row in parsed if row.unit_id is not None]
        ),
    }


def _resolve_ids(row, rows_by_id):
    """The ids exist and belong to each other. A blank id means "create"."""
    if row.product_id is not None:
        row.product = rows_by_id["products"].get(row.product_id)
        if row.product is None:
            row.error(
                "product_id",
                "UNKNOWN_PRODUCT",
                f"Product ID {row.product_id} is not in the catalogue: type the id the "
                "export wrote, or leave Product ID blank to create a new product.",
            )

    if row.variant_id is not None:
        row.variant = rows_by_id["variants"].get(row.variant_id)
        if row.variant is None:
            row.error(
                "variant_id",
                "UNKNOWN_VARIANT",
                f"Variant ID {row.variant_id} is not in the catalogue: type the id the "
                "export wrote, or leave Variant ID blank to create a new variant.",
            )
        elif row.product is not None and row.variant.product_id != row.product.pk:
            row.error(
                "variant_id",
                "VARIANT_NOT_IN_PRODUCT",
                f'Variant ID {row.variant_id} belongs to "{row.variant.product.base_name}"'
                f', not to "{row.product.base_name}": type the Variant ID of this '
                "product's variant, or leave it blank to create a new one.",
            )

    if row.unit_id is not None:
        row.unit = rows_by_id["units"].get(row.unit_id)
        if row.unit is None:
            row.error(
                "unit_id",
                "UNKNOWN_UNIT",
                f"Unit ID {row.unit_id} is not in the catalogue: type the id the export "
                "wrote, or leave Unit ID blank to create a new selling unit.",
            )

    # A row may name only its unit, or only its variant: the parents are then the ones
    # the record already hangs off. Nothing is guessed beyond that one step.
    if row.variant is None and row.unit is not None:
        row.variant = row.unit.variant
    if row.product is None and row.variant is not None:
        row.product = row.variant.product

    if (
        row.unit is not None
        and row.variant is not None
        and row.unit.variant_id != row.variant.pk
    ):
        row.error(
            "unit_id",
            "UNIT_NOT_IN_VARIANT",
            f'Unit ID {row.unit_id} is a selling unit of "{_variant_label(row.unit.variant)}", '
            f'not of "{_variant_label(row.variant)}": type the Unit ID that belongs to this '
            "variant, or leave it blank to create a new selling unit.",
        )


def _variant_label(variant):
    """A variant named from its fields: `str()` joins product and name with an em dash.

    Error copy is read in a dialog next to the cell it is about, and this project's copy
    has no em dashes in it, so this module never interpolates a model's `__str__`.
    """
    return f"{variant.product.base_name} - {variant.variant_name}"


def _require_create_cells(row):
    """A create needs the columns nobody else can fill in for it."""
    if row.product is None:
        _require(row, "category", "the category the new product belongs to")
        _require(row, "product_name", "the name of the new product")
        _require(row, "brand", "the brand of the new product")
    if row.variant is None:
        _require(row, "variant", 'the name of the new variant, for example "40kg"')
    if row.unit is None:
        _require(
            row, "unit_code", "the unit code of the new selling unit, for example BAG"
        )
        _require(
            row,
            "units_per_base",
            "1 when this unit is the base unit, or how many base units it holds",
        )
        _require(row, "price", "the selling price of the new selling unit")


def _require(row, field, sentence):
    if not _text(row.cells, field):
        row.error(
            field, "MISSING_VALUE", f"{COLUMNS[field]} is blank: type {sentence}."
        )


# ---------------------------------------------------------------------------
# What the file knows and a single row cannot see
# ---------------------------------------------------------------------------


def _group(parsed, attribute):
    """Rows grouped by the record they belong to, in first-appearance order."""
    groups = {}
    for row in parsed:
        setattr(row, attribute, _group_key(row, attribute))
        groups.setdefault(getattr(row, attribute), []).append(row)
    return groups


def _group_key(row, attribute):
    if attribute == "product_key":
        if row.product is not None:
            return ("pk", row.product.pk)
        return ("name", _text(row.cells, "product_name").casefold())
    if row.variant is not None:
        return ("pk", row.variant.pk)
    return (row.product_key, _text(row.cells, "variant").casefold())


def _effective(row, field):
    """The value a field WOULD have after the import: the cell, else the stored value."""
    if field == "category":
        if row.category is not None:
            return row.category.pk
        return row.product.category_id if row.product is not None else None
    if field == "brand":
        if row.brand is not None:
            return row.brand.pk
        return row.product.brand_id if row.product is not None else None
    if field == "stored_at":
        if row.location is not None:
            return row.location.pk
        return row.product.stored_at_id if row.product is not None else None
    if field == "active":
        if row.active is not None:
            return row.active
        return row.product.is_active if row.product is not None else None
    text = _text(row.cells, "product_name")
    if text:
        return text.casefold()
    return row.product.base_name.casefold() if row.product is not None else ""


def _shown(row, field):
    """The same value as the clerk sees it, for an error sentence."""
    if field == "category":
        return row.category.name if row.category is not None else ""
    if field == "brand":
        return row.brand.name if row.brand is not None else ""
    if field == "stored_at":
        return row.location.name if row.location is not None else ""
    if field == "active":
        return "" if row.active is None else ("Yes" if row.active else "No")
    if _text(row.cells, "product_name"):
        return _text(row.cells, "product_name")
    return row.product.base_name if row.product is not None else ""


def _check_rows_agree(rows_of_product):
    """Decision 23: a product has one Active, Category, name, Stored at and Brand.

    Those five are product-level facts repeated on every row of that product, so a file
    where two rows disagree has no answer - the import refuses both readings and names
    the row that differs.
    """
    first = rows_of_product[0]
    for row in rows_of_product[1:]:
        for field in DISAGREE_FIELDS:
            if _effective(row, field) == _effective(first, field):
                continue
            row.error(
                field,
                "PRODUCT_ROWS_DISAGREE",
                f'{COLUMNS[field]} "{_shown(row, field)}" disagrees with row '
                f'{first.number} ("{_shown(first, field)}"): one product has one '
                f"{COLUMNS[field].lower()} on every row, so type the same value as row "
                f"{first.number}.",
            )


def _factor(row):
    """How many base units this row's unit holds, as it would be after the import."""
    if row.units_per_base is not None:
        return row.units_per_base
    return row.unit.conversion_factor if row.unit is not None else None


def _check_thresholds_agree(variant_groups):
    """One Low-stock threshold per variant, like the product columns above (B2 fix).

    The threshold is a VARIANT column that every row of that variant repeats (decision
    23's sheet), so two rows of one variant disagreeing about it is the same ambiguity as
    two rows disagreeing about the product name - and it used to be silent: only the first
    row's value was read, so the clerk's later edit vanished. Blank keeps the stored value,
    which is why a blank row and a row naming the stored value agree.
    """
    for rows_of_variant in variant_groups.values():
        first = rows_of_variant[0]
        for row in rows_of_variant[1:]:
            if _threshold(row) == _threshold(first):
                continue
            row.error(
                "low_stock_threshold",
                "VARIANT_ROWS_DISAGREE",
                f'Low-stock threshold "{_shown_threshold(row)}" disagrees with row '
                f'{first.number} ("{_shown_threshold(first)}"): one variant has one '
                f"low-stock threshold on every row, so type the same value as row "
                f"{first.number}.",
            )


def _threshold(row):
    """The Low-stock threshold as it would be after the import: the cell, else stored."""
    if row.threshold is not None:
        return row.threshold
    if row.variant is not None:
        return row.variant.min_stock_threshold
    return Decimal(0)  # a new variant's column default


def _shown_threshold(row):
    return f"{_threshold(row):.2f}"


def _check_base_unit(rows_of_variant):
    """Exactly one row per variant is the base unit. Returns False when it is not."""
    base_rows = [row for row in rows_of_variant if _factor(row) == 1]
    if not base_rows:
        first = rows_of_variant[0]
        counted_in = (
            f", for example the {first.variant.base_uom.code} row"
            if first.variant is not None
            else ""
        )
        first.error(
            "units_per_base",
            "BASE_UNIT_ROW_MISSING",
            f'No row has Units per base 1 for "{_variant_name(first)}": exactly one row '
            "is the base unit, the one its stock is counted in"
            f"{counted_in}. Type 1 in Units per base on that row.",
        )
        return False
    for extra in base_rows[1:]:
        extra.error(
            "units_per_base",
            "BASE_UNIT_ROW_DUPLICATE",
            f"Units per base 1 is also on row {base_rows[0].number}: a variant has "
            "exactly one base unit, so type how many base units this unit holds, for "
            "example 50.",
        )
    return len(base_rows) == 1


def _variant_name(row):
    if row.variant is not None:
        return row.variant.variant_name
    return _text(row.cells, "variant")


def _check_barcodes(parsed):
    """One code, one selling unit - inside the file, not only inside the database."""
    holders = {}
    for row in parsed:
        code = normalise_barcode(row.barcode)
        if not code:
            continue
        holder = holders.get(code)
        if holder is None:
            holders[code] = row
            continue
        row.error(
            "barcode",
            "DUPLICATE_BARCODE_IN_FILE",
            f"Barcode {code} is also on row {holder.number}: one code belongs to one "
            "selling unit, so type a different barcode here or leave the cell blank to "
            "have the server issue one.",
        )


def _check_unit_rows(parsed):
    """One row per (variant, unit code) - the pair the database only polices after apply.

    `uniq_variantuom_barcode` and the model's `(variant, uom)` constraint are the real
    guards, but neither can see a file that creates a variant AND two of its selling units
    at once: the variant has no pk yet. That is also why the unit serializer's
    unique-together validator cannot run for such a row, so this check stands in for it.
    """
    holders = {}
    for row in parsed:
        if row.uom is None:
            continue
        key = (row.variant_key, row.uom.pk)
        holder = holders.get(key)
        if holder is None:
            holders[key] = row
            continue
        row.error(
            "unit_code",
            "DUPLICATE_UNIT_IN_FILE",
            f"Unit code {row.uom.code} is also on row {holder.number} for this variant: a "
            "variant has one selling unit per unit code, so type a different unit code or "
            "remove the extra row.",
        )


# ---------------------------------------------------------------------------
# The existing serializers, run over the difference
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# The existing serializers, run over the difference
# ---------------------------------------------------------------------------


def _write_op(kind, key, row_number, instance, serializer):
    """One record an apply will write, with the serializer that already passed.

    `key` is the row group it belongs to, so a create can find the parent this same file
    created above it (a new variant's product, a new unit's variant).
    """
    return {
        "kind": kind,
        "key": key,
        "row": row_number,
        "instance": instance,
        "serializer": serializer,
    }


def _preview_products(product_groups, creates, changes, changed_rows, plan):
    """Product-level columns, once per product (they repeat on its every row)."""
    for key, rows_of_product in product_groups.items():
        if any(row.errors for row in rows_of_product):
            continue
        first = rows_of_product[0]
        if first.product is None:
            data = {
                "category": first.category.pk,
                "brand": first.brand.pk,
                "base_name": _text(first.cells, "product_name"),
            }
            if first.location is not None:
                data["stored_at"] = first.location.pk
            if first.active is not None:
                data["is_active"] = first.active
            serializer = _run(ProductSerializer, None, data, first)
            if serializer is not None:
                creates["products"] += 1
                changed_rows.update(row.number for row in rows_of_product)
                plan.append(_write_op("product", key, first.number, None, serializer))
            continue
        data = _product_payload(first, first.product)
        serializer = _run(ProductSerializer, first.product, data, first)
        if serializer is not None:
            validated = serializer.validated_data
            changes.extend(_changes(first.number, first.product, validated))
            changed_rows.update(row.number for row in rows_of_product)
            plan.append(
                _write_op("product", key, first.number, first.product, serializer)
            )


def _product_payload(row, product):
    """Only the columns that differ: an unchanged cell must not re-state what is stored.

    That is what keeps a product already labelled with a since-deactivated location an
    unchanged row instead of a refused one (decision 18's asymmetry: the label stays
    where the goods are; only a NEW assignment of an inactive place is refused).
    """
    data = {}
    if row.category is not None and row.category.pk != product.category_id:
        data["category"] = row.category.pk
    if row.brand is not None and row.brand.pk != product.brand_id:
        data["brand"] = row.brand.pk
    if row.location is not None and row.location.pk != product.stored_at_id:
        data["stored_at"] = row.location.pk
    name = _text(row.cells, "product_name")
    if name and name != product.base_name:
        data["base_name"] = name
    if row.active is not None and row.active != product.is_active:
        data["is_active"] = row.active
    return data


def _preview_variants(
    variant_groups, base_unit_ok, creates, changes, changed_rows, plan
):
    """Variant name and low-stock threshold, once per variant."""
    for key, rows_of_variant in variant_groups.items():
        if not base_unit_ok[key] or any(row.errors for row in rows_of_variant):
            continue
        first = rows_of_variant[0]
        if first.variant is None:
            data = {"variant_name": _text(first.cells, "variant")}
            if first.product is not None:
                data["product"] = first.product.pk
            base_row = next(row for row in rows_of_variant if _factor(row) == 1)
            if base_row.uom is not None:
                data["base_uom"] = base_row.uom.pk
            if first.threshold is not None:
                data["min_stock_threshold"] = first.threshold
            serializer = _run(ProductVariantSerializer, None, data, first)
            if serializer is not None:
                creates["variants"] += 1
                changed_rows.update(row.number for row in rows_of_variant)
                op = _write_op("variant", key, first.number, None, serializer)
                op["parent_key"] = first.product_key
                plan.append(op)
            continue
        data = {}
        name = _text(first.cells, "variant")
        if name and name != first.variant.variant_name:
            data["variant_name"] = name
        if (
            first.threshold is not None
            and first.threshold != first.variant.min_stock_threshold
        ):
            data["min_stock_threshold"] = first.threshold
        serializer = _run(ProductVariantSerializer, first.variant, data, first)
        if serializer is not None:
            changes.extend(
                _changes(first.number, first.variant, serializer.validated_data)
            )
            changed_rows.update(row.number for row in rows_of_variant)
            plan.append(
                _write_op("variant", key, first.number, first.variant, serializer)
            )


def _preview_units(parsed, creates, changes, changed_rows, plan):
    """One selling unit per row: the price, the barcode, the unit and its factor."""
    for row in parsed:
        if row.errors:
            continue
        if row.unit is None:
            data = {
                "uom": row.uom.pk,
                "conversion_factor": row.units_per_base,
                "default_selling_price": row.price,
                "barcode_qr": row.barcode,
            }
            if row.variant is not None:
                data["variant"] = row.variant.pk
            serializer = _run(VariantUOMSerializer, None, data, row)
            if serializer is not None:
                creates["units"] += 1
                changed_rows.add(row.number)
                op = _write_op("unit", row.variant_key, row.number, None, serializer)
                op["parent_key"] = row.variant_key
                plan.append(op)
            continue
        data = _unit_payload(row, row.unit)
        serializer = _run(VariantUOMSerializer, row.unit, data, row)
        if serializer is not None:
            changes.extend(_changes(row.number, row.unit, serializer.validated_data))
            changed_rows.add(row.number)
            plan.append(
                _write_op("unit", row.variant_key, row.number, row.unit, serializer)
            )


def _unit_payload(row, unit):
    data = {}
    if row.uom is not None and row.uom.pk != unit.uom_id:
        data["uom"] = row.uom.pk
    if row.units_per_base is not None and row.units_per_base != unit.conversion_factor:
        data["conversion_factor"] = row.units_per_base
    if row.price is not None and row.price != unit.default_selling_price:
        data["default_selling_price"] = row.price
    if normalise_barcode(row.barcode) != unit.barcode_qr:
        # A blank cell is a real value here: it means "issue this unit its own code"
        # (decision 16), so a cleared barcode in Excel is not "leave it alone".
        data["barcode_qr"] = row.barcode
    return data


def _run(serializer_class, instance, data, row):
    """Run one existing serializer over the difference. `None` means "nothing/refused".

    `partial=True` in both directions: the sheet's required cells were checked above
    (`MISSING_VALUE`), and a create whose parent is being created in the same file has no
    saved instance to hand an `PrimaryKeyRelatedField`. Every rule that is not about a
    missing field still runs, because the serializer is the one that owns it.

    Returns the VALIDATED SERIALIZER, not its data: the apply saves that same object, so
    the rows written are the rows this one validation passed, not a second run of the
    rules over the same cells.
    """
    if not data:
        return None
    serializer = serializer_class(instance, data=data, partial=True)
    _drop_unfillable_unique_together(serializer, data)
    try:
        valid = serializer.is_valid()
    except CatalogWriteRefused as refusal:
        row.error_at(
            _refusal_column(serializer_class, refusal.code, data),
            refusal.code,
            _clean(str(refusal)),
        )
        return None
    if not valid:
        for name, messages in serializer.errors.items():
            key = FIELD_KEYS.get(name)
            if key is None:
                row.error_at(
                    "Row", "FIELD_INVALID", _clean(" ".join(str(m) for m in messages))
                )
                continue
            row.error(key, "FIELD_INVALID", _clean(f"{COLUMNS[key]}: {messages[0]}"))
        return None
    return serializer


def _clean(text):
    """One import-surfaced sentence with no em dash in it.

    `SELLING_UNIT_IN_USE` and `DUPLICATE_BASE_UNIT` are shared with the per-row
    endpoints, whose wording is pinned by their own tests, and they interpolate
    `str(variant)` / `str(record)` - which joins with an em dash. Rewriting the serializers
    would change what a PATCH answers, so the import normalises instead: it is the only
    caller that reads these sentences in a dialog. `UNIT_NOT_IN_VARIANT` is built from
    fields rather than from `str()`, because this module owns that sentence outright.
    """
    return text.replace("\u2014", "-")


def _drop_unfillable_unique_together(serializer, data):
    """Let a create run when a field of its unique-together pair is created by this file.

    DRF's `UniqueTogetherValidator` runs on a create even with `partial=True`, so a new
    selling unit of a NEW variant is refused with "variant: This field is required" -
    a pk that cannot exist yet. The pair itself is still policed: against the database by
    the model constraint, and inside the file by `DUPLICATE_UNIT_IN_FILE`.
    """
    if serializer.instance is not None:
        return
    serializer.validators = [
        validator
        for validator in serializer.validators
        if not isinstance(validator, UniqueTogetherValidator)
        or set(validator.fields) <= set(data)
    ]


def _refusal_column(serializer_class, code, data):
    """Which column the refusal is about, so the clerk knows what to fix in Excel."""
    if serializer_class is VariantUOMSerializer:
        if code.startswith("BARCODE_"):
            return COLUMNS["barcode"]
        if code == "INVALID_SELLING_UNIT":
            price = data.get("default_selling_price")
            return (
                COLUMNS["price"]
                if price is not None and price < 0
                else COLUMNS["units_per_base"]
            )
        if code == "SELLING_UNIT_IN_USE" and "conversion_factor" not in data:
            return COLUMNS["unit_code"]
        return COLUMNS["units_per_base"]
    if serializer_class is ProductSerializer:
        return COLUMNS["stored_at"]
    return COLUMNS["low_stock_threshold"]


def _changes(row_number, instance, validated):
    """What the serializer would write, as the sheet's own columns."""
    changes = []
    for name, value in validated.items():
        key = FIELD_KEYS.get(name)
        if key is None:
            continue
        before = getattr(instance, name)
        if _same(before, value):
            continue
        changes.append(
            {
                "row": row_number,
                "field": COLUMNS[key],
                "before": _shown_value(name, before),
                "after": _shown_value(name, value),
            }
        )
    return changes


def _same(before, after):
    if isinstance(before, Decimal) and isinstance(after, Decimal):
        return before == after
    return getattr(before, "pk", before) == getattr(after, "pk", after)


def _shown_value(field, value):
    if field in ("category", "brand", "stored_at"):
        return getattr(value, "name", str(value))
    if field == "uom":
        return getattr(value, "code", str(value))
    if isinstance(value, bool):
        return "Yes" if value else "No"
    if isinstance(value, Decimal):
        return f"{value:.2f}"
    return str(value)


# ---------------------------------------------------------------------------
# The fingerprint
# ---------------------------------------------------------------------------


def _fingerprint(parsed, rows):
    """A hash of the referenced rows' `(model, pk, updated_at)` plus the payload.

    Apply recomputes it under its locks: if any row the preview read has moved since, or
    the clerk's rows are not the ones the preview saw, the hash differs and the apply is
    refused with "run the preview again" instead of writing against a catalogue that
    changed underneath it.

    The RAW row list is hashed position by position, so the hash also pins the file's
    length and what sat in each position - a malformed row (`"not a row"`) contributes its
    text instead of vanishing, which is what used to let two different malformed bodies
    share one fingerprint.
    """
    referenced = sorted(
        {
            (obj._meta.label, obj.pk, obj.updated_at.isoformat())
            for row in parsed
            for obj in (
                row.product,
                row.variant,
                row.unit,
                row.category,
                row.brand,
                row.location,
                row.uom,
            )
            if obj is not None
        }
    )
    payload = [
        {field: _text(cells, field) for field in COLUMNS}
        if isinstance(cells, dict)
        else {"__not_a_row__": str(cells)}
        for cells in rows
    ]
    document = json.dumps(
        {
            "rows": payload,
            "row_count": len(rows),
            "referenced": referenced,
            # HOW MANY catalogue rows exist is part of what the preview saw. A file of
            # CREATES touches no referenced row (nothing to move), so without this a
            # second Apply of the same fingerprint would quietly make the product twice;
            # with it, the catalogue that grew answers 409 and the clerk re-previews.
            "catalogue": [
                Product.objects.count(),
                ProductVariant.objects.count(),
                VariantUOM.objects.count(),
            ],
        },
        sort_keys=True,
        default=str,
    )
    return hashlib.sha256(document.encode()).hexdigest()


# ---------------------------------------------------------------------------
# The apply
# ---------------------------------------------------------------------------

# The three things an apply writes, as the names the response and the audit row use.
KINDS = {
    "product": ("Product", "products"),
    "variant": ("Variant", "variants"),
    "unit": ("Selling unit", "units"),
}


# Postgres only: `SET LOCAL lock_timeout` is transaction-scoped, so it lapses with the
# apply's own block and cannot leak into the next request on a pooled connection.
LOCK_TIMEOUT = "5s"


def _set_lock_timeout():
    """Cap how long the apply will WAIT for a row lock (Postgres only, best effort).

    If another writer holds a required row, the apply gives up after five seconds,
    rolls back, and returns a retryable 503. This bounds the import's lock wait only;
    tills may still wait while an executing import holds its locks.

    Best effort on purpose: a backend without `lock_timeout` (sqlite) simply keeps the
    default behaviour rather than failing the apply.
    """
    if connection.vendor != "postgresql":
        return
    with connection.cursor() as cursor:
        # `SET LOCAL` takes no bind parameters, and the value is a module constant, so
        # nothing from the request reaches this statement.
        cursor.execute(f"SET LOCAL lock_timeout = '{LOCK_TIMEOUT}'")


def _is_lock_timeout(exc):
    """True when `exc` is Postgres giving up on a LOCK WAIT (SQLSTATE 55P03).

    Matched on the SQLSTATE code, never on the English text (localisation, and psycopg's
    wording is not a contract). `psycopg2` reports the code on the wrapped error, which
    Django re-raises as `OperationalError` with the original kept in `__cause__`.
    """
    for candidate in (exc, getattr(exc, "__cause__", None)):
        if getattr(candidate, "pgcode", None) == "55P03":
            return True
    return False


def apply_catalogue_import(*, rows, fingerprint, request):
    """Write the sheet, or refuse it whole: ONE transaction, nothing half-applied.

    The same rows the preview answered are posted back with its `fingerprint`. Inside one
    `atomic` block the referenced catalogue rows are locked (selling units, then variants,
    then products, each in PK order), the SAME validation runs again against those locked
    rows, and the fingerprint is recomputed. Any row error - here, not only in the preview
    - refuses the file with the error list and writes nothing; a fingerprint that no longer
    matches means the catalogue moved, and the answer is 409 "Run the preview again".

    Every created or changed record gets one `CREATE`/`UPDATE` audit row, plus ONE summary
    row under the new `CATALOGUE_IMPORT` action. A sheet with nothing to do writes nothing
    at all, not even the summary: pressing Apply on an unchanged file leaves no trace to
    read as "something happened".

    `IntegrityError` is deliberately NOT caught here: it must be handled outside this
    `atomic` block (see `views.catalogue_import_apply_view`), so the savepoint is rolled
    back before the race is explained and no half-write survives.
    """
    rows = _checked_rows(rows)  # 400 before the transaction: nothing to undo
    if not isinstance(fingerprint, str) or not fingerprint.strip():
        raise CatalogueImportRefused(
            "The apply needs the fingerprint the preview returned: send {rows, "
            "fingerprint} and nothing is written without it."
        )
    try:
        with transaction.atomic():  # pyright: ignore[reportGeneralTypeIssues]
            _set_lock_timeout()
            _lock_referenced(rows)
            body, plan = _plan_catalogue_import(rows)
            # Row errors first, the fingerprint second: a file the clerk still has to fix
            # is not "stale", and telling them to re-preview would hide the cells to
            # correct.
            if body["errors"]:
                raise CatalogueImportRowsRefused(body["errors"])
            if fingerprint.strip() != body["fingerprint"]:
                raise CataloguePreviewStale()
            applied = _write_plan(plan, request)
            summary = _summary_text(applied, body["unchanged"])
            if any(applied["creates"].values()) or any(applied["updates"].values()):
                audit_request(request, AuditLog.ActionType.CATALOGUE_IMPORT, summary)
    except OperationalError as exc:
        # A lock wait that ran out (55P03, `lock_timeout`) is the catalogue being busy,
        # not this request being wrong. Caught OUTSIDE the block so the whole apply is
        # rolled back - the clerk's retry starts from a clean sheet, never a half one.
        if not _is_lock_timeout(exc):
            raise
        raise CatalogueImportBusy() from exc
    return {
        "creates": applied["creates"],
        "updates": applied["updates"],
        "unchanged": body["unchanged"],
        "summary": summary,
    }


def _referenced_ids(rows):
    """The product/variant/unit ids the cells NAME, tolerant of junk.

    Only for choosing what to lock, so a cell that is not a whole number is simply not an
    id: the row's own validation reports the typo, and nothing here has to be kind about
    it. Returns three sets, because the lock order below is per model.
    """
    products, variants, units = set(), set(), set()
    for cells in rows:
        if not isinstance(cells, dict):
            continue
        for field, bucket in (
            ("product_id", products),
            ("variant_id", variants),
            ("unit_id", units),
        ):
            text = _text(cells, field)
            if text.isdigit():
                bucket.add(int(text))
    return products, variants, units


def _lock_referenced(rows):
    """Lock every catalogue row the sheet can reach, in the Phase 9 order.

    A row may name only its selling unit, and that row still carries product and variant
    columns, so the variant and product above a named unit are locked too. The order -
    the SELLING UNIT first, then the variant, then the product, each ascending by PK - is
    Phase 9's documented writer order (`transfers.record_stock_transfer` step (0) locks
    the selling units, step (c) reaches the variant through `_check_low_stock`), so an
    import and a sale/receipt/adjustment/transfer queue instead of deadlocking. The
    parent ids are read UNLOCKED first, so the three statements below are pure locks, all
    in one order.
    """
    products, variants, units = _referenced_ids(rows)
    for variant_id, product_id in VariantUOM.objects.filter(pk__in=units).values_list(
        "variant_id", "variant__product_id"
    ):
        variants.add(variant_id)
        products.add(product_id)
    for product_id in ProductVariant.objects.filter(pk__in=variants).values_list(
        "product_id", flat=True
    ):
        products.add(product_id)
    for model, ids in (
        (VariantUOM, units),
        (ProductVariant, variants),
        (Product, products),
    ):
        if ids:
            # `list()` is the point: the rows are locked when the query RUNS, so it must
            # run here and not when something later iterates the queryset.
            list(
                model.objects.select_for_update()
                .filter(pk__in=sorted(ids))
                .order_by("pk")
            )


def _write_plan(plan, request):
    """Save the validated rows in dependency order, auditing each record it touches.

    Products come first, then variants, then selling units - the order the plan was built
    in - so a variant created by this file can find the product created above it, and a
    unit can find its variant. `serializer.save(...)` writes the SAME serializer that
    passed validation: the rows written are the rows the dialog described.
    """
    created = {"product": {}, "variant": {}}
    applied = {
        "creates": {"products": 0, "variants": 0, "units": 0},
        "updates": {"products": 0, "variants": 0, "units": 0},
    }
    for op in plan:
        kind = op["kind"]
        label, plural = KINDS[kind]
        serializer = op["serializer"]
        if op["instance"] is None:
            instance = serializer.save(**_parent_link(op, created))
            if kind != "unit":
                # Only a product and a variant can be a PARENT of another row this same
                # file creates; a selling unit is a leaf, so it is not remembered here.
                created[kind][op["key"]] = instance
            applied["creates"][plural] += 1
            audit_request(
                request,
                AuditLog.ActionType.CREATE,
                f"{label} {_audit_detail(kind, instance)} created.",
            )
            continue
        # Snapshot BEFORE save(): `serializer.instance` is the row as it was, which is the
        # half of the change worth auditing (the same order the per-row endpoint uses).
        snapshot = _audit_snapshot(kind, op["instance"])
        instance = serializer.save()
        applied["updates"][plural] += 1
        changes = _audit_changes(kind, snapshot, instance)
        description = f"{label} {_audit_detail(kind, instance)} updated"
        if changes:
            description = f"{description}: {changes}"
        audit_request(request, AuditLog.ActionType.UPDATE, f"{description}.")
    return applied


def _parent_link(op, created):
    """The parent this file just created, for a create that could not name it.

    A new variant's `product` and a new unit's `variant` have no pk while the preview
    runs, so the payload omits them; by the time the row is saved the parent exists, and
    DRF's `save(**kwargs)` puts it into `validated_data`.
    """
    if op["kind"] == "product":
        return {}
    field = "variant" if op["kind"] == "unit" else "product"
    parent = created[field].get(op["parent_key"])
    return {} if parent is None else {field: parent}


def _audit_detail(kind, instance):
    """How the audit trail names the record, in the wording the per-row endpoints use."""
    if kind == "product":
        return f"{instance.base_name} (active={instance.is_active})"
    return str(instance)


def _audit_snapshot(kind, instance):
    if kind == "unit":
        return {
            "default_selling_price": instance.default_selling_price,
            "barcode_qr": instance.barcode_qr,
        }
    return {}


def _audit_changes(kind, snapshot, instance):
    """What changed on the record, in the per-row endpoint's own sentence.

    A selling unit reuses `VariantUOMViewSet.audit_changes` verbatim (imported inside the
    function: `views` imports this module), so a price reads "price 10.00 -> 12.50" and a
    code reads "barcode 'OLD' -> 'NEW'" whether it was typed into a form or applied from
    Excel. A product or a variant records none, exactly as their viewsets do.
    """
    if kind != "unit":
        return ""
    from .views import selling_unit_changes

    return selling_unit_changes(snapshot, instance)


def _summary_text(applied, unchanged):
    """ONE sentence for the summary audit row and the response: what this import did."""
    parts = []
    for verb, counts in (
        ("created", applied["creates"]),
        ("updated", applied["updates"]),
    ):
        listed = _listed(counts)
        if listed:
            parts.append(f"{listed} {verb}")
    if not parts:
        return (
            f"Catalogue import applied: nothing to change, {unchanged} rows unchanged."
        )
    return f"Catalogue import applied: {'; '.join(parts)}; {unchanged} rows unchanged."


def _listed(counts):
    """`2 products, 1 variant and 3 selling units` - the nonzero counts, sheet order."""
    names = {
        "products": ("product", "products"),
        "variants": ("variant", "variants"),
        "units": ("selling unit", "selling units"),
    }
    parts = [
        f"{count} {names[key][0 if count == 1 else 1]}"
        for key, count in counts.items()
        if count
    ]
    if not parts:
        return ""
    if len(parts) == 1:
        return parts[0]
    return ", ".join(parts[:-1]) + f" and {parts[-1]}"
