import 'package:client/data/models/json_field.dart';

/// How far along a cheque is, as `GET /api/v1/cheques/` reports it.
///
/// Decision 18: a cheque is not money yet. `PENDING` means the shop is waiting on
/// the bank; `CLEARED` means it paid the utang; `BOUNCED` means it never will and
/// the customer still owes it. Only [pending] offers a decision.
enum ChequeStatus {
  pending('Pending', 'PENDING'),
  cleared('Cleared', 'CLEARED'),
  bounced('Bounced', 'BOUNCED');

  const ChequeStatus(this.label, this.code);

  /// What the manager reads.
  final String label;

  /// What the wire carries (`Payment.Status`).
  final String code;

  /// The status [value] names, or null when it names none of them.
  static ChequeStatus? fromWire(String? value) {
    final wanted = value?.trim().toUpperCase();
    if (wanted == null || wanted.isEmpty) return null;
    for (final status in values) {
      if (status.code == wanted) return status;
    }
    return null;
  }
}

/// One row of `GET /api/v1/cheques/` — a cheque the shop is waiting on, or has
/// decided (Phase 4 task B2's `ChequeSerializer`).
///
/// Field names follow the wire rather than being prettified, so a rename on the
/// server surfaces as a parse failure at the boundary instead of a blank queue.
/// `amount` arrives as a 2-decimal STRING (DRF's DecimalField) and `cheque_date`
/// as `YYYY-MM-DD`, which is the day written on the cheque, not a timestamp.
class Cheque {
  const Cheque({
    required this.id,
    required this.transactionId,
    required this.transactionNo,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.chequeNumber,
    required this.bank,
    required this.chequeDate,
    required this.status,
    this.ledgerId,
    this.referenceNo = '',
    this.receivedAt,
    this.decidedById,
    this.decidedByName,
    this.decidedAt,
    this.decisionReason,
  });

  final int id;
  final int transactionId;
  final String transactionNo;
  final int customerId;
  final String customerName;

  /// The utang this cheque is waiting on, or null when it is not tied to one.
  final int? ledgerId;

  final double amount;
  final String chequeNumber;
  final String bank;
  final DateTime chequeDate;
  final ChequeStatus status;
  final String referenceNo;
  final DateTime? receivedAt;
  final int? decidedById;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionReason;

  /// True while the bank has not been heard from: the only state a manager can
  /// clear or bounce.
  bool get isPending => status == ChequeStatus.pending;

  static Cheque fromJson(Map<String, dynamic> json) {
    final rawStatus = stringField(json, 'status');
    final status = ChequeStatus.fromWire(rawStatus);
    if (status == null) {
      // A status this client cannot render must not be flattened into Pending:
      // that would offer Clear on a cheque the server may already have settled.
      throw FormatException('Unknown cheque status "$rawStatus"');
    }
    return Cheque(
      id: intField(json, 'id'),
      transactionId: intField(json, 'transaction'),
      transactionNo: stringField(json, 'transaction_no'),
      customerId: intField(json, 'customer'),
      customerName: stringField(json, 'customer_name'),
      ledgerId: json['ledger'] as int?,
      amount: decimalField(json, 'amount'),
      chequeNumber: stringField(json, 'cheque_number'),
      bank: stringField(json, 'bank'),
      chequeDate: DateTime.parse(stringField(json, 'cheque_date')),
      status: status,
      referenceNo: (json['reference_no'] as String?) ?? '',
      receivedAt: nullableDateField(json, 'received_at'),
      decidedById: json['decided_by'] as int?,
      decidedByName: json['decided_by_name'] as String?,
      decidedAt: nullableDateField(json, 'decided_at'),
      decisionReason: json['decision_reason'] as String?,
    );
  }
}
