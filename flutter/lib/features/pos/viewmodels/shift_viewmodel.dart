import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:flutter/foundation.dart';

/// The cashier's shift behind the POS shell (Phase 4, decision 06).
///
/// Every sale is accounted for against a shift, and the server refuses a sale
/// with no open one. That makes the three states of [currentShift] different
/// answers the till must render differently:
///
/// * **An open shift** -> ring sales.
/// * **Null with no [loadError]** -> the cashier has none; show the prompt.
/// * **Null with a [loadError]** -> nobody knows; show the failure and a retry.
///
/// Collapsing the last two would tell a cashier with a live shift that they have
/// none, which is how a second shift gets opened on top of a real drawer.
class ShiftViewmodel extends ChangeNotifier {
  ShiftViewmodel({ShiftService? service})
    : _service = service ?? ShiftService();

  final ShiftService _service;

  Shift? _currentShift;
  Shift? get currentShift => _currentShift;

  List<Shift> _history = const [];
  List<Shift> get history => _history;

  bool isLoading = false;

  // Kept apart so a successful history load cannot hide a failed current-shift
  // load (or the reverse): the till gate reads [loadError], and an unrelated
  // success must never turn "unknown" into "no shift".
  String? _currentError;
  String? _historyError;

  /// Why the last load failed, or null. Non-null means "unknown", not "no
  /// shift".
  String? get loadError => _currentError ?? _historyError;

  /// Why the last CURRENT-shift read failed, or null.
  ///
  /// Exposed apart from [loadError] because the Shifts tab may only offer "open
  /// a shift" when the current-shift answer is a real "none" — a failed history
  /// load says nothing about whether a drawer is open, and a failed current load
  /// says nothing either way.
  String? get currentShiftError => _currentError;

  /// Why the last open/close failed, or null.
  String? actionError;

  bool get hasOpenShift => _currentShift?.isOpen ?? false;

  /// Reads the caller's open shift. Null from the service is the normal
  /// start-of-day answer, so it clears [loadError] rather than setting one.
  Future<void> loadCurrent() async {
    isLoading = true;
    notifyListeners();
    try {
      _currentShift = await _service.fetchCurrent();
      _currentError = null;
    } on ShiftServiceException catch (failure) {
      // Deliberately NOT `_currentShift = null`: a failed request says nothing
      // about the shift, and clearing it would hand this cashier the
      // open-a-shift prompt while the server still has one open for them.
      _currentError = failure.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// The shift list for the management tab.
  Future<void> loadHistory() async {
    isLoading = true;
    notifyListeners();
    try {
      _history = await _service.fetchAll();
      _historyError = null;
    } on ShiftServiceException catch (failure) {
      _historyError = failure.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the current shift and the history in one call, for the page that
  /// shows both.
  Future<void> load() async {
    await loadCurrent();
    await loadHistory();
  }

  /// Opens a shift with the counted drawer float.
  ///
  /// Returns the opened shift, or null after setting [actionError]. The current
  /// shift is set from the server's own copy: its id is what Close acts on.
  Future<Shift?> openShift(double openingFloat) async {
    actionError = null;
    try {
      final opened = await _service.openShift(openingFloat);
      _currentShift = opened;
      _history = [opened, ..._history];
      notifyListeners();
      return opened;
    } on ShiftServiceException catch (failure) {
      actionError = failure.message;
      notifyListeners();
      return null;
    }
  }

  /// Closes the current shift with the counted cash.
  ///
  /// Returns the closed shift — its [Shift.zReading] is what the cashier reads
  /// — or null after setting [actionError]. [currentShift] is cleared only on
  /// success: a failed close leaves the shift open on the server, so the till
  /// must keep showing it open.
  Future<Shift?> closeShift(double closingCount) async {
    final shift = _currentShift;
    if (shift == null) return null;

    actionError = null;
    try {
      final closed = await _service.closeShift(shift.id, closingCount);
      _currentShift = null;
      _history = [closed, ..._history.where((other) => other.id != closed.id)];
      notifyListeners();
      return closed;
    } on ShiftServiceException catch (failure) {
      actionError = failure.message;
      notifyListeners();
      return null;
    }
  }
}
