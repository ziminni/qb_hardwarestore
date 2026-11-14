import 'package:client/data/models/json_field.dart';

/// What a supplier bill owes, in the vocabulary the badge and chips use
/// (`SUPPLIER_BILL_STATUS`, ENDPOINTS.md §3.3).
enum SupplierBillStatus {
  unpaid('UNPAID', 'Unpaid'),
  partial('PARTIAL', 'Partially paid'),
  paid('PAID', 'Paid');

  const SupplierBillStatus(this.code, this.label);

  /// The server's code, and the value `?status=` filters by.
  final String code;

  /// What a reader sees. Sentence case, like every label in the app.
  final String label;

  /// Maps the wire code, failing loudly on one this build does not know: a bill
  /// silently shown as "Unpaid" when the server said something else is a debt
  /// read wrong.
  static SupplierBillStatus fromWire(String value) {
    for (final status in values) {
      if (status.code == value) return status;
    }
    throw FormatException('Unknown supplier bill status "$value"');
  }
}

/// How a supplier was paid (B2). Deliberately not `TenderMethod`: the till's
/// enum also carries CARD and GCASH, which a supplier payment cannot be, and
/// the supplier set has no `labelFor` legacy rows to tolerate.
enum SupplierPaymentMethod {
  cash('CASH', 'Cash'),
  cheque('CHEQUE', 'Cheque'),
  bankTransfer('BANK_TRANSFER', 'Bank transfer'),

  /// Phase 8 (decision 20): a CREDIT payment spends a credit note, never the
  /// till, so it is decoded but is NOT offered by the pay dialog.
  credit('CREDIT', 'Supplier Credit');

  const SupplierPaymentMethod(this.code, this.label);

  final String code;
  final String label;

  /// The methods the pay dialog offers, written out instead of `values`.
  ///
  /// Applying a credit note is its own flow (it picks a note and caps against
  /// that note), so listing `values` in the dropdown would offer a method whose
  /// server route refuses a body with no note.
  static const List<SupplierPaymentMethod> selectable = [
    cash,
    cheque,
    bankTransfer,
  ];

  /// True for the one method whose three facts the server insists on.
  bool get needsChequeDetails => this == cheque;

  static SupplierPaymentMethod? fromWire(String value) {
    for (final method in values) {
      if (method.code == value) return method;
    }
    return null;
  }
}

/// A supplier cheque's own life (B1, decision 20): it starts `ISSUED` and a
/// Store Manager/Admin marks it `CLEARED` or `BOUNCED` exactly once. Every
/// non-cheque method is born `CLEARED` — cash and transfers leave nothing to
/// decide.
enum SupplierPaymentStatus {
  issued('ISSUED', 'Issued'),
  cleared('CLEARED', 'Cleared'),
  bounced('BOUNCED', 'Bounced');

  const SupplierPaymentStatus(this.code, this.label);

  /// The server's code, and the value `?status=` filters the queue by.
  final String code;

  final String label;

  /// The status [value] names, or null when it names none of them.
  ///
  /// Null is the safe fallback: a status this build does not know must never
  /// read as [issued], because that would offer Clear on a decided cheque.
  static SupplierPaymentStatus? fromWire(String? value) {
    final wanted = value?.trim().toUpperCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final status in values) {
      if (status.code == wanted) return status;
    }
    return null;
  }
}

/// One payment against one bill (`SupplierPaymentSerializer`).
///
/// The cheque facts are history, but the cheque's STATUS is not: since Phase 8
/// (decision 20) a supplier cheque is born `ISSUED` and a manager clears or
/// bounces it, and a bounce puts the amount back on the bill.
class SupplierPayment {
  const SupplierPayment({
    required this.id,
    required this.billId,
    required this.amount,
    required this.method,
    required this.methodCode,
    required this.reference,
    required this.chequeNumber,
    required this.chequeBank,
    required this.chequeDate,
    required this.paidByName,
    required this.paidOn,
    this.status,
    this.statusCode = '',
    this.decidedById,
    this.decidedByName,
    this.decidedAt,
    this.decisionReason = '',
    this.creditNoteId,
  });

