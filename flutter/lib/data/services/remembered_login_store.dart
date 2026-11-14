import 'package:shared_preferences/shared_preferences.dart';

/// The username "Remember me" keeps between sessions (decision D14).
///
/// The NAME only. The password is never stored, and neither are the tokens: the
/// JWT pair lives in `ApiClient`'s token store and sign-out clears it, so this
/// helper can outlive a sign-out without keeping anybody signed in.
///
/// Same sink as the rest of the auth layer on Linux and web
/// (`shared_preferences`), read once when the login page opens. It sits beside
/// `location_hint_store.dart` for the same reason: device-local knowledge, not
/// API data, in the one folder the client keeps those in.
class RememberedLoginStore {
  const RememberedLoginStore();

  /// The preferences key. Named here so a test can seed it.
  static const String usernameKey = 'login_remembered_username';

  /// The remembered username, or null when there is none.
  Future<String?> readUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(usernameKey);
    if (username == null || username.trim().isEmpty) return null;
    return username;
  }

  Future<void> saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(usernameKey, username.trim());
  }

  Future<void> clearUsername() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(usernameKey);
  }
}
