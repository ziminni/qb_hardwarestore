import 'package:client/data/models/json_field.dart';

/// How a receivable stands, as the sales screens must colour it.
///
/// Derived on the CLIENT from the due date and the server's `is_overdue` flag, rather than
/// trusting a single server token: the server computes `is_overdue` from the database clock
/// while the screen renders on the terminal's clock, and the two can disagree across a
/// midnight boundary. `overdue` therefore wins whenever either source says so - a receivable
/// shown as current when the server calls it overdue is a debt nobody chases.
enum LedgerStatus {
  current('Current', 'success'),
  dueSoon('Due Soon', 'warning'),
  overdue('Overdue', 'error');

  const LedgerStatus(this.label, this.tone);

  final String label;

  /// The `SalesStatusBadge` tone token this status renders as.
  final String tone;
}

/// One row of `GET /api/v1/ledgers/` — a customer's outstanding receivable.
///
/// This is the first REAL data behind the sales receivables screen, which until now read a
/// mock list out of `SalesModuleViewmodel`. Field names follow the wire
/// (`balance_due`, `customer_name`) rather than being prettified, so a rename on the server
/// surfaces as a parse failure at the boundary instead of a silent default.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.transactionNo,
    required this.originalAmount,
    required this.balanceDue,
    required this.dueDate,
    required this.isOverdue,
  });

  final int id;
  final int customerId;
  final String customerName;

  /// The receipt/transaction number the debt came from — what a cashier searches by.
  final String transactionNo;

  final double originalAmount;
  final double balanceDue;
  final DateTime dueDate;
  final bool isOverdue;

  /// What has actually been paid against this receivable.
  ///
  /// Derived as `original - balance` rather than summed from `recent_payments`, because the
  /// serializer nests only the RECENT payments: summing those would understate what was paid
  /// on an older, part-settled debt and show a customer's balance as larger than it is.
  double get paidAmount => originalAmount - balanceDue;

  /// True when nothing has been paid yet.
  bool get isUnpaid => balanceDue >= originalAmount;

  /// The status as of [now], so the day-boundary case is testable without waiting for it.
  ///
  /// [dueSoonWindow] is how far ahead "due soon" starts; the default week matches how far a
  /// counter clerk plans.
  LedgerStatus statusAt(DateTime now, {Duration dueSoonWindow = const Duration(days: 7)}) {
    if (isOverdue || dueDate.isBefore(now)) return LedgerStatus.overdue;
    if (dueDate.difference(now) <= dueSoonWindow) return LedgerStatus.dueSoon;
    return LedgerStatus.current;
  }

  static LedgerEntry fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      id: intField(json, 'id'),
      customerId: intField(json, 'customer'),
      customerName: stringField(json, 'customer_name'),
      transactionNo: stringField(json, 'transaction_no'),
      originalAmount: decimalField(json, 'original_amount'),
      balanceDue: decimalField(json, 'balance_due'),
      dueDate: DateTime.parse(stringField(json, 'due_date')),
      isOverdue: json['is_overdue'] == true,
    );
  }
}
