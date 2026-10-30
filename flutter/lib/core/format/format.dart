/// One money format, one date format, one count format for the whole app.
///
/// D1: money is `₱1,480.00` (peso sign, thousands separators, 2 decimals,
/// negatives written `-₱25.50`). D6: dates are `Oct 29, 2026` and date-times
/// are `Oct 29, 2026, 2:14 PM`. D7: plain counts are `1,248`.
///
/// Hand-written instead of `intl` because `intl` is not a dependency and D19
/// keeps this refresh free of new packages.
library;

const String _peso = '₱';
const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `1480` becomes `₱1,480.00`, `-25.5` becomes `-₱25.50`.
String formatPeso(num amount) {
  final fixed = amount.abs().toStringAsFixed(2);
  // A tiny negative rounds to 0.00; showing "-₱0.00" would be nonsense.
  final sign = amount < 0 && fixed != '0.00' ? '-' : '';
  final dot = fixed.indexOf('.');
  final whole = _groupThousands(fixed.substring(0, dot));
  return '$sign$_peso$whole${fixed.substring(dot)}';
}

/// `DateTime(2026, 10, 29)` becomes `Oct 29, 2026`.
String formatDate(DateTime value) =>
    '${_months[value.month - 1]} ${value.day}, ${value.year}';

/// `DateTime(2026, 10, 29, 14, 14)` becomes `Oct 29, 2026, 2:14 PM`.
String formatDateTime(DateTime value) {
  final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour < 12 ? 'AM' : 'PM';
  return '${formatDate(value)}, $hour12:$minute $meridiem';
}

/// `1248` becomes `1,248`.
String formatCount(int value) {
  final digits = value.abs().toString();
  final sign = value < 0 ? '-' : '';
  return '$sign${_groupThousands(digits)}';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
