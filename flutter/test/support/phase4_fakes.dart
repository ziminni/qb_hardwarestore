// Shared fakes for the Phase 4 Stock Manager tests.
//
// Why they exist: the inventory store used to seed itself from
// `InventoryMockData` and expose in-memory mutators (`addProduct`,
// `updateProduct`, `sellStock`) that tests used purely as ARRANGEMENT. Phase 4
// deleted those paths, so arrangement moved to where production data really comes
// from — the repositories. Every fake below answers with rows a test wrote down,
// and records the calls it received so a test can assert the request body rather
// than a screen's pixels.
//
// This file is test-only on purpose: none of it is compiled into `lib/`.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/storage_location_repository.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/storage_location_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';

/// A selling unit at factor 1 — the base unit the till prices.
VariantUom variantUom({
  required int id,
  required int variantId,
  double price = 315,
  String barcode = '',
  String uomCode = 'PC',
  int uomId = 1,
  String uomName = 'Piece',
  double factor = 1,
  bool isWhole = false,
  bool inUse = false,
}) => VariantUom(
  id: id,
  variantId: variantId,
  uomId: uomId,
  uomCode: uomCode,
  uomName: uomName,
  barcodeQr: barcode,
  conversionFactor: factor,
  defaultSellingPrice: price,
  uomIsWhole: isWhole,
  inUse: inUse,
);

ProductVariant variant({
  required int id,
  required int productId,
  String name = '20A 1-pole',
  double threshold = 5,
  double maxStockLevel = 0,
  List<VariantUom>? sellingUoms,
  String baseUomCode = 'PC',
  int baseUomId = 1,
  bool isActive = true,
}) => ProductVariant(
  id: id,
  productId: productId,
  baseUomId: baseUomId,
  minStockThreshold: threshold,
  maxStockLevel: maxStockLevel,
  sellingUoms:
      sellingUoms ??
      [
        variantUom(
          id: id,
          variantId: id,
          uomId: baseUomId,
          uomCode: baseUomCode,
          uomName: _unitName(baseUomCode),
        ),
      ],
  variantName: name,
  baseUomCode: baseUomCode,
  isActive: isActive,
);

/// The server's display name for the codes the fixtures use, so the default
/// selling unit of a `BAG` variant is not called "Piece".
String _unitName(String code) => switch (code) {
  'PC' => 'Piece',
  'BAG' => 'Bag',
  'BOX' => 'Box',
  'KG' => 'Kilogram',
  'RL' => 'Roll',
  'SHT' => 'Sheet',
  _ => code,
};

Product product({
  required int id,
  String name = 'Circuit Breaker',
  String categoryName = 'Electrical',
  String brandName = 'Omni',
  int categoryId = 1,
  int brandId = 1,
  List<ProductVariant>? variants,
  bool isActive = true,
}) => Product(
  id: id,
  categoryId: categoryId,
  categoryName: categoryName,
  brandId: brandId,
  brandName: brandName,
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: isActive,
  variants: variants ?? [variant(id: id, productId: id)],
);

InventoryBatch batch({
  required int id,
  required int variantId,
  double qty = 100,
  double cost = 180,
  int receiptId = 1,
}) => InventoryBatch(
  id: id,
  variantId: variantId,
  receiptId: receiptId,
  initialQty: qty,
  currentQty: qty,
  unitCostLanded: cost,
  markupPercentage: 0,
  batchSellingPrice: cost,
  expirationDate: null,
  createdAt: null,
);

SystemAlert alert({
  int id = 1,
  int variantId = 8,
  bool resolved = false,
  String resolvedByName = '',
  DateTime? resolvedAt,
  SystemAlertType type = SystemAlertType.lowStock,
}) => SystemAlert(
  id: id,
  type: type,
  variantId: variantId,
  message: 'Circuit Breaker 20A 1-pole is low.',
  isResolved: resolved,
  createdAt: DateTime(2026, 10, 25, 9),
  resolvedByName: resolvedByName,
  resolvedAt: resolvedAt,
);

Category category({
  required int id,
  required String name,
  bool isActive = true,
}) => Category(id: id, name: name, isActive: isActive);

