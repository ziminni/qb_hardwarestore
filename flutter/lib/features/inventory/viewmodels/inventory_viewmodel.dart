import 'dart:math';

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:client/data/services/catalogue_assembler.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/location_hint_store.dart';
import 'package:client/data/services/products_service.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;

/// The catalogue, the stock and the server's alerts, in one store.
///
/// **Everything here comes from the server** (decision 13, Phase 4 Task 4). Until
/// Phase 4 the lists were seeded from `InventoryMockData` and several mutations
/// were applied in memory — `addProduct`, `updateProduct`, `updateCategory`,
/// `archiveCategory`, `sellStock`. Those wrote rows that no server had ever
/// heard of and vanished on reload, so a stock manager could "add a product" and
/// then lose it by pressing Retry. They are gone, together with the mock file:
/// the honest first paint is a **loading state**, not twelve invented products.
class InventoryViewmodel extends ChangeNotifier {
  InventoryViewmodel({
    ProductsRepository? products,
    InventoryRepository? inventory,
    CatalogueRepository? catalogue,
  }) : _catalogue = products ?? ProductsRepository(ProductsService()),
       _inventory = inventory ?? InventoryRepository(InventoryService()),
       _catalogueLists = catalogue ?? CatalogueRepository();

  /// A store holding a snapshot, for TESTS ONLY (no network, no widget tree).
  ///
  /// Deliberately a constructor and not a method: it can only fill the lists
  /// BEFORE the first load, so no production path can reach it and no screen can
  /// write a row the server has never seen. The in-memory mutators that used to
  /// exist (`addProduct`, `updateProduct`, `sellStock`) were exactly that bug, and
  /// they are gone. Production builds the plain constructor and calls [load].
  @visibleForTesting
  InventoryViewmodel.seeded({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
    List<SystemAlert> alerts = const [],
    List<Category> categories = const [],
    List<Brand> brands = const [],
    List<UnitOfMeasure> units = const [],
    ProductsRepository? catalogue,
    InventoryRepository? inventory,
    CatalogueRepository? catalogueLists,
  }) : _catalogue = catalogue ?? ProductsRepository(ProductsService()),
       _inventory = inventory ?? InventoryRepository(InventoryService()),
       _catalogueLists = catalogueLists ?? CatalogueRepository() {
    _products.addAll(products);
    _batches.addAll(batches);
    _alerts.addAll(alerts);
    _categories.addAll(categories);
    _brands.addAll(brands);
    _units.addAll(units);
    _hasLoaded = true;
  }

  final List<Category> _categories = [];
  final List<Product> _products = [];
  final List<Brand> _brands = [];
  final List<UnitOfMeasure> _units = [];

  /// Where the catalogue is fetched from (decision 12). Injected so a test can
  /// drive a load without a network, and so the store keeps the one-data-path
  /// shape: viewmodel -> repository -> service -> ApiClient.
  final ProductsRepository _catalogue;

  /// Where alerts and adjustments come from (decision 13). Separate from the
  /// catalogue because they are a different authority: products and batches are
  /// the catalogue, while these are the server's record of what happened.
  final InventoryRepository _inventory;

  /// Categories, brands and units — the three lists a product (and its variant)
  /// cannot be created without.
  final CatalogueRepository _catalogueLists;

  final List<SystemAlert> _alerts = [];
  final List<StockAdjustment> _adjustments = [];

  bool _isLoading = false;
  String? _loadError;
  bool _hasLoaded = false;

  /// Where stock actually lives (decision 02). Every quantity question is
  /// answered from here, never from a field on the variant.
  final List<InventoryBatch> _batches = [];

  final LocationHintStore _locationHintStore = LocationHintStore();
  Map<int, String> _locationHints = const {};

  List<Category> get categories => List.unmodifiable(_categories);
  List<Product> get products => List.unmodifiable(_products);
  List<Brand> get brands => List.unmodifiable(_brands);
  List<UnitOfMeasure> get units => List.unmodifiable(_units);

  /// Every live batch. The dashboard values inventory from these
  /// (on-hand x landed cost), the same lots FIFO deducts from.
  List<InventoryBatch> get batches => List.unmodifiable(_batches);

  /// Alerts the server has raised (low stock, out of stock, expiring).
  ///
  /// Read, not derived — decision 13. Note the consequence that decision
  /// accepted: this is a list of events the server generated, so a variant that
  /// dropped below its threshold without an alerted path will not appear until an
  /// alert exists.
  List<SystemAlert> get alerts => List.unmodifiable(_alerts);

  /// The server's recorded stock adjustments, newest first.
  List<StockAdjustment> get adjustments => List.unmodifiable(_adjustments);

