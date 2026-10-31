import 'package:client/shared/widgets/status_badge.dart';

/// The words the Audit logs screen uses for the server's action codes.
///
/// The server stores `AuditLog.ActionType` choices (`SALE`, `STOCK_ADJUST`,
/// ...), and an audit trail an admin cannot read at a glance is barely a trail.
/// The mapping lives in one place so the row badge, the action chips and the
/// search all say the same word for the same code: a chip called "Stock
/// adjustment" that searched for "STOCK_ADJUST" would silently miss rows.
class AdminAuditAction {
  const AdminAuditAction._();

  /// The codes the server sends today, in the order the chips prefer.
  static const List<String> knownCodes = [
    'LOGIN',
    'LOGOUT',
    'CREATE',
    'UPDATE',
    'DELETE',
    'SALE',
    'STOCK_ADJUST',
    'RECEIPT',
    'PAYMENT',
  ];

  static const Map<String, String> _labels = {
    'LOGIN': 'Sign in',
    'LOGOUT': 'Sign out',
    'CREATE': 'Created',
    'UPDATE': 'Updated',
    'DELETE': 'Deleted',
    'SALE': 'Sale',
    'STOCK_ADJUST': 'Stock adjustment',
    'RECEIPT': 'Receipt',
    'PAYMENT': 'Payment',
  };

  /// `SALE` becomes "Sale". An unknown code is not swallowed: it is shown as
  /// words, because a blank action column in an audit trail hides a fact.
  static String label(String code) =>
      _labels[code] ??
      [
        for (final word in code.toLowerCase().split('_'))
          if (word.isNotEmpty) '${word[0].toUpperCase()}${word.substring(1)}',
      ].join(' ');

  /// Deletions and stock adjustments changed something that cannot be undone
  /// from the screen, so they read as warnings; ordinary writes and money are
  /// successes; a sign in is context, not an outcome.
  static StatusTone tone(String code) => switch (code) {
    'CREATE' || 'SALE' || 'RECEIPT' || 'PAYMENT' => StatusTone.success,
    'DELETE' || 'STOCK_ADJUST' => StatusTone.warning,
    'LOGIN' || 'LOGOUT' || 'UPDATE' => StatusTone.info,
    _ => StatusTone.neutral,
  };
}
