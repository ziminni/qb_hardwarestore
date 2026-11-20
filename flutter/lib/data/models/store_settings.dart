import 'package:client/data/models/json_field.dart';

/// The store-wide settings the server owns (Phase 4 B1, singleton `StoreSettings`
/// in `apps/pos`), read through `GET /api/v1/store-settings/` and written through
/// `PATCH` (Admin only).
///
/// Wire shape: `{"vat_registered": true, "vat_rate": "12.00",
/// "discount_cap_percent": "10.00", "updated_at": "..."}`. DRF sends every
/// `DecimalField` as a STRING, so the percents are parsed string-first and sent
/// back as 2 dp strings: `12.0` as a double can serialize as
/// `11.999999999999998`, and the server would then store a rate nobody typed.
class StoreSettings {
  const StoreSettings({
    required this.vatRegistered,
    required this.vatRate,
    required this.discountCapPercent,
    this.tenderFees = const [],
    this.updatedAt,
  });

  /// The server's own defaults, repeated here for the two places a value can be
  /// absent: a payload from a build that predates a field, and the moment
  /// before the first load answers.
  ///
  /// The discount cap defaults to the server's 10.00 on purpose. 0 would refuse
  /// every discount and 100 would allow any discount, and neither is a safe
  /// guess for a till that has not heard from the server yet.
  static const double defaultVatRate = 12;
  static const double defaultDiscountCapPercent = 10;

  /// What a till uses until the first load answers.
  static const StoreSettings defaults = StoreSettings(
    vatRegistered: true,
    vatRate: defaultVatRate,
    discountCapPercent: defaultDiscountCapPercent,
  );

  /// Whether the store is VAT registered. When false, no VAT is broken out.
  final bool vatRegistered;

  /// VAT rate as a percent of the VAT-inclusive price (`12.00` = 12%).
  final double vatRate;

  /// The largest discount a cashier may take without an approval (`10.00` = 10%).
  final double discountCapPercent;

  /// Per-tender fees the shop charges on CARD / GCASH / BANK_TRANSFER (owner
  /// ruling). EMPTY on a fresh shop: no rate is invented here, ever.
  final List<TenderFee> tenderFees;

  /// When the server last stored these values, or null if it did not say.
  final DateTime? updatedAt;

  /// The active fee for a tender method, or null when the shop charges none.
  TenderFee? feeFor(String method) {
    for (final fee in tenderFees) {
      if (fee.isActive && fee.method == method) return fee;
    }
    return null;
  }

  /// What ONE payment row owes for [method] on [covered] - the server's own
  /// rule (`round(covered x value/100)` or the flat value), mirrored ONLY for
  /// the preview. The wire never carries it: the server recomputes and stores
  /// `fee`, and the receipt prints that stored number.
  double previewFee(String method, double covered) {
    final fee = feeFor(method);
    if (fee == null || covered <= 0) return 0;
    final raw = fee.kind == TenderFee.kindPercent
        ? covered * fee.value / 100
        : fee.value;
    return (raw * 100).roundToDouble() / 100;
  }

  factory StoreSettings.fromJson(Map<String, dynamic> json) {
    return StoreSettings(
      vatRegistered: boolFieldOr(json, 'vat_registered', or: true),
      vatRate: _percentOr(json, 'vat_rate', defaultVatRate),
      discountCapPercent: _percentOr(
        json,
        'discount_cap_percent',
        defaultDiscountCapPercent,
      ),
      tenderFees: nestedList(json, 'tender_fees', TenderFee.fromJson),
      updatedAt: nullableDateField(json, 'updated_at'),
    );
  }

  /// The PATCH body: 2 dp strings, the shape the serializer expects back.
  Map<String, dynamic> toPatchJson() => {
    'vat_registered': vatRegistered,
    'vat_rate': vatRate.toStringAsFixed(2),
    'discount_cap_percent': discountCapPercent.toStringAsFixed(2),
    // The list REPLACES the server's table: a method left out ends up with no
    // fee, which is the only reading of a list a client can reason about.
    'tender_fees': [for (final fee in tenderFees) fee.toJson()],
  };

  /// The one percent rule the form and the viewmodel share, as a sentence for
  /// the field, or null when [raw] is sendable.
  ///
  /// Negative values are refused explicitly: DRF would accept them, and a
  /// negative cap would block every discount with no explanation.
  static String? percentError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return 'Enter a number from 0 to 100.';
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) {
      return 'Enter a number from 0 to 100.';
    }
    if (value < 0 || value > 100) return 'Enter a number from 0 to 100.';
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot - 1 > 2) {
      return 'Use at most 2 decimal places.';
    }
    return null;
  }
}

/// A percent from the wire, falling back to [fallback] when it is absent or
/// unreadable.
///
/// Missing or malformed is not worth stopping a sale over, and the fallback is
/// the server's own default, so the client stays where the server would be.
/// A WRONG TYPE for a flag (see `vat_registered`) is still loud: that is a
/// changed contract, not a short payload.
double _percentOr(Map<String, dynamic> json, String key, double fallback) {
  final value = json[key];
  if (value == null) return fallback;
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
  if (parsed == null || !parsed.isFinite) return fallback;
  return parsed;
}

/// One per-tender fee row (`GET/PATCH /store-settings/` -> `tender_fees[]`).
///
/// Wire shape (server serializer): `{method, kind, value, is_active}` - the flag
/// is `is_active`, NOT `active`, and it is a real boolean. `value` is a
/// 2-decimal STRING like every other money field.
class TenderFee {
  const TenderFee({
    required this.method,
    required this.kind,
    required this.value,
    this.isActive = true,
  });

  static const kindPercent = 'PERCENT';
  static const kindAmount = 'AMOUNT';

  /// The ONLY methods a fee may attach to (the server refuses the rest).
  static const feeableMethods = ['GCASH', 'CARD', 'BANK_TRANSFER'];

  factory TenderFee.fromJson(Map<String, dynamic> json) {
    return TenderFee(
      method: stringField(json, 'method'),
      kind: stringField(json, 'kind'),
      value: decimalField(json, 'value'),
      isActive: boolFieldOr(json, 'is_active', or: true),
    );
  }

  final String method;
  final String kind;
  final double value;
  final bool isActive;

  TenderFee copyWith({String? kind, double? value, bool? isActive}) =>
      TenderFee(
        method: method,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => {
    'method': method,
    'kind': kind,
    'value': value.toStringAsFixed(2),
    'is_active': isActive,
  };

  String get label => switch (method) {
    'GCASH' => 'GCash',
    'CARD' => 'Card',
    'BANK_TRANSFER' => 'Bank transfer',
    _ => method,
  };
}
