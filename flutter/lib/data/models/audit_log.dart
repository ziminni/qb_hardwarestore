import 'package:client/data/models/json_field.dart';

/// One row of the server's immutable audit trail (decision D-01).
///
/// Shape verified against `apps/users/serializers.py::AuditLogSerializer`
/// (2026-10-22):
/// `id, user, user_email, action_type, description, ip_address, timestamp`.
///
/// Two fields are genuinely optional and are the only ones allowed to be
/// missing: `user_email` is null when the acting account was deleted
/// (`user` is `SET_NULL`), and `ip_address` is nullable on the model. Everything
/// else is required, so a contract break fails loudly rather than rendering a
/// blank audit row a reviewer would read as "nothing happened" — which in an
/// audit trail is the worst possible lie.
class AuditLog {
  const AuditLog({
    required this.id,
    required this.userEmail,
    required this.actionType,
    required this.description,
    required this.ipAddress,
    required this.timestamp,
  });

  final int id;

  /// The acting account's email, or `(deleted)` when the account is gone.
  final String userEmail;

  /// `LOGIN | LOGOUT | CREATE | UPDATE | DELETE | SALE | STOCK_ADJUST |
  /// RECEIPT | PAYMENT` — the server's `AuditLog.ActionType` choices.
  final String actionType;

  final String description;

  final String? ipAddress;

  final DateTime timestamp;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
    id: intField(json, 'id'),
    userEmail: json['user_email'] as String? ?? '(deleted)',
    actionType: stringField(json, 'action_type'),
    description: stringField(json, 'description'),
    ipAddress: json['ip_address'] as String?,
    timestamp: DateTime.parse(stringField(json, 'timestamp')),
  );
}
