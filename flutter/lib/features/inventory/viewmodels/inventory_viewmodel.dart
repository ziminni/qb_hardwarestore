import 'dart:math';

import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/catalogue_assembler.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/location_hint_store.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_mock_data.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

class InventoryViewmodel extends ChangeNotifier {
  InventoryViewmodel({ProductsRepository? products, InventoryRepository? inventory})
    : _catalogue = products ?? ProductsRepository(ProductsService()),
      _inventory = inventory ?? InventoryRepository(InventoryService()),
      _categories = List.of(InventoryMockData.categories),
      _products = List.of(InventoryMockData.products),
      _batches = List.of(InventoryMockData.batches) {
    // Deliberately no `_seedMovements()`: movements are the SERVER's record now
    // (decision 13), and inventing fixtures is the thing being removed.
    // Deliberately no `loadLocationHints()` here: the constructor stays free of
    // side effects reaching platform storage, so a viewmodel can be built in a
    // plain test. The app loads the hints once at startup (see `main.dart`), and
    // until then `locationHintFor` honestly reads as "unknown".
  }

  final List<Category> _categories;
  final List<Product> _products;

  /// Where the catalogue is fetched from (decision 12). Injected so a test can
  /// drive a load without a network, and so the store keeps the one-data-path
  /// shape: viewmodel -> repository -> service -> ApiClient.
  final ProductsRepository _catalogue;

  /// Where alerts and adjustments come from (decision 13). Separate from the
  /// catalogue because they are a different authority: products and batches are
  /// the catalogue, while these are the server's record of what happened.
  final InventoryRepository _inventory;

  final List<SystemAlert> _alerts = [];
  final List<StockAdjustment> _adjustments = [];

  bool _isLoading = false;
  String? _loadError;
  bool _hasLoaded = false;

  /// Where stock actually lives (decision 02). Every quantity question is
  /// answered from here, never from a field on the variant.
  final List<InventoryBatch> _batches;

  final List<InventoryMovement> _movements = [];

  final LocationHintStore _locationHintStore = LocationHintStore();
  Map<int, String> _locationHints = const {};

  List<Category> get categories => List.unmodifiable(_categories);
  List<Product> get products => List.unmodifiable(_products);

  /// Alerts the server has raised (low stock, out of stock, expiring).
  ///
  /// Read, not derived — decision 13. Note the consequence that decision
  /// accepted: this is a list of events the server generated, so a variant that
  /// dropped below its threshold without an alerted path will not appear until an
  /// alert exists.
  List<SystemAlert> get alerts => List.unmodifiable(_alerts);

  /// The server's recorded stock adjustments, newest first.
  List<StockAdjustment> get adjustments => List.unmodifiable(_adjustments);

  /// What the movements screen renders.
  ///
  /// **Two sources, and the split is deliberate** (ledger ruling, Phase 2 Task 2):
  ///
  /// * stock ADJUSTMENTS come from the server, which is their authority;
  /// * POS sales and opening stock are still recorded locally in [_movements],
  ///   because **no row-level endpoint carries them**.
  ///   `GET /api/v1/reports/stock-movements/` reports Stock IN vs OUT as a
  ///   *summary*, not rows, so a complete history would need adjustments, sales
  ///   and receipts merged from three endpoints — later phases' work.
  ///
  /// [_movements] therefore holds ONLY the kinds the API cannot supply, and it is
  /// provisional. Decision 13 said to delete it; that rested on the premise that
  /// `/adjustments/` covers the movement history, which it does not — deleting it
  /// would make a demo sale produce no row at all.
  List<InventoryMovement> get movements {
    final merged = <InventoryMovement>[
      ..._adjustments.map(_movementFromAdjustment),
      ..._movements,
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List.unmodifiable(merged);
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
  /// The screen needs this to tell "not fetched yet" from "fetched and empty",
  /// because until the first attempt completes the lists still hold the MOCK
  /// catalogue. Without it the products page renders 12 mock products for a frame
  /// before the API's 6 arrive: a visible flash of data that is not real.
  ///
  /// A FAILED attempt also counts, so the page shows the retryable error instead
  /// of spinning forever.
  bool get hasLoaded => _hasLoaded;

  /// Replaces the catalogue and its stock with live API data (decision 12).
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
  ///
  /// Only products and batches are touched. The mock stays the source for
  /// movements, adjustments and tracking until their phases land.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final snapshot = await _catalogue.loadCatalogue();
      final alerts = await _inventory.loadAlerts();
      final adjustments = await _inventory.loadAdjustments();
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
      _loadError = null;
    } on ProductsServiceException catch (error) {
      _loadError = error.message;
    } on InventoryServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  /// A variant's batches, oldest delivery first — the order FIFO deducts in.
  ///
  /// Ordered by `receiptId`, which is the client's only non-null date proxy:
  /// every mock batch was materialised with `createdAt: null`, so ordering by
  /// date is impossible here even though the live API populates it.
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

  void updateCategory(Category category) {
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index < 0) return;
    _categories[index] = category;
    notifyListeners();
  }

