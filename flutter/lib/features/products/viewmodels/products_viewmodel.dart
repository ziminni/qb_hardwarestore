import 'dart:math';

import 'package:client/data/models/product.dart';
import 'package:flutter/foundation.dart';

class ProductsViewmodel extends ChangeNotifier {
  ProductsViewmodel(List<Product> products)
    : _products = List<Product>.of(products);

  final List<Product> _products;
  final Set<int> _selectedProductIds = {};

  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedBrand;
  bool? _activeStatus;
  int _currentPage = 1;
  int _rowsPerPage = 5;

  List<Product> get products => List.unmodifiable(_products);
  Set<int> get selectedProductIds => Set.unmodifiable(_selectedProductIds);
  String get searchQuery => _searchQuery;
  String? get selectedCategory => _selectedCategory;
  String? get selectedBrand => _selectedBrand;
  bool? get activeStatus => _activeStatus;
  int get currentPage => _currentPage;
  int get rowsPerPage => _rowsPerPage;
  int get totalProducts => _products.length;
  int get activeProducts =>
      _products.where((product) => product.isActive).length;
  int get inactiveProducts => totalProducts - activeProducts;
  int get totalVariants =>
      _products.fold(0, (total, product) => total + product.variants.length);

  List<String> get categories =>
      (_products.map((product) => product.categoryName).toSet().toList()
        ..sort());

  List<String> get brands =>
      (_products.map((product) => product.brandName).toSet().toList()..sort());

  List<Product> get filteredProducts {
    final normalizedQuery = _searchQuery.trim().toLowerCase();

    return _products
        .where((product) {
          final matchesSearch =
              normalizedQuery.isEmpty ||
              product.baseName.toLowerCase().contains(normalizedQuery) ||
              product.description.toLowerCase().contains(normalizedQuery) ||
              product.categoryName.toLowerCase().contains(normalizedQuery) ||
              product.brandName.toLowerCase().contains(normalizedQuery) ||
              product.variants.any(
                (variant) =>
                    variant.variantName.toLowerCase().contains(normalizedQuery),
              );
          final matchesCategory =
              _selectedCategory == null ||
              product.categoryName == _selectedCategory;
          final matchesBrand =
              _selectedBrand == null || product.brandName == _selectedBrand;
          final matchesStatus =
              _activeStatus == null || product.isActive == _activeStatus;

          return matchesSearch &&
              matchesCategory &&
              matchesBrand &&
              matchesStatus;
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

  void setActiveStatus(bool? value) {
    _activeStatus = value;
    _resetPage();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategory = null;
    _selectedBrand = null;
    _activeStatus = null;
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

  void setSelectedProductsActive(bool isActive) {
    for (var index = 0; index < _products.length; index++) {
      final product = _products[index];
      if (_selectedProductIds.contains(product.id)) {
        _products[index] = product.copyWith(isActive: isActive);
      }
    }
    _selectedProductIds.clear();
    notifyListeners();
  }

  void addProduct(Product product) {
    final nextId = _products.isEmpty
        ? 1
        : _products.map((item) => item.id).reduce(max) + 1;
    _products.add(product.copyWith(id: nextId));
    notifyListeners();
  }

  void updateProduct(Product updatedProduct) {
    final index = _products.indexWhere(
      (product) => product.id == updatedProduct.id,
    );
    if (index == -1) return;
    _products[index] = updatedProduct;
    notifyListeners();
  }

  void toggleProductStatus(Product product) {
    updateProduct(product.copyWith(isActive: !product.isActive));
  }

  void _resetPage() {
    _currentPage = 1;
    _selectedProductIds.clear();
    notifyListeners();
  }
}
