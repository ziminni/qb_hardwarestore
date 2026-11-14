// Phase 4 Task F4b (decision 18): a CHEQUE is not money yet.
//
// The till must (a) refuse a cheque it cannot back with the three facts the server
// requires, (b) refuse one against the walk-in record, (c) never count a pending
// cheque as paid, and (d) send exactly the wire shape ENDPOINTS.md documents:
// {method: CHEQUE, amount_tendered: "8.00", cheque_number, bank, cheque_date}.

import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _openChequeDialog(
  WidgetTester tester, {
  double total = 20,
  bool customerIsNamed = true,
  String cash = '12',
}) async {
  // The dialog is taller than the default 800x600 test window, and a row below the
  // fold cannot be tapped (the tap would land nowhere).
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<PosPaymentDetails>(
              context: context,
              builder: (_) => PosPaymentDialog(
                total: total,
                customerIsNamed: customerIsNamed,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pos-tender-amount-0')),
    cash,
  );
  await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pos-tender-method-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cheque').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pos-tender-amount-1')),
    '8',
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the cheque wire shape', () {
    test('a cheque tender carries its number, bank and date', () {
      final json = const PosTender(
        method: TenderMethod.cheque,
        amount: 8,
        chequeNumber: 'CHQ-1001',
        bank: 'BDO',
        chequeDate: null,
      ).toJson();

      expect(json['method'], 'CHEQUE');
      expect(json['amount_tendered'], '8.00');
      expect(json['cheque_number'], 'CHQ-1001');
      expect(json['bank'], 'BDO');
    });

    test('the cheque date goes as YYYY-MM-DD, the shape parse_date takes', () {
      final json = const PosTender(
        method: TenderMethod.cheque,
        amount: 8,
        chequeNumber: 'CHQ-1001',
        bank: 'BDO',
      ).toJson();
      expect(json.containsKey('cheque_date'), isTrue);

      final dated = PosCheckoutPayment(
        method: 'CHEQUE',
        amountTendered: 8,
        chequeNumber: 'CHQ-1001',
        bank: 'BDO',
        chequeDate: DateTime(2026, 11, 20),
      ).toJson();
      expect(dated['cheque_date'], '2026-11-20');
    });

    test('a non-cheque tender sends no cheque fields at all', () {
      final json = const PosCheckoutPayment(
        method: 'CASH',
        amountTendered: 5,
      ).toJson();

      expect(json.containsKey('cheque_number'), isFalse);
      expect(json.containsKey('bank'), isFalse);
      expect(json.containsKey('cheque_date'), isFalse);
      expect(json['amount_tendered'], '5.00');
    });

    test('CHEQUE is offered at the till but never as a refund method', () {
      expect(TenderMethod.tillTenders, contains(TenderMethod.cheque));
      expect(
        TenderMethod.refundTenders.contains(TenderMethod.cheque),
        isFalse,
        reason:
            'the server refuses a CHEQUE refund; offering it would be a trap',
      );
      expect(TenderMethod.labelFor('CHEQUE'), 'Cheque');
    });
  });

  group('refusal copy', () {
    test('each cheque refusal tells the cashier what to do', () {
      expect(
        posRefusalSentence('CHEQUE_NEEDS_CUSTOMER'),
        contains('named customer'),
      );
      expect(
        posRefusalSentence('CHEQUE_DETAILS_REQUIRED', missing: ['bank']),
        contains('bank'),
      );
      expect(
        posRefusalSentence('CHEQUE_EXCEEDS_BALANCE', chequeTotal: 5, owed: 0),
        contains('cash only'),
      );
    });

    test('an unknown code keeps the server detail (no invented sentence)', () {
      expect(posRefusalSentence('SOMETHING_NEW'), isNull);
      expect(discountRefusalSentence('SOMETHING_NEW'), isNull);
    });
  });

  group('the dialog refuses a cheque it cannot back', () {
    testWidgets('a missing cheque date is caught before the round trip', (
      tester,
    ) async {
      await _openChequeDialog(tester);
      await tester.enterText(
        find.byKey(const ValueKey('pos-cheque-number-1')),
        'CHQ-1001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pos-cheque-bank-1')),
        'BDO',
      );
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cheque date'), findsWidgets);
      // Still open: nothing was handed back.
      expect(find.text('Payment'), findsOneWidget);
    });

    testWidgets('a cheque against the walk-in record is refused', (
      tester,
    ) async {
      await _openChequeDialog(tester, customerIsNamed: false);
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('named customer'), findsOneWidget);
    });

    testWidgets('a cheque bigger than what is owed is refused, never changed', (
      tester,
    ) async {
      // Cash already covers the 20, so the cheque has nothing left to hold.
      await _openChequeDialog(tester, cash: '20');
      await tester.enterText(
        find.byKey(const ValueKey('pos-cheque-number-1')),
        'CHQ-1001',
      );
      await tester.enterText(
        find.byKey(const ValueKey('pos-cheque-bank-1')),
        'BDO',
      );
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('cash only'), findsOneWidget);
    });

    testWidgets('a pending cheque is shown apart from what was paid now', (
      tester,
    ) async {
      await _openChequeDialog(tester);

      expect(find.text('Cheque pending (not counted as paid)'), findsOneWidget);
      expect(find.text('Paid now'), findsOneWidget);
      // The cheque is holding the remaining 8 open as utang, and the sentence
      // says a cheque holds it, never that it settled it.
      expect(find.textContaining('holds it open as utang'), findsOneWidget);
    });
  });
}
