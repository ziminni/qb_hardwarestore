import 'package:client/data/models/json_field.dart';

/// Where a requisition stands in its lifecycle.
///
/// `unknown` exists so a status the client has not been taught does not read as DRAFT — the
/// approve queue's whole job is to show what is WAITING, and a row that silently disappeared (or
/// claimed to be a draft) would be material nobody releases.
enum RequisitionStatus {
  draft('DRAFT', 'Draft'),
  submitted('SUBMITTED', 'Awaiting approval'),
  approved('APPROVED', 'Approved'),
  released('RELEASED', 'Released'),
  rejected('REJECTED', 'Rejected'),
  unknown('', 'Unknown');

  const RequisitionStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Only SUBMITTED can be approved or rejected, mirroring the server's guards.
  bool get isAwaitingApproval => this == submitted;

  static RequisitionStatus fromApiValue(String? value) {
    for (final status in values) {
      if (status != unknown && status.apiValue == value) return status;
    }
    return unknown;
  }
}

/// One line of a requisition: what was asked for, and how much has gone out.
class RequisitionItem {
  const RequisitionItem({
    required this.id,
    required this.variantId,
    required this.variantName,
    required this.quantity,
    required this.releasedQty,
    this.notes = '',
  });

  final int id;
  final int variantId;
  final String variantName;
  final double quantity;
  final double releasedQty;
  final String notes;

  /// What is still to be handed over.
  double get remaining => quantity - releasedQty;

  static RequisitionItem fromJson(Map<String, dynamic> json) => RequisitionItem(
    id: intField(json, 'id'),
    variantId: intField(json, 'variant'),
    variantName: stringField(json, 'variant_name'),
    quantity: decimalField(json, 'quantity'),
    releasedQty: decimalField(json, 'released_qty'),
    notes: (json['notes'] as String?) ?? '',
  );
}

/// A material request, as `GET /api/v1/requisitions/` returns it.
///
/// POS reads requisitions it did NOT create (decision 09: CPMS owns create and submit), which is
/// why [projectName], [projectCustomerName] and [requestedByName] are carried: a manager approving an anonymous list of
/// material requests is the failure mode that split creates.
class Requisition {
  const Requisition({
    required this.id,
    required this.reqNumber,
    required this.rawStatus,
    required this.projectName,
    required this.projectCustomerName,
    required this.requestedByName,
    required this.items,
    this.token,
  });

  final int id;
  final String reqNumber;

  /// The status exactly as the server sent it, kept so `unknown` rows can still be described.
  final String rawStatus;

  final String projectName;
  final String projectCustomerName;
  final String requestedByName;
  final List<RequisitionItem> items;

  /// The material token, minted on approval. **Null until then** — a DRAFT or SUBMITTED
  /// requisition has no token row at all, which is a live-verified fact, not an assumption.
  final String? token;

  RequisitionStatus get status => RequisitionStatus.fromApiValue(rawStatus);

  static Requisition fromJson(Map<String, dynamic> json) => Requisition(
    id: intField(json, 'id'),
    reqNumber: stringField(json, 'req_number'),
    rawStatus: stringField(json, 'status'),
    projectName: stringField(json, 'project_name'),
    projectCustomerName: stringField(json, 'project_customer_name'),
    requestedByName: stringField(json, 'requested_by_name'),
    items: ((json['items'] as List?) ?? const [])
        .map((row) => RequisitionItem.fromJson(row as Map<String, dynamic>))
        .toList(growable: false),
    token: json['token'] as String?,
  );
}

/// One line of a VERIFIED token, carrying what is still outstanding.
class VerifiedRequisitionItem {
  const VerifiedRequisitionItem({
    required this.id,
    required this.variantId,
    required this.variantName,
    required this.quantity,
    required this.remaining,
  });

  final int id;
  final int variantId;
  final String variantName;
  final double quantity;
  final double remaining;

  static VerifiedRequisitionItem fromJson(Map<String, dynamic> json) =>
      VerifiedRequisitionItem(
        id: intField(json, 'id'),
        variantId: intField(json, 'variant_id'),
        variantName: stringField(json, 'variant_name'),
        quantity: decimalField(json, 'quantity'),
        remaining: decimalField(json, 'remaining'),
      );
}

/// What `POST /api/v1/tokens/verify/` answers — the requisition shown to the cashier BEFORE
/// anything moves.
///
/// A DIFFERENT shape from [Requisition]: verify describes what the token is FOR, and it carries
/// the customer, which is what the counter needs to know who is collecting.
class TokenVerification {
  const TokenVerification({
    required this.token,
    required this.requisitionId,
    required this.reqNumber,
    required this.project,
    required this.customer,
    required this.items,
  });

  final String token;
  final int requisitionId;
  final String reqNumber;
  final String project;
  final String customer;
  final List<VerifiedRequisitionItem> items;

  static TokenVerification fromJson(Map<String, dynamic> json) {
    final req = (json['requisition'] as Map<String, dynamic>?) ?? const {};
    return TokenVerification(
      token: stringField(json, 'token'),
      requisitionId: intField(req, 'id'),
      reqNumber: stringField(req, 'req_number'),
      project: stringField(req, 'project'),
      customer: stringField(req, 'customer'),
      items: ((json['items'] as List?) ?? const [])
          .map((row) => VerifiedRequisitionItem.fromJson(row as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// What `POST /api/v1/tokens/release/` answers — the sale the release created.
///
/// A release is a SALE, not a stock adjustment: the server FIFO-deducts through the same
/// allocator the checkout uses and creates a `SalesTransaction` with `source=REQUISITION`.
/// [ledgerId] is always set because a construction firm pays later, so every release posts a
/// receivable for the whole value.
class ReleaseResult {
  const ReleaseResult({
    required this.transactionId,
    required this.transactionNo,
    required this.grandTotal,
    required this.ledgerId,
    required this.balanceDue,
  });

  final int transactionId;
  final String transactionNo;
  final double grandTotal;
  final int ledgerId;
  final double balanceDue;

  static ReleaseResult fromJson(Map<String, dynamic> json) => ReleaseResult(
    transactionId: intField(json, 'transaction_id'),
    transactionNo: stringField(json, 'transaction_no'),
    grandTotal: decimalField(json, 'grand_total'),
    ledgerId: intField(json, 'ledger_id'),
    balanceDue: decimalField(json, 'balance_due'),
  );
}
