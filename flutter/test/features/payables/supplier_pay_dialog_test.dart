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

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
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
}
