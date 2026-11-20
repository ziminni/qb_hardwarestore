import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto-print behavior after completing a POS sale.
enum PosAutoPrintMode {
  always('always', 'Always print automatically'),
  ask('ask', 'Ask before printing'),
  off('off', 'Off (manual print only)');

  const PosAutoPrintMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static PosAutoPrintMode fromStorage(String? value) {
    for (final mode in PosAutoPrintMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return PosAutoPrintMode.ask;
  }
}

/// Default fulfillment mode when opening a new POS transaction.
enum PosDefaultFulfillment {
  walkIn('walk_in', 'Walk-in'),
  delivery('delivery', 'Delivery');

  const PosDefaultFulfillment(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static PosDefaultFulfillment fromStorage(String? value) {
    for (final mode in PosDefaultFulfillment.values) {
      if (mode.storageValue == value) return mode;
    }
    return PosDefaultFulfillment.walkIn;
  }
}

/// Persists counter-level POS checkout, printing, and register preferences.
class PosTillSettingsController extends ChangeNotifier {
  PosTillSettingsController();

  static final PosTillSettingsController instance =
      PosTillSettingsController();

  static const String autoPrintKey = 'pos.auto_print_mode';
  static const String receiptCopiesKey = 'pos.receipt_copies';
  static const String openDrawerKey = 'pos.auto_open_cash_drawer';
  static const String autoAddScanKey = 'pos.auto_add_on_scan';
  static const String refocusSearchKey = 'pos.auto_refocus_search';
  static const String soundFeedbackKey = 'pos.sound_feedback';
  static const String defaultFulfillmentKey = 'pos.default_fulfillment';

  PosAutoPrintMode _autoPrintMode = PosAutoPrintMode.ask;
  int _receiptCopies = 1;
  bool _autoOpenCashDrawer = false;
  bool _autoAddOnScan = true;
  bool _autoRefocusSearch = true;
  bool _soundFeedback = true;
  PosDefaultFulfillment _defaultFulfillment = PosDefaultFulfillment.walkIn;
  bool _loaded = false;

  PosAutoPrintMode get autoPrintMode => _autoPrintMode;
  int get receiptCopies => _receiptCopies;
  bool get autoOpenCashDrawer => _autoOpenCashDrawer;
  bool get autoAddOnScan => _autoAddOnScan;
  bool get autoRefocusSearch => _autoRefocusSearch;
  bool get soundFeedback => _soundFeedback;
  PosDefaultFulfillment get defaultFulfillment => _defaultFulfillment;

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nextPrint = PosAutoPrintMode.fromStorage(
        prefs.getString(autoPrintKey),
      );
      final nextCopies = (prefs.getInt(receiptCopiesKey) ?? 1) == 2 ? 2 : 1;
      final nextDrawer = prefs.getBool(openDrawerKey) ?? false;
      final nextAutoAdd = prefs.getBool(autoAddScanKey) ?? true;
      final nextRefocus = prefs.getBool(refocusSearchKey) ?? true;
      final nextSound = prefs.getBool(soundFeedbackKey) ?? true;
      final nextFulfillment = PosDefaultFulfillment.fromStorage(
        prefs.getString(defaultFulfillmentKey),
      );

      if (nextPrint != _autoPrintMode ||
          nextCopies != _receiptCopies ||
          nextDrawer != _autoOpenCashDrawer ||
          nextAutoAdd != _autoAddOnScan ||
          nextRefocus != _autoRefocusSearch ||
          nextSound != _soundFeedback ||
          nextFulfillment != _defaultFulfillment) {
        _autoPrintMode = nextPrint;
        _receiptCopies = nextCopies;
        _autoOpenCashDrawer = nextDrawer;
        _autoAddOnScan = nextAutoAdd;
        _autoRefocusSearch = nextRefocus;
        _soundFeedback = nextSound;
        _defaultFulfillment = nextFulfillment;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setAutoPrintMode(PosAutoPrintMode mode) async {
    if (_autoPrintMode == mode) return;
    _autoPrintMode = mode;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(autoPrintKey, mode.storageValue));
  }

  Future<void> setReceiptCopies(int copies) async {
    final normalized = copies == 2 ? 2 : 1;
    if (_receiptCopies == normalized) return;
    _receiptCopies = normalized;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setInt(receiptCopiesKey, normalized));
  }

  Future<void> setAutoOpenCashDrawer(bool enabled) async {
    if (_autoOpenCashDrawer == enabled) return;
    _autoOpenCashDrawer = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(openDrawerKey, enabled));
  }

  Future<void> setAutoAddOnScan(bool enabled) async {
    if (_autoAddOnScan == enabled) return;
    _autoAddOnScan = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(autoAddScanKey, enabled));
  }

  Future<void> setAutoRefocusSearch(bool enabled) async {
    if (_autoRefocusSearch == enabled) return;
    _autoRefocusSearch = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(refocusSearchKey, enabled));
  }

  Future<void> setSoundFeedback(bool enabled) async {
    if (_soundFeedback == enabled) return;
    _soundFeedback = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(soundFeedbackKey, enabled));
  }

  Future<void> setDefaultFulfillment(PosDefaultFulfillment mode) async {
    if (_defaultFulfillment == mode) return;
    _defaultFulfillment = mode;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(defaultFulfillmentKey, mode.storageValue));
  }

  Future<void> _write(Future<bool> Function(SharedPreferences prefs) fn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await fn(prefs);
    } catch (_) {}
  }
}
