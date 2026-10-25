import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/services/catalogue_service.dart';

/// The repository layer for categories, brands and units of measure.
///
/// Policy-free pass-through, keeping the one data path the map pins:
/// `View → ViewModel → Repository → Service → ApiClient`. The inventory
/// viewmodel owns when to reload; this class only forwards.
class CatalogueRepository {
  CatalogueRepository({CatalogueService? service})
    : _service = service ?? CatalogueService();

  final CatalogueService _service;

  Future<List<Category>> fetchCategories() => _service.fetchCategories();
  Future<List<Brand>> fetchBrands() => _service.fetchBrands();
  Future<List<UnitOfMeasure>> fetchUnits() => _service.fetchUnits();
  Future<int> createCategory(String name) => _service.createCategory(name);

  Future<void> patchCategory(int id, {String? name, bool? isActive}) =>
      _service.patchCategory(id, name: name, isActive: isActive);
}
