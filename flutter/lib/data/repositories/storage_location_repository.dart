import 'package:client/data/models/storage_location.dart';
import 'package:client/data/services/storage_location_service.dart';

/// Policy-free pass-through over [StorageLocationService], keeping the one data
/// path `View → ViewModel → Repository → Service → ApiClient` (Phase 5 F4).
///
/// No filtering lives here: "only the active ones are offered in the product
/// form" is a screen decision a test can read, and hiding it in a pass-through
/// would put it where nobody looks.
class StorageLocationRepository {
  StorageLocationRepository({StorageLocationService? service})
    : _service = service ?? StorageLocationService();

  final StorageLocationService _service;

  Future<List<StorageLocation>> fetchAll() => _service.fetchAll();

  Future<StorageLocation> create(String name) => _service.create(name);

  Future<StorageLocation> patch(int id, {String? name, bool? isActive}) =>
      _service.patch(id, name: name, isActive: isActive);
}
