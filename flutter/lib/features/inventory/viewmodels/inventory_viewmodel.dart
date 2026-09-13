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
      _movements.add(
        InventoryMovement(
          id: id++,
          productId: record.product.id,
          variantId: record.variant.id,
          timestamp: DateTime(2026, 9, 10, 8, record.variant.id),
          type: InventoryMovementType.initialStock,
          quantityChange: current,
          previousStock: 0,
          newStock: current,
          reference: 'INITIAL',
          reason: 'Initial setup',
          userName: 'Admin',
        ),
      );
      if (record.variant.id <= 4) {
        _movements.addAll([
          InventoryMovement(
            id: id++,
            productId: record.product.id,
            variantId: record.variant.id,
            timestamp: DateTime(2026, 9, 11, 9, record.variant.id),
            type: InventoryMovementType.purchaseReceipt,
            quantityChange: 10,
            previousStock: current,
            newStock: current + 10,
            reference: 'PO-${record.variant.id.toString().padLeft(4, '0')}',
            reason: 'Supplier delivery',
            userName: 'Inventory Staff',
          ),
          InventoryMovement(
            id: id++,
            productId: record.product.id,
            variantId: record.variant.id,
            timestamp: DateTime(2026, 9, 12, 14, record.variant.id),
            type: InventoryMovementType.sale,
            quantityChange: -10,
            previousStock: current + 10,
            newStock: current,
            reference:
                'SALE-${(50 + record.variant.id).toString().padLeft(4, '0')}',
            reason: 'POS sale',
            userName: 'Sales Staff',
          ),
        ]);
      }
    }
    _movements.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }
}
