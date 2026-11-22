// Phase 3 Task F1: what sheet 1 of the catalogue workbook contains.
//
// The workbook is the editing surface for the whole catalogue and the import
// (F2, then the server's preview/apply) reads it back BY HEADER NAME, so this file
// is the contract: the headings, their order, and which column is a number and
// which is text. Decision 23 fixes the columns; the owner ruling of 2026-11-12
// adds Brand.
//
// One row per SELLING UNIT, because the unit owns the price and the barcode. The
// product-level facts (category, brand, name, stored at, active) repeat on each of
// that product's rows: that is what lets a storekeeper add a unit by copying a row
// and changing the unit columns only.
//
// Nothing here reaches the server and nothing here reads stock: the export is a
// snapshot of the catalogue, and importing never touches a count.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';

/// The headings of sheet 1, in decision 23's column order with Brand after
/// Category (both are matched by NAME on import).
const catalogueSheetHeaders = <String>[
  'Product ID',
  'Variant ID',
  'Unit ID',
  'Category',
  'Brand',
  'Product name',
  'Variant',
  'Unit code',
  'Units per base',
  'Price',
  'Barcode',
  'Low-stock threshold',
  'Stored at',
  'Active',
];

/// One selling unit as a spreadsheet row.
///
/// Raw values, no formatting: the writer decides what is a text cell and what is a
/// number, and the escape for formula-like text happens there too, so a value is
/// escaped once, on the way into the file, and never stored escaped.
class CatalogueSheetRow {
  const CatalogueSheetRow({
    required this.productId,
    required this.variantId,
    required this.unitId,
    required this.category,
    required this.brand,
    required this.productName,
    required this.variantName,
    required this.unitCode,
    required this.unitsPerBase,
    required this.price,
    required this.barcode,
    required this.lowStockThreshold,
    required this.storedAt,
    required this.active,
  });

  /// Null on an import-TEMPLATE row: a blank ID tells the import to create.
  final int? productId;
  final int? variantId;
  final int? unitId;
  final String category;
  final String brand;
  final String productName;
  final String variantName;
  final String unitCode;

  /// How many base units one of this selling unit holds; 1 marks the base unit.
  final double unitsPerBase;
  final double price;
  final String barcode;
  final double lowStockThreshold;

  /// Where the shop keeps the product. Product-level, as the ruling says.
  final String storedAt;

  /// Product-level too: `Active = No` archives the whole product on import.
  final bool active;
}

/// Every selling unit of every product, archived products included: the file
/// carries the archive flag instead of dropping them, so a round trip changes
/// nothing.
///
/// [unitsOf] lets a caller pass the selling units the store reloaded (the nested
/// `selling_uoms` on the products endpoint can be older than the `/variant-uoms/`
/// rows a code edit returns).
List<CatalogueSheetRow> catalogueSheetRows(
  Iterable<Product> products, {
  List<VariantUom> Function(ProductVariant variant)? unitsOf,
}) {
  final rows = <CatalogueSheetRow>[];
  for (final product in products) {
    for (final variant in product.variants) {
      for (final unit in unitsOf?.call(variant) ?? variant.sellingUoms) {
        rows.add(
          CatalogueSheetRow(
            productId: product.id,
            variantId: variant.id,
            unitId: unit.id,
            category: product.categoryName,
            brand: product.brandName,
            productName: product.baseName,
            variantName: variant.variantName,
            unitCode: unit.uomCode,
            unitsPerBase: unit.conversionFactor,
            price: unit.defaultSellingPrice,
            // The server's own text, digit for digit: a factory code with leading
            // zeros must come back the same code.
            barcode: unit.barcodeQr,
            lowStockThreshold: variant.minStockThreshold,
            storedAt: product.storedAtName,
            active: product.isActive,
          ),
        );
      }
    }
  }
  return rows;
}

/// The valid values for the four by-name columns, for the "Lists" sheet.
///
/// Only what an import can ACCEPT: an archived category or location cannot be
/// assigned (the server refuses), so offering it would be a trap.
class CatalogueSheetLists {
  const CatalogueSheetLists({
    required this.categories,
    required this.unitCodes,
    required this.locations,
    required this.brands,
  });

  const CatalogueSheetLists.empty()
    : categories = const [],
      unitCodes = const [],
      locations = const [],
      brands = const [];

  final List<String> categories;
  final List<String> unitCodes;
  final List<String> locations;
  final List<String> brands;

  /// The lists the catalogue screens already loaded, sorted once each so the
  /// sheet reads like a dropdown.
  factory CatalogueSheetLists.fromSources({
    required List<Category> categories,
    required List<UnitOfMeasure> units,
    required List<StorageLocation> locations,
    required List<Brand> brands,
  }) => CatalogueSheetLists(
    categories: _sorted([
      for (final category in categories)
        if (category.isActive) category.name,
    ]),
    unitCodes: _sorted([for (final unit in units) unit.code]),
    locations: _sorted([
      for (final location in locations)
        if (location.isActive) location.name,
    ]),
    brands: _sorted([for (final brand in brands) brand.name]),
  );

  /// The sheet's contents: the four lists, one per column, in this order.
  List<List<String>> get columns => [categories, unitCodes, locations, brands];

  static List<String> _sorted(Iterable<String> values) =>
      values.where((value) => value.isNotEmpty).toSet().toList()..sort();
}

