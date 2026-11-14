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

  final int productId;
  final int variantId;
  final int unitId;
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

/// Everything the exporter writes: the rows and the lists sheet.
class CatalogueSheetData {
  const CatalogueSheetData({required this.rows, required this.lists});

  final List<CatalogueSheetRow> rows;
  final CatalogueSheetLists lists;
}