  final int id;
  final int billId;
  final double amount;

  /// Null when this build does not know the server's method code.
  final SupplierPaymentMethod? method;
  final String methodCode;
  final String reference;
  final String? chequeNumber;
  final String? chequeBank;
  final DateTime? chequeDate;
  final String paidByName;
  final DateTime? paidOn;

  /// Null when this build does not know the server's status code.
  final SupplierPaymentStatus? status;

  /// The raw wire code, kept so a row always has something to show.
  final String statusCode;
  final int? decidedById;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String decisionReason;

  /// The credit note a `CREDIT` payment spent; null for every other method.
  final int? creditNoteId;

  /// [method]'s label, or the raw code when this build does not know it (a
  /// payment is history: its row must still read, not crash the dialog).
  String get methodLabel => method?.label ?? methodCode;

  /// [status]'s label, or the raw code when this build does not know it.
  String get statusLabel => status?.label ?? statusCode;

  /// True only while the bank has not been heard from: the one state a manager
  /// may clear or bounce. An unknown status is never this.
  bool get isIssued => status == SupplierPaymentStatus.issued;

  factory SupplierPayment.fromJson(Map<String, dynamic> json) {
    final raw = stringField(json, 'method');
    final rawStatus = json['status'] as String?;
    return SupplierPayment(
      id: intField(json, 'id'),
      billId: intField(json, 'bill'),
      amount: decimalField(json, 'amount'),
      method: SupplierPaymentMethod.fromWire(raw),
      methodCode: raw,
      reference: json['reference'] as String? ?? '',
      chequeNumber: _text(json, 'cheque_number'),
      chequeBank: _text(json, 'cheque_bank'),
      chequeDate: nullableDateField(json, 'cheque_date'),
      paidByName: json['paid_by_name'] as String? ?? '',
      paidOn: nullableDateField(json, 'paid_on'),
      status: SupplierPaymentStatus.fromWire(rawStatus),
      statusCode: rawStatus ?? '',
      decidedById: json['decided_by'] == null
          ? null
          : intField(json, 'decided_by'),
      decidedByName: _text(json, 'decided_by_name'),
      decidedAt: nullableDateField(json, 'decided_at'),
      decisionReason: json['decision_reason'] as String? ?? '',
      creditNoteId: json['credit_note'] == null
          ? null
          : intField(json, 'credit_note'),
    );
  }
}

/// One bill the shop owes, written by `POST /goods-receipts/{id}/process/` and
/// immutable from then on (B2, decision 18).
///
/// Every money figure is a SNAPSHOT: the VAT rate and the terms were the ones
/// in force when the goods arrived, so this model never recomputes them.
class SupplierBill {
  const SupplierBill({
    required this.id,
    required this.receiptId,
    required this.purchaseOrderId,
    required this.supplierId,
    required this.supplierName,
    required this.receivedDate,
    required this.termsDays,
    required this.dueDate,
    required this.grossAmount,
    required this.discountAmount,
    required this.netAmount,
    required this.vatableAmount,
    required this.vatAmount,
    required this.vatRate,
    required this.totalAmount,
    required this.balanceAmount,
    required this.paidAmount,
    required this.status,
    required this.isOverdue,
    required this.payments,
  });

  final int id;
  final int receiptId;

  /// Null on a bill written from a receipt whose order the server no longer
  /// links (nothing to show, and nothing to guess).
  final int? purchaseOrderId;
  final int supplierId;
  final String supplierName;
  final DateTime receivedDate;
  final int termsDays;
  final DateTime dueDate;

  /// Delivered PACKAGE quantity × package cost — never base quantity × cost.
  final double grossAmount;
  final double discountAmount;
  final double netAmount;
  final double vatableAmount;
  final double vatAmount;
  final double vatRate;
  final double totalAmount;
  final double balanceAmount;

  /// What has been paid so far. Derived server-side; computed from the total and
  /// the balance when a payload leaves it out, so a partial bill never reads as
  /// unpaid.
  final double paidAmount;
  final SupplierBillStatus status;
  final bool isOverdue;
  final List<SupplierPayment> payments;

