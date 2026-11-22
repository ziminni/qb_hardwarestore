import 'package:client/data/models/json_field.dart';

/// `held_cart_count`, read leniently when ABSENT and strictly when present.
///
/// The server always sends it on `current`, on the list and at close (Phase 3
/// Task 3), but a body that predates the field — or a proxy that trims unknown
/// keys — must not break the Shifts tab: "no carts" is the honest reading of a
/// count nobody sent. A count that IS sent is parsed strictly, because a wrong
/// warning about a cashier's parked carts is worse than none.
int _heldCartCount(Map<String, dynamic> json) {
  if (!json.containsKey('held_cart_count') || json['held_cart_count'] == null) {
    return 0;
  }
  return intField(json, 'held_cart_count');
}

double _optionalDecimalField(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return 0;
  }
  return decimalField(json, key);
}

/// A money field the server may send as `null`, where null means "not recorded"
/// and is NOT the same fact as `0.00` (owner ruling, drawer carry).
///
/// `null` stays null: "the drawer was cleared" and "nobody said what was left"
/// must not be shown as the same number.
double? _nullableMoney(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  return decimalField(json, key);
}

/// What `GET /shifts/opening-suggestion/` says the open-shift form may prefill.
///
/// `suggestedFloat` is null when there is no previous close OR that close did not
/// record what it left behind - the cashier then counts instead of being offered
/// a figure the server invented. `cleared` is true only when the last close
/// recorded exactly `0.00` (the float is entirely on the cashier starting now).
class ShiftOpeningSuggestion {
  const ShiftOpeningSuggestion({
    this.suggestedFloat,
    this.source,
    this.cleared = false,
  });

  factory ShiftOpeningSuggestion.fromJson(Map<String, dynamic> json) {
    final rawSource = json['source'];
    return ShiftOpeningSuggestion(
      suggestedFloat: _nullableMoney(json, 'suggested_float'),
      source: rawSource is Map<String, dynamic>
          ? ShiftOpeningSource.fromJson(rawSource)
          : null,
      cleared: boolFieldOr(json, 'cleared', or: false),
    );
  }

  final double? suggestedFloat;
  final ShiftOpeningSource? source;
  final bool cleared;
}

/// The previous close the suggestion came from, for the one sentence a cashier
/// reads (who closed it, when, what they counted).
class ShiftOpeningSource {
  const ShiftOpeningSource({
    required this.shiftId,
    required this.cashierName,
    required this.closingCount,
    this.closedAt,
    this.cashLeftInDrawer,
  });

  factory ShiftOpeningSource.fromJson(Map<String, dynamic> json) {
    return ShiftOpeningSource(
      shiftId: intField(json, 'shift_id'),
      cashierName: stringField(json, 'cashier_name'),
      closedAt: nullableDateField(json, 'closed_at'),
      closingCount: decimalField(json, 'closing_count'),
      cashLeftInDrawer: _nullableMoney(json, 'cash_left_in_drawer'),
    );
  }

  final int shiftId;
  final String cashierName;
  final DateTime? closedAt;
  final double closingCount;
  final double? cashLeftInDrawer;
}

/// A mid-shift cash withdrawal (`CASH_OUT`) or addition (`CASH_IN`) recorded on
/// an open shift so expected drawer cash accounts for safe drops / petty cash.
class ShiftCashMovement {
  const ShiftCashMovement({
    required this.id,
    required this.kind,
    required this.amount,
    required this.reason,
    required this.recordedByName,
    required this.createdAt,
    this.category = otherCategory,
  });

  factory ShiftCashMovement.fromJson(Map<String, dynamic> json) {
    return ShiftCashMovement(
      id: intField(json, 'id'),
      kind: stringField(json, 'kind'),
      category: json['category'] is String && (json['category'] as String).isNotEmpty
          ? json['category'] as String
          : otherCategory,
      amount: decimalField(json, 'amount'),
      reason: stringField(json, 'reason'),
      recordedByName: json['recorded_by_name'] is String
          ? json['recorded_by_name'] as String
          : '',
      createdAt: DateTime.parse(stringField(json, 'created_at')),
    );
  }

