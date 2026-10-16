import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Client-local storage-location hints: "where we put this in our store".
///
/// **Not API data.** The backend has no location field — verified against the
/// models, the serializers and the live API. This is store-local knowledge that
/// happens to be useful, so it lives locally and is persisted so it survives a
/// restart. The UI must not present it as though the server sent it.
///
/// Keyed by **variant id** (a hint belongs to a variant, not a product) and held
/// as one JSON blob under a single preferences key rather than one key per
/// variant, so loading the whole map is a single read.
///
/// Hints for variants that no longer exist are inert rather than garbage
/// collected: the client cannot know the catalogue's full membership without a
/// fetch, and deleting a user's note on the strength of a partial view would be
/// worse than keeping it.
///
/// Decision: `planning/api-integration/decisions/10-stock-identifier-and-location-hint.md`.
class LocationHintStore {
  static const String _prefsKey = 'stock_location_hints';

  /// Every stored hint, keyed by variant id.
  ///
  /// A missing or corrupt blob yields an empty map rather than throwing — a bad
  /// preferences value must not take the inventory screen down with it.
  Future<Map<int, String>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return <int, String>{};

    final decoded = _tryDecode(raw);
    if (decoded == null) return <int, String>{};

    final hints = <int, String>{};
    for (final entry in decoded.entries) {
      final variantId = int.tryParse(entry.key);
      final location = entry.value;
      if (variantId == null || location is! String) continue;
      if (location.trim().isEmpty) continue;
      hints[variantId] = location;
    }
    return hints;
  }

  /// The hint for one variant, or null when none is recorded.
  Future<String?> hintFor(int variantId) async {
    return (await loadAll())[variantId];
  }

  /// Records a hint. A blank [location] clears it instead — blank means "we do
  /// not know where it is", which must not render as an empty-looking location.
  Future<void> save(int variantId, String location) async {
    final trimmed = location.trim();
    final hints = await loadAll();

    if (trimmed.isEmpty) {
      hints.remove(variantId);
    } else {
      hints[variantId] = trimmed;
    }

    await _write(hints);
  }

  /// Forgets the hint for one variant.
  Future<void> clear(int variantId) async {
    final hints = await loadAll()..remove(variantId);
    await _write(hints);
  }

  Future<void> _write(Map<int, String> hints) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      hints.map((variantId, location) => MapEntry('$variantId', location)),
    );
    await prefs.setString(_prefsKey, encoded);
  }

  Map<String, dynamic>? _tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
