import 'dart:math';

import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/catalogue_assembler.dart';
import 'package:client/data/services/location_hint_store.dart';
import 'package:client/features/inventory/viewmodels/inventory_mock_data.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

class InventoryViewmodel extends ChangeNotifier {
  InventoryViewmodel()
    : _categories = List.of(InventoryMockData.categories),
      _products = List.of(InventoryMockData.products),
      _batches = List.of(InventoryMockData.batches) {
    _seedMovements();
    // Deliberately no `loadLocationHints()` here: the constructor stays free of
    // side effects reaching platform storage, so a viewmodel can be built in a
    // plain test. The app loads the hints once at startup (see `main.dart`), and
    // until then `locationHintFor` honestly reads as "unknown".
  }

  final List<Category> _categories;
  final List<Product> _products;

  /// Where stock actually lives (decision 02). Every quantity question is
  /// answered from here, never from a field on the variant.
  final List<InventoryBatch> _batches;

  final List<InventoryMovement> _movements = [];

  final LocationHintStore _locationHintStore = LocationHintStore();
  Map<int, String> _locationHints = const {};

  List<Category> get categories => List.unmodifiable(_categories);
  List<Product> get products => List.unmodifiable(_products);
  List<InventoryMovement> get movements => List.unmodifiable(_movements);

  /// A variant's batches, oldest delivery first — the order FIFO deducts in.
  ///
  /// Ordered by `receiptId`, which is the client's only non-null date proxy:
  /// every mock batch was materialised with `createdAt: null`, so ordering by
  /// date is impossible here even though the live API populates it.
  List<InventoryBatch> batchesFor(int variantId) {
    final rows = _batches
        .where((batch) => batch.variantId == variantId)
        .toList()
      ..sort((a, b) {
        final byReceipt = a.receiptId.compareTo(b.receiptId);
        return byReceipt != 0 ? byReceipt : a.id.compareTo(b.id);
      });
    return List.unmodifiable(rows);
  }

  /// Stock on hand for a variant — the sum of its batches.
  double stockOnHandFor(int variantId) => batchesFor(
    variantId,
  ).fold(0, (sum, batch) => sum + batch.currentQty);

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
  String barcodeFor(int variantId) {
    final uoms = variantFor(variantId)?.sellingUoms ?? const <VariantUom>[];
    for (final uom in uoms) {
      if (uom.barcodeQr.isNotEmpty) return uom.barcodeQr;
    }
    return '';
  }

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

  /// Low-stock status derived from the **batch** total, so it keeps working once
  /// the legacy `currentStock` field is deleted in step 4.
  InventoryStockStatus statusForVariant(int variantId) {
    final stock = stockOnHandFor(variantId);
    if (stock <= 0) return InventoryStockStatus.outOfStock;
    final threshold = variantFor(variantId)?.minStockThreshold ?? 0;
    if (stock <= threshold) return InventoryStockStatus.lowStock;
    return InventoryStockStatus.inStock;
  }

  /// Transitional overload for readers not yet migrated. Delegates to the
  /// batch-derived status so there is one source of truth for the rule.
  InventoryStockStatus statusFor(ProductVariant variant) {
    return statusForVariant(variant.id);
  }

  int productCountForCategory(int categoryId) =>
      _products.where((product) => product.categoryId == categoryId).length;

  List<Product> productsForCategory(int categoryId) => _products
      .where((product) => product.categoryId == categoryId)
      .toList(growable: false);

  List<InventoryMovement> movementsForVariant(int variantId) => _movements
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
    final delta = newQuantity - previous;
    if (delta == 0) return;

    if (delta < 0) {
      _deductFifo(variantId: variantId, quantity: -delta);
    } else {
      _addToNewestBatch(variantId: variantId, quantity: delta);
    }
    _syncLegacyStock();

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
    _syncLegacyStock();

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