  void archiveCategory(Category category) =>
      updateCategory(category.copyWith(isActive: false));

  /// Sets a variant's stock to an absolute count (a count correction). Mirrors
  /// the backend's `apply_stock_adjustment`: a reduction goes through FIFO oldest
  /// batch first, an addition lands on the newest batch.
  void adjustStock({
    required int variantId,
    required double newQuantity,
    required String reason,
    required String notes,
    required String userName,
  }) {
    final product = _productForVariant(variantId);
    if (product == null) return;

    final previous = stockOnHandFor(variantId);
    // A caller can hand us a negative "new quantity" even though the dialog
    // validates >= 0. Clamp it: otherwise the FIFO deduction drains every batch
    // and the movement is recorded with a NEGATIVE newStock.
    final target = newQuantity < 0 ? 0.0 : newQuantity;
    final delta = target - previous;
    if (delta == 0) return;

    if (delta < 0) {
      _deductFifo(variantId: variantId, quantity: -delta);
    } else {
      _addToNewestBatch(variantId: variantId, quantity: delta);
    }

    _movements.insert(
      0,
      InventoryMovement(
        id: _movements.length + 1,
        productId: product.id,
        variantId: variantId,
        timestamp: DateTime.now(),
        type: InventoryMovementType.stockAdjustment,
        quantityChange: delta,
        previousStock: previous,
        newStock: previous + delta,
        reference: 'ADJ-${(_movements.length + 1).toString().padLeft(4, '0')}',
        reason: notes.trim().isEmpty ? reason : '$reason — ${notes.trim()}',
        userName: userName,
      ),
    );
    notifyListeners();
  }

  /// Sells [quantity] of a variant, deducting the oldest batch first — the client
  /// mirror of `inventory.services.allocate_fifo`. A sale larger than the stock on
  /// hand is refused and changes nothing, which is what the backend does by
  /// raising before it writes anything.
  void sellStock({
    required int variantId,
    required double quantity,
    required String reference,
    required String userName,
  }) {
    if (quantity <= 0) return;
    final product = _productForVariant(variantId);
    if (product == null) return;

    final previous = stockOnHandFor(variantId);
    if (quantity > previous) return;

    _deductFifo(variantId: variantId, quantity: quantity);

    _movements.insert(
      0,
      InventoryMovement(
        id: _movements.length + 1,
        productId: product.id,
        variantId: variantId,
        timestamp: DateTime.now(),
        type: InventoryMovementType.sale,
        quantityChange: -quantity,
        previousStock: previous,
        newStock: previous - quantity,
        reference: reference,
        reason: 'Frontend POS sale',
        userName: userName,
      ),
    );
    notifyListeners();
  }

