import 'package:client/data/models/json_field.dart';

/// Where a requisition stands in its lifecycle.
///
/// `unknown` exists so a status the client has not been taught does not read as DRAFT: the
/// reports tab shows every status CPMS can leave behind, and a row filed under the wrong word
/// is worse than one that admits the client is behind.
///
/// The POS no longer approves anything (decision 01), so `submitted` survives only to describe
/// a legacy row; `partial` and `closed` are the two CPMS and the till write today.
enum RequisitionStatus {
  draft('DRAFT', 'Draft'),
  submitted('SUBMITTED', 'Awaiting approval'),
  approved('APPROVED', 'Approved'),
  partial('PARTIAL', 'Partially released'),
  released('RELEASED', 'Released'),
  closed('CLOSED', 'Closed'),
  cancelled('CANCELLED', 'Cancelled'),
  rejected('REJECTED', 'Rejected'),
  unknown('', 'Unknown');

  const RequisitionStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

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

/// What the till can hand over from one requested line, as the token check reports it
/// (decision 05).
///
/// The server sends one of these four words for every line. A word this build was never
/// taught reads as [unavailable]: promising stock that is not on the shelf is the one
/// release error that cannot be undone, so the unknown case fails towards "nothing goes".
enum LineAvailability {
  full('FULL'),
  short('SHORT'),
  unavailable('UNAVAILABLE'),
  done('DONE');

  const LineAvailability(this.apiValue);

  final String apiValue;

  static LineAvailability fromApiValue(String? value) {
    for (final known in values) {
      if (known.apiValue == value) return known;
    }
    return unavailable;
  }
}

/// One line of a VERIFIED token, carrying what is still outstanding and what can leave
/// the store now.
///
/// [releasable] is capped by [remaining] and by the shelf on the server, so a short line
/// says exactly how much goes today ([goesNow]) and how much stays on the token
/// ([outstanding]).
class VerifiedRequisitionItem {
  const VerifiedRequisitionItem({
    required this.id,
    required this.variantId,
    required this.variantName,
    required this.quantity,
    required this.remaining,
    required this.availability,
    required this.releasable,
  });

  final int id;
  final int variantId;
  final String variantName;
  final double quantity;
  final double remaining;
  final LineAvailability availability;

  /// What the server says can leave the store on this scan, capped by [remaining].
  final double releasable;

  /// True when this line hands something over today.
  ///
  /// Read off [availability] as well as the quantity, because a line the server called
  /// [LineAvailability.unavailable] or [LineAvailability.done] must never be released
  /// whatever number rode along with it.
  bool get isReleasable =>
      (availability == LineAvailability.full ||
          availability == LineAvailability.short) &&
      releasable > 0;

  /// What leaves the store on this scan.
  double get goesNow => isReleasable ? releasable : 0;

  /// What stays open on this token after the release: the project comes back for it.
  double get outstanding => remaining > goesNow ? remaining - goesNow : 0;

  /// Parses one line, tolerating a response without the two availability fields.
  ///
  /// An older server that does not send them reads as "nothing can go", which disables
  /// the confirm press instead of promising stock nobody counted.
  static VerifiedRequisitionItem fromJson(Map<String, dynamic> json) =>
      VerifiedRequisitionItem(
        id: intField(json, 'id'),
        variantId: intField(json, 'variant_id'),
        variantName: stringField(json, 'variant_name'),
        quantity: decimalField(json, 'quantity'),
        remaining: decimalField(json, 'remaining'),
        availability: LineAvailability.fromApiValue(
          json['availability'] as String?,
        ),
        releasable: json['releasable'] == null
            ? 0
            : decimalField(json, 'releasable'),
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
          .map(
            (row) =>
                VerifiedRequisitionItem.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

/// Where the REQUEST stands after a release (decision 05): [partial] means the token is
/// still alive because some lines kept their outstanding quantity.
enum ReleaseStatus {
  released('RELEASED'),
  partial('PARTIAL'),
  unknown('');

  const ReleaseStatus(this.apiValue);

  final String apiValue;

  static ReleaseStatus fromApiValue(String? value) {
    for (final known in values) {
      if (known != unknown && known.apiValue == value) return known;
    }
    return unknown;
  }
}

/// One line of the release answer: what this scan moved and what is still owed on it.
class ReleasedLine {
  const ReleasedLine({
    required this.code,
    required this.releasedNow,
    required this.outstanding,
  });

  /// The material's barcode/QR code — the server's handle for a line, not its name.
  final String code;
  final double releasedNow;
  final double outstanding;

  bool get isOpen => outstanding > 0;

  static ReleasedLine fromJson(Map<String, dynamic> json) => ReleasedLine(
    code: stringField(json, 'code'),
    releasedNow: decimalField(json, 'released_now'),
    outstanding: decimalField(json, 'outstanding'),
  );
}

/// What `POST /api/v1/tokens/release/` answers — the sale the release created, and what
/// is left on the request.
///
/// A release is a SALE, not a stock adjustment: the server FIFO-deducts through the same
/// allocator the checkout uses and creates a `SalesTransaction` with `source=REQUISITION`.
/// [ledgerId] is always set because a construction firm pays later, so every release posts a
/// receivable for the whole value.
class ReleaseResult {
  const ReleaseResult({
    required this.transactionId,
    required this.transactionNo,
    required this.status,
    required this.items,
    required this.grandTotal,
    required this.ledgerId,
    required this.balanceDue,
  });

  final int transactionId;
  final String transactionNo;
  final ReleaseStatus status;

  /// What this scan moved and what is still owed, one entry per requested line.
  final List<ReleasedLine> items;

  final double grandTotal;
  final int ledgerId;
  final double balanceDue;

  /// Lines a later scan still has to hand over.
  int get openLineCount => items.where((line) => line.isOpen).length;

  /// True when the request is still partly open.
  ///
  /// The lines decide, not only the status word: a status this build has not been taught
  /// must not tell a clerk the request is finished while a line still owes goods.
  bool get isPartial => status == ReleaseStatus.partial || openLineCount > 0;

  static ReleaseResult fromJson(Map<String, dynamic> json) => ReleaseResult(
    transactionId: intField(json, 'transaction_id'),
    transactionNo: stringField(json, 'transaction_no'),
    status: ReleaseStatus.fromApiValue(json['status'] as String?),
    items: ((json['items'] as List?) ?? const [])
        .map((row) => ReleasedLine.fromJson(row as Map<String, dynamic>))
        .toList(growable: false),
    grandTotal: decimalField(json, 'grand_total'),
    ledgerId: intField(json, 'ledger_id'),
    balanceDue: decimalField(json, 'balance_due'),
  );
}
