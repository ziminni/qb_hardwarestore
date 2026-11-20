import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto-lock timeout options for the Cashier (POS) till screen.
enum PosAutoLockOption {
  off(0, null, 'Off'),
  fiveMinutes(5, Duration(minutes: 5), '5 minutes'),
  thirtyMinutes(30, Duration(minutes: 30), '30 minutes'),
  oneHour(60, Duration(hours: 1), '1 hour'),
  twoHours(120, Duration(hours: 2), '2 hours'),
  threeHours(180, Duration(hours: 3), '3 hours');

  const PosAutoLockOption(this.minutes, this.duration, this.label);

  /// Persisted integer value in `SharedPreferences`.
  final int minutes;

  /// Inactivity duration before locking, or `null` when disabled.
  final Duration? duration;

  /// Human-readable label shown in the Settings dropdown.
  final String label;

  static PosAutoLockOption fromMinutes(int? minutes) {
    if (minutes == null) return PosAutoLockOption.off;
    for (final option in PosAutoLockOption.values) {
      if (option.minutes == minutes) return option;
    }
    return PosAutoLockOption.off;
  }
}

/// Persists and broadcasts Cashier security & lock settings for this computer.
class PosLockSettingsController extends ChangeNotifier {
  PosLockSettingsController();

  static final PosLockSettingsController instance =
      PosLockSettingsController();

  static const String prefsKey = 'pos.auto_lock_minutes';
  static const String shortcutPrefsKey = 'pos.lock_shortcut_enabled';
  static const String lockAfterSalePrefsKey = 'pos.lock_after_sale';

  PosAutoLockOption _option = PosAutoLockOption.off;
  bool _lockShortcutEnabled = true;
  bool _lockAfterSale = false;
  int _saleLockVersion = 0;
  bool _loaded = false;

  PosAutoLockOption get option => _option;
  Duration? get duration => _option.duration;
  bool get lockShortcutEnabled => _lockShortcutEnabled;
  bool get lockAfterSale => _lockAfterSale;

  /// Monotonically increments whenever a sale completes while [lockAfterSale]
  /// is enabled, signaling [DashboardShell] to lock immediately.
  int get saleLockVersion => _saleLockVersion;

  /// Loads the saved lock settings from `SharedPreferences` once.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOption = PosAutoLockOption.fromMinutes(prefs.getInt(prefsKey));
      final savedShortcut = prefs.getBool(shortcutPrefsKey) ?? true;
      final savedAfterSale = prefs.getBool(lockAfterSalePrefsKey) ?? false;
      if (savedOption != _option ||
          savedShortcut != _lockShortcutEnabled ||
          savedAfterSale != _lockAfterSale) {
        _option = savedOption;
        _lockShortcutEnabled = savedShortcut;
        _lockAfterSale = savedAfterSale;
        notifyListeners();
      }
    } catch (_) {
      // Ignore storage errors in restricted environments; keep current default.
    }
  }

  /// Updates the active auto-lock option and saves it to `SharedPreferences`.
  Future<void> setOption(PosAutoLockOption next) async {
    if (_option == next) return;
    _option = next;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefsKey, next.minutes);
    } catch (_) {
      // Ignore storage errors; in-memory state stays updated for this session.
    }
  }

  /// Enables or disables the `Ctrl+L` / `Cmd+L` quick-lock shortcut.
  Future<void> setLockShortcutEnabled(bool enabled) async {
    if (_lockShortcutEnabled == enabled) return;
    _lockShortcutEnabled = enabled;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(shortcutPrefsKey, enabled);
    } catch (_) {}
  }

  /// Enables or disables locking automatically after a sale completes.
  Future<void> setLockAfterSale(bool enabled) async {
    if (_lockAfterSale == enabled) return;
    _lockAfterSale = enabled;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(lockAfterSalePrefsKey, enabled);
    } catch (_) {}
  }

  /// Called by checkout flows when a sale completes.
  void notifySaleCompleted() {
    if (!_lockAfterSale) return;
    _saleLockVersion++;
    notifyListeners();
  }
}
