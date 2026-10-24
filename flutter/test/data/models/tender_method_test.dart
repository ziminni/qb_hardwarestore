// C1 — the ONE tender-method table: wire code on one side, label on the other.
//
// The till could not sell because a `String` carried both meanings. These tests pin the
// two directions: a code and a label both resolve to the same method, and a value this
// client does not know is displayed VERBATIM rather than blanked or thrown on (the
// database still holds pre-Phase-1 label rows, and a receipt for one must print).

import 'package:client/data/models/tender_method.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every method carries its wire code and its label', () {
    expect(TenderMethod.cash.code, 'CASH');
    expect(TenderMethod.cash.label, 'Cash');
    expect(TenderMethod.card.code, 'CARD');
    expect(TenderMethod.gcash.code, 'GCASH');
    expect(TenderMethod.bankTransfer.code, 'BANK_TRANSFER');
    expect(TenderMethod.bankTransfer.label, 'Bank transfer');
  });

  test('the till offers three tenders, and never the bank transfer', () {
    expect(TenderMethod.tillTenders, [
      TenderMethod.cash,
      TenderMethod.card,
      TenderMethod.gcash,
    ]);
    expect(
      TenderMethod.refundTenders.contains(TenderMethod.bankTransfer),
      isTrue,
      reason: 'a refund may be paid out in a method the till cannot take',
    );
  });

  test('a code, a label and a legacy row all resolve to the same method', () {
    expect(TenderMethod.fromWire('CASH'), TenderMethod.cash);
    expect(TenderMethod.fromWire('Cash'), TenderMethod.cash);
    expect(TenderMethod.fromWire(' cash '), TenderMethod.cash);
    expect(TenderMethod.fromWire('GCash'), TenderMethod.gcash);
    expect(TenderMethod.fromWire('Bank Transfer'), TenderMethod.bankTransfer);
    expect(TenderMethod.fromWire('bank_transfer'), TenderMethod.bankTransfer);
  });

  test('an unknown method resolves to nothing, and displays as itself', () {
    expect(TenderMethod.fromWire('MAYA'), isNull);
    expect(TenderMethod.fromWire(null), isNull);
    expect(TenderMethod.labelFor('MAYA'), 'MAYA');
    expect(TenderMethod.labelFor(null), '—');
    expect(TenderMethod.labelFor('  '), '—');
  });

  test('labelFor never crashes on a legacy label value', () {
    expect(TenderMethod.labelFor('Cash'), 'Cash');
    expect(TenderMethod.labelFor('RETURN_CREDIT'), 'RETURN_CREDIT');
  });
}
