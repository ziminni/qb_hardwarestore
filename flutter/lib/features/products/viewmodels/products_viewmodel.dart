import 'dart:math';

import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
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
/// Phase 4 Task 4 removed the last of the in-memory writes: creating, editing and
/// archiving a product now POST/PATCH the server and reload. Each method returns
/// `null` on success or a message to show, so the page never announces a save
/// that the server refused.
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
  int get totalProducts => products.where((product) => product.isActive).length;
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

  /// Creates the catalog item on the server (product → variant → selling unit).
  ///
  /// Returns `null` on success, or the message to show. The store reloads either
  /// way — a chain that failed at step 2 leaves a product row behind, and hiding
  /// it would invite a duplicate retry.
  Future<String?> createProduct(NewProductDraft draft) =>
      _inventory.createProduct(draft);

  /// PATCHes the fields that changed. Returns `null` on success.
  Future<String?> editProduct(ProductEditDraft draft) =>
      _inventory.editProduct(draft);

  /// Archive (`false`) or restore (`true`). Never a delete — the route is 405.
  Future<String?> setProductActive(Product product, bool isActive) =>
      _inventory.setProductActive(product.id, isActive);

  /// Archives every selected product through the store, one PATCH each.
  ///
  /// The selection is cleared FIRST: the store notifies after every write, and a
  /// listener that re-enters this loop would archive the same row twice.
  Future<String?> archiveSelectedProducts() async {
    final selected = Set<int>.of(_selectedProductIds);
    _selectedProductIds.clear();
    notifyListeners();
    String? failure;
    for (final product in _inventory.products) {
      if (!selected.contains(product.id)) continue;
      final error = await _inventory.setProductActive(product.id, false);
      // Keep going: one refused row must not leave the rest selected and
      // un-archived. The first message is what the page shows.
      failure ??= error;
    }
    return failure;
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