  static const cashOutKind = 'CASH_OUT';
  static const cashInKind = 'CASH_IN';

  static const lunchCategory = 'LUNCH';
  static const fuelCategory = 'FUEL';
  static const suppliesCategory = 'SUPPLIES';
  static const safeDropCategory = 'SAFE_DROP';
  static const changeFloatCategory = 'CHANGE_FLOAT';
  static const otherCategory = 'OTHER';

  static const Map<String, String> cashOutCategories = {
    lunchCategory: 'Lunch',
    fuelCategory: 'Fuel',
    suppliesCategory: 'Supplies',
    safeDropCategory: 'Safe drop',
    otherCategory: 'Other',
  };

  /// Standard PHP bills and coins supported by the shift-close denomination counter.
  static const List<({String key, String label, double value})> phpDenominations = [
    (key: '1000', label: '₱1,000', value: 1000),
    (key: '500', label: '₱500', value: 500),
    (key: '200', label: '₱200', value: 200),
    (key: '100', label: '₱100', value: 100),
    (key: '50', label: '₱50', value: 50),
    (key: '20', label: '₱20', value: 20),
    (key: '10', label: '₱10', value: 10),
    (key: '5', label: '₱5', value: 5),
    (key: '1', label: '₱1', value: 1),
    (key: '0.25', label: '₱0.25', value: 0.25),
  ];

  final int id;
  final String kind;
  final String category;
  final double amount;
  final String reason;
  final String recordedByName;
  final DateTime createdAt;

  bool get isCashOut => kind == cashOutKind;
}

/// The end-of-shift summary (Z-reading) returned with a closed shift.
///
/// Derived on the server from the shift's own transactions — never stored — so
/// asking twice can never show two different days.
class ZReading {
  const ZReading({
    required this.transactionCount,
    required this.grossSales,
    required this.cashSales,
    required this.cardSales,
    required this.gcashSales,
    required this.expectedDrawer,
    required this.variance,
    this.cashIn = 0,
    this.cashOut = 0,
    this.heldCartCount = 0,
    this.cashTakenOut,
    this.openingDifference,
  });

  factory ZReading.fromJson(Map<String, dynamic> json) {
    // `variance` is null while the shift is still OPEN: there is no closing
    // count to compare the drawer against yet. Every other field is always sent.
    return ZReading(
      transactionCount: intField(json, 'transaction_count'),
      grossSales: decimalField(json, 'gross_sales'),
      cashSales: decimalField(json, 'cash_sales'),
      cardSales: decimalField(json, 'card_sales'),
      gcashSales: decimalField(json, 'gcash_sales'),
      expectedDrawer: decimalField(json, 'expected_drawer'),
      variance: json['variance'] == null
          ? null
          : decimalField(json, 'variance'),
      cashIn: _optionalDecimalField(json, 'cash_in'),
      cashOut: _optionalDecimalField(json, 'cash_out'),
      // ADVISORY (Phase 3 Task 3): the count of carts still parked by this
      // cashier. Absent is read as 0 rather than failing — a fixture written
      // before the field existed must still parse — but a PRESENT value is read
      // strictly, because a count the client guessed would be a wrong warning.
      heldCartCount: _heldCartCount(json),
      // Owner ruling (drawer carry): what the cashier took to the safe
      // (`closing_count - cash_left`) and how far the drawer was from what the
      // previous close said it left. Null when there was nothing to compare.
      cashTakenOut: _nullableMoney(json, 'cash_taken_out'),
      openingDifference: _nullableMoney(json, 'opening_difference'),
    );
  }

  final int transactionCount;
  final double grossSales;
  final double cashSales;
  final double cardSales;
  final double gcashSales;
  final double expectedDrawer;
  final double cashIn;
  final double cashOut;