  /// What the movements screen renders: the server's adjustments.
  ///
  /// The local log that used to sit beside them held POS sales and opening
  /// stock, both invented here. Phase 4 removed it with the mutations that fed
  /// it — a movement the server did not record is not a movement.
  List<InventoryMovement> get movements {
    final rows = _adjustments.map(_movementFromAdjustment).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(rows);
  }

  /// Projects a server adjustment into the shape the movements UI renders.
  ///
  /// `previousStock`, `newStock` and `reference` have NO server counterpart —
  /// `StockAdjustmentSerializer` carries a delta (`qty_adjusted`), not a
  /// before/after pair. They are left at zero here and rendered as an em dash by
  /// the table, so the UI does not present an invented number as a real one.
  InventoryMovement _movementFromAdjustment(StockAdjustment adjustment) {
    return InventoryMovement(
      id: adjustment.id,
      timestamp: adjustment.timestamp,
      productId: variantFor(adjustment.variantId)?.productId ?? 0,
      variantId: adjustment.variantId,
      type: InventoryMovementType.stockAdjustment,
      quantityChange: adjustment.quantityAdjusted,
      previousStock: 0,
      newStock: 0,
      reference: '',
      reason: adjustment.remarks,
      userName: 'User ${adjustment.userId}',
    );
  }

  /// A catalogue fetch is in flight. Public per decision 07's convention, so
  /// [AsyncView] can render the loading state.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null. Outranks the empty state in
  /// [AsyncView], so a failed fetch is never reported as "no products".
  String? get loadError => _loadError;

  /// Whether a load attempt has finished — successfully or not.
  ///
  /// The screen needs this to tell "not fetched yet" from "fetched and empty".
  /// The lists start EMPTY now (no mock seed), so without it the products page
  /// would render "No products in the catalogue yet." for the frame before the
  /// first fetch — an empty state that claims a fact nobody has checked yet.
  ///
  /// A FAILED attempt also counts, so the page shows the retryable error instead
  /// of spinning forever.
  bool get hasLoaded => _hasLoaded;

