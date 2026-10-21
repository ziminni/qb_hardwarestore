import 'package:client/data/models/json_field.dart';

/// The end-of-shift summary (Z-reading) returned with a closed shift.
///
/// Derived on the server from the shift's own transactions — never stored — so
/// asking twice can never show two different days.
class ZReading {
  const ZReading({
    required this.transactionCount,
    required this.grossSales,
    required this.cashSales,
    required this.cardSales,
    required this.gcashSales,
    required this.expectedDrawer,
    required this.variance,
  });

  factory ZReading.fromJson(Map<String, dynamic> json) {
    // `variance` is null while the shift is still OPEN: there is no closing
    // count to compare the drawer against yet. Every other field is always sent.
    return ZReading(
      transactionCount: intField(json, 'transaction_count'),
      grossSales: decimalField(json, 'gross_sales'),
      cashSales: decimalField(json, 'cash_sales'),
      cardSales: decimalField(json, 'card_sales'),
      gcashSales: decimalField(json, 'gcash_sales'),
      expectedDrawer: decimalField(json, 'expected_drawer'),
      variance: json['variance'] == null
          ? null
          : decimalField(json, 'variance'),
    );
  }

  final int transactionCount;
  final double grossSales;
  final double cashSales;
  final double cardSales;
  final double gcashSales;
  final double expectedDrawer;

  /// Counted minus expected. Null until the shift is closed; non-zero is
  /// recorded and warned about, never blocked (decision 06, ruling 3).
  final double? variance;
}

/// A cashier's shift — Phase 4 of the cashier workflow (decision 06).
///
/// The server assigns `cashier` from the request, so the client never chooses
/// the actor. `status` moves OPEN -> CLOSED once and never back, which is why it
/// is read-only on the wire and treated as read-only here.
class Shift {
  const Shift({
    required this.id,
    required this.cashierName,
    required this.status,
    required this.openingFloat,
    required this.closingCount,
    required this.openedAt,
    required this.closedAt,
    required this.notes,
    required this.zReading,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    final zReading = json['z_reading'];
    return Shift(
      id: intField(json, 'id'),
      cashierName: stringField(json, 'cashier_name'),
      status: stringField(json, 'status'),
      openingFloat: decimalField(json, 'opening_float'),
      closingCount: json['closing_count'] == null
          ? null
          : decimalField(json, 'closing_count'),
      openedAt: DateTime.parse(stringField(json, 'opened_at')),
      closedAt: nullableDateField(json, 'closed_at'),
      notes: stringField(json, 'notes'),
      zReading: zReading is Map<String, dynamic>
          ? ZReading.fromJson(zReading)
          : null,
    );
  }

  static const openStatus = 'OPEN';
  static const closedStatus = 'CLOSED';

  final int id;
  final String cashierName;
  final String status;
  final double openingFloat;
  final double? closingCount;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String notes;

  /// Only complete on a closed shift — the server computes it at close and
  /// returns it with every later read of the same shift.
  final ZReading? zReading;

  bool get isOpen => status == openStatus;
}
