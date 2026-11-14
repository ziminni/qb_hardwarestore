import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/repositories/stock_transfer_repository.dart';
import 'package:client/data/repositories/storage_location_repository.dart';
import 'package:client/data/services/storage_location_service.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/services/stock_transfer_service.dart';
import 'package:flutter/foundation.dart';

/// What one record attempt produced: the slip the server numbered, or the
/// sentence it refused with. Never both.
///
/// A record so the dialog and the viewmodel can name the same shape without the
/// viewmodel importing a widget.
typedef StockTransferOutcome = ({StockTransfer? recorded, String? refusal});

/// The transfers screen's data (Phase 9 F3, decision 21 §3).
///
/// Screen-scoped and provided by its own page rather than registered in
/// `main.dart`: a slip list that outlived its screen would show yesterday's
/// moves as the shelf's current state.
class TransfersViewmodel extends ChangeNotifier {
  TransfersViewmodel({
    StockTransferRepository? repository,
    StorageLocationRepository? locations,
  }) : _repository = repository ?? StockTransferRepository(),
       _locations = locations ?? StorageLocationRepository();

  final StockTransferRepository _repository;
  final StorageLocationRepository _locations;

  List<StockTransfer> _transfers = const [];
  List<StorageLocation> _locations_ = const [];
  bool _isLoading = false;
  bool _isRecording = false;
  String? _loadError;
  String? _locationError;
  String? _actionError;

  /// The recorded slips, newest first (the server's own order; a slip recorded
  /// here joins the top).
  List<StockTransfer> get transfers => List.unmodifiable(_transfers);

  /// Every shelf the caller may see — an Admin also sees the deactivated ones,
  /// which stock can still be moved OUT of.
  List<StorageLocation> get locations => List.unmodifiable(_locations_);

  /// The shelves a transfer may END on: an inactive shelf refuses new stock
  /// (Design 11), and the server answers `INVALID_STORAGE_LOCATION` for it, so
  /// the picker does not offer one.
  List<StorageLocation> get activeLocations => List.unmodifiable([
    for (final row in _locations_)
      if (row.isActive) row,
  ]);

  bool get isLoading => _isLoading;

  /// The last slip read's failure. A failed read keeps the rows it already had:
  /// "no transfers" and "not loaded" are different facts about the shelves.
  String? get loadError => _loadError;

  /// Why the shelf list could not be read, or null. Kept APART from [loadError]
  /// on purpose: a screen that cannot name the shelves must say so rather than
  /// offer an empty picker that looks like a shop with no storage.
  String? get locationError => _locationError;

  /// The last refusal, in the server's own words; null when none.
  String? get actionError => _actionError;

  /// True while a transfer is on the wire. The dialog reads this to keep its
  /// button disabled — one click moves stock once.
  bool get isRecording => _isRecording;

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _locationError = null;
    notifyListeners();
    try {
      _transfers = await _repository.fetchAll();
    } on StockTransferServiceException catch (error) {
      // Deliberately NOT `_transfers = []`: see loadError.
      _loadError = error.message;
    }
    try {
      _locations_ = await _locations.fetchAll();
    } on StorageLocationServiceException catch (error) {
      _locations_ = const [];
      _locationError = error.message;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Records the transfer and returns the slip, or the refusal.
  ///
  /// A second call while the first is on the wire is refused HERE, without a
  /// request: the server would move the stock twice if it arrived twice, and a
  /// double click on a "Move stock" button is the ordinary way that happens.
  Future<StockTransferOutcome> record(StockTransferRequest request) async {
    if (_isRecording) {
      return (
        recorded: null,
        refusal:
            'Still recording the last transfer. Wait for its slip before '
            'sending another.',
      );
    }
    _isRecording = true;
    _actionError = null;
    notifyListeners();
    try {
      final recorded = await _repository.create(request);
      _transfers = [recorded, ..._transfers];
      return (recorded: recorded, refusal: null);
    } on StockTransferServiceException catch (error) {
      _actionError = error.message;
      return (recorded: null, refusal: error.message);
    } finally {
      _isRecording = false;
      notifyListeners();
    }
  }

  /// Drops a refusal so a reopened dialog starts clean.
  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }
}
