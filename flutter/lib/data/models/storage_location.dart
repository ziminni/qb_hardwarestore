import 'package:client/data/models/json_field.dart';

/// Where a product is kept — `GET /api/v1/storage-locations/` (Phase 5 B4/F4,
/// decision 18 "Bodega lite").
///
/// This is the SERVER's pick-up point: the till badges a line with it and the
/// receipt says "Pick up at Bodega". It is a label, not a stock ledger — nothing
/// counts stock per location and nothing transfers stock between them.
///
/// It is NOT `LocationHintStore`, which stays a device-only shelf note ("Rack
/// A-01") that no other till can see. The two are shown separately and never
/// merged.
class StorageLocation {
  const StorageLocation({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  final int id;
  final String name;

  /// Deactivating is the supported exit (the route answers 405 to DELETE). An
  /// inactive location keeps labelling the products already assigned to it;
  /// only NEW assignments are refused.
  final bool isActive;

  factory StorageLocation.fromJson(Map<String, dynamic> json) =>
      StorageLocation(
        id: intField(json, 'id'),
        name: stringField(json, 'name'),
        isActive: boolFieldOr(json, 'is_active', or: true),
      );

  @override
  String toString() => 'StorageLocation($id, $name, active=$isActive)';
}