/// Answers `loadCatalogue()` with a snapshot the test can swap, and records every
/// write so the request BODY is assertable.
class FakeProductsRepository extends ProductsRepository {
  FakeProductsRepository({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
  }) : _snapshot = ProductsSnapshot(products: products, batches: batches),
       super(ProductsService());

  ProductsSnapshot _snapshot;
  int loadCount = 0;

  /// Fail the create chain at this step instead of succeeding.
  ProductWriteStep? failAt;

  /// Refuse this extra selling unit AFTER the product exists (a partial create).
  String? partialFailUnit;

  /// Set to throw from any write (edit / archive).
  String? writeError;

  final List<NewProductDraft> createdDrafts = [];
  final List<ProductEditDraft> editDrafts = [];
  final List<({int productId, bool isActive})> activePatches = [];

  /// Every selling-unit code PATCH, in order (Phase 6 decision 18).
  final List<({int unitId, String barcode})> barcodePatches = [];

  /// Units removed through the details dialog, and units added to a variant
  /// (Phase 1d Task 9). The snapshot is really mutated, so a reload after a
  /// success shows the row gone or present.
  final List<int> deletedUnitIds = [];
  final List<({int variantId, NewSellingUnit unit})> createdUnits = [];

  /// Set to refuse a removal or an added unit with this message.
  String? deleteError;
  String? createUnitError;

  /// Set to refuse a code PATCH with this message (e.g. a 400 `BARCODE_TAKEN`).
  String? barcodeError;

  void setSnapshot({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
  }) => _snapshot = ProductsSnapshot(products: products, batches: batches);

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    loadCount++;
    return _snapshot;
  }

  @override
  Future<CreatedProduct> createProductChain(NewProductDraft draft) async {
    final step = failAt;
    if (step != null) {
      throw ProductWriteException(step: step, message: 'server said no');
    }
    createdDrafts.add(draft);
    final created = CreatedProduct(
      productId: 100 + createdDrafts.length,
      variantId: 200 + createdDrafts.length,
      sellingUnitId: 300 + createdDrafts.length,
    );
    final refusedUnit = partialFailUnit;
    if (refusedUnit != null) {
      throw PartialCreateException(
        created: created,
        unit: refusedUnit,
        message: 'One selling unit always holds at least one base unit.',
      );
    }
    return created;
  }

  @override
  Future<void> patchSellingUnit(int id, Map<String, dynamic> body) async {
    final error = barcodeError;
    if (error != null) {
      throw ProductWriteException(
        step: ProductWriteStep.sellingUnit,
        message: error,
      );
    }
    barcodePatches.add((unitId: id, barcode: '${body['barcode_qr']}'));
  }

  @override
  Future<void> createSellingUnit(int variantId, NewSellingUnit unit) async {
    final error = createUnitError;
    if (error != null) {
      throw ProductWriteException(
        step: ProductWriteStep.sellingUnit,
        message: error,
      );
    }
    createdUnits.add((variantId: variantId, unit: unit));
    _snapshot = ProductsSnapshot(
      products: [
        for (final product in _snapshot.products)
          product.copyWith(
            variants: [
              for (final variant in product.variants)
                variant.id == variantId
                    ? variant.copyWith(
                        sellingUoms: [
                          ...variant.sellingUoms,
                          VariantUom(
                            id: 900 + createdUnits.length,
                            variantId: variantId,
                            uomId: unit.uomId,
                            uomCode: unit.uomCode,
                            uomName: unit.uomCode,
                            barcodeQr: unit.barcodeQr,
                            conversionFactor: unit.conversionFactor,
                            defaultSellingPrice: unit.sellingPrice,
                          ),
                        ],
                      )
                    : variant,
            ],
          ),
      ],
      batches: _snapshot.batches,
    );
  }

  @override
  Future<void> deleteSellingUnit(int id) async {
    final error = deleteError;
    if (error != null) {
      throw ProductWriteException(
        step: ProductWriteStep.sellingUnit,
        message: error,
      );
    }
    deletedUnitIds.add(id);
    _snapshot = ProductsSnapshot(
      products: [
        for (final product in _snapshot.products)
          product.copyWith(
            variants: [
              for (final variant in product.variants)
                variant.copyWith(
                  sellingUoms: [
                    for (final unit in variant.sellingUoms)
                      if (unit.id != id) unit,
                  ],
                ),
            ],
          ),
      ],
      batches: _snapshot.batches,
    );
  }

  @override
  Future<void> editProductChain(ProductEditDraft draft) async {
    final error = writeError;
    if (error != null) {
      throw ProductWriteException(
        step: ProductWriteStep.product,
        message: error,
      );
    }
    editDrafts.add(draft);
  }

  @override
  Future<void> setProductActive(int productId, bool isActive) async {
    final error = writeError;
    if (error != null) {
      throw ProductWriteException(
        step: ProductWriteStep.product,
        message: error,
      );
    }
    activePatches.add((productId: productId, isActive: isActive));
  }
}

