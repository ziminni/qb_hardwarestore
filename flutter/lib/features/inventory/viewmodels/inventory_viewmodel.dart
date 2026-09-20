import 'dart:math';

import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_mock_data.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

class InventoryViewmodel extends ChangeNotifier {
  InventoryViewmodel()
    : _categories = List.of(InventoryMockData.categories),
      _products = List.of(InventoryMockData.products) {
    _seedMovements();
  }

  final List<Category> _categories;
  final List<Product> _products;
  final List<InventoryMovement> _movements = [];

  List<Category> get categories => List.unmodifiable(_categories);
  List<Product> get products => List.unmodifiable(_products);
  List<InventoryMovement> get movements => List.unmodifiable(_movements);

  Iterable<({Product product, ProductVariant variant})> get stockRecords sync* {
    for (final product in _products) {
      for (final variant in product.variants) {
        yield (product: product, variant: variant);
      }
    }
  }

  InventoryStockStatus statusFor(ProductVariant variant) {
    if (variant.currentStock <= 0) return InventoryStockStatus.outOfStock;
    if (variant.currentStock <= variant.reorderLevel) {
      return InventoryStockStatus.lowStock;
    }
    return InventoryStockStatus.inStock;
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

  void adjustStock({
    required int variantId,
    required double newQuantity,
    required String reason,
    required String notes,
    required String userName,
  }) {
    final record = stockRecords.firstWhere(
      (record) => record.variant.id == variantId,
    );
    final previous = record.variant.currentStock;
    _replaceVariant(
      record.product,
      record.variant.copyWith(currentStock: newQuantity),
    );
    _movements.insert(
      0,
      InventoryMovement(
        id: _movements.length + 1,
        productId: record.product.id,
        variantId: variantId,
        timestamp: DateTime.now(),
        type: InventoryMovementType.stockAdjustment,
        quantityChange: newQuantity - previous,
        previousStock: previous,
        newStock: newQuantity,
        reference: 'ADJ-${(_movements.length + 1).toString().padLeft(4, '0')}',
        reason: notes.trim().isEmpty ? reason : '$reason — ${notes.trim()}',
        userName: userName,
      ),
    );
    notifyListeners();
  }

  void addProduct(Product product) {
    final id = _products.fold<int>(0, (value, item) => max(value, item.id)) + 1;
    _products.add(product.copyWith(id: id));
    for (final variant in product.variants.where(
      (item) => item.currentStock > 0,
    )) {
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
    notifyListeners();
  }

  void updateProduct(Product product) {
    final index = _products.indexWhere((item) => item.id == product.id);
    if (index < 0) return;
    _products[index] = product;
    notifyListeners();
  }

  void _replaceVariant(Product product, ProductVariant variant) {
    _products[_products.indexWhere((item) => item.id == product.id)] = product
        .copyWith(
          variants: product.variants
              .map((item) => item.id == variant.id ? variant : item)
              .toList(growable: false),
        );
  }

  void _seedMovements() {
    var id = 1;
    for (final record in stockRecords) {
      final current = record.variant.currentStock;
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