  /// Adds a product and records the opening stock it arrived with.
  ///
  /// Opening stock arrives as [InventoryBatch] rows because a batch is exactly
  /// "a lot at a cost": the quantity and cost the form collects become real
  /// entities here instead of numbers parked on the variant (decision 02, and
  /// the answer to decision 10's add-product question). The form passes batch
  /// ids of 0 and the viewmodel assigns real batch and receipt ids from its own
  /// `max+1`, so opening stock cannot collide with existing lots. Variant ids are
  /// the form's own (a microsecond timestamp) and are NOT reassigned here.
  ///
  /// A variant added with no opening stock simply has no batch — `stockOnHandFor`
  /// then reads 0 and `statusForVariant` calls it out of stock.
  void addProduct(
    Product product, {
    List<InventoryBatch> openingStock = const [],
  }) {
    final id = _products.fold<int>(0, (value, item) => max(value, item.id)) + 1;
    final stored = product.copyWith(id: id);
    _products.add(stored);

    for (final batch in openingStock) {
      if (batch.initialQty <= 0) continue;
      _batches.add(
        InventoryBatch(
          id: _nextBatchId(),
          variantId: batch.variantId,
          receiptId: _nextReceiptId(),
          initialQty: batch.initialQty,
          currentQty: batch.currentQty,
          unitCostLanded: batch.unitCostLanded,
          markupPercentage: batch.markupPercentage,
          batchSellingPrice: batch.batchSellingPrice,
          expirationDate: batch.expirationDate,
          createdAt: batch.createdAt,
        ),
      );
      _movements.insert(
        0,
        InventoryMovement(
          id: _movements.length + 1,
          productId: id,
          variantId: batch.variantId,
          timestamp: DateTime.now(),
          type: InventoryMovementType.initialStock,
          quantityChange: batch.initialQty,
          previousStock: 0,
          newStock: batch.initialQty,
          reference: 'INITIAL',
          reason: 'Initial setup',
          userName: 'Inventory Staff',
        ),
      );
    }
    notifyListeners();
  }

  void updateProduct(Product product) {
    final index = _products.indexWhere((item) => item.id == product.id);
    if (index < 0) return;
    _products[index] = product;
    notifyListeners();
  }

  Product? _productForVariant(int variantId) {
    for (final product in _products) {
      if (product.variants.any((variant) => variant.id == variantId)) {
        return product;
      }
    }
    return null;
  }

  int _nextBatchId() =>
      _batches.fold<int>(0, (value, batch) => max(value, batch.id)) + 1;

  int _nextReceiptId() =>
      _batches.fold<int>(0, (value, batch) => max(value, batch.receiptId)) + 1;

  /// Deducts from the oldest batches first, stopping once the quantity is met.
  /// Mirrors `allocate_fifo`; every caller checks sufficiency before calling.
  void _deductFifo({required int variantId, required double quantity}) {
    var remaining = quantity;
    for (final batch in batchesFor(variantId)) {
      if (remaining <= 0) break;
      final take = min(batch.currentQty, remaining);
      if (take <= 0) continue;
      _replaceBatch(batch, currentQty: batch.currentQty - take);
      remaining -= take;
    }
  }

  /// Mirrors the addition branch of `apply_stock_adjustment`: the newest batch.
  void _addToNewestBatch({required int variantId, required double quantity}) {
    final newest = latestBatchFor(variantId);
    if (newest == null) {
      // An upward correction with no prior lot: the count is real but there is no
      // cost basis for it, so the lot carries the quantity at zero cost rather
      // than inventing a figure.
      _batches.add(
        InventoryBatch(
          id: _nextBatchId(),
          variantId: variantId,
          receiptId: _nextReceiptId(),
          initialQty: quantity,
          currentQty: quantity,
          unitCostLanded: 0,
          markupPercentage: 0,
          batchSellingPrice: 0,
          expirationDate: null,
          createdAt: null,
        ),
      );
      return;
    }
    _replaceBatch(newest, currentQty: newest.currentQty + quantity);
  }

  void _replaceBatch(InventoryBatch batch, {required double currentQty}) {
    final index = _batches.indexWhere((item) => item.id == batch.id);
    if (index < 0) return;
    _batches[index] = InventoryBatch(
      id: batch.id,
      variantId: batch.variantId,
      receiptId: batch.receiptId,
      initialQty: batch.initialQty,
      currentQty: currentQty,
      unitCostLanded: batch.unitCostLanded,
      markupPercentage: batch.markupPercentage,
      batchSellingPrice: batch.batchSellingPrice,
      expirationDate: batch.expirationDate,
      createdAt: batch.createdAt,
    );
  }

}
