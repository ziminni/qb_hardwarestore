/// One rule for a typed amount, for every screen that asks for money.
///
/// A price, a delivery fee and an order's fee are the same money: a number, not
/// negative, at most two decimals. `10.005` is refused by the server rather than
/// rounded, so the client refuses it too — and the two screens that used to hold
/// their own copy of this rule can no longer drift apart.
///
/// Only the RULE lives here. Each screen keeps its own sentence, because a clerk
/// reads "The delivery fee needs at most two decimals." on the till and
/// "At most two decimals." on an order form.
library;

/// Why a typed amount is refused, or null when the server would accept it.
enum MoneyInputProblem {
  /// Not a number at all, or below zero.
  notAnAmount,

  /// A third decimal, or any shape the cent cannot hold (`1e3`, `.5`, `1.`).
  moreThanTwoDecimals,
}

final RegExp _twoDecimals = RegExp(r'^\d+(\.\d{1,2})?$');

/// [value] judged as money: null when it is acceptable, else why not.
MoneyInputProblem? moneyInputProblem(String? value) {
  final text = (value ?? '').trim();
  final parsed = double.tryParse(text);
  if (parsed == null || parsed < 0) return MoneyInputProblem.notAnAmount;
  if (!_twoDecimals.hasMatch(text)) return MoneyInputProblem.moreThanTwoDecimals;
  return null;
}
