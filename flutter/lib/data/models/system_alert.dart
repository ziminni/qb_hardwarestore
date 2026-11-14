import 'package:client/data/models/json_field.dart';

/// A system alert raised by the backend.
///
/// Contract: `apps/inventory/serializers.py::SystemAlertSerializer` —
/// `id, alert_type, variant, message, is_resolved, created_at` (verified against
/// the running API 2026-10-16). The backend raises these from `_check_low_stock`
/// and friends; the client reads them rather than deciding for itself
/// (decision 13).
enum SystemAlertType {
  lowStock('LOW_STOCK', 'Low stock'),
  outOfStock('OUT_OF_STOCK', 'Out of stock'),
  expiring('EXPIRING', 'Expiring batch'),

  /// A type this client build does not know about.
  ///
  /// Deliberately NOT dropped and NOT thrown on: a backend that adds an alert
  /// type must not make the screen silently shorter, and an alert the user
  /// cannot see is worse than one with a vague label.
  unknown('UNKNOWN', 'Alert');

  const SystemAlertType(this.apiValue, this.displayName);

  final String apiValue;
  final String displayName;

  static SystemAlertType fromApiValue(String value) {
    for (final type in values) {
      if (type.apiValue == value) return type;
    }
    return unknown;
  }
}

class SystemAlert {
  const SystemAlert({
    required this.id,
    required this.type,
    required this.variantId,
    required this.message,
    required this.isResolved,
    required this.createdAt,
    this.resolvedByName = '',
    this.resolvedAt,
  });

  final int id;
  final SystemAlertType type;
  final int variantId;
  final String message;
  final bool isResolved;
  final DateTime? createdAt;

  /// Who cleared the alert, as the server spells it (full name, else username).
  ///
  /// Empty until resolved — the server sends `null`, and inventing a name here
  /// would be a claim about who did the work. Phase 4 Task 6 shows this beside
  /// the resolved time so a cleared alert still says who cleared it.
  final String resolvedByName;

  /// When it was cleared, or null while it is still open.
  final DateTime? resolvedAt;

  factory SystemAlert.fromJson(Map<String, dynamic> json) {
    return SystemAlert(
      id: intField(json, 'id'),
      type: SystemAlertType.fromApiValue(stringField(json, 'alert_type')),
      variantId: intField(json, 'variant'),
      message: stringField(json, 'message'),
      isResolved: boolFieldOr(json, 'is_resolved', or: false),
      createdAt: nullableDateField(json, 'created_at'),
      resolvedByName: json['resolved_by_name'] as String? ?? '',
      resolvedAt: nullableDateField(json, 'resolved_at'),
    );
  }
}
