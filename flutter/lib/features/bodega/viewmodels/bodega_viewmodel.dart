import 'dart:convert';

import 'package:client/core/sms/offline_sms_sender.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/data/repositories/bodega_repository.dart';
import 'package:client/data/services/bodega_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback signature for sending an offline release SMS reply.
typedef OfflineSmsReleaseSender =
    Future<OfflineSmsOutcome> Function({
      required String reference,
      required String smsCode,
      String receivedBy,
    });

/// The Bodega Checker's data (decision 25), with local snapshot caching and an
/// offline release outbox queue (`docs/offline-sync-design.md`).
///
/// The checker reads and confirms; it never moves stock itself. Screen-scoped:
/// each page provides its own and loads only what it shows.
class BodegaViewmodel extends ChangeNotifier {
  BodegaViewmodel({
    BodegaRepository? repository,
    OfflineSmsReleaseSender? smsSender,
  }) : _repository = repository ?? BodegaRepository(),
       _smsSender = smsSender ?? OfflineSmsSender.sendReleaseReply;

  static const cachedClaimsKey = 'bodega_offline_claims_v1';
  static const outboxKey = 'bodega_offline_outbox_v1';

  final BodegaRepository _repository;
  final OfflineSmsReleaseSender _smsSender;

  List<BodegaStockRow> _stock = const [];
  List<BodegaClaim> _openClaims = const [];
  List<BodegaClaim> _completedClaims = const [];
  List<BodegaRelease> _releases = const [];
  List<BodegaDelivery> _deliveries = const [];
  final Map<String, BodegaClaim> _cachedClaims = {};
  final List<BodegaReleaseRequest> _queuedReleases = [];
  BodegaClaim? _claim;

  bool _isLoading = false;
  bool _isSaving = false;
  bool _usingOfflineSnapshot = false;
  bool _lastLookupWasOfflineMiss = false;
  bool _cacheHydrated = false;
  int _keySequence = 0;
  String? _loadError;
  String? _actionError;
  String? _outboxNotice;

  List<BodegaStockRow> get stock => List.unmodifiable(_stock);
  List<BodegaClaim> get openClaims => List.unmodifiable(_openClaims);
  List<BodegaClaim> get completedClaims => List.unmodifiable(_completedClaims);
  List<BodegaRelease> get releases => List.unmodifiable(_releases);
  List<BodegaDelivery> get deliveries => List.unmodifiable(_deliveries);
  List<BodegaReleaseRequest> get queuedReleases =>
      List.unmodifiable(_queuedReleases);
  int get queuedReleaseCount => _queuedReleases.length;
  bool get usingOfflineSnapshot => _usingOfflineSnapshot;

  /// True when the last [lookup] failed because the phone is offline AND the
  /// scanned/typed receipt was not yet cached locally (e.g. rung after the
  /// phone went offline), so the UI can offer direct Offline SMS release.
  bool get lastLookupWasOfflineMiss => _lastLookupWasOfflineMiss;
  String? get outboxNotice => _outboxNotice;

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

