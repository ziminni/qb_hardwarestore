import 'package:client/data/models/json_field.dart';

/// What each stable server code means, in words a cashier can act on.
///
/// ONE home for that wording (decision 05). Three callers need it — the
/// `returnable/` pre-flight (`reason_if_not`), the POST refusal (`code`) and the
/// page's own guards — and two copies would eventually disagree about what
/// `RETURN_QTY_EXCEEDED` is telling the counter.
///
/// The server's own `detail` is preferred where it sent one; these texts exist
/// because a refusal must still read as an instruction when the body lost its
/// prose (a proxy, a DRF field error, a bare `{"code": ...}`).
const Map<String, String> returnCodeMessages = {
  'NO_OPEN_SHIFT':
      'You have no open shift. Open a shift before posting a return — a refund '
      'is cash out of a drawer, and a drawer is a shift.',
  'RETURN_REASON_REQUIRED':
      'A return needs a reason before it can be posted: say why the customer '
      'brought the goods back.',
  'UNLINKED_RETURN_FORBIDDEN':
      'A cashier returns against the receipt in hand. Only a Store Manager can '
      'post a return with no original sale.',
  'RELEASE_NOT_RETURNABLE':
      'That document is a material release, not a sale, so it cannot be '
      'returned at the till.',
  'RETURN_OF_RETURN':
      'That document is itself a return, and a return cannot '
      'reverse another return.',
  'ORIGINAL_NOT_COMPLETED':
      'Only a completed sale can be returned. This document is not completed.',
  'RETURN_QTY_EXCEEDED': 'That is more than the sale still has to return.',
};

/// Clerk-readable text for a stable [code], or null when this client has never
/// heard of it (the caller then shows the server's own detail instead of
/// inventing an explanation).
String? returnMessageFor(String? code) =>
    code == null ? null : returnCodeMessages[code];

/// One **selling unit** on the original sale and how much of it can still come
/// back.
///
/// One entry per selling unit, not per line: a sale may name the same bag twice
/// and the server's cap counts them together, so a screen that showed two rows
/// would let a cashier return the same goods twice.
class ReturnableLine {
  const ReturnableLine({
    required this.variantUomId,
    required this.name,
    required this.uom,
    required this.soldQty,
    required this.returnedQty,
    required this.remainingQty,
    required this.unitPrice,
  });

  factory ReturnableLine.fromJson(Map<String, dynamic> json) => ReturnableLine(
    // The API calls it `variant_uom`; it is a **VariantUOM** id, and it is what
    // the return POST sends as `variant_id` (same naming quirk as checkout).
    variantUomId: intField(json, 'variant_uom'),
    name: stringField(json, 'name'),
    uom: stringField(json, 'uom'),
    soldQty: decimalField(json, 'sold_qty'),
    returnedQty: decimalField(json, 'returned_qty'),
    remainingQty: decimalField(json, 'remaining_qty'),
    unitPrice: decimalField(json, 'unit_price'),
  );

  final int variantUomId;
  final String name;
  final String uom;
  final double soldQty;
  final double returnedQty;
  final double remainingQty;
  final double unitPrice;

  /// False once everything sold has already come back — such a line is shown
  /// DISABLED rather than hidden, so the cashier can see the sale did happen.
  bool get hasRemaining => remainingQty > 0;

  /// What returning [qty] of this line is worth, at the ORIGINAL sale price.
  ///
  /// The client's figure is a preview only: `process_return` prices every line
  /// from the original sale and ignores a client `unit_price`, because a
  /// forgeable refund price is money out of the drawer.
  double valueOf(double qty) => qty * unitPrice;

  /// [qty] capped to what is left, so the stepper cannot even offer an amount
  /// the server would refuse with `RETURN_QTY_EXCEEDED`.
  double cappedQty(double qty) {
    if (qty <= 0) return 0;
    return qty > remainingQty ? remainingQty : qty;
  }
}

/// `GET /api/v1/transactions/{id}/returnable/` — the till's pre-flight.
///
/// [returnable] is the server's verdict and [reasonIfNot] is the SAME stable
/// code the POST would refuse with, so the screen maps one set of codes, not
/// two. [openDebt] is what the sale's collectible ledger still owes; the return
/// value settles that BEFORE any cash leaves the drawer (decision 05).
class ReturnableSale {
  const ReturnableSale({
    required this.transactionNo,
    required this.customer,
    required this.source,
    required this.returnable,
    required this.reasonIfNot,
    required this.lines,
    required this.openDebt,
  });

