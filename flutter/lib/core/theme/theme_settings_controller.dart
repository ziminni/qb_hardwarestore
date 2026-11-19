import 'package:client/core/theme/app_palette.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds and persists the local device's theme preferences.
///
/// Device-local only (`SharedPreferences`): never sends anything to the server
/// and never changes any store/business rule. Every platform failure is
/// swallowed cleanly so a missing store or widget test never blocks rendering.
class ThemeSettingsController extends ChangeNotifier {
  ThemeSettingsController({ThemeSettings initial = ThemeSettings.defaults})
    : _settings = initial;

  /// App-wide singleton loaded once during boot in `main.dart` and observed by
  /// `MyApp` and `SystemSettingsPanel`.
  static final ThemeSettingsController instance = ThemeSettingsController();

  static const String appearanceKey = 'local_theme_appearance';
  static const String accentKey = 'local_theme_accent';
  static const String sidebarStyleKey = 'local_theme_sidebar_style';
  static const String displayScaleKey = 'local_theme_display_scale';

  ThemeSettings _settings;

  ThemeSettings get settings => _settings;

  /// Reads saved local preferences from `SharedPreferences`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = ThemeSettings(
        appearance: AppAppearanceMode.fromId(prefs.getString(appearanceKey)),
        accent: AppAccentPreset.fromId(prefs.getString(accentKey)),
        sidebarStyle: AppSidebarStyle.fromId(prefs.getString(sidebarStyleKey)),
        displayScale: AppDisplayScale.fromId(prefs.getString(displayScaleKey)),
      );
      if (next == _settings) return;
      _settings = next;
      notifyListeners();
    } catch (_) {
      // Keep the current defaults if local storage is unavailable.
    }
  }

  Future<void> setAppearance(AppAppearanceMode mode) =>
      update(_settings.copyWith(appearance: mode));

  Future<void> setAccent(AppAccentPreset preset) =>
      update(_settings.copyWith(accent: preset));

  Future<void> setSidebarStyle(AppSidebarStyle style) =>
      update(_settings.copyWith(sidebarStyle: style));

  Future<void> setDisplayScale(AppDisplayScale scale) =>
      update(_settings.copyWith(displayScale: scale));

  Future<void> reset() => update(ThemeSettings.defaults);

  Future<void> update(ThemeSettings next) async {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(appearanceKey, next.appearance.id);
      await prefs.setString(accentKey, next.accent.id);
      await prefs.setString(sidebarStyleKey, next.sidebarStyle.id);
      await prefs.setString(displayScaleKey, next.displayScale.id);
    } catch (_) {
      // Theme still applies for this session even if persistence fails.
    }
  }

  /// Resets in-memory state cleanly for isolated unit/widget tests.
  @visibleForTesting
  void resetInMemory([ThemeSettings value = ThemeSettings.defaults]) {
    _settings = value;
    notifyListeners();
  }
}
