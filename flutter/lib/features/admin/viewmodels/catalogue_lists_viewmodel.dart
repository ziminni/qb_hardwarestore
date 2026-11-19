import 'package:client/data/models/category.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:flutter/foundation.dart' hide Category;

/// Admin → Settings: the shop's categories and suppliers (owner 2026-11-18).
///
/// These are the SAME server lists the product form, purchase orders and
/// receiving read, so an add, rename or archive here is what every other screen
/// offers next time it loads. Every write returns null on success or the
/// server's sentence (e.g. "Cement is used by 12 products…").
class CatalogueListsViewmodel extends ChangeNotifier {
  CatalogueListsViewmodel({
    CatalogueRepository? categories,
    SupplierRepository? suppliers,
  }) : _categories = categories ?? CatalogueRepository(),
       _suppliers = suppliers ?? SupplierRepository();

  final CatalogueRepository _categories;
  final SupplierRepository _suppliers;

  List<Category> _categoryRows = const [];
  List<Supplier> _supplierRows = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;

  List<Category> get categories => List.unmodifiable(_categoryRows);
  List<Supplier> get suppliers => List.unmodifiable(_supplierRows);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final categories = await _categories.fetchCategories();
      final suppliers = await _suppliers.fetchSuppliers();
      _categoryRows = [...categories]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _supplierRows = [...suppliers]
        ..sort(
          (a, b) => a.companyName.toLowerCase().compareTo(
            b.companyName.toLowerCase(),
          ),
        );
    } on CatalogueServiceException catch (error) {
      _loadError = error.message;
    } on SupplierServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// One write at a time, then a reload so the list is the server's.
  Future<String?> _write(Future<void> Function() body) async {
    if (_isSaving) return 'Still saving the last change.';
    _isSaving = true;
    notifyListeners();
    try {
      await body();
    } on CatalogueServiceException catch (error) {
      return error.message;
    } on SupplierServiceException catch (error) {
      return error.message;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
    await load();
    return null;
  }

  Future<String?> saveCategory({int? id, required String name}) => _write(
    () async => id == null
        ? await _categories.createCategory(name)
        : await _categories.patchCategory(id, name: name),
  );

  Future<String?> setCategoryActive(Category category, bool isActive) =>
      _write(() => _categories.patchCategory(category.id, isActive: isActive));

  Future<String?> deleteCategory(Category category) =>
      _write(() => _categories.deleteCategory(category.id));

  Future<String?> saveSupplier(Supplier supplier) {
    final body = {
      'company_name': supplier.companyName,
      'contact_person': supplier.contactPerson,
      'phone': supplier.phone,
      'email': supplier.email,
      'address': supplier.address,
      'terms_days': supplier.termsDays,
    };
    return _write(
      () async => supplier.id == 0
          ? await _suppliers.createSupplier(body)
          : await _suppliers.patchSupplier(supplier.id, body),
    );
  }

  Future<String?> setSupplierActive(Supplier supplier, bool isActive) => _write(
    () => _suppliers.patchSupplier(supplier.id, {'is_active': isActive}),
  );

  Future<String?> deleteSupplier(Supplier supplier) =>
      _write(() => _suppliers.deleteSupplier(supplier.id));
}
