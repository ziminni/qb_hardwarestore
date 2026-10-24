/// The tender methods a till may take, and the ONE place the wire code and the
/// cashier-facing label are defined (C1, 2026-10-24).
///
/// The till could not sell: the payment dialog's dropdown held the display labels
/// ('Cash', 'GCash', 'Card') and `_pay` put whichever one was picked straight into the
/// checkout body as `payments[].method`. The server validates that field strictly
/// (`Payment.Method` codes only, Phase 1 `3c2349e`), so every sale was answered
///
///     400 INVALID_SALE — "'Cash' is not a payment method this till takes."
///
/// A `String` for the method let the two meanings share one type. This enum separates
/// them: [code] is what goes on the wire (`CASH`), [label] is what the cashier reads
/// (`Cash`). Anything that parses a method back out of a server response goes through
/// [labelFor], which tolerates the legacy label rows the database still holds.
enum TenderMethod {
  cash(code: 'CASH', label: 'Cash'),
  card(code: 'CARD', label: 'Card'),
  gcash(code: 'GCASH', label: 'GCash'),
  bankTransfer(code: 'BANK_TRANSFER', label: 'Bank transfer');

  const TenderMethod({required this.code, required this.label});

  /// What the server stores and accepts — `Payment.Method`.
  final String code;

  /// What the cashier sees.
  final String label;

  /// The methods the TILL offers today, in the order the dialog lists them.
  ///
  /// Bank transfer is deliberately absent: no screen at the counter takes one (the
  /// money arrives in an account, not the drawer), and offering it here would ask the
  /// cashier to record a tender they cannot verify. It stays in [values] because the
  /// server accepts it on a refund and a historical sale can carry it.
  static const List<TenderMethod> tillTenders = [cash, card, gcash];

  /// The methods a REFUND may be paid out in (`process_return`'s allowed set), cash
  /// first because only cash moves the expected drawer.
  static const List<TenderMethod> refundTenders = [
    cash,
    card,
    gcash,
    bankTransfer,
  ];

  /// The method [value] names, or null when it names none of them.
  ///
  /// Accepts a wire code (`CASH`), a label (`Cash`, `Bank transfer`) and a legacy row
  /// that predates the codes, matching case-insensitively and ignoring spaces — the
  /// database holds `'Cash'` rows written by the pre-Phase-1 till, and a receipt for one
  /// of them must still print.
  static TenderMethod? fromWire(String? value) {
    if (value == null) return null;
    final wanted = _key(value);
    if (wanted.isEmpty) return null;
    for (final method in values) {
      if (method.code == wanted) return method;
    }
    return null;
  }

  /// The label for a method read from the server, for display only.
  ///
  /// An unknown value is returned VERBATIM rather than blanked or thrown on: a method
  /// this client does not know (a server that gains one) is still a fact about the sale,
  /// and a receipt with no method line is worse than one with an unfamiliar word.
  static String labelFor(String? value) {
    final method = fromWire(value);
    if (method != null) return method.label;
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? '—' : trimmed;
  }

  /// `'Bank Transfer'`, `'bank_transfer'` and `'BANK_TRANSFER'` all become `BANK_TRANSFER`.
  static String _key(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '_');
}