/// Alerts, adjustments and the goods-receipt history.
class FakeInventoryRepository extends InventoryRepository {
  FakeInventoryRepository({
    List<SystemAlert> alerts = const [],
    List<StockAdjustment> adjustments = const [],
    List<GoodsReceiptRecord> receipts = const [],
  }) : _alerts = alerts,
       _adjustments = adjustments,
       _receipts = receipts,
       super(InventoryService());

  List<SystemAlert> _alerts;
  final List<StockAdjustment> _adjustments;
  final List<GoodsReceiptRecord> _receipts;

  /// The ids `resolveAlert()` was called with, in order.
  final List<int> resolvedAlertIds = [];

  /// Set to refuse a resolve with this message.
  String? resolveError;

  /// Set to refuse a receipt create with this message.
  String? receiptError;

  void setAlerts(List<SystemAlert> alerts) => _alerts = alerts;

  @override
  Future<List<SystemAlert>> loadAlerts() async => _alerts;

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => _adjustments;

  @override
  Future<List<GoodsReceiptRecord>> loadGoodsReceipts() async => _receipts;

  @override
  Future<SystemAlert> resolveAlert(int alertId) async {
    final error = resolveError;
    if (error != null) throw InventoryServiceException(error);
    resolvedAlertIds.add(alertId);
    final index = _alerts.indexWhere((alert) => alert.id == alertId);
    if (index < 0) throw const InventoryServiceException('Alert not found.');
    final resolved = SystemAlert(
      id: _alerts[index].id,
      type: _alerts[index].type,
      variantId: _alerts[index].variantId,
      message: _alerts[index].message,
      isResolved: true,
      createdAt: _alerts[index].createdAt,
      resolvedByName: 'Ana Lopez',
      resolvedAt: DateTime(2026, 10, 25, 14, 30),
    );
    _alerts = [..._alerts]..[index] = resolved;
    return resolved;
  }
}

/// Categories, brands and units, with the writes recorded.
class FakeCatalogueRepository extends CatalogueRepository {
  FakeCatalogueRepository({
    List<Category> categories = const [],
    List<Brand> brands = const [],
    List<UnitOfMeasure> units = const [],
  }) : _categories = categories,
       _brands = brands,
       _units = units,
       super();

  List<Category> _categories;
  final List<Brand> _brands;
  final List<UnitOfMeasure> _units;

  final List<String> createdCategories = [];
  final List<({int id, String? name, bool? isActive})> categoryPatches = [];
  String? writeError;

  void setCategories(List<Category> categories) => _categories = categories;

  @override
  Future<List<Category>> fetchCategories() async => _categories;

  @override
  Future<List<Brand>> fetchBrands() async => _brands;

  @override
  Future<List<UnitOfMeasure>> fetchUnits() async => _units;

  @override
  Future<int> createCategory(String name) async {
    final error = writeError;
    if (error != null) throw CatalogueServiceException(error);
    createdCategories.add(name);
    final created = Category(id: 900 + createdCategories.length, name: name);
    _categories = [..._categories, created];
    return created.id;
  }

  @override
  Future<void> patchCategory(int id, {String? name, bool? isActive}) async {
    final error = writeError;
    if (error != null) throw CatalogueServiceException(error);
    categoryPatches.add((id: id, name: name, isActive: isActive));
    _categories = [
      for (final item in _categories)
        item.id == id ? item.copyWith(name: name, isActive: isActive) : item,
    ];
  }
}