  /// Adds a product and creates one opening batch per variant that arrives with
  /// stock — a batch is exactly "a lot at a cost", so the form's quantity and
  /// cost become real entities here instead of a number on the variant.
  ///
  /// Transitional: the quantity and cost are still read off the legacy
  /// `currentStock`/`costPrice` fields, which step 4 deletes. The products form is
  /// migrated onto explicit opening stock before then; if it is not, step 4 fails
  /// to compile rather than letting this silently write wrong stock.
  void addProduct(Product product) {
    final id = _products.fold<int>(0, (value, item) => max(value, item.id)) + 1;
    final stored = product.copyWith(id: id);
    _products.add(stored);

    for (final variant in stored.variants.where(
      (item) => item.currentStock > 0,
    )) {
      _batches.add(
        InventoryBatch(
          id: _nextBatchId(),
          variantId: variant.id,
          receiptId: _nextReceiptId(),
          initialQty: variant.currentStock,
          currentQty: variant.currentStock,
          unitCostLanded: variant.costPrice,
          markupPercentage: 0,
          batchSellingPrice: variant.sellingPrice,
          expirationDate: null,
          createdAt: null,
        ),
      );
      _movements.insert(
        0,
        InventoryMovement(
          id: _movements.length + 1,
          productId: id,
          variantId: variant.id,
          timestamp: DateTime.now(),
          type: InventoryMovementType.initialStock,
          quantityChange: variant.currentStock,
          previousStock: 0,
          newStock: variant.currentStock,
          reference: 'INITIAL',
          reason: 'Initial setup',
          userName: 'Inventory Staff',
        ),
      );
    }
    _syncLegacyStock();
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

  /// Transitional mirror: keeps the legacy `currentStock` equal to the batch
  /// total, so readers not yet migrated onto `CatalogueItem` are never shown a
  /// stale number. Deleted in step 4 along with the field itself.
  void _syncLegacyStock() {
    for (var i = 0; i < _products.length; i++) {
      final product = _products[i];
      _products[i] = product.copyWith(
        variants: product.variants
            .map(
              (variant) => variant.copyWith(
                currentStock: stockOnHandFor(variant.id),
              ),
            )
            .toList(growable: false),
      );
    }
  }

  void _seedMovements() {
    var id = 1;
    for (final record in stockRecords) {
      final current = stockOnHandFor(record.variant.id);
      final opening = max(current - 5, 0).toDouble();
      final received = 10.0;
      final sold = opening + received - current;
      _movements.add(
        InventoryMovement(
          id: id++,
          productId: record.product.id,
          variantId: record.variant.id,
          timestamp: DateTime(2026, 9, 1, 8, record.variant.id),
          type: InventoryMovementType.initialStock,
          quantityChange: opening,
          previousStock: 0,
          newStock: opening,
          reference: 'INITIAL',
          reason: 'Initial setup',
          userName: 'Admin',
          source: 'Opening inventory',
        ),
      );
      _movements.addAll([
        InventoryMovement(
          id: id++,
          productId: record.product.id,
          variantId: record.variant.id,
          timestamp: DateTime(2026, 9, 5, 9, record.variant.id),
          type: InventoryMovementType.purchaseReceipt,
          quantityChange: received,
          previousStock: opening,
          newStock: opening + received,
          reference: 'PO-${record.variant.id.toString().padLeft(4, '0')}',
          reason: 'Supplier delivery received',
          userName: 'Inventory Staff',
          source: 'Purchase',
        ),
        InventoryMovement(
          id: id++,
          productId: record.product.id,
          variantId: record.variant.id,
          timestamp: DateTime(2026, 9, 10, 14, record.variant.id),
          type: InventoryMovementType.sale,
          quantityChange: -sold,
          previousStock: opening + received,
          newStock: current,
          reference:
              'SALE-${(50 + record.variant.id).toString().padLeft(4, '0')}',
          reason: 'POS sale',
          userName: 'Sales Staff',
          source: 'Sale',
        ),
      ]);
    }
    _seedDemonstrationMovements(id);
    _movements.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  void _seedDemonstrationMovements(int startingId) {
    var id = startingId;
    void add({
      required int variantId,
      required InventoryMovementType type,
      required double change,
      required double before,
      required DateTime timestamp,
      required String reference,
      required String reason,
      required String source,
      String? unit,
      InventoryMovementPhysicalDetail? detail,
    }) {
      final product = _products.firstWhere(
        (item) => item.variants.any((variant) => variant.id == variantId),
      );
      _movements.add(
        InventoryMovement(
          id: id++,
          productId: product.id,
          variantId: variantId,
          timestamp: timestamp,
          type: type,
          quantityChange: change,
          previousStock: before,
          newStock: before + change,
          reference: reference,
          reason: reason,
          userName: 'Inventory Staff',
          source: source,
          unit: unit,
          physicalDetail: detail,
        ),
      );
    }

    add(
      variantId: 1,
      type: InventoryMovementType.customerReturn,
      change: 1.5,
      before: 130,
      timestamp: DateTime(2026, 9, 14, 10, 20),
      reference: 'RET-0007',
      reason: 'Unopened material returned and restocked',
      source: 'Customer Return',
    );
    add(
      variantId: 1,
      type: InventoryMovementType.sale,
      change: -1.5,
      before: 131.5,
      timestamp: DateTime(2026, 9, 15, 11, 5),
      reference: 'SALE-0088',
      reason: 'Partial package sale',
      source: 'Sale',
      detail: const InventoryMovementPhysicalDetail(
        packageDescription: '40 kg bag',
        packageEffect:
            '1 sealed bag and 20 kg from an opened bag; 20 kg remains',
      ),
    );
    add(
      variantId: 3,
      type: InventoryMovementType.stockAdjustment,
      change: 3,
      before: 97,
      timestamp: DateTime(2026, 9, 16, 8, 30),
      reference: 'ADJ-0021',
      reason: 'Physical count correction',
      source: 'Stock Adjustment',
      unit: 'm',
    );
    add(
      variantId: 3,
      type: InventoryMovementType.sale,
      change: -3,
      before: 100,
      timestamp: DateTime(2026, 9, 16, 13, 20),
      reference: 'SALE-0091',
      reason: 'Sale / Cut',
      source: 'Sale',
      unit: 'm',
      detail: const InventoryMovementPhysicalDetail(
        sourcePiece: 10,
        remainingPiece: 7,
      ),
    );
    add(
      variantId: 19,
      type: InventoryMovementType.stockAdjustment,
      change: 2.5,
      before: 122.5,
      timestamp: DateTime(2026, 9, 17, 9),
      reference: 'ADJ-0022',
      reason: 'Physical count correction',
      source: 'Stock Adjustment',
      unit: 'kg',
    );
    add(
      variantId: 19,
      type: InventoryMovementType.stockAdjustment,
      change: -2.5,
      before: 125,
      timestamp: DateTime(2026, 9, 18, 15),
      reference: 'ADJ-0023',
      reason: 'Damaged stock',
      source: 'Stock Adjustment',
      unit: 'kg',
    );
    add(
      variantId: 18,
      type: InventoryMovementType.supplierReturn,
      change: -2,
      before: 16,
      timestamp: DateTime(2026, 9, 18, 16),
      reference: 'SRET-0003',
      reason: 'Defective tools returned to supplier',
      source: 'Supplier Return',
    );
    add(
      variantId: 18,
      type: InventoryMovementType.purchaseReceipt,
      change: 2,
      before: 14,
      timestamp: DateTime(2026, 9, 19, 9),
      reference: 'PO-REPLACE-0003',
      reason: 'Supplier replacement received',
      source: 'Purchase',
    );
  }
}