/// Example rows for the import TEMPLATE (owner 2026-11-18): blank IDs, so an
/// import CREATES them, built only from names this shop's [lists] already hold
/// (an unknown category, brand, unit or location is a row error on import).
///
/// Shows the three shapes a storekeeper needs: a measured Bodega product (one base
/// row), a counted product sold by the piece AND by a pack (two rows, one with
/// Units per base 1), and a Store product.
List<CatalogueSheetRow> catalogueTemplateRows(CatalogueSheetLists lists) {
  String pick(List<String> values, List<String> preferred) {
    for (final want in preferred) {
      for (final value in values) {
        if (value.toLowerCase() == want.toLowerCase()) return value;
      }
    }
    return values.isEmpty ? '' : values.first;
  }

  final bodega = pick(lists.locations, const ['Bodega']);
  final store = pick(lists.locations, const ['Store']);
  final brand = pick(lists.brands, const ['Local Supply']);
  final measured = pick(lists.unitCodes, const ['CU.M', 'KG', 'M', 'L']);
  final kg = pick(lists.unitCodes, const ['KG', 'CU.M', 'M', 'L']);
  final piece = pick(lists.unitCodes, const ['PC']);
  final pack = pick(
    [
      for (final code in lists.unitCodes)
        if (code != piece) code,
    ],
    const ['BOX', 'PACK', 'BUNDLE', 'BAG'],
  );
  final bag = pick(
    [
      for (final code in lists.unitCodes)
        if (code != kg) code,
    ],
    const ['BAG', 'PACK', 'BOX'],
  );

  CatalogueSheetRow row({
    required String category,
    required String name,
    required String variant,
    required String unit,
    required double perBase,
    required double price,
    required double threshold,
    required String storedAt,
  }) => CatalogueSheetRow(
    productId: null,
    variantId: null,
    unitId: null,
    category: category,
    brand: brand,
    productName: name,
    variantName: variant,
    unitCode: unit,
    unitsPerBase: perBase,
    price: price,
    barcode: '',
    lowStockThreshold: threshold,
    storedAt: storedAt,
    active: true,
  );

  return [
    row(
      category: pick(lists.categories, const ['Aggregates', 'Sand', 'Gravel']),
      name: 'Gravel',
      variant: '3/4 inch',
      unit: measured,
      perBase: 1,
      price: 1350,
      threshold: 8,
      storedAt: bodega,
    ),
    row(
      category: pick(lists.categories, const [
        'Masonry',
        'Blocks',
        'Aggregates',
      ]),
      name: 'Hollow Blocks',
      variant: '4 inch',
      unit: piece,
      perBase: 1,
      price: 16,
      threshold: 300,
      storedAt: bodega,
    ),
    row(
      category: pick(lists.categories, const [
        'Masonry',
        'Blocks',
        'Aggregates',
      ]),
      name: 'Hollow Blocks',
      variant: '6 inch',
      unit: piece,
      perBase: 1,
      price: 22,
      threshold: 200,
      storedAt: bodega,
    ),
    row(
      category: pick(lists.categories, const ['Paint', 'Hardware']),
      name: 'Paint (example)',
      variant: '1 Liter',
      unit: piece,
      perBase: 1,
      price: 15,
      threshold: 20,
      storedAt: store,
    ),
    if (pack.isNotEmpty && pack != piece)
      row(
        category: pick(lists.categories, const ['Paint', 'Hardware']),
        name: 'Paint (example)',
        variant: '1 Liter',
        unit: pack,
        perBase: 10,
        price: 100,
        threshold: 20,
        storedAt: store,
      ),
    row(
      category: pick(lists.categories, const ['Cement']),
      name: 'Portland Cement (example)',
      variant: '40kg',
      unit: kg,
      perBase: 1,
      price: 7,
      threshold: 200,
      storedAt: store,
    ),
    if (bag.isNotEmpty && bag != kg)
      row(
        category: pick(lists.categories, const ['Cement']),
        name: 'Portland Cement (example)',
        variant: '40kg',
        unit: bag,
        perBase: 40,
        price: 260,
        threshold: 200,
        storedAt: store,
      ),
  ];
}

/// The "How to fill" sheet of the import template, one line per row.
const catalogueTemplateInstructions = <String>[
  'HOW TO FILL THIS TEMPLATE',
  'One row per selling unit (base unit and any pack units). Replace the example rows with your products before importing.',
  'Product ID, Variant ID, Unit ID: leave BLANK for new products, new variants, or new pack units. Rows with IDs update existing items (use an export for that).',
  'Category, Brand, Unit code, Stored at: copy the exact names from the Lists sheet. They must already exist.',
  'Product name and Variant: required. Repeat the same Product name and Variant with a different Unit code to add a pack unit (e.g. PC + BOX); use a different Variant (e.g. "4 inch", "6 inch") for separate variants.',
  'Units per base: type 1 on exactly ONE row per variant (the base unit stock is counted in). On pack rows, type how many base units the pack holds (e.g. 10 for a box of 10 PC, 40 for a 40 KG bag, or decimals like 2.5).',
  'Price: the selling price of THAT unit (per piece/kilo on the base row, or for the whole pack on a pack row).',
  'Barcode: optional. Leave blank and the system generates one automatically.',
  'Low-stock threshold, Stored at, Active: Stored at and Active are product-level; Low-stock threshold is variant-level. Active is Yes or No.',
  'Import never adds stock. Add stock with a purchase order and Receiving; Bodega deliveries go to the checker first.',
  'Import shows a preview of every change and every error, and saves only when there are no errors.',
];

/// Everything the exporter writes: the rows and the lists sheet.
class CatalogueSheetData {
  const CatalogueSheetData({required this.rows, required this.lists});

  final List<CatalogueSheetRow> rows;
  final CatalogueSheetLists lists;
}