  /// Counted minus expected. Null until the shift is closed; non-zero is
  /// recorded and warned about, never blocked (decision 06, ruling 3).
  final double? variance;

  /// Parked carts the shift's cashier left behind (Phase 3 Task 3).
  ///
  /// ADVISORY ONLY: the close is recorded and warned about, never blocked, and
  /// the carts are never deleted — they can still be resumed (decision 06,
  /// record-and-warn). Defaults to 0 so a fixture written before the field
  /// existed still parses.
  final int heldCartCount;

  /// The deposit: `closing_count` minus what stayed in the drawer (owner ruling,
  /// drawer carry). Null when the close recorded no `cash_left`, which is a
  /// different fact from leaving `0.00`.
  final double? cashTakenOut;

  /// The opening float minus what the previous close said it left (server
  /// arithmetic). Null when there was no previous number to compare against.
  final double? openingDifference;
}

/// A cashier's shift — Phase 4 of the cashier workflow (decision 06).
///
/// The server assigns `cashier` from the request, so the client never chooses
/// the actor. `status` moves OPEN -> CLOSED once and never back, which is why it
/// is read-only on the wire and treated as read-only here.
class Shift {
  const Shift({
    required this.id,
    required this.cashierName,
    required this.status,
    required this.openingFloat,
    required this.closingCount,
    required this.openedAt,
    required this.closedAt,
    required this.notes,
    required this.zReading,
    this.heldCartCount = 0,
    this.cashMovements = const [],
    this.expectedOpening,
    this.cashLeftInDrawer,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    final zReading = json['z_reading'];
    final rawMovements = json['cash_movements'];
    return Shift(
      id: intField(json, 'id'),
      cashierName: stringField(json, 'cashier_name'),
      status: stringField(json, 'status'),
      openingFloat: decimalField(json, 'opening_float'),
      closingCount: json['closing_count'] == null
          ? null
          : decimalField(json, 'closing_count'),
      openedAt: DateTime.parse(stringField(json, 'opened_at')),
      closedAt: nullableDateField(json, 'closed_at'),
      notes: stringField(json, 'notes'),
      zReading: zReading is Map<String, dynamic>
          ? ZReading.fromJson(zReading)
          : null,
      heldCartCount: _heldCartCount(json),
      // Owner ruling (drawer carry): read-only wire facts. Null means the server
      // did not know / nobody recorded it - never coerced to 0.00.
      expectedOpening: _nullableMoney(json, 'expected_opening'),
      cashLeftInDrawer: _nullableMoney(json, 'cash_left_in_drawer'),
      cashMovements: rawMovements is List
          ? [
              for (final item in rawMovements)
                if (item is Map<String, dynamic>)
                  ShiftCashMovement.fromJson(item),
            ]
          : const [],
    );
  }

  static const openStatus = 'OPEN';
  static const closedStatus = 'CLOSED';

  final int id;
  final String cashierName;
  final String status;
  final double openingFloat;
  final double? closingCount;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String notes;

  /// Only complete on a closed shift — the server computes it at close and
  /// returns it with every later read of the same shift.
  final ZReading? zReading;

  /// Parked carts this cashier still has (Phase 3 Task 3).
  ///
  /// Advisory: the close dialog WARNS about them and closes anyway, and they
  /// stay resumable. Read-only on the wire — a client that could write it could
  /// silence the advisory.
  final int heldCartCount;

  /// Mid-shift cash withdrawals and additions recorded on this shift.
  final List<ShiftCashMovement> cashMovements;

  /// What the drawer was EXPECTED to start with, from the previous close
  /// store-wide (owner ruling). Null when there was no previous close, or that
  /// close recorded no `cash_left_in_drawer`.
  final double? expectedOpening;

  /// What this close said STAYS in the drawer. Null = not recorded; `0.00` =
  /// the drawer was cleared. The two are different facts and stay different.
  final double? cashLeftInDrawer;

  bool get isOpen => status == openStatus;
}
