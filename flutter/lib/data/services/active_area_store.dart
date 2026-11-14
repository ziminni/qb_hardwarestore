import 'package:shared_preferences/shared_preferences.dart';

/// The area a person last chose, remembered per account on this device
/// (Phase 4 F3b, decision 18).
///
/// The CHOICE only, never an authority: the server owns `roles[]`, and
/// `AuthViewmodel` re-checks every restored pick against the assignment before
/// it opens anything. Keyed by account id, so one person's pick cannot place
/// the next person who signs in on a shared till.
///
/// Reads are SYNCHRONOUS from a cache filled once by [load]. They sit on the
/// session-restore path, and awaiting a platform channel there stalls a restore
/// whose caller is waiting on it (a widget test's fake clock never answers it,
/// and a slow keychain would show the same stall on a real start). A missing or
/// unreadable store simply remembers nothing, exactly like
/// `SidebarCollapsePreference`.
class ActiveAreaStore {
  const ActiveAreaStore();

  static const String _prefix = 'active_area_';

  /// The preferences key for [userId]. Named here so a test can seed it.
  static String keyFor(int userId) => '$_prefix$userId';

  static Map<String, String> _cache = const {};

  /// Fills the cache from the device. Called once at startup, before the first
  /// session restore, and by tests that seed a value.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cache = {
        for (final key in prefs.getKeys())
          if (key.startsWith(_prefix))
            if (prefs.get(key) case final String value) key: value,
      };
    } catch (_) {
      // A binding without the plugin (a test, a platform without prefs) has
      // remembered nothing.
      _cache = const {};
    }
  }

  /// The remembered area code for [userId], or null.
  String? readArea(int userId) {
    final area = _cache[keyFor(userId)];
    if (area == null || area.trim().isEmpty) return null;
    return area.trim();
  }

  /// Remembers [code] for [userId] on this device.
  Future<void> writeArea(int userId, String code) async {
    // The cache first, so this session reads its own write immediately.
    _cache = {..._cache, keyFor(userId): code};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyFor(userId), code);
    } catch (_) {
      // Not worth a message: the area still applies for this session.
    }
  }
}