/// A ready-to-use store for widget tests that only need a catalogue.
///
/// Two products with one factor-1 selling unit each and stock to sell from —
/// the shape the POS tests used to read out of `InventoryMockData`, which Phase 4
/// deleted. Names/prices are the ones those tests assert against, so their
/// assertions stay honest about what is on screen.
/// The same two-product catalogue as [seededInventory], as a repository — for
/// tests that build the store themselves and only need `loadCatalogue()` to
/// answer.
FakeProductsRepository seededProductsRepository() => FakeProductsRepository(
  products: seededProducts(),
  batches: [
    batch(id: 1, variantId: 1, qty: 130, cost: 235, receiptId: 1),
    batch(id: 2, variantId: 2, qty: 40, cost: 70, receiptId: 2),
  ],
);

List<Product> seededProducts() => [
  product(
    id: 1,
    name: 'Portland Cement',
    categoryName: 'Cement',
    brandName: 'Holcim',
    variants: [
      variant(
        id: 1,
        productId: 1,
        name: '40kg',
        threshold: 30,
        maxStockLevel: 200,
        baseUomId: 2,
        baseUomCode: 'BAG',
        sellingUoms: [
          variantUom(
            id: 1,
            variantId: 1,
            price: 270,
            uomId: 2,
            uomCode: 'BAG',
            uomName: 'Bag',
            isWhole: true,
          ),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'PVC Pipe',
    categoryName: 'Plumbing',
    brandName: 'Neltex',
    variants: [
      variant(
        id: 2,
        productId: 2,
        name: '1/2 inch',
        threshold: 10,
        maxStockLevel: 100,
        sellingUoms: [
          variantUom(id: 2, variantId: 2, price: 95, uomCode: 'PC'),
        ],
      ),
    ],
  ),
];

InventoryViewmodel seededInventory() {
  return InventoryViewmodel.seeded(
    // Fake repositories as well as fake rows: a widget under test may trigger a
    // `load()` (the till does, on open), and a real service would reach a Dio that
    // was never initialised in a unit test.
    catalogue: FakeProductsRepository(
      products: seededProducts(),
      batches: [
        batch(id: 1, variantId: 1, qty: 130, cost: 235, receiptId: 1),
        batch(id: 2, variantId: 2, qty: 40, cost: 70, receiptId: 2),
      ],
    ),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
    products: seededProducts(),
    batches: [
      batch(id: 1, variantId: 1, qty: 130, cost: 235, receiptId: 1),
      batch(id: 2, variantId: 2, qty: 40, cost: 70, receiptId: 2),
    ],
    categories: [
      category(id: 1, name: 'Cement'),
      category(id: 2, name: 'Plumbing'),
    ],
  );
}

/// The shop's storage locations (Phase 5 F4), with every write recorded.
///
/// Answers from a list the test writes down, so a screen under test asserts the
/// REQUEST (which id was named, which flag was flipped) rather than pixels.
class FakeStorageLocationRepository extends StorageLocationRepository {
  FakeStorageLocationRepository({List<StorageLocation> locations = const []})
    : _locations = [...locations],
      super();

  List<StorageLocation> _locations;

  final List<String> created = [];
  final List<({int id, String? name, bool? isActive})> patches = [];

  /// Set to refuse reads like the API would (a 403/500 message).
  String? readError;

  /// Set to refuse writes like the API would.
  String? writeError;

  @override
  Future<List<StorageLocation>> fetchAll() async {
    final error = readError;
    if (error != null) throw StorageLocationServiceException(error);
    return [..._locations];
  }

  @override
  Future<StorageLocation> create(String name) async {
    final error = writeError;
    if (error != null) throw StorageLocationServiceException(error);
    created.add(name);
    final createdRow = StorageLocation(id: 900 + created.length, name: name);
    _locations = [..._locations, createdRow];
    return createdRow;
  }

  @override
  Future<StorageLocation> patch(int id, {String? name, bool? isActive}) async {
    final error = writeError;
    if (error != null) throw StorageLocationServiceException(error);
    patches.add((id: id, name: name, isActive: isActive));
    late StorageLocation updated;
    _locations = [
      for (final row in _locations)
        if (row.id == id)
          updated = StorageLocation(
            id: row.id,
            name: name ?? row.name,
            isActive: isActive ?? row.isActive,
          )
        else
          row,
    ];
    return updated;
  }
}
