// Phase 4 Task F4 (decision 18): the discount math the till previews.
//
// The server is the authority on every number here. These tests pin the PREVIEW the
// cashier reads before pressing Complete sale, and the mapping from the server's four
// refusal codes to sentences: a wrong preview is not a wrong receipt, but it is the
// number the cashier says out loud to the customer.

import 'package:client/data/models/sale_discount.dart';
import 'package:flutter_test/flutter_test.dart';

PosDiscount _amount(double value, [String reason = 'bulk order']) =>
    PosDiscount(kind: DiscountKind.amount, value: value, reason: reason);

PosDiscount _percent(double value, [String reason = 'loyal customer']) =>
    PosDiscount(kind: DiscountKind.percent, value: value, reason: reason);

void main() {
  group('PosDiscountAmounts', () {
    test('a peso discount comes straight off the gross', () {
      final amounts = PosDiscountAmounts.forDiscount(1000, _amount(100));

      expect(amounts.discountAmount, 100);
      expect(amounts.net, 900);
    });

    test('a percent discount is of the GROSS, not of the net', () {
      // B1: percent is of gross. 10% of 250.50 is 25.05, and the net is 225.45.
      final amounts = PosDiscountAmounts.forDiscount(250.50, _percent(10));

      expect(amounts.discountAmount, 25.05);
      expect(amounts.net, 225.45);
    });

    test('a peso discount bigger than the gross is clamped to it', () {
      // The server refuses this with INVALID_DISCOUNT; the preview must not show a
      // negative amount due on the way there.
      final amounts = PosDiscountAmounts.forDiscount(100, _amount(250));

      expect(amounts.discountAmount, 100);
      expect(amounts.net, 0);
    });

    test('no discount leaves gross and net equal', () {
      final amounts = PosDiscountAmounts.forDiscount(315, null);

      expect(amounts.discountAmount, 0);
      expect(amounts.net, 315);
      expect(amounts.percentOfGross, 0);
    });

    test('percentOfGross is the number the cap is compared against', () {
      final amounts = PosDiscountAmounts.forDiscount(200, _amount(30));

      expect(amounts.percentOfGross, 15);
    });

    test('a discount AT the cap does not need approval', () {
      final amounts = PosDiscountAmounts.forDiscount(200, _percent(10));

      expect(amounts.needsApproval(10), isFalse);
    });

    test('a discount ABOVE the cap needs approval', () {
      final amounts = PosDiscountAmounts.forDiscount(200, _percent(10.01));

      expect(amounts.needsApproval(10), isTrue);
    });

    test('a zero discount never needs approval, even at a zero cap', () {
      final amounts = PosDiscountAmounts.forDiscount(200, null);

      expect(amounts.needsApproval(0), isFalse);
    });

    test('the wire carries the kind, a 2 dp value and the reason', () {
      final json = _percent(12.5).toJson();

      expect(json['kind'], 'PERCENT');
      // A double can serialize as 12.499999999999998; the server stores strings.
      expect(json['value'], '12.50');
      expect(json['reason'], 'loyal customer');
    });
  });

  group('discountRefusalSentence', () {
    test('each discount code names a different action', () {
      final sentences = {
        for (final code in [
          'DISCOUNT_REASON_REQUIRED',
          'DISCOUNT_OVER_CAP',
          'DISCOUNT_APPROVAL_INVALID',
          'INVALID_DISCOUNT',
        ])
          code: discountRefusalSentence(code),
      };

      expect(sentences.values.every((s) => s != null), isTrue);
      expect(
        sentences.values.toSet(),
        hasLength(4),
        reason: 'four codes mean four different things to do next',
      );
    });

    test('the over-cap sentence names the cap and what was asked', () {
      final sentence = discountRefusalSentence(
        'DISCOUNT_OVER_CAP',
        capPercent: 10,
        requestedPercent: 15,
      );

      expect(sentence, contains('15%'));
      expect(sentence, contains('10%'));
      expect(sentence, contains('Store Manager'));
    });

    test('an approval refusal tells the cashier to ask again', () {
      final sentence = discountRefusalSentence('DISCOUNT_APPROVAL_INVALID');

      expect(sentence, contains('approve'));
    });

    test('a code that is not a discount code is left to the caller', () {
      expect(discountRefusalSentence('INSUFFICIENT_STOCK'), isNull);
      expect(discountRefusalSentence(null), isNull);
    });

    test('no sentence uses an em dash (house copy rule)', () {
      for (final code in [
        'DISCOUNT_REASON_REQUIRED',
        'DISCOUNT_OVER_CAP',
        'DISCOUNT_APPROVAL_INVALID',
        'INVALID_DISCOUNT',
      ]) {
        expect(discountRefusalSentence(code), isNot(contains('—')));
      }
    });
  });
}
