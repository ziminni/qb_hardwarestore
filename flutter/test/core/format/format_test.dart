import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
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

  group('formatWeekdayDate', () {
    // The page header says which day it is, and a weekday name is what a
    // manager reads faster than a bare number.
    test('weekday, then month, day and year', () {
      expect(formatWeekdayDate(DateTime(2026, 10, 15)), 'Thu, Oct 15, 2026');
      expect(formatWeekdayDate(DateTime(2026, 11, 10)), 'Tue, Nov 10, 2026');
      expect(formatWeekdayDate(DateTime(2026, 10, 19)), 'Mon, Oct 19, 2026');
      expect(formatWeekdayDate(DateTime(2027, 1, 3)), 'Sun, Jan 3, 2027');
    });

    test('the pinned test clock (2026-10-15 10:00) is a Thursday', () {
      // flutter_test_config.dart pins appClock, so this is also the date every
      // golden shows in the header.
      expect(formatWeekdayDate(appClock.now()), 'Thu, Oct 15, 2026');
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

  group('formatQuantity', () {
    // FX4 (wave 3a fix pass): one quantity format for the app. D7: quantities
    // are counts when they are whole. "38.0 of 40.0 left" was a double leaking
    // through a display format, not a unit of measure.
    test('a whole quantity is a grouped count with no decimals', () {
      expect(formatQuantity(38), '38');
      expect(formatQuantity(38.0), '38');
      expect(formatQuantity(1200), '1,200');
      expect(formatQuantity(0.0), '0');
    });

    test('a fractional quantity keeps up to two decimals, no padding', () {
      expect(formatQuantity(0.5), '0.5');
      expect(formatQuantity(2.25), '2.25');
      expect(formatQuantity(1234.5), '1,234.5');
    });

    test('a negative quantity keeps its sign', () {
      expect(formatQuantity(-2), '-2');
      expect(formatQuantity(-0.5), '-0.5');
    });
  });

  group('formatSignedQuantity', () {
    test('a change carries its sign, a drop included', () {
      expect(formatSignedQuantity(10), '+10');
      expect(formatSignedQuantity(-2), '-2');
      expect(formatSignedQuantity(-0.5), '-0.5');
      expect(formatSignedQuantity(1200), '+1,200');
    });
  });
}
