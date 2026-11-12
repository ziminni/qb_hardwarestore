// Item 10: one money rule for the order form and the till.
//
// This file pins the ACCEPTED SET, which is the part a deduplication can quietly
// change: both dialogs used to hold their own copy, and a screen that accepted
// `10.005` would send the server a figure it refuses rather than rounds.

import 'package:client/core/format/money_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money the server accepts is accepted here', () {
    for (final value in ['0', '0.5', '10', '10.5', '10.05', '1000.00', ' 250 ']) {
      expect(
        moneyInputProblem(value),
        isNull,
        reason: '"$value" is an amount the server charges',
      );
    }
  });

  test('a negative or unreadable amount is not money', () {
    for (final value in ['', '  ', '-1', '-0.01', 'ten']) {
      expect(
        moneyInputProblem(value),
        MoneyInputProblem.notAnAmount,
        reason: '"$value" must never reach the wire as a price',
      );
    }
  });

  test('a third decimal, or an exponent, is refused rather than rounded', () {
    for (final value in ['10.005', '0.001', '1e3']) {
      expect(
        moneyInputProblem(value),
        MoneyInputProblem.moreThanTwoDecimals,
        reason: '"$value" is a shape the cent cannot hold',
      );
    }
  });
}
