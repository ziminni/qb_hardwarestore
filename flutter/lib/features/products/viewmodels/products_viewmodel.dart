import 'dart:math';

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter/foundation.dart';

/// View state for the products screen: search, category and brand filters,
/// sorting, paging and row selection. It owns **no product data**.
///
/// Decision 11. Before this, the class held a *copy* of the product list taken
/// at construction
///
/// ```dart
/// ProductsViewmodel(context.read<InventoryViewmodel>().products)
/// ```
///
/// and the page applied every mutation to both this and [InventoryViewmodel] —
/// each computing its own `max(id)+1`. Two lists, two id authorities, and a
/// table that could disagree with its own counters the moment a call site
/// forgot to mirror one. The list is now read live from the store and every
/// mutation is delegated to it, so there is one authority.
///
/// This mirrors `PosTransactionViewmodel`, which already took the live store and
/// listened to it — the correct pattern already existed one screen over.
///
/// NOT registered in `main.dart`, deliberately: this is per-screen view state,
/// and a single app-wide instance would share one search box, one page number
/// and one selection across every visit to the screen.
class ProductsViewmodel extends ChangeNotifier {
  ProductsViewmodel(this._inventory) {
    _inventory.addListener(_onStoreChanged);
  }

  final InventoryViewmodel _inventory;
  final Set<int> _selectedProductIds = {};

  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedBrand;
  int _currentPage = 1;
  int _rowsPerPage = 5;

  /// The store's list, live. Never a copy — see the class doc.
  List<Product> get products => _inventory.products;

  Set<int> get selectedProductIds => Set.unmodifiable(_selectedProductIds);
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String? get selectedBrand => _selectedBrand;
  int get currentPage => _currentPage;
  int get rowsPerPage => _rowsPerPage;
  int get totalProducts =>
      products.where((product) => product.isActive).length;
  int get archivedProducts =>
      products.where((product) => !product.isActive).length;
  int get totalVariants => products
      .where((product) => product.isActive)
      .fold(0, (total, product) => total + product.variants.length);

  List<String> get categories =>
      (products
          .where((product) => product.isActive)
          .map((product) => product.categoryName)
          .toSet()
          .toList()
        ..sort());

  List<String> get brands =>
      (products
          .where((product) => product.isActive)
          .map((product) => product.brandName)
          .toSet()
          .toList()
        ..sort());

  List<Product> get filteredProducts {
    final normalizedQuery = _searchQuery.trim().toLowerCase();

    return products
        .where((product) {
          final matchesSearch =
              normalizedQuery.isEmpty ||
              product.baseName.toLowerCase().contains(normalizedQuery) ||
              product.description.toLowerCase().contains(normalizedQuery) ||
              product.categoryName.toLowerCase().contains(normalizedQuery) ||
              product.brandName.toLowerCase().contains(normalizedQuery) ||
              product.variants.any(
                (variant) =>
                    variant.variantName.toLowerCase().contains(
                      normalizedQuery,
                    ) ||
                    variant.barcode.toLowerCase().contains(normalizedQuery),
              );
          final matchesCategory =
              _selectedCategory == null ||
              product.categoryName == _selectedCategory;
          final matchesBrand =
              _selectedBrand == null || product.brandName == _selectedBrand;
          return matchesSearch &&
              matchesCategory &&
              matchesBrand &&
              product.isActive;
        })
        .toList(growable: false);
  }

  int get totalPages => max(1, (filteredProducts.length / _rowsPerPage).ceil());

  List<Product> get visibleProducts {
    final start = (_currentPage - 1) * _rowsPerPage;
    final filtered = filteredProducts;
    if (start >= filtered.length) return const [];
    return filtered.sublist(start, min(start + _rowsPerPage, filtered.length));
  }

  int get firstVisibleItem =>
      filteredProducts.isEmpty ? 0 : ((_currentPage - 1) * _rowsPerPage) + 1;

  int get lastVisibleItem =>
      min(_currentPage * _rowsPerPage, filteredProducts.length);

  void setSearchQuery(String value) {
    _searchQuery = value;
    _resetPage();
  }

  void setCategory(String? value) {
    _selectedCategory = value;
    _resetPage();
  }

  void setBrand(String? value) {
    _selectedBrand = value;
    _resetPage();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategory = null;
    _selectedBrand = null;
    _resetPage();
  }

  void setRowsPerPage(int value) {
    _rowsPerPage = value;
    _resetPage();
  }

  void goToPage(int page) {
    _currentPage = page.clamp(1, totalPages);
    notifyListeners();
  }

  void toggleSelection(int productId, bool selected) {
    selected
        ? _selectedProductIds.add(productId)
        : _selectedProductIds.remove(productId);
    notifyListeners();
  }

  void selectVisibleProducts(bool selected) {
    for (final product in visibleProducts) {
      selected
          ? _selectedProductIds.add(product.id)
          : _selectedProductIds.remove(product.id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedProductIds.clear();
    notifyListeners();
  }

  /// Adds a product to the store, carrying the opening stock the form collected.
  ///
  /// Opening stock is a batch — "a lot at a cost" — so it is passed straight
  /// through to the store rather than kept here (decisions 02 and 11).
  void addProduct(
    Product product, {
    List<InventoryBatch> openingStock = const [],
  }) {
    _inventory.addProduct(product, openingStock: openingStock);
  }

  void updateProduct(Product updatedProduct) {
    _inventory.updateProduct(updatedProduct);
  }

  void archiveProduct(Product product) {
    _inventory.updateProduct(product.copyWith(isActive: false));
  }

  /// Archives every selected product through the store, then clears the
  /// selection. Clearing first means the store's per-product notifications
  /// cannot re-enter this loop.
  void archiveSelectedProducts() {
    final selected = Set<int>.of(_selectedProductIds);
    _selectedProductIds.clear();
    for (final product in _inventory.products) {
      if (selected.contains(product.id)) {
        _inventory.updateProduct(product.copyWith(isActive: false));
      }
    }
    notifyListeners();
  }

  void _onStoreChanged() => notifyListeners();

  @override
  void dispose() {
    _inventory.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _resetPage() {
    _currentPage = 1;
    _selectedProductIds.clear();
    notifyListeners();
  }
}