  /// Replaces the catalogue, its stock and the catalog lists with live data.
  ///
  /// The product list has exactly ONE home — here — which is why Phase 1 makes
  /// this store API-backed rather than adding a second source: `ProductsViewmodel`
  /// (decision 11) and `assembleCatalogue` both already read from these lists, so
  /// every downstream screen goes live without a single consumer change.
  ///
  /// On failure the message is surfaced and the existing catalogue is **left
  /// intact**. It is deliberately not cleared: an empty list would render as a
  /// legitimate "no products" that the user cannot act on, whereas a retained
  /// list plus [loadError] lets [AsyncView] show a retryable error.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final snapshot = await _catalogue.loadCatalogue();
      final alerts = await _inventory.loadAlerts();
      final adjustments = await _inventory.loadAdjustments();
      final categories = await _catalogueLists.fetchCategories();
      final brands = await _catalogueLists.fetchBrands();
      final units = await _catalogueLists.fetchUnits();
      _products
        ..clear()
        ..addAll(snapshot.products);
      _batches
        ..clear()
        ..addAll(snapshot.batches);
      _alerts
        ..clear()
        ..addAll(alerts);
      _adjustments
        ..clear()
        ..addAll(adjustments);
      _categories
        ..clear()
        ..addAll(categories);
      _brands
        ..clear()
        ..addAll(brands);
      _units
        ..clear()
        ..addAll(units);
      _loadError = null;
    } on ProductsServiceException catch (error) {
      _loadError = error.message;
    } on InventoryServiceException catch (error) {
      _loadError = error.message;
    } on CatalogueServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Product writes (Phase 4 Task 4)
  //
  // Each returns `null` on success and a clerk-readable message on refusal, and
  // each RELOADS. Reloading is not politeness: the create chain is three POSTs
  // with no server-side transaction across them, so a failure at step 2 leaves a
  // real product row that the screen must show rather than hide behind a
  // "could not add product" message the user would retry into a duplicate.
  // ---------------------------------------------------------------------

  /// Creates the catalog item (product → variant → factor-1 selling unit).
  Future<String?> createProduct(NewProductDraft draft) async {
    try {
      await _catalogue.createProductChain(draft);
    } on ProductWriteException catch (error) {
      await load();
      return 'The ${error.step.label} could not be created: ${error.message}';
    }
    await load();
    return null;
  }

  /// Applies an edit through PATCH, one call per row that changed.
  Future<String?> editProduct(ProductEditDraft draft) async {
    try {
      await _catalogue.editProductChain(draft);
    } on ProductWriteException catch (error) {
      await load();
      return 'The ${error.step.label} could not be saved: ${error.message}';
    }
    await load();
    return null;
  }

  /// Archive (`false`) or restore (`true`) a product. Never a delete: the route
  /// answers 405 and history PROTECT-references the row.
  Future<String?> setProductActive(int productId, bool isActive) async {
    try {
      await _catalogue.setProductActive(productId, isActive);
    } on ProductWriteException catch (error) {
      return 'The product could not be '
          '${isActive ? 'restored' : 'archived'}: ${error.message}';
    }
    await load();
    return null;
  }

  // ---------------------------------------------------------------------
  // Category writes
  // ---------------------------------------------------------------------

  Future<String?> createCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a category name.';
    try {
      await _catalogueLists.createCategory(trimmed);
    } on CatalogueServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  Future<String?> renameCategory(int id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a category name.';
    try {
      await _catalogueLists.patchCategory(id, name: trimmed);
    } on CatalogueServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// Archives (`false`) or restores (`true`) a category.
  ///
  /// Archiving hides it from the new-product picker; the products already filed
  /// under it stay sellable, because the till prices a line from the selling
  /// unit, never from the category.
  Future<String?> setCategoryActive(int id, bool isActive) async {
    try {
      await _catalogueLists.patchCategory(id, isActive: isActive);
    } on CatalogueServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// Resolves one alert on the server and reloads, so the resolver and the time
  /// shown are the server's, not the client's guess.
  Future<String?> resolveAlert(int alertId) async {
    try {
      await _inventory.resolveAlert(alertId);
    } on InventoryServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// A variant's batches, oldest delivery first — the order FIFO deducts in.
  ///
  /// Ordered by `receiptId`, the client's only always-present ordering key: a
  /// row can carry `createdAt: null`, so ordering by date is not available even
  /// though the live API populates it.
  List<InventoryBatch> batchesFor(int variantId) {
    final rows =
        _batches.where((batch) => batch.variantId == variantId).toList()
          ..sort((a, b) {
            final byReceipt = a.receiptId.compareTo(b.receiptId);
            return byReceipt != 0 ? byReceipt : a.id.compareTo(b.id);
          });
    return List.unmodifiable(rows);
  }

  /// Stock on hand for a variant — the sum of its batches.
  double stockOnHandFor(int variantId) =>
      batchesFor(variantId).fold(0, (sum, batch) => sum + batch.currentQty);

  /// The newest batch: what an upward correction lands on, and where the
  /// displayed cost comes from (decision 08 — no weighted average, no charging).
  InventoryBatch? latestBatchFor(int variantId) {
    final rows = batchesFor(variantId);
    return rows.isEmpty ? null : rows.last;
  }

  /// One row per (variant, selling unit), assembled from products and batches.
  /// Price comes from the selling unit and stock from the batches, so no screen
  /// has to re-do that join.
  List<CatalogueItem> get catalogue =>
      assembleCatalogue(products: _products, batches: _batches);

  /// The variant behind an id, searched across every product.
  ProductVariant? variantFor(int variantId) {
    for (final product in _products) {
      for (final variant in product.variants) {
        if (variant.id == variantId) return variant;
      }
    }
    return null;
  }

  /// The variant's barcode — `VariantUom.barcode_qr`, the only identifier the API
  /// carries. Empty when no selling unit has one, which is the honest state for
  /// all seeded data.
  ///
  /// This replaces the invented `sku` (decision 10): there is no SKU field
  /// anywhere in the backend, and the `CEM-HOL-40`-style values were fabricated
  /// by the mock data rather than typed into any database.
  String barcodeFor(int variantId) => variantFor(variantId)?.barcode ?? '';

  /// The price the POS charges: the selling unit's default price (decision 08).
  /// Never the batch price, so FIFO crossing a batch boundary cannot split a
  /// cart line or change what the customer pays. Null when there is no selling
  /// unit — no price is invented for it.
  double? priceFor(int variantId) {
    final uoms = variantFor(variantId)?.sellingUoms ?? const <VariantUom>[];
    return uoms.isEmpty ? null : uoms.first.defaultSellingPrice;
  }

  /// The **displayed** cost: the newest batch's landed unit cost, which is what
  /// decision 08 chose over a weighted average. This is not a charging price.
  double? costFor(int variantId) => latestBatchFor(variantId)?.unitCostLanded;

  /// Storage-location hints, keyed by variant id.
  ///
  /// Store-local knowledge, explicitly **not** API data (decision 10): the
  /// backend has no location field, so these live on the device and must not be
  /// presented as though the server sent them.
  Map<int, String> get locationHints => Map.unmodifiable(_locationHints);

  /// The recorded location for a variant, or an empty string when none is
  /// recorded. Empty rather than a placeholder, because "we do not know where it
  /// is" is a real state and must not look like a location.
  String locationHintFor(int variantId) => _locationHints[variantId] ?? '';

  Future<void> loadLocationHints() async {
    _locationHints = await _locationHintStore.loadAll();
    notifyListeners();
  }

  /// Records a location hint. A blank [location] clears it.
  Future<void> setLocationHint(int variantId, String location) async {
    await _locationHintStore.save(variantId, location);
    await loadLocationHints();
  }

  Iterable<({Product product, ProductVariant variant})> get stockRecords sync* {
    for (final product in _products) {
      for (final variant in product.variants) {
        yield (product: product, variant: variant);
      }
    }
  }

  /// Low-stock status derived from the **batch** total.
  ///
  /// The predicate is deliberately the **server's**, not a client invention:
  /// `apps/inventory/services.py::_check_low_stock` raises a LOW_STOCK alert when
  /// `total < min_stock_threshold` **and** `threshold > 0`, and an OUT_OF_STOCK
  /// alert when `total <= 0`.
  ///
  /// It previously read `stock <= threshold` with no `threshold > 0` guard. On a
  /// variant sitting exactly on its threshold that returned `lowStock` while the
  /// server raised no alert, so the stock list and the alert screen contradicted
  /// each other about the same row. Aligning it is the whole reason this method
  /// changed in Phase 2 (decision 13, rule 2).
  InventoryStockStatus statusForVariant(int variantId) {
    final stock = stockOnHandFor(variantId);
    if (stock <= 0) return InventoryStockStatus.outOfStock;
    final threshold = variantFor(variantId)?.minStockThreshold ?? 0;
    if (threshold > 0 && stock < threshold) {
      return InventoryStockStatus.lowStock;
    }
    return InventoryStockStatus.inStock;
  }

  int productCountForCategory(int categoryId) =>
      _products.where((product) => product.categoryId == categoryId).length;

  List<Product> productsForCategory(int categoryId) => _products
      .where((product) => product.categoryId == categoryId)
      .toList(growable: false);

  List<InventoryMovement> movementsForVariant(int variantId) => movements
      .where((movement) => movement.variantId == variantId)
      .toList(growable: false);

  /// Records a stock adjustment ON THE SERVER, then re-reads.
  ///
  /// Decision 13: the server owns inventory state, so this does not move the
  /// local batches or insert a movement row of its own. It POSTs to
  /// `/api/v1/adjustments/` and calls [load].
  ///
  /// Returns whether the server accepted it, so the caller does not announce
  /// success unconditionally.
  Future<bool> adjustStock({
    required int variantId,
    required double newQuantity,
    required String reason,
    required String notes,
  }) async {
    final previous = stockOnHandFor(variantId);
    // A caller can hand us a negative "new quantity" even though the dialog
    // validates >= 0. Clamp it: otherwise the adjustment asks the server to
    // remove more than exists.
    final target = newQuantity < 0 ? 0.0 : newQuantity;
    final delta = target - previous;
    if (delta == 0) return true;

    final trimmed = notes.trim();
    try {
      await _inventory.recordAdjustment(
        variantId: variantId,
        type: _serverTypeFor(reason),
        quantity: delta,
        remarks: trimmed.isEmpty ? reason : '$reason — $trimmed',
      );
    } on InventoryServiceException catch (error) {
      _loadError = error.message;
      notifyListeners();
      return false;
    }
    await load();
    return true;
  }

  /// Maps the adjust dialog's human wording onto the server's `adjustment_type`
  /// codes. An unknown wording becomes a count correction, matching
  /// `StockAdjustmentType.fromApiValue`'s own fallback in the other direction.
  static StockAdjustmentType _serverTypeFor(String reason) {
    switch (reason) {
      case 'Damaged Items':
        return StockAdjustmentType.damage;
      case 'Shrinkage / Loss':
        return StockAdjustmentType.shrinkage;
      case 'Supplier Return':
        return StockAdjustmentType.returnToSupplier;
      default:
        return StockAdjustmentType.correction;
    }
  }

  /// The variant of a PO line, for the purchase-order and reorder dialogs.
  ///
  /// Returns null rather than throwing: a variant the server no longer lists is
  /// a row this client cannot describe, and a picker must not crash over it.
  ProductVariant? variantById(int variantId) => variantFor(variantId);

  /// Suggested order quantity for a low-stock variant.
  ///
  /// `max_stock_level − on hand` when that is positive (fill the shelf back to
  /// its ceiling), else the reorder threshold, else 1 — so the field is never
  /// zero, which the server refuses as `INVALID_PO`.
  double suggestedReorderQty(int variantId) {
    final variant = variantFor(variantId);
    final onHand = stockOnHandFor(variantId);
    final ceiling = variant?.maxStockLevel ?? 0;
    if (ceiling - onHand > 0) return ceiling - onHand;
    final threshold = variant?.minStockThreshold ?? 0;
    return threshold > 0 ? max(threshold, 1) : 1;
  }
}
