import 'package:client/core/format/format.dart';

/// One stock quantity as text.
///
/// Whole quantities are counts and group their thousands (D7, `1,248`).
/// Fractional ones keep two decimals instead of rounding: a batch can hold
/// 0.5 cubic metres, and "1" would be a number nobody put on the shelf.
String formatQuantity(double value) {
  if (value == value.truncateToDouble()) return formatCount(value.round());
  final fixed = value.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  return '${formatCount(int.parse(fixed.substring(0, dot)))}'
      '${fixed.substring(dot)}';
}

/// A signed quantity change, for an adjustment: `+10`, `-2`, `-0.50`.
String formatSignedQuantity(double value) =>
    '${value >= 0 ? '+' : '-'}${formatQuantity(value.abs())}';
