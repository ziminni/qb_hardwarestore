import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SalesDefaultReportRange {
  today('today', 'Today'),
  last7Days('last_7_days', 'Last 7 days'),
  last30Days('last_30_days', 'Last 30 days'),
  thisMonth('this_month', 'This month');

  const SalesDefaultReportRange(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static SalesDefaultReportRange fromStorage(String? value) {
    for (final range in SalesDefaultReportRange.values) {
      if (range.storageValue == value) return range;
    }
    return SalesDefaultReportRange.last7Days;
  }
}

enum SalesDefaultExportFormat {
  excel('excel', 'Excel (.xlsx)'),
  csv('csv', 'CSV (.csv)');

  const SalesDefaultExportFormat(this.storageValue, this.label);
  final String storageValue;
  final String label;

  static SalesDefaultExportFormat fromStorage(String? value) {
    for (final format in SalesDefaultExportFormat.values) {
      if (format.storageValue == value) return format;
    }
    return SalesDefaultExportFormat.excel;
  }
}

/// Persists device-local Store Manager preferences in `SharedPreferences`.
class SalesSettingsController extends ChangeNotifier {
  SalesSettingsController();

  static final SalesSettingsController instance = SalesSettingsController();

  static const String reportRangeKey = 'sales.default_report_range';
  static const String exportFormatKey = 'sales.default_export_format';
  static const String maskCostKey = 'sales.mask_cost_and_margin';
  static const String overdueDaysKey = 'sales.overdue_alert_days';
  static const String confirmDiscountsKey = 'sales.confirm_large_discounts';
  static const String autoLockKey = 'sales.auto_lock_minutes';
  static const String lockShortcutKey = 'sales.lock_shortcut_enabled';

  SalesDefaultReportRange _defaultReportRange =
      SalesDefaultReportRange.last7Days;
  SalesDefaultExportFormat _defaultExportFormat =
      SalesDefaultExportFormat.excel;
  bool _maskCostAndMargin = false;
  int _overdueAlertDays = 7;
  bool _confirmLargeDiscounts = true;
  PosAutoLockOption _autoLockOption = PosAutoLockOption.off;
  bool _lockShortcutEnabled = true;
  bool _loaded = false;

  SalesDefaultReportRange get defaultReportRange => _defaultReportRange;
  SalesDefaultExportFormat get defaultExportFormat => _defaultExportFormat;
  bool get maskCostAndMargin => _maskCostAndMargin;
  int get overdueAlertDays => _overdueAlertDays;
  bool get confirmLargeDiscounts => _confirmLargeDiscounts;
  PosAutoLockOption get autoLockOption => _autoLockOption;
  bool get lockShortcutEnabled => _lockShortcutEnabled;

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nextRange = SalesDefaultReportRange.fromStorage(
        prefs.getString(reportRangeKey),
      );
      final nextFormat = SalesDefaultExportFormat.fromStorage(
        prefs.getString(exportFormatKey),
      );
      final nextMask = prefs.getBool(maskCostKey) ?? false;
      final savedDays = prefs.getInt(overdueDaysKey) ?? 7;
      final nextDays = const [3, 7, 14, 30].contains(savedDays) ? savedDays : 7;
      final nextConfirm = prefs.getBool(confirmDiscountsKey) ?? true;
      final nextAutoLock = PosAutoLockOption.fromMinutes(
        prefs.getInt(autoLockKey),
      );
      final nextShortcut = prefs.getBool(lockShortcutKey) ?? true;

      if (nextRange != _defaultReportRange ||
          nextFormat != _defaultExportFormat ||
          nextMask != _maskCostAndMargin ||
          nextDays != _overdueAlertDays ||
          nextConfirm != _confirmLargeDiscounts ||
          nextAutoLock != _autoLockOption ||
          nextShortcut != _lockShortcutEnabled) {
        _defaultReportRange = nextRange;
        _defaultExportFormat = nextFormat;
        _maskCostAndMargin = nextMask;
        _overdueAlertDays = nextDays;
        _confirmLargeDiscounts = nextConfirm;
        _autoLockOption = nextAutoLock;
        _lockShortcutEnabled = nextShortcut;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setDefaultReportRange(SalesDefaultReportRange range) async {
    if (_defaultReportRange == range) return;
    _defaultReportRange = range;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(reportRangeKey, range.storageValue));
  }

  Future<void> setDefaultExportFormat(SalesDefaultExportFormat format) async {
    if (_defaultExportFormat == format) return;
    _defaultExportFormat = format;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setString(exportFormatKey, format.storageValue));
  }

  Future<void> setMaskCostAndMargin(bool mask) async {
    if (_maskCostAndMargin == mask) return;
    _maskCostAndMargin = mask;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(maskCostKey, mask));
  }

  Future<void> setOverdueAlertDays(int days) async {
    if (_overdueAlertDays == days) return;
    _overdueAlertDays = days;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setInt(overdueDaysKey, days));
  }

  Future<void> setConfirmLargeDiscounts(bool confirm) async {
    if (_confirmLargeDiscounts == confirm) return;
    _confirmLargeDiscounts = confirm;
    _loaded = true;
    notifyListeners();
    await _write((p) => p.setBool(confirmDiscountsKey, confirm));
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
