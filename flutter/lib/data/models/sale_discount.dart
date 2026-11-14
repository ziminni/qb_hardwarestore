import 'dart:math' as math;

/// A whole-sale discount the cashier typed at the till (Phase 4 F4, decision 18).
///
/// The server is the authority: it re-validates the kind, the value, the reason and
/// the Admin's cap, and answers with the amount it actually applied. This class is
/// the WIRE shape plus the preview arithmetic the dialog shows before the sale is
/// submitted, never the number the receipt prints.
enum DiscountKind {
  amount(code: 'AMOUNT', label: 'Amount'),
  percent(code: 'PERCENT', label: 'Percent');

  const DiscountKind({required this.code, required this.label});

  /// What the server stores and accepts (`discount.kind`).
  final String code;

  /// What the cashier reads on the kind switch.
  final String label;

  /// The kind [value] names, or null when it names neither.
  static DiscountKind? fromWire(String? value) {
    final wanted = (value ?? '').trim().toUpperCase();
    for (final kind in values) {
      if (kind.code == wanted) return kind;
    }
    return null;
  }
}

class PosDiscount {
  const PosDiscount({
    required this.kind,
    required this.value,
    required this.reason,
  });

  final DiscountKind kind;

  /// The peso amount for [DiscountKind.amount], the percent for [DiscountKind.percent].
  final double value;

  /// Why the discount is being given. Required by the server whenever it is above
  /// zero, so this is never sent empty.
  final String reason;

  /// The `discount` object of a checkout body.
  ///
  /// `value` goes as a 2 dp string for the same reason store settings do: a double
  /// can serialize as `9.999999999999998`, and the server would then store a discount
  /// nobody typed.
  Map<String, dynamic> toJson() => {
    'kind': kind.code,
    'value': value.toStringAsFixed(2),
    'reason': reason,
  };
}

/// Gross, the discount, and what is left to pay, rounded once at 2 dp.
///
/// A PREVIEW. The server runs the same arithmetic on its own prices and its answer
/// wins; this exists so the cashier sees the net before they press Complete sale.
class PosDiscountAmounts {
  const PosDiscountAmounts({required this.gross, required this.discountAmount});

  /// Builds the preview for [discount] against [gross].
  ///
  /// A percent is of the gross (decision 18). The discount is clamped to the gross so
  /// a peso discount larger than the sale previews as "free", not as a negative net
  /// that the server would refuse.
  factory PosDiscountAmounts.forDiscount(double gross, PosDiscount? discount) {
    if (discount == null || gross <= 0) {
      return PosDiscountAmounts(gross: gross, discountAmount: 0);
    }
    final raw = switch (discount.kind) {
      DiscountKind.amount => discount.value,
      DiscountKind.percent => gross * (discount.value / 100),
    };
    return PosDiscountAmounts(
      gross: gross,
      discountAmount: roundMoney(raw.clamp(0, gross)),
    );
  }

  final double gross;
  final double discountAmount;

  /// What the customer actually pays: the amount due, and what change is counted from.
  double get net => roundMoney(gross - discountAmount);

  /// The discount as a share of the gross, the number the cap is compared against.
  double get percentOfGross =>
      gross <= 0 ? 0 : roundMoney(discountAmount / gross * 100);

  /// True when this discount is larger than [capPercent], so the till must ask a
  /// manager to approve it before the sale can be submitted.
  bool needsApproval(double capPercent) =>
      discountAmount > 0 && percentOfGross > capPercent;
}

/// Two decimals, half away from zero (the server's `ROUND_HALF_UP` for positives).
double roundMoney(double value) => (value * 100).roundToDouble() / 100;

/// The server's refusal codes for a discount, as something a cashier can act on.
///
/// The four codes name four different actions (decision 18): fix the discount, write
/// a reason, fetch a manager, or ask the manager to approve again. One catch-all
/// sentence would hide which of them applies. `null` means the code is not a discount
/// code, so the caller keeps its own handling.
String? discountRefusalSentence(
  String? code, {
  double? capPercent,
  double? requestedPercent,
}) {
  switch (code) {
    case 'DISCOUNT_REASON_REQUIRED':
      return 'A discount needs a reason. Write why the discount is being given.';
    case 'DISCOUNT_OVER_CAP':
      final cap = capPercent == null ? null : _percent(capPercent);
      final asked = requestedPercent == null
          ? null
          : _percent(requestedPercent);
      if (cap != null && asked != null) {
        return 'This discount is $asked% and a cashier may give up to $cap% '
            'without approval. Ask a Store Manager or Admin to approve it.';
      }
      return 'This discount is above the cashier cap. Ask a Store Manager or '
          'Admin to approve it.';
    case 'DISCOUNT_APPROVAL_INVALID':
      return 'That discount approval is not valid or has expired. Ask the manager '
          'to approve the discount again.';
    case 'INVALID_DISCOUNT':
      return 'That discount cannot be applied. Check the amount against the sale '
          'total and try again.';
    default:
      return null;
  }
}

/// The server's refusal codes for a CHEQUE tender (Phase 4 B2, decision 18).
///
/// A cheque is the one tender that is not money yet, so its refusals are about the
/// rows the cashier can still fix: name the customer, fill the three cheque facts, or
/// lower the cheque so it does not ask for change the drawer cannot give.
/// `null` means the code is not a cheque code.
String? chequeRefusalSentence(
  String? code, {
  List<String> missing = const [],
  double? chequeTotal,
  double? owed,
}) {
  switch (code) {
    case 'CHEQUE_NEEDS_CUSTOMER':
      return 'A cheque needs a named customer, because the amount stays owed until '
          'the bank clears it. Pick the customer before taking the cheque.';
    case 'CHEQUE_DETAILS_REQUIRED':
      final which = missing.isEmpty
          ? 'a cheque number, bank and cheque date'
          : 'the ${missing.join(', ')}';
      return 'A cheque needs its number, bank and date. Fill in $which and try '
          'again.';
    case 'CHEQUE_EXCEEDS_BALANCE':
      if (chequeTotal != null && owed != null) {
        return 'The cheque is ${_money(chequeTotal)} and the sale still owes '
            '${_money(owed)}. Lower the cheque, because change is paid from cash '
            'only.';
      }
      return 'A cheque cannot be more than the sale still owes, because change is '
          'paid from cash only.';
    default:
      return null;
  }
}

/// Any refusal the till maps: a discount code first, then a cheque code.
///
/// The two come from the same checkout call, so one function keeps the till from
/// having to know which feature refused it. `null` means the code is neither, and the
/// caller keeps the server's own detail.
String? posRefusalSentence(
  String? code, {
  double? capPercent,
  double? requestedPercent,
  List<String> missing = const [],
  double? chequeTotal,
  double? owed,
}) =>
    discountRefusalSentence(
      code,
      capPercent: capPercent,
      requestedPercent: requestedPercent,
    ) ??
    chequeRefusalSentence(
      code,
      missing: missing,
      chequeTotal: chequeTotal,
      owed: owed,
    );

String _money(double value) => value.toStringAsFixed(2);

/// `12.00` reads as `12`, `12.50` as `12.5`: a percent label, not a money amount.
String _percent(double value) {
  final text = value.toStringAsFixed(2);
  return text.endsWith('.00')
      ? text.substring(0, text.length - 3)
      : text.replaceFirst(RegExp(r'0+$'), '');
}

/// The larger of two amounts, kept here so callers do not import dart:math.
double largerOf(double a, double b) => math.max(a, b);
