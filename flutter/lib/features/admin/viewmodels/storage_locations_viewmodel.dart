import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/storage_location_repository.dart';
import 'package:client/data/services/storage_location_service.dart';
import 'package:flutter/foundation.dart';

/// The Admin storage-locations screen's data (Phase 5 F4, decision 18).
///
/// Screen-scoped and provided by its own page rather than registered in
/// `main.dart`: a list of the shop's places that outlived its screen would show
/// a location an Admin had just deactivated on the register next door.
///
/// **No delete.** The route answers 405 — a location a product still points at is
/// PROTECT-referenced — so deactivating is the exit and restoring is the same
/// PATCH with the other flag.
class StorageLocationsViewmodel extends ChangeNotifier {
  StorageLocationsViewmodel({StorageLocationRepository? repository})
    : _repository = repository ?? StorageLocationRepository();

  final StorageLocationRepository _repository;

  List<StorageLocation> _locations = const [];
  bool _isLoading = false;
  String? _loadError;
  String? _actionError;

  /// Rows with a write in flight. One write per location, so a double click
  /// cannot rename or deactivate twice.
  final Set<int> _busy = <int>{};

  /// True while the CREATE is on the wire, so the button cannot post twice.
  bool _isCreating = false;

  List<StorageLocation> get locations => List.unmodifiable(_locations);
  bool get isLoading => _isLoading;

  /// The last read's failure. A failed refresh keeps the rows it already had:
  /// "no locations" and "not loaded" are different facts about the shop.
  String? get loadError => _loadError;

  /// The last refusal, in the server's own words; null when none.
  String? get actionError => _actionError;

  bool get isCreating => _isCreating;
  bool isBusy(int id) => _busy.contains(id);

  /// Locations in the order the screen shows them: active first, then by name.
  ///
  /// The server orders A→Z; lifting the active rows above the deactivated ones is
  /// the screen's own decision, because the live places are what an Admin works
  /// with and the switched-off ones are what they occasionally restore.
  List<StorageLocation> get rows {
    final sorted = [..._locations];
    sorted.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  int get activeCount => _locations.where((row) => row.isActive).length;
  int get inactiveCount => _locations.length - activeCount;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      _locations = await _repository.fetchAll();
    } on StorageLocationServiceException catch (error) {
      // Deliberately NOT `_locations = []`: see [loadError].
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// True when [name] is already used by a DIFFERENT location, compared the way
  /// the server compares it (trimmed, case-insensitive).
  ///
  /// The server refuses the duplicate too; checking here means the clerk is told
  /// before a round trip, and the refusal still surfaces when two Admins race.
  bool nameTaken(String name, {int? excludingId}) {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return _locations.any(
      (row) => row.id != excludingId && row.name.trim().toLowerCase() == needle,
    );
  }

  /// Creates a location. Returns null on success, or the sentence to show.
  Future<String?> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name for the location.';
    if (nameTaken(trimmed)) return _duplicateSentence(trimmed);
    if (_isCreating) {
      // Item 13: null is the success value, so returning it made the page say
      // '"Yard" added.' for a location nobody added.
      return 'Still adding the previous location: wait for it to finish.';
    }
    _isCreating = true;
    _actionError = null;
    notifyListeners();
    try {
      final created = await _repository.create(trimmed);
      _locations = [..._locations, created];
      return null;
    } on StorageLocationServiceException catch (error) {
      _actionError = error.message;
      return error.message;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  /// Renames a location. Returns null on success, or the sentence to show.
  Future<String?> rename(StorageLocation location, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name for the location.';
    if (trimmed == location.name) return null;
    if (nameTaken(trimmed, excludingId: location.id)) {
      return _duplicateSentence(trimmed);
    }
    return _update(location, name: trimmed);
  }

  /// Hides a location from the picker (`isActive: false`), or brings it back.
  ///
  /// Products already assigned to it keep their label: the goods did not move.
  /// Only a NEW assignment is refused (`INVALID_STORAGE_LOCATION`).
  Future<String?> setActive(StorageLocation location, bool isActive) =>
      _update(location, isActive: isActive);

  void clearActionError() {
    _actionError = null;
    notifyListeners();
  }

  Future<String?> _update(
    StorageLocation location, {
    String? name,
    bool? isActive,
  }) async {
    if (_busy.contains(location.id)) return null;
    _busy.add(location.id);
    _actionError = null;
    notifyListeners();
    try {
      final updated = await _repository.patch(
        location.id,
        name: name,
        isActive: isActive,
      );
      _locations = [
        for (final row in _locations) row.id == updated.id ? updated : row,
      ];
      return null;
    } on StorageLocationServiceException catch (error) {
      _actionError = error.message;
      return error.message;
    } finally {
      _busy.remove(location.id);
      notifyListeners();
    }
  }

  String _duplicateSentence(String name) =>
      '"$name" is already a storage location. Two places with one name would '
      'show the same pick-up point twice.';
}
