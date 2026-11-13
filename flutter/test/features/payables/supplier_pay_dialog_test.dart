// Phase 5 F2 (decision 18): the pay dialog.
//
// Pinned here:
//   * the amount is prefilled with the balance as a PLAIN parseable number
//     ("400.00", no peso sign, no thousands separator) so a clerk can edit it;
//   * a partial payment is allowed, and a settled bill is never offered;
//   * the three cheque facts are required ONLY for a cheque;
//   * the button posts once and stays disabled while it does;
//   * a refusal is shown in the server's own sentence, inside the dialog, so
//     the clerk can correct the amount without retyping the rest;
//   * at 760 px with 1.3x text and the real fonts nothing clips.

import 'dart:async';
import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/features/payables/widgets/supplier_pay_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SupplierBill _bill({double balance = 400, double total = 900}) => SupplierBill(
  id: 4,
  receiptId: 9,
  purchaseOrderId: 41,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  receivedDate: DateTime(2026, 10, 1),
  termsDays: 30,
  dueDate: DateTime(2026, 10, 31),
  grossAmount: 1000,
  discountAmount: 100,
  netAmount: total,
  vatableAmount: 803.57,
  vatAmount: 96.43,
  vatRate: 12,
  totalAmount: total,
  balanceAmount: balance,
  paidAmount: total - balance,
  status: balance > 0 ? SupplierBillStatus.partial : SupplierBillStatus.paid,
  isOverdue: true,
  payments: const [],
);

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

/// What the dialog handed to the viewmodel, and what it was told back.
class _Posted {
  final List<SupplierPaymentRequest> requests = [];
  String? failure;
  Completer<void>? hold;
}

