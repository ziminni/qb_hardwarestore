/// The four areas an account can be placed in, widest authority first.
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

  static const List<String> codes = [admin, sales, inventory, pos];

  static bool contains(String code) => codes.contains(code);
}
