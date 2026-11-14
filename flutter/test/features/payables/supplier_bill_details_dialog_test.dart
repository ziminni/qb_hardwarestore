// Phase 8 F3 (decision 20): a bill's payment history says how each payment
// stands and, for a credit, WHICH note settled it.
//
// Pinned here:
//   * a payment carries its own status (a supplier cheque is `Issued` until a
//     manager decides it), not just the bill's;
//   * a `CREDIT` row names the credit note — the whole point of the row is that
//     no money left the till;
//   * a bounced cheque shows why the bank refused it.

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/features/payables/widgets/supplier_bill_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SupplierBill _bill({List<SupplierPayment> payments = const []}) => SupplierBill(
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
  netAmount: 900,
  vatableAmount: 803.57,
  vatAmount: 96.43,
  vatRate: 12,
  totalAmount: 900,
  balanceAmount: 200,
  paidAmount: 700,
  status: SupplierBillStatus.partial,
  isOverdue: false,
  payments: payments,
);

SupplierPayment _payment({
  int id = 7,
  double amount = 400,
  SupplierPaymentMethod method = SupplierPaymentMethod.cheque,
  SupplierPaymentStatus? status = SupplierPaymentStatus.issued,
  int? creditNoteId,
  String decisionReason = '',
}) => SupplierPayment(
  id: id,
  billId: 4,
  amount: amount,
  method: method,
  methodCode: method.code,
  reference: '',
  chequeNumber: method == SupplierPaymentMethod.cheque ? '000123' : null,
  chequeBank: method == SupplierPaymentMethod.cheque ? 'BDO' : null,
  chequeDate: method == SupplierPaymentMethod.cheque
      ? DateTime(2026, 10, 20)
      : null,
  paidByName: 'Maria Santos',
  paidOn: DateTime(2026, 10, 20),
  status: status,
  statusCode: status?.code ?? '',
  decisionReason: decisionReason,
  creditNoteId: creditNoteId,
);

SupplierCreditNote _note() => SupplierCreditNote(
  id: 12,
  number: 'CN-20261113-0001',
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  supplierReturnId: 3,
  sourceBillId: 4,
  value: 267.86,
  vatRate: 12,
  vatInclusive: true,
  vatAmount: 32.14,
  totalAmount: 300,
  remainingAmount: 0,
  appliedAmount: 300,
  createdAt: DateTime(2026, 11, 13),
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

Future<void> _open(
  WidgetTester tester, {
  required SupplierBill bill,
  List<SupplierCreditNote> creditNotes = const [],
  Size size = const Size(1400, 900),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SupplierBillDetailsDialog(
                  bill: bill,
                  creditNotes: creditNotes,
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
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('a credit payment names the note that settled it', (
    tester,
  ) async {
    await _open(
      tester,
      bill: _bill(
        payments: [
          _payment(
            method: SupplierPaymentMethod.credit,
            status: SupplierPaymentStatus.cleared,
            creditNoteId: 12,
          ),
        ],
      ),
      creditNotes: [_note()],
    );

    expect(find.textContaining('CN-20261113-0001'), findsOneWidget);
    expect(find.textContaining('Supplier Credit'), findsOneWidget);
  });

  testWidgets('an unknown note id still reads, by its own number', (
    tester,
  ) async {
    await _open(
      tester,
      bill: _bill(
        payments: [
          _payment(
            method: SupplierPaymentMethod.credit,
            status: SupplierPaymentStatus.cleared,
            creditNoteId: 99,
          ),
        ],
      ),
    );

    expect(find.textContaining('Credit note #99'), findsOneWidget);
  });

  testWidgets('a supplier cheque shows its own status', (tester) async {
    await _open(tester, bill: _bill(payments: [_payment()]));

    expect(find.text('Issued'), findsOneWidget);
  });

  testWidgets('a bounced cheque shows the reason the bank gave', (
    tester,
  ) async {
    await _open(
      tester,
      bill: _bill(
        payments: [
          _payment(
            status: SupplierPaymentStatus.bounced,
            decisionReason: 'Insufficient funds',
          ),
        ],
      ),
    );

    expect(find.text('Bounced'), findsOneWidget);
    expect(find.textContaining('Insufficient funds'), findsOneWidget);
  });

  testWidgets('760 px at 1.3x text, the history renders whole', (tester) async {
    await _open(
      tester,
      bill: _bill(
        payments: [
          _payment(
            method: SupplierPaymentMethod.credit,
            status: SupplierPaymentStatus.cleared,
            creditNoteId: 12,
          ),
          _payment(id: 8),
        ],
      ),
      creditNotes: [_note()],
      size: const Size(760, 900),
      scale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('CN-20261113-0001'), findsOneWidget);
  });
}
