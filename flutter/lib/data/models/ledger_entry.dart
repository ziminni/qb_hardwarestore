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
  overdue('Overdue', 'error'),
  paid('Paid', 'neutral');

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
    this.projectName,
    this.paidAt,
  });

  final int id;
  final int customerId;
  final String customerName;

  /// The project this utang was released for, or null for a counter sale
  /// (decision 03: the contractor stays the payer, the project tags the debt).
  ///
  /// Optional with a null default so the older, project-less shape of the row
  /// still parses: a missing key is a counter sale, not a broken response.
  final String? projectName;

  /// The receipt/transaction number the debt came from — what a cashier searches by.
  final String transactionNo;

  final double originalAmount;
  final double balanceDue;
  final DateTime dueDate;
  final bool isOverdue;

  /// When a settled ledger (`balanceDue <= 0`) was paid in full, if known.
  final DateTime? paidAt;

  /// True when the ledger has been settled in full (`balanceDue <= 0`).
  bool get isPaid => balanceDue <= 0;

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
  LedgerStatus statusAt(
    DateTime now, {
    Duration dueSoonWindow = const Duration(days: 7),
  }) {
    if (isPaid) return LedgerStatus.paid;
    // Compared at DAY granularity, to match the server's `due_date < date.today()`.
    // Comparing raw DateTimes made a receivable due today read Overdue from 00:00, while the
    // server calls it overdue only after midnight - so the two disagreed for a whole day.
    final today = DateTime(now.year, now.month, now.day);
    if (isOverdue || dueDate.isBefore(today)) {
      return LedgerStatus.overdue;
    }
    if (dueDate.difference(now) <= dueSoonWindow) return LedgerStatus.dueSoon;
    return LedgerStatus.current;
  }

  static LedgerEntry fromJson(Map<String, dynamic> json) {
    final balanceDue = decimalField(json, 'balance_due');
    var paidAt = nullableDateField(json, 'paid_at');
    if (paidAt == null && balanceDue <= 0) {
      final recent = json['recent_payments'];
      if (recent is List) {
        for (final item in recent) {
          if (item is Map<String, dynamic>) {
            final parsed = nullableDateField(item, 'payment_date');
            if (parsed != null && (paidAt == null || parsed.isAfter(paidAt))) {
              paidAt = parsed;
            }
          }
        }
      }
    }
    return LedgerEntry(
      id: intField(json, 'id'),
      customerId: intField(json, 'customer'),
      customerName: stringField(json, 'customer_name'),
      projectName: (json['project_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['project_name'] as String).trim(),
      transactionNo: stringField(json, 'transaction_no'),
      originalAmount: decimalField(json, 'original_amount'),
      balanceDue: balanceDue,
      dueDate: DateTime.parse(stringField(json, 'due_date')),
      isOverdue: json['is_overdue'] == true,
      paidAt: paidAt,
    );
  }
}

/// One row of `GET /api/v1/payment-receipts/` — a CPMS online payment receipt (Phase 1c).
class PaymentReceipt {
  const PaymentReceipt({
    required this.id,
    required this.cpmsPaymentId,
    required this.cpmsProjectId,
    required this.projectName,
    required this.customerName,
    required this.amount,
    this.approvedAmount,
    required this.paymentMethod,
    required this.referenceNo,
    required this.notes,
    required this.submittedByName,
    required this.status,
    required this.declineReason,
    required this.createdAt,
    this.decidedByName,
    this.decidedAt,
  });

  final int id;
  final String cpmsPaymentId;
  final String cpmsProjectId;
  final String projectName;
  final String customerName;
  final double amount;
  final double? approvedAmount;
  final String paymentMethod;
  final String referenceNo;
  final String notes;
  final String submittedByName;
  final String status;
  final String declineReason;
  final DateTime createdAt;
  final String? decidedByName;
  final DateTime? decidedAt;

  static PaymentReceipt fromJson(Map<String, dynamic> json) => PaymentReceipt(
    id: intField(json, 'id'),
    cpmsPaymentId: stringField(json, 'cpms_payment_id'),
    cpmsProjectId: stringField(json, 'cpms_project_id'),
    projectName: stringField(json, 'project_name'),
    customerName: stringField(json, 'customer_name'),
    amount: decimalField(json, 'amount'),
    approvedAmount: json['approved_amount'] == null
        ? null
        : decimalField(json, 'approved_amount'),
    paymentMethod: stringField(json, 'payment_method'),
    referenceNo: stringField(json, 'reference_no'),
    notes: (json['notes'] as String?) ?? '',
    submittedByName: (json['submitted_by_name'] as String?) ?? '',
    status: stringField(json, 'status'),
    declineReason: (json['decline_reason'] as String?) ?? '',
    createdAt: DateTime.parse(stringField(json, 'created_at')),
    decidedByName: (json['decided_by_name'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['decided_by_name'] as String).trim(),
    decidedAt: nullableDateField(json, 'decided_at'),
  );
}

/// One row of `GET /api/v1/ledger-payments/` — an immutable payment posted against a ledger.
class LedgerPayment {
  const LedgerPayment({
    required this.id,
    required this.collectibleId,
    required this.customerName,
    this.projectName,
    required this.transactionNo,
    required this.amountPaid,
    required this.paymentMethod,
    required this.paymentDate,
    required this.officialReceiptNo,
    required this.processedByName,
    this.paymentReceiptId,
    this.cpmsReceiptRef,
  });

  final int id;
  final int collectibleId;
  final String customerName;
  final String? projectName;
  final String transactionNo;
  final double amountPaid;
  final String paymentMethod;
  final DateTime paymentDate;
  final String officialReceiptNo;
  final String processedByName;
  final int? paymentReceiptId;
  final String? cpmsReceiptRef;

  /// True when this payment was posted by approving a CPMS payment receipt.
  bool get isFromCpmsReceipt =>
      paymentReceiptId != null ||
      (cpmsReceiptRef != null && cpmsReceiptRef!.isNotEmpty);

  static LedgerPayment fromJson(Map<String, dynamic> json) => LedgerPayment(
    id: intField(json, 'id'),
    collectibleId: intField(json, 'collectible'),
    customerName: stringField(json, 'customer_name'),
    projectName: (json['project_name'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['project_name'] as String).trim(),
    transactionNo: stringField(json, 'transaction_no'),
    amountPaid: decimalField(json, 'amount_paid'),
    paymentMethod: stringField(json, 'payment_method'),
    paymentDate: DateTime.parse(stringField(json, 'payment_date')),
    officialReceiptNo: ((json['official_receipt_no'] as String?) ?? '').trim(),
    processedByName: ((json['processed_by_name'] as String?) ?? '').trim(),
    paymentReceiptId: json['payment_receipt'] == null
        ? null
        : intField(json, 'payment_receipt'),
    cpmsReceiptRef:
        (json['cpms_receipt_ref'] as String?)?.trim().isEmpty ?? true
        ? null
        : (json['cpms_receipt_ref'] as String).trim(),
  );
}