  factory ReturnableSale.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    if (rawLines is! List) {
      throw const FormatException('Missing required list field "lines"');
    }
    final reason = json['reason_if_not'];
    return ReturnableSale(
      transactionNo: stringField(json, 'transaction_no'),
      // The payload names the customer but does NOT carry their id: the POST's
      // `customer` comes from the searched transaction row (`TransactionRecord`),
      // which is why the viewmodel keeps both.
      customer: stringField(json, 'customer'),
      source: stringField(json, 'source'),
      returnable: boolFieldOr(json, 'returnable', or: false),
      reasonIfNot: reason is String && reason.isNotEmpty ? reason : null,
      lines: [
        for (final row in rawLines)
          if (row is Map<String, dynamic>) ReturnableLine.fromJson(row),
      ],
      openDebt: decimalField(json, 'open_debt'),
    );
  }

  final String transactionNo;
  final String customer;
  final String source;

  /// Whether the server would accept a return against this sale at all.
  final bool returnable;

  /// Why not, as a stable code (`RELEASE_NOT_RETURNABLE`, `RETURN_OF_RETURN`,
  /// `ORIGINAL_NOT_COMPLETED`), or null when it is reversible.
  final String? reasonIfNot;

  final List<ReturnableLine> lines;

  /// What the sale's ledger still owes. A return settles this first.
  final double openDebt;

  /// See [returnCodeMessages]; null when the sale is returnable.
  String? get notReturnableMessage => returnMessageFor(reasonIfNot);
}

/// The `refund_summary` block of a 201 return (decision 05).
///
/// The server does the arithmetic — what the return was worth, how much settled
/// utang, how much cash actually left the drawer — and the client must not
/// recompute it: a client that disagreed with the drawer by a centavo would be
/// wrong about whose money it is.
class RefundSummary {
  const RefundSummary({
    required this.returnValue,
    required this.debtReduced,
    required this.cashRefund,
    required this.refundMethod,
    required this.ledgerId,
    required this.ledgerBalance,
  });

  factory RefundSummary.fromJson(Map<String, dynamic> json) {
    final ledgerId = json['ledger_id'];
    final ledgerBalance = json['ledger_balance'];
    return RefundSummary(
      returnValue: decimalField(json, 'return_value'),
      debtReduced: decimalField(json, 'debt_reduced'),
      cashRefund: decimalField(json, 'cash_refund'),
      refundMethod: stringField(json, 'refund_method'),
      ledgerId: ledgerId is int ? ledgerId : null,
      // `null` when the sale had nothing owing — NOT zero, which would claim a
      // ledger exists with a zero balance.
      ledgerBalance: ledgerBalance == null
          ? null
          : decimalField(json, 'ledger_balance'),
    );
  }

  /// What came back, at the original sale's prices.
  final double returnValue;

  /// How much of that settled the original sale's utang.
  final double debtReduced;

  /// What actually left the drawer.
  final double cashRefund;

  final String refundMethod;

  /// The ledger that was reduced, or null when the sale owed nothing.
  final int? ledgerId;

  /// What that ledger still owes after this return, or null when there was no
  /// ledger at all.
  final double? ledgerBalance;
}

/// A posted return: its own transaction number plus the refund summary.
class ReturnResult {
  const ReturnResult({required this.returnNo, required this.refund});

  factory ReturnResult.fromJson(Map<String, dynamic> json) {
    final summary = json['refund_summary'];
    if (summary is! Map<String, dynamic>) {
      // A 201 without the summary is a contract break worth failing on: the
      // whole point of the response is that the client does not compute the
      // refund, and printing a made-up one is printing a lie about money.
      throw const FormatException(
        'Missing required object field "refund_summary"',
      );
    }
    return ReturnResult(
      returnNo: stringField(json, 'transaction_no'),
      refund: RefundSummary.fromJson(summary),
    );
  }

  final String returnNo;
  final RefundSummary refund;
}

/// One line of a return request: how much of a selling unit comes back.
class ReturnRequestLine {
  const ReturnRequestLine({required this.variantUomId, required this.qty});

  final int variantUomId;
  final double qty;

  /// `variant_id` is the API's name for a **VariantUOM** id (see
  /// [ReturnableLine.variantUomId]).
  Map<String, dynamic> toJson() => {'variant_id': variantUomId, 'qty': qty};
}