Future<_Posted> _open(
  WidgetTester tester, {
  SupplierBill? bill,
  List<SupplierCreditNote> creditNotes = const [],
  Size size = const Size(1440, 900),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final posted = _Posted();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => SupplierPayDialog(
                  bill: bill ?? _bill(),
                  creditNotes: creditNotes,
                  onSubmit: (request) async {
                    posted.requests.add(request);
                    final hold = posted.hold;
                    if (hold != null) await hold.future;
                    return posted.failure;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return posted;
}

Finder _amount() => find.byKey(const ValueKey('pay-amount'));
Finder _submit() => find.widgetWithText(FilledButton, 'Record payment');
Finder _applyCredit() => find.byKey(const ValueKey('pay-apply-credit'));
Finder _notePicker() => find.byKey(const ValueKey('pay-credit-note'));

SupplierCreditNote _note({
  int id = 12,
  String number = 'CN-20261113-0001',
  double total = 300,
  double remaining = 200,
}) => SupplierCreditNote(
  id: id,
  number: number,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  supplierReturnId: 3,
  sourceBillId: 4,
  value: 267.86,
  vatRate: 12,
  vatInclusive: true,
  vatAmount: 32.14,
  totalAmount: total,
  remainingAmount: remaining,
  appliedAmount: total - remaining,
  createdAt: DateTime(2026, 11, 13),
);

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('the amount is prefilled with the balance as a plain number', (
    tester,
  ) async {
    await _open(tester);

    final field = tester.widget<TextFormField>(_amount());
    expect(field.controller?.text, '400.00');
    expect(field.controller?.text, isNot(contains('₱')));
    expect(field.controller?.text, isNot(contains(',')));
    expect(double.parse(field.controller!.text), 400);
  });

  testWidgets('a partial payment is allowed and sent as 2 dp text', (
    tester,
  ) async {
    final posted = await _open(tester);

    await tester.enterText(_amount(), '100');
    await tester.tap(_submit());
    await tester.pumpAndSettle();

    final request = posted.requests.single;
    expect(request.amount, 100);
    expect(request.method, SupplierPaymentMethod.cash);
    expect(request.amount.toStringAsFixed(2), '100.00');
  });

  testWidgets('the cheque facts appear and are required only for a cheque', (
    tester,
  ) async {
    final posted = await _open(tester);
    expect(find.byKey(const ValueKey('pay-cheque-number')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pay-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheque').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pay-cheque-number')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-cheque-bank')), findsOneWidget);
    expect(find.byKey(const ValueKey('pay-cheque-date')), findsOneWidget);

    await tester.tap(_submit());
    await tester.pumpAndSettle();

    expect(posted.requests, isEmpty, reason: 'a cheque needs its three facts');
    expect(find.textContaining('A cheque needs its number'), findsOneWidget);
  });

  testWidgets('a cheque with its three facts posts them', (tester) async {
    final posted = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('pay-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheque').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('pay-cheque-number')),
      '000123',
    );
    await tester.enterText(
      find.byKey(const ValueKey('pay-cheque-bank')),
      'BDO',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('pay-cheque-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pay-cheque-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(_submit());
    await tester.pumpAndSettle();

    final request = posted.requests.single;
    expect(request.method, SupplierPaymentMethod.cheque);
    expect(request.chequeNumber, '000123');
    expect(request.chequeBank, 'BDO');
    expect(request.chequeDate, isNotNull);
  });

  testWidgets('the button posts once and stays disabled while it does', (
    tester,
  ) async {
    final posted = await _open(tester);
    posted.hold = Completer<void>();

    await tester.tap(_submit());
    await tester.pump();

    expect(tester.widget<FilledButton>(_submit()).onPressed, isNull);
    await tester.tap(_submit(), warnIfMissed: false);
    await tester.pump();
    expect(posted.requests, hasLength(1));

    posted.hold!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a refusal is shown in the server sentence and the form stays', (
    tester,
  ) async {
    final posted = await _open(tester);
    posted.failure =
        'Bill #4 has 400.00 left to pay: 999.00 is more than that.';

    await tester.enterText(_amount(), '999');
    await tester.tap(_submit());
    await tester.pumpAndSettle();

    expect(find.text(posted.failure!), findsOneWidget);
    expect(
      _amount(),
      findsOneWidget,
      reason: 'the clerk corrects, not retypes',
    );
  });

  testWidgets('760 px at 1.3x text, a cheque form shows whole values', (
    tester,
  ) async {
    await _open(tester, size: const Size(760, 900), scale: 1.3);

    await tester.tap(find.byKey(const ValueKey('pay-method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheque').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Record payment').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pay-amount')).hitTestable(),
      findsOneWidget,
    );
  });

  // Phase 8 F3 (decision 20 #1/#4): applying a credit note from the pay dialog.
  group('apply credit', () {
    testWidgets("the supplier's open notes are what the picker offers", (
      tester,
    ) async {
      await _open(
        tester,
        creditNotes: [
          _note(id: 12, remaining: 200),
          _note(id: 13, number: 'CN-20261113-0002', remaining: 0, total: 90),
        ],
      );

      await tester.tap(_applyCredit());
      await tester.pumpAndSettle();

      await tester.tap(_notePicker());
      await tester.pumpAndSettle();

      expect(find.textContaining('CN-20261113-0001'), findsWidgets);
      expect(
        find.textContaining('CN-20261113-0002'),
        findsNothing,
        reason: 'a spent note has nothing left to spend',
      );
    });

    testWidgets('picking a note caps the amount at what it still has', (
      tester,
    ) async {
      final posted = await _open(
        tester,
        // The note holds less than the bill owes, so the note is the cap.
        bill: _bill(balance: 400),
        creditNotes: [_note(remaining: 200)],
      );

      await tester.tap(_applyCredit());
      await tester.pumpAndSettle();
      await tester.tap(_notePicker());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CN-20261113-0001').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextFormField>(_amount()).controller?.text,
        '200.00',
      );

      await tester.tap(_submit());
      await tester.pumpAndSettle();

      final request = posted.requests.single;
      expect(request.method, SupplierPaymentMethod.credit);
      expect(request.creditNoteId, 12);
      expect(request.amount, 200);
    });

    testWidgets('a note worth more than the bill caps at the balance', (
      tester,
    ) async {
      await _open(
        tester,
        bill: _bill(balance: 50),
        creditNotes: [_note(remaining: 200)],
      );

      await tester.tap(_applyCredit());
      await tester.pumpAndSettle();
      await tester.tap(_notePicker());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CN-20261113-0001').last);
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(_amount()).controller?.text, '50.00');
    });

    testWidgets('more than the note has left is refused before posting', (
      tester,
    ) async {
      final posted = await _open(tester, creditNotes: [_note(remaining: 200)]);

      await tester.tap(_applyCredit());
      await tester.pumpAndSettle();
      await tester.tap(_notePicker());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CN-20261113-0001').last);
      await tester.pumpAndSettle();

      await tester.enterText(_amount(), '250');
      await tester.tap(_submit());
      await tester.pumpAndSettle();

      expect(posted.requests, isEmpty);
      expect(
        find.textContaining('${formatPeso(200)} left'),
        findsWidgets,
        reason: "the clerk is told the note's own limit",
      );
    });

    testWidgets("the server's refusal wins over the client cap", (
      tester,
    ) async {
      final posted = await _open(tester, creditNotes: [_note(remaining: 200)]);
      posted.failure =
          'Credit note CN-20261113-0001 has 100.00 left: 200.00 is more ';

      await tester.tap(_applyCredit());
      await tester.pumpAndSettle();
      await tester.tap(_notePicker());
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('CN-20261113-0001').last);
      await tester.pumpAndSettle();
      await tester.tap(_submit());
      await tester.pumpAndSettle();

      expect(find.text(posted.failure!), findsOneWidget);
      expect(_amount(), findsOneWidget, reason: 'the form stays to correct');
    });

    testWidgets('with no credit on file the dialog offers no Apply credit', (
      tester,
    ) async {
      await _open(tester);

      expect(_applyCredit(), findsNothing);
    });
  });
}
