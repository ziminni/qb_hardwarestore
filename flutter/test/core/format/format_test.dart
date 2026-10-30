import 'package:client/core/format/format.dart';
import 'package:flutter_test/flutter_test.dart';

/// D1 (money), D6 (dates), D7 (counts): one format for the whole app.
void main() {
  group('formatPeso', () {
    test('adds a leading peso sign, thousands separators and 2 decimals', () {
      expect(formatPeso(1480), '₱1,480.00');
      expect(formatPeso(1480.5), '₱1,480.50');
      expect(formatPeso(1234567.89), '₱1,234,567.89');
      expect(formatPeso(999.999), '₱1,000.00');
    });

    test('zero is ₱0.00', () {
      expect(formatPeso(0), '₱0.00');
      expect(formatPeso(0.0), '₱0.00');
    });

    test('a negative amount puts the sign before the peso sign', () {
      expect(formatPeso(-25.5), '-₱25.50');
      expect(formatPeso(-1234.5), '-₱1,234.50');
    });

    test('no thousands separator below 1000', () {
      expect(formatPeso(7), '₱7.00');
      expect(formatPeso(999.99), '₱999.99');
    });
  });

  group('formatDate', () {
    test('month name, day, year', () {
      expect(formatDate(DateTime(2026, 10, 29)), 'Oct 29, 2026');
      expect(formatDate(DateTime(2026, 1, 5)), 'Jan 5, 2026');
    });
  });

  group('formatDateTime', () {
    test('12-hour clock with AM/PM', () {
      expect(
        formatDateTime(DateTime(2026, 10, 29, 14, 14)),
        'Oct 29, 2026, 2:14 PM',
      );
      expect(
        formatDateTime(DateTime(2026, 1, 5, 9, 5)),
        'Jan 5, 2026, 9:05 AM',
      );
    });

    test('midnight and noon are 12 AM and 12 PM', () {
      expect(
        formatDateTime(DateTime(2026, 10, 29, 0, 0)),
        'Oct 29, 2026, 12:00 AM',
      );
      expect(
        formatDateTime(DateTime(2026, 10, 29, 12, 0)),
        'Oct 29, 2026, 12:00 PM',
      );
    });
  });

  group('formatCount', () {
    test('thousands separators, no decimals', () {
      expect(formatCount(1248), '1,248');
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1234567), '1,234,567');
    });

    test('a negative count keeps its sign', () {
      expect(formatCount(-1248), '-1,248');
    });
  });
}
