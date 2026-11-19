import 'package:client/data/models/bodega.dart';
import 'package:client/data/repositories/bodega_repository.dart';
import 'package:client/data/services/bodega_service.dart';
import 'package:flutter/foundation.dart';

/// The Bodega Checker's data (decision 25).
///
/// The checker reads and confirms; it never moves stock itself. Screen-scoped:
/// each page provides its own and loads only what it shows.
class BodegaViewmodel extends ChangeNotifier {
  BodegaViewmodel({BodegaRepository? repository})
    : _repository = repository ?? BodegaRepository();

  final BodegaRepository _repository;

  List<BodegaStockRow> _stock = const [];
  List<BodegaClaim> _openClaims = const [];
  List<BodegaRelease> _releases = const [];
  List<BodegaDelivery> _deliveries = const [];
  BodegaClaim? _claim;

  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;
  String? _actionError;

  List<BodegaStockRow> get stock => List.unmodifiable(_stock);
  List<BodegaClaim> get openClaims => List.unmodifiable(_openClaims);
  List<BodegaRelease> get releases => List.unmodifiable(_releases);
  List<BodegaDelivery> get deliveries => List.unmodifiable(_deliveries);

  List<BodegaDelivery> get pendingDeliveries => [
    for (final delivery in _deliveries)
      if (delivery.isPending) delivery,
  ];

  List<BodegaDelivery> get checkedDeliveries => [
    for (final delivery in _deliveries)
      if (!delivery.isPending) delivery,
  ];

  /// The receipt the checker is releasing against, or null.
  BodegaClaim? get claim => _claim;

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get loadError => _loadError;
  String? get actionError => _actionError;

  Future<void> _load(Future<void> Function() body) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      await body();
    } on BodegaServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Receipts waiting at the gate, plus the deliveries count for the banner.
  Future<void> loadPickups() => _load(() async {
    _openClaims = await _repository.fetchClaims();
    _deliveries = await _repository.fetchDeliveries(status: 'PENDING');
  });

  /// The phone's Home and Arrivals: receipts waiting at the gate and every
  /// delivery (waiting ones first in [pendingDeliveries]).
  Future<void> loadHome() => _load(() async {
    _openClaims = await _repository.fetchClaims();
    _deliveries = await _repository.fetchDeliveries();
  });

  Future<void> loadDeliveries() => _load(() async {
    _deliveries = await _repository.fetchDeliveries();
  });

  Future<void> loadStock() => _load(() async {
    _stock = await _repository.fetchStock();
  });

  Future<void> loadHistory() => _load(() async {
    _releases = await _repository.fetchReleases();
    _deliveries = await _repository.fetchDeliveries(status: 'CHECKED');
  });

  List<BodegaClaim> _found = const [];
  String? _searchError;
  bool _searching = false;
  String _searched = '';

  /// The phone's Pick-ups search: every receipt matching the typed OR number,
  /// open or not (the screen shows the completed ones).
  List<BodegaClaim> get foundClaims => List.unmodifiable(_found);
  String? get searchError => _searchError;
  bool get isSearching => _searching;

  /// The query [foundClaims] answers; empty before the first search.
  String get searchedFor => _searched;

  Future<void> searchClaims(String query) async {
    final wanted = query.trim();
    _searched = wanted;
    _searchError = null;
    if (wanted.isEmpty) {
      _found = const [];
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    try {
      _found = await _repository.fetchClaims(openOnly: false, query: wanted);
    } on BodegaServiceException catch (error) {
      _found = const [];
      _searchError = error.message;
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }

  void closeClaim() {
    _claim = null;
    _actionError = null;
    notifyListeners();
  }

  /// Finds a receipt's claim by OR or transaction number (typed or scanned).
  Future<bool> lookup(String receipt) async {
    final wanted = receipt.trim();
    if (wanted.isEmpty) {
      _actionError = 'Scan the QR code on the receipt, or type its OR number.';
      notifyListeners();
      return false;
    }
    return _act(() async {
      _claim = await _repository.lookupClaim(wanted);
    });
  }

  /// Hands goods over against [claim]; the claim is re-read so the remaining
  /// figures are the server's.
  Future<BodegaRelease?> release(BodegaReleaseRequest request) async {
    BodegaRelease? recorded;
    final ok = await _act(() async {
      recorded = await _repository.release(request);
      _claim = await _repository.lookupClaim(request.receipt);
      _openClaims = await _repository.fetchClaims();
    });
    return ok ? recorded : null;
  }

  Future<BodegaDelivery?> confirmDelivery(
    int id,
    BodegaDeliveryConfirmation confirmation,
  ) async {
    BodegaDelivery? checked;
    final ok = await _act(() async {
      checked = await _repository.confirmDelivery(id, confirmation);
      _deliveries = [
        for (final delivery in _deliveries)
          delivery.id == id ? checked! : delivery,
      ];
    });
    return ok ? checked : null;
  }

  /// Attaches the checker's photo to one waiting line; the delivery is
  /// replaced with the server's copy, which carries the photo's URL.
  Future<bool> uploadLinePhoto(
    int deliveryId,
    int lineId,
    List<int> bytes, {
    String filename = 'item.jpg',
  }) => _act(() async {
    final updated = await _repository.uploadLinePhoto(
      deliveryId,
      lineId,
      bytes,
      filename: filename,
    );
    _deliveries = [
      for (final delivery in _deliveries)
        delivery.id == deliveryId ? updated : delivery,
    ];
  });

  /// One write at a time: a double tap must not hand goods over twice.
  Future<bool> _act(Future<void> Function() body) async {
    if (_isSaving) return false;
    _isSaving = true;
    _actionError = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on BodegaServiceException catch (error) {
      _actionError = error.message;
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