  /// The server refuses a settled bill (`BILL_PAID`), so a Pay button is only
  /// offered while money is still owed.
  bool get canPay => balanceAmount > 0 && status != SupplierBillStatus.paid;

  factory SupplierBill.fromJson(Map<String, dynamic> json) {
    final total = decimalField(json, 'total_amount');
    final balance = decimalField(json, 'balance_amount');
    final paid = json['paid_amount'] == null
        ? (total - balance)
        : decimalField(json, 'paid_amount');
    return SupplierBill(
      id: intField(json, 'id'),
      receiptId: intField(json, 'receipt'),
      purchaseOrderId: json['purchase_order'] == null
          ? null
          : intField(json, 'purchase_order'),
      supplierId: intField(json, 'supplier'),
      supplierName: json['supplier_name'] as String? ?? '',
      receivedDate: _date(json, 'received_date'),
      termsDays: intField(json, 'terms_days'),
      dueDate: _date(json, 'due_date'),
      grossAmount: decimalField(json, 'gross_amount'),
      discountAmount: decimalField(json, 'discount_amount'),
      netAmount: decimalField(json, 'net_amount'),
      vatableAmount: decimalField(json, 'vatable_amount'),
      vatAmount: decimalField(json, 'vat_amount'),
      vatRate: decimalField(json, 'vat_rate'),
      totalAmount: total,
      balanceAmount: balance,
      paidAmount: paid,
      status: SupplierBillStatus.fromWire(stringField(json, 'status')),
      isOverdue: boolFieldOr(json, 'is_overdue', or: false),
      payments: nestedList(json, 'payments', SupplierPayment.fromJson),
    );
  }
}

/// One row of `GET /suppliers/payables/` — a supplier's totals across its bills.
///
/// Suppliers with no bills are absent from the response, never a row of zeros
/// (a zero row would claim the shop has settled with them).
class SupplierPayable {
  const SupplierPayable({
    required this.supplierId,
    required this.supplierName,
    required this.billCount,
    required this.original,
    required this.paid,
    required this.balance,
    required this.overdue,
    this.credited = 0,
    this.unappliedCredit = 0,
    this.issuedCheques = 0,
  });

  final int supplierId;
  final String supplierName;
  final int billCount;

  /// `SUM(total_amount)` over the supplier's bills.
  final double original;

  /// Money that left the till: `original - balance - credited`.
  final double paid;
  final double balance;

  /// The part of [balance] past its due date and still owed.
  final double overdue;

  /// Bills settled with supplier credit (`SUM` of CREDIT payments).
  final double credited;

  /// Credit still to spend, its own column — deliberately NOT subtracted from
  /// [balance], because that credit is not owed yet.
  final double unappliedCredit;

  /// Cheques issued and not yet cleared (money promised, not yet paid).
  final double issuedCheques;

  factory SupplierPayable.fromJson(Map<String, dynamic> json) =>
      SupplierPayable(
        supplierId: intField(json, 'supplier'),
        supplierName: json['supplier_name'] as String? ?? '',
        billCount: intField(json, 'bills'),
        original: decimalField(json, 'original'),
        paid: decimalField(json, 'paid'),
        balance: decimalField(json, 'balance'),
        overdue: decimalField(json, 'overdue'),
        // Required, not defaulted: a 0.00 here would claim the shop holds no
        // supplier credit, which is the reading a manager must never be given
        // by accident.
        credited: decimalField(json, 'credited'),
        unappliedCredit: decimalField(json, 'unapplied_credit'),
        issuedCheques: decimalField(json, 'issued_cheques'),
      );
}

/// A nullable string that the API may send as `null` or omit entirely.
String? _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// A required `YYYY-MM-DD` date, read through [nullableDateField] so the
/// failure names the field it could not parse.
DateTime _date(Map<String, dynamic> json, String key) {
  final value = nullableDateField(json, key);
  if (value == null) throw FormatException('Missing required date "$key"');
  return value;
}
