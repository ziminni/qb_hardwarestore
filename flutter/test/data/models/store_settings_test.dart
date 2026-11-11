// Phase 4 Task F3a: the store-wide settings the server owns (B1).
//
// The wire shape is `{"vat_registered": true, "vat_rate": "12.00",
// "discount_cap_percent": "10.00", "updated_at": "..."}`: DRF sends every
// `DecimalField` as a STRING, which is why the parsing here is string-first and
// why the patch body goes back as 2 dp strings (12.0 as a float can serialize as
// 11.999999999999998 on some platforms).

import 'package:client/data/models/store_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StoreSettings.fromJson', () {
    test('reads the DRF decimal strings', () {
      final settings = StoreSettings.fromJson(const {
        'vat_registered': false,
        'vat_rate': '0.00',
        'discount_cap_percent': '15.50',
        'updated_at': '2026-11-11T09:12:00Z',
      });

      expect(settings.vatRegistered, isFalse);
      expect(settings.vatRate, 0);
      expect(settings.discountCapPercent, 15.5);
      expect(settings.updatedAt, DateTime.utc(2026, 11, 11, 9, 12));
    });

    test('accepts JSON numbers too', () {
      final settings = StoreSettings.fromJson(const {
        'vat_registered': true,
        'vat_rate': 12,
        'discount_cap_percent': 7.25,
      });

      expect(settings.vatRegistered, isTrue);
      expect(settings.vatRate, 12);
      expect(settings.discountCapPercent, 7.25);
      expect(settings.updatedAt, isNull);
    });

    // A till might get this payload from a build that predates one of the
    // fields, so a missing field must not stop a sale. The defaults are the
    // server's own (B1: vat_registered true, vat_rate 12.00, cap 10.00) and the
    // cap default is deliberately the server's: 0 would refuse every discount
    // and 100 would allow any discount, and neither is a safe guess.
    test('missing fields fall back to the server defaults', () {
      final settings = StoreSettings.fromJson(const {});

      expect(StoreSettings.defaultVatRate, 12);
      expect(StoreSettings.defaultDiscountCapPercent, 10);
      expect(settings.vatRegistered, isTrue);
      expect(settings.vatRate, StoreSettings.defaultVatRate);
      expect(
        settings.discountCapPercent,
        StoreSettings.defaultDiscountCapPercent,
      );
      expect(settings.updatedAt, isNull);
    });

    test('an unreadable percent falls back instead of throwing', () {
      final settings = StoreSettings.fromJson(const {
        'vat_rate': 'twelve',
        'discount_cap_percent': 'NaN',
      });

      expect(settings.vatRate, StoreSettings.defaultVatRate);
      expect(
        settings.discountCapPercent,
        StoreSettings.defaultDiscountCapPercent,
      );
    });

    // A wrong TYPE is a broken contract, not a missing optional field, so it is
    // loud: silently reading "yes" as `true` would hide a serializer change.
    test('a non-bool vat_registered is a wire error', () {
      expect(
        () => StoreSettings.fromJson(const {'vat_registered': 'yes'}),
        throwsFormatException,
      );
    });
  });

  group('StoreSettings.toPatchJson', () {
    test('sends 2 dp strings, never floats', () {
      const settings = StoreSettings(
        vatRegistered: false,
        vatRate: 12,
        discountCapPercent: 15.5,
      );

      expect(settings.toPatchJson(), {
        'vat_registered': false,
        'vat_rate': '12.00',
        'discount_cap_percent': '15.50',
      });
    });
  });

  group('StoreSettings.percentError', () {
    test('accepts 0, 100 and anything with up to 2 dp', () {
      for (final raw in const ['0', '0.00', '7', '12.05', '100', '100.00']) {
        expect(StoreSettings.percentError(raw), isNull, reason: raw);
      }
    });

    test('refuses a value outside 0 to 100', () {
      for (final raw in const ['-1', '100.01', '101', '250']) {
        expect(StoreSettings.percentError(raw), isNotNull, reason: raw);
      }
    });

    test('refuses more than 2 decimal places', () {
      expect(
        StoreSettings.percentError('12.345'),
        contains('2 decimal places'),
      );
    });

    test('refuses blank and text', () {
      for (final raw in const ['', '   ', 'twelve', '12%']) {
        expect(StoreSettings.percentError(raw), isNotNull, reason: raw);
      }
    });
  });
}