  Future<void> _hydrateOfflineState() async {
    if (_cacheHydrated) return;
    _cacheHydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawClaims = prefs.getString(cachedClaimsKey);
      if (rawClaims != null && rawClaims.isNotEmpty) {
        final decoded = jsonDecode(rawClaims);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _storeClaimInMemory(BodegaClaim.fromJson(item));
            }
          }
        }
      }
      final rawOutbox = prefs.getString(outboxKey);
      if (rawOutbox != null && rawOutbox.isNotEmpty) {
        final decoded = jsonDecode(rawOutbox);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _queuedReleases.add(BodegaReleaseRequest.fromJson(item));
            }
          }
        }
      }
    } on Object {
      // In-memory cache still works in isolated tests without SharedPreferences.
    }
  }

  void _storeClaimInMemory(BodegaClaim claim) {
    final txnKey = claim.transactionNo.trim().toUpperCase();
    if (txnKey.isNotEmpty) {
      _cachedClaims[txnKey] = claim;
    }
    final orKey = claim.orNumber.trim().toUpperCase();
    if (orKey.isNotEmpty) {
      _cachedClaims[orKey] = claim;
    }
  }

  BodegaClaim? _findCachedClaim(String receipt) {
    final key = receipt.trim().toUpperCase();
    final direct = _cachedClaims[key];
    if (direct != null) return direct;
    for (final item in [..._openClaims, ..._completedClaims]) {
      if (item.transactionNo.trim().toUpperCase() == key ||
          item.orNumber.trim().toUpperCase() == key) {
        return item;
      }
    }
    return null;
  }

  Future<void> _persistClaimsCache(Iterable<BodegaClaim> claims) async {
    for (final item in claims) {
      _storeClaimInMemory(item);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final unique = <int, BodegaClaim>{
        for (final c in _cachedClaims.values) c.saleId: c,
      };
      await prefs.setString(
        cachedClaimsKey,
        jsonEncode([for (final c in unique.values) c.toJson()]),
      );
    } on Object {
      // Ignored when platform storage is unavailable.
    }
  }

  Future<void> _persistOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        outboxKey,
        jsonEncode([for (final q in _queuedReleases) q.toJson()]),
      );
    } on Object {
      // Ignored when platform storage is unavailable.
    }
  }

  String _nextIdempotencyKey(String receipt) {
    _keySequence++;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'bodega-$receipt-$stamp-$_keySequence';
  }

  /// Replays queued offline releases in FIFO order when connectivity returns.
  Future<int> syncOutbox() async {
    await _hydrateOfflineState();
    if (_queuedReleases.isEmpty) return 0;
    var synced = 0;
    final remaining = <BodegaReleaseRequest>[];
    for (var i = 0; i < _queuedReleases.length; i++) {
      final item = _queuedReleases[i];
      try {
        await _repository.release(item);
        synced++;
      } on BodegaServiceException catch (error) {
        if (error.isConnectionFailure) {
          remaining.addAll(_queuedReleases.sublist(i));
          break;
        }
        // Server rejected with a business error (e.g. already released via SMS):
        // drop from queue and surface the server's message for review.
        _outboxNotice = '${item.receipt}: ${error.message}';
      }
    }
    _queuedReleases
      ..clear()
      ..addAll(remaining);
    await _persistOutbox();
    if (synced > 0 && _queuedReleases.isEmpty) {
      _usingOfflineSnapshot = false;
    }
    notifyListeners();
    return synced;
  }

  Future<void> _load(
    Future<void> Function() body, {
    bool fallbackToCachedClaims = false,
  }) async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      await _hydrateOfflineState();
      await body();
    } on BodegaServiceException catch (error) {
      if (fallbackToCachedClaims && error.isConnectionFailure) {
        final cachedOpen = <int, BodegaClaim>{
          for (final c in _cachedClaims.values)
            if (c.isOpen) c.saleId: c,
        };
        if (cachedOpen.isNotEmpty || _openClaims.isNotEmpty) {
          if (_openClaims.isEmpty) {
            _openClaims = cachedOpen.values.toList();
          }
          _usingOfflineSnapshot = true;
          _loadError = null;
          return;
        }
      }
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Receipts waiting at the gate, plus accomplished ones and pending deliveries.
  Future<void> loadPickups() => _load(() async {
    await syncOutbox();
    final all = await _repository.fetchClaims(openOnly: false);
    _openClaims = [for (final c in all) if (c.isOpen) c];
    _completedClaims = [for (final c in all) if (!c.isOpen) c];
    _usingOfflineSnapshot = false;
    await _persistClaimsCache(all);
    _deliveries = await _repository.fetchDeliveries(status: 'PENDING');
  }, fallbackToCachedClaims: true);

  /// The phone's Home and Arrivals: receipts waiting at the gate, accomplished
  /// pick-ups, and every delivery (waiting ones first in [pendingDeliveries]).
  Future<void> loadHome() => _load(() async {
    await syncOutbox();
    final all = await _repository.fetchClaims(openOnly: false);
    _openClaims = [for (final c in all) if (c.isOpen) c];
    _completedClaims = [for (final c in all) if (!c.isOpen) c];
    _usingOfflineSnapshot = false;
    await _persistClaimsCache(all);
    _deliveries = await _repository.fetchDeliveries();
  }, fallbackToCachedClaims: true);

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
      await _hydrateOfflineState();
      _found = await _repository.fetchClaims(openOnly: false, query: wanted);
      await _persistClaimsCache(_found);
    } on BodegaServiceException catch (error) {
      if (error.isConnectionFailure) {
        final cached = _findCachedClaim(wanted);
        if (cached != null) {
          _found = [cached];
          _usingOfflineSnapshot = true;
          return;
        }
      }
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
  /// Falls back to the cached pick-up snapshot when the phone is in a Wi-Fi dead zone.
  Future<bool> lookup(String receipt) async {
    final wanted = receipt.trim();
    _lastLookupWasOfflineMiss = false;
    if (wanted.isEmpty) {
      _actionError =
          'Scan the QR code on the Order Slip, or type its OS number.';
      notifyListeners();
      return false;
    }
    await _hydrateOfflineState();
    if (_isSaving) return false;
    _isSaving = true;
    _actionError = null;
    notifyListeners();
    try {
      final fetched = await _repository.lookupClaim(wanted);
      _claim = fetched;
      _usingOfflineSnapshot = false;
      await _persistClaimsCache([fetched]);
      return true;
    } on BodegaServiceException catch (error) {
      if (error.isConnectionFailure) {
        final cached = _findCachedClaim(wanted);
        if (cached != null) {
          _claim = cached;
          _usingOfflineSnapshot = true;
          return true;
        }
        _usingOfflineSnapshot = true;
        _lastLookupWasOfflineMiss = true;
      }
      _actionError = error.message;
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Sends a direct offline SMS release reply (`DONE <receipt> <4-digit-code>`)
  /// for a scanned/typed receipt that was created while the phone was already
  /// offline (not yet in local cache).
  Future<OfflineSmsOutcome> sendOfflineSmsRelease({
    required String receipt,
    required String smsCode,
    String receivedBy = '',
  }) async {
    final outcome = await _smsSender(
      reference: receipt.trim(),
      smsCode: smsCode.trim(),
      receivedBy: receivedBy.trim(),
    );
    _outboxNotice = switch (outcome) {
      OfflineSmsOutcome.sent =>
        'Offline: sent automatic SMS confirmation (${receipt.trim()}) to store.',
      OfflineSmsOutcome.composer =>
        'Offline: opened SMS app with pre-filled reply — tap Send.',
      OfflineSmsOutcome.skipped =>
        'Store SMS number is not configured on this build. Reply manually: '
            '${OfflineSmsSender.buildReleaseBody(reference: receipt, smsCode: smsCode, receivedBy: receivedBy)}',
      OfflineSmsOutcome.failed =>
        'Could not send SMS automatically. Reply manually: '
            '${OfflineSmsSender.buildReleaseBody(reference: receipt, smsCode: smsCode, receivedBy: receivedBy)}',
    };
    notifyListeners();
    return outcome;
  }

  BodegaClaim _applyOptimisticRelease(
    BodegaClaim current,
    BodegaReleaseRequest request,
    BodegaRelease queuedRelease,
  ) {
    final byKey = <String, double>{
      for (final item in request.lines)
        '${item.variantId}.${item.locationId}': item.qty,
    };
    final updatedLines = <BodegaClaimLine>[
      for (final line in current.lines)
        () {
          final delta = byKey['${line.variantId}.${line.locationId}'] ?? 0;
          final nextRemaining = (line.remaining - delta)
              .clamp(0, double.infinity)
              .toDouble();
          return BodegaClaimLine(
            variantId: line.variantId,
            label: line.label,
            unit: line.unit,
            locationId: line.locationId,
            locationName: line.locationName,
            sold: line.sold,
            released: line.released + delta,
            remaining: nextRemaining,
          );
        }(),
    ];
    final nextTotal = updatedLines.fold<double>(
      0,
      (sum, line) => sum + line.remaining,
    );
    return BodegaClaim(
      saleId: current.saleId,
      transactionNo: current.transactionNo,
      orNumber: current.orNumber,
      customerName: current.customerName,
      soldAt: current.soldAt,
      isOpen: nextTotal > 0,
      remainingTotal: nextTotal,
      lines: updatedLines,
      releases: [queuedRelease, ...current.releases],
      smsCode: current.smsCode,
    );
  }

  /// Hands goods over against [claim]; the claim is re-read so the remaining
  /// figures are the server's. When the phone is offline in the warehouse,
  /// queues the release with an `Idempotency-Key` and updates the local snapshot.
  Future<BodegaRelease?> release(BodegaReleaseRequest request) async {
    await _hydrateOfflineState();
    final withKey = request.idempotencyKey.isEmpty
        ? request.withIdempotencyKey(_nextIdempotencyKey(request.receipt))
        : request;
    if (_isSaving) return null;
    _isSaving = true;
    _actionError = null;
    notifyListeners();
    try {
      final recorded = await _repository.release(withKey);
      _claim = await _repository.lookupClaim(withKey.receipt);
      _openClaims = await _repository.fetchClaims();
      _usingOfflineSnapshot = false;
      await _persistClaimsCache([?_claim, ..._openClaims]);
      return recorded;
    } on BodegaServiceException catch (error) {
      if (error.isConnectionFailure) {
        _queuedReleases.add(withKey);
        await _persistOutbox();
        _usingOfflineSnapshot = true;
        final current = _claim ?? _findCachedClaim(withKey.receipt);
        final queued = BodegaRelease(
          id: 0,
          number: 'QUEUED-OFFLINE',
          transactionNo: current?.transactionNo ?? withKey.receipt,
          customerName: current?.customerName ?? '',
          checkerName: '',
          receivedBy: withKey.receivedBy,
          plateNo: withKey.plateNo,
          notes: withKey.notes,
          createdAt: DateTime.now(),
          lines: [
            for (final item in withKey.lines)
              () {
                BodegaClaimLine? match;
                if (current != null) {
                  for (final line in current.lines) {
                    if (line.variantId == item.variantId &&
                        line.locationId == item.locationId) {
                      match = line;
                      break;
                    }
                  }
                }
                return BodegaReleaseLine(
                  variantId: item.variantId,
                  label: match?.label ?? 'Item #${item.variantId}',
                  unit: match?.unit ?? 'PC',
                  locationName: match?.locationName ?? 'Bodega',
                  qty: item.qty,
                );
              }(),
          ],
        );
        if (current != null) {
          final updated = _applyOptimisticRelease(current, withKey, queued);
          _claim = updated;
          _openClaims = [
            for (final c in _openClaims)
              if (c.saleId != updated.saleId)
                c
              else if (updated.isOpen)
                updated,
          ];
          await _persistClaimsCache([updated]);
        }
        // Offline SMS fallback (Option B direct Android SMS -> Option A pre-filled composer):
        // automatically notifies the store's SIM800C USB modem with zero manual typing.
        final ref = (current?.orNumber.isNotEmpty ?? false)
            ? current!.orNumber
            : (current?.transactionNo ?? withKey.receipt);
        final smsCode = current?.smsCode ?? '';
        if (smsCode.isNotEmpty) {
          final outcome = await _smsSender(
            reference: ref,
            smsCode: smsCode,
            receivedBy: withKey.receivedBy,
          );
          if (outcome == OfflineSmsOutcome.sent) {
            _outboxNotice =
                'Offline: sent automatic SMS confirmation ($ref) to store.';
          } else if (outcome == OfflineSmsOutcome.composer) {
            _outboxNotice =
                'Offline: opened SMS app with pre-filled reply — tap Send.';
          } else if (outcome == OfflineSmsOutcome.skipped) {
            _outboxNotice =
                'Queued offline. Set Store SMS number in Server Settings for automatic SMS fallback.';
          } else {
            _outboxNotice =
                'Queued offline (SMS send failed — will sync when online).';
          }
        } else {
          _outboxNotice =
              'Queued offline (refresh pick-ups while online to cache SMS code).';
        }
        return queued;
      }
      _actionError = error.message;
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
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
