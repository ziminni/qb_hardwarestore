/// The five areas an account can be placed in, widest authority first.
///
/// This is the order the server sends `roles[]` in, and the client compares
/// CODES (`admin`, `sales`, `inventory`, `pos`) everywhere: group ids change
/// when the server canonicalises a group, and a display label is not an
/// identity. `cpms` is deliberately absent, because a CPMS service account is
/// not an area and must never be offered one.
class AppAreas {
  const AppAreas._();

  static const String admin = 'admin';
  static const String sales = 'sales';
  static const String inventory = 'inventory';
  static const String pos = 'pos';

  /// The Bodega Checker (decision 25): Bodega stock, hand-overs and counts
  /// only. Narrowest area, so it is listed last.
  static const String bodega = 'bodega';

  static const List<String> codes = [admin, sales, inventory, pos, bodega];

  static bool contains(String code) => codes.contains(code);
}
