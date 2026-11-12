import 'package:client/data/models/delivery.dart';
import 'package:client/data/services/delivery_service.dart';
import 'package:flutter/foundation.dart';

/// The deliveries screen's data: the schedule, and one status move at a time.
///
/// Screen-scoped and provided by its own page rather than registered in
/// `main.dart` (decision 11's ruling): a schedule that outlived its screen would
/// show yesterday's trips as still scheduled.
class DeliveriesViewmodel extends ChangeNotifier {
  DeliveriesViewmodel({DeliveryService? service})
    : _service = service ?? DeliveryService();

  final DeliveryService _service;

  List<Delivery> _deliveries = const [];
  bool _isLoading = false;
  String? _loadError;
  String? _actionError;

  /// Rows with a status move in flight. One move per slip, so a double click
  /// cannot post twice — the server's lock would answer 409, but there is no
  /// reason to spend a request finding that out.
  final Set<int> _moving = <int>{};

  List<Delivery> get deliveries => List.unmodifiable(_deliveries);
  bool get isLoading => _isLoading;

  /// The last read's failure. A failed refresh keeps the rows it already had:
  /// "no deliveries" and "not loaded" are different facts about the day.
  String? get loadError => _loadError;

  /// The last refusal, in the server's own words; null when none.
  String? get actionError => _actionError;

  /// True while [id]'s status move is on the wire. The row disables its buttons
  /// on this.
  bool isMoving(int id) => _moving.contains(id);

  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      _deliveries = await _service.fetchAll();
    } on DeliveryServiceException catch (error) {
      // Deliberately NOT `_deliveries = []`: see loadError.
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The rows the reader asked for: scheduled date first, then document number.
  ///
  /// The order is the point of the screen — it is a work queue, so today's trips
  /// come before next week's. The server already orders by `scheduled_date`; the
  /// tie-break keeps a refresh from shuffling same-day rows under a reader.
  List<Delivery> filtered({
    DeliveryStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    final rows = [
      for (final delivery in _deliveries)
        if ((status == null || delivery.status == status) &&
            (needle.isEmpty ||
                delivery.documentNo.toLowerCase().contains(needle) ||
                delivery.customerName.toLowerCase().contains(needle) ||
                delivery.contactName.toLowerCase().contains(needle) ||
                delivery.address.toLowerCase().contains(needle)) &&
            (dateFrom == null ||
                !delivery.scheduledDate.isBefore(_dayOf(dateFrom))) &&
            (dateTo == null || !delivery.scheduledDate.isAfter(_dayOf(dateTo))))
          delivery,
    ];
    rows.sort((a, b) {
      final byDate = a.scheduledDate.compareTo(b.scheduledDate);
      return byDate != 0 ? byDate : a.deliveryNo.compareTo(b.deliveryNo);
    });
    return rows;
  }

  /// Scheduled → out for delivery. Returns false (with [actionError]) on a
  /// refusal.
  Future<bool> start(int id) => _move(id, () => _service.start(id));

  /// Out for delivery → delivered. Terminal.
  Future<bool> deliver(int id) => _move(id, () => _service.deliver(id));

  /// Scheduled or out for delivery → failed. The reason is REQUIRED: the server
  /// refuses a bare failure, so it is refused here before a round trip.
  Future<bool> fail(int id, String reason) {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      _actionError =
          'A failed delivery needs a reason. Write why the goods '
          'did not land.';
      notifyListeners();
      return Future.value(false);
    }
    return _move(id, () => _service.fail(id, trimmed));
  }

  Future<bool> _move(int id, Future<Delivery> Function() action) async {
    if (_moving.contains(id)) return false;
    _moving.add(id);
    _actionError = null;
    notifyListeners();
    try {
      final updated = await action();
      _deliveries = [
        for (final delivery in _deliveries)
          delivery.id == id ? updated : delivery,
      ];
      return true;
    } on DeliveryServiceException catch (error) {
      _actionError = error.message;
      // A refused move means this screen's row is behind the server (someone
      // else moved it, or it was already delivered). Re-read so the buttons
      // match what the server holds instead of the stale row that was clicked.
      await _reload();
      return false;
    } finally {
      _moving.remove(id);
      notifyListeners();
    }
  }

  /// Re-reads the schedule after a refusal, keeping [actionError] on screen.
  Future<void> _reload() async {
    try {
      _deliveries = await _service.fetchAll();
      _loadError = null;
    } on DeliveryServiceException catch (error) {
      _loadError = error.message;
    }
  }

  /// Drops a refusal so a reopened dialog starts clean.
  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    notifyListeners();
  }

  static DateTime _dayOf(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
