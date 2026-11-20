import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InventoryAdjustmentReason {
  supplierDelivery('supplier_delivery', 'Supplier delivery'),
  physicalCount('physical_count', 'Physical count'),
  damaged('damaged', 'Damaged / spoilage'),
  returned('returned', 'Customer / project return');

  const InventoryAdjustmentReason(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static InventoryAdjustmentReason fromStorage(String? value) {
    for (final reason in InventoryAdjustmentReason.values) {
      if (reason.storageValue == value) return reason;
    }
    return InventoryAdjustmentReason.supplierDelivery;
  }
}

enum InventoryProductSort {
  lowStockFirst('low_stock_first', 'Low stock first'),
  nameAsc('name_asc', 'Name (A–Z)'),
  recentlyUpdated('recently_updated', 'Recently updated');

  const InventoryProductSort(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static InventoryProductSort fromStorage(String? value) {
    for (final sort in InventoryProductSort.values) {
      if (sort.storageValue == value) return sort;
    }
    return InventoryProductSort.lowStockFirst;
  }
}

/// Persists device-local Stock Manager preferences in `SharedPreferences`.
class InventorySettingsController extends ChangeNotifier {
  InventorySettingsController();

  static final InventorySettingsController instance =
      InventorySettingsController();

  static const String adjustmentReasonKey = 'inventory.default_reason';
  static const String productSortKey = 'inventory.default_product_sort';
  static const String confirmLargeAdjKey =
      'inventory.confirm_large_adjustments';
  static const String autoFocusSearchKey = 'inventory.auto_focus_search';
  static const String soundFeedbackKey = 'inventory.sound_feedback';
  static const String quickCountStepKey = 'inventory.quick_count_step';
  static const String autoLockKey = 'inventory.auto_lock_minutes';
  static const String lockShortcutKey = 'inventory.lock_shortcut_enabled';

  InventoryAdjustmentReason _defaultAdjustmentReason =
      InventoryAdjustmentReason.supplierDelivery;
  InventoryProductSort _defaultProductSort =
      InventoryProductSort.lowStockFirst;
  bool _confirmLargeAdjustments = true;
  bool _autoFocusBarcodeSearch = true;
  bool _soundFeedback = true;
  int _quickCountStep = 1;
  PosAutoLockOption _autoLockOption = PosAutoLockOption.off;
  bool _lockShortcutEnabled = true;
  bool _loaded = false;

  InventoryAdjustmentReason get defaultAdjustmentReason =>
      _defaultAdjustmentReason;
  InventoryProductSort get defaultProductSort => _defaultProductSort;
  bool get confirmLargeAdjustments => _confirmLargeAdjustments;
  bool get autoFocusBarcodeSearch => _autoFocusBarcodeSearch;
  bool get soundFeedback => _soundFeedback;
  int get quickCountStep => _quickCountStep;
  PosAutoLockOption get autoLockOption => _autoLockOption;
  bool get lockShortcutEnabled => _lockShortcutEnabled;

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nextReason = InventoryAdjustmentReason.fromStorage(
        prefs.getString(adjustmentReasonKey),
      );
      final nextSort = InventoryProductSort.fromStorage(
        prefs.getString(productSortKey),
      );
      final nextConfirm = prefs.getBool(confirmLargeAdjKey) ?? true;
      final nextFocus = prefs.getBool(autoFocusSearchKey) ?? true;
      final nextSound = prefs.getBool(soundFeedbackKey) ?? true;
      final savedStep = prefs.getInt(quickCountStepKey) ?? 1;
      final nextStep = const [1, 5, 10].contains(savedStep) ? savedStep : 1;
      final nextAutoLock = PosAutoLockOption.fromMinutes(
        prefs.getInt(autoLockKey),
      );
      final nextShortcut = prefs.getBool(lockShortcutKey) ?? true;

      if (nextReason != _defaultAdjustmentReason ||
          nextSort != _defaultProductSort ||
          nextConfirm != _confirmLargeAdjustments ||
          nextFocus != _autoFocusBarcodeSearch ||
          nextSound != _soundFeedback ||
          nextStep != _quickCountStep ||
          nextAutoLock != _autoLockOption ||
          nextShortcut != _lockShortcutEnabled) {
        _defaultAdjustmentReason = nextReason;
        _defaultProductSort = nextSort;
        _confirmLargeAdjustments = nextConfirm;
        _autoFocusBarcodeSearch = nextFocus;
        _soundFeedback = nextSound;
        _quickCountStep = nextStep;
        _autoLockOption = nextAutoLock;
        _lockShortcutEnabled = nextShortcut;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setDefaultAdjustmentReason(
    InventoryAdjustmentReason reason,
  ) async {
    if (_defaultAdjustmentReason == reason) return;
    _defaultAdjustmentReason = reason;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(adjustmentReasonKey, reason.storageValue));
  }

  Future<void> setDefaultProductSort(InventoryProductSort sort) async {
    if (_defaultProductSort == sort) return;
    _defaultProductSort = sort;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(productSortKey, sort.storageValue));
  }

  Future<void> setConfirmLargeAdjustments(bool confirm) async {
    if (_confirmLargeAdjustments == confirm) return;
    _confirmLargeAdjustments = confirm;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(confirmLargeAdjKey, confirm));
  }

  Future<void> setAutoFocusBarcodeSearch(bool enabled) async {
    if (_autoFocusBarcodeSearch == enabled) return;
    _autoFocusBarcodeSearch = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(autoFocusSearchKey, enabled));
  }

  Future<void> setSoundFeedback(bool enabled) async {
    if (_soundFeedback == enabled) return;
    _soundFeedback = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(soundFeedbackKey, enabled));
  }

  Future<void> setQuickCountStep(int step) async {
    final normalized = const [1, 5, 10].contains(step) ? step : 1;
    if (_quickCountStep == normalized) return;
    _quickCountStep = normalized;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setInt(quickCountStepKey, normalized));
  }

  Future<void> setAutoLockOption(PosAutoLockOption option) async {
    if (_autoLockOption == option) return;
    _autoLockOption = option;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setInt(autoLockKey, option.minutes));
  }

  Future<void> setLockShortcutEnabled(bool enabled) async {
    if (_lockShortcutEnabled == enabled) return;
    _lockShortcutEnabled = enabled;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(lockShortcutKey, enabled));
  }

  Future<void> _write(Future<bool> Function(SharedPreferences prefs) fn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await fn(prefs);
    } catch (_) {}
  }
}
