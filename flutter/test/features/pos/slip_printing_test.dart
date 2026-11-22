import 'dart:convert';

import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/features/pos/widgets/pos_return_receipt.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _RecordingReturnPrinter implements ReturnSlipPrinter {
  final List<ReturnSlipData> printed = [];

  @override
  Future<void> print(ReturnSlipData slip) async {
    printed.add(slip);
  }
}

class _RecordingUtangPrinter implements UtangPaymentSlipPrinter {
  final List<UtangPaymentSlipData> printed = [];

  @override
  Future<void> print(UtangPaymentSlipData slip) async {
    printed.add(slip);
  }
}

class _StubReturnsRepo extends ReturnsRepository {
  @override
  Future<TransactionRecord?> findSale(String query) async => TransactionRecord(
    id: 18,
    transactionNo: 'OS-20261122-0007',
    transDate: DateTime(2026, 11, 22, 9),
    customerId: 2,
    customerName: 'Maria Santos',
    cashierName: 'Ana Cruz',
    source: 'CHARGE',
    originalTransactionId: null,
    status: 'COMPLETED',
    grandTotal: 1000,
    items: const [],
    payments: const [],
  );

  @override
  Future<ReturnableSale> fetchReturnable(int transactionId) async =>
      const ReturnableSale(
        transactionNo: 'OS-20261122-0007',
        customer: 'Maria Santos',
        source: 'CHARGE',
        returnable: true,
        reasonIfNot: null,
        openDebt: 600,
        lines: [
          ReturnableLine(
            variantUomId: 8,
            name: 'Portland Cement - 40kg',
            uom: 'BAG',
            soldQty: 10,
            returnedQty: 0,
            remainingQty: 10,
            unitPrice: 100,
          ),
        ],
      );

  @override
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async => const ReturnResult(
    returnNo: 'RTN-20261122-0001',
    refund: RefundSummary(
      returnValue: 800,
      debtReduced: 600,
      cashRefund: 200,
      refundMethod: 'CASH',
      ledgerId: 5,
      ledgerBalance: 0,
    ),
  );
}

class _StubShiftService extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 4,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 11, 22, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

class _StubLedgerRepo extends LedgerRepository {
  double balance = 472;
  List<LedgerPayment> payments = [];

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => [
    LedgerEntry(
      id: 4,
      customerId: 2,
      customerName: 'Dela Cruz Construction',
      projectName: 'Site A',
      transactionNo: 'OS-20261122-0007',
      originalAmount: 5000,
      balanceDue: balance,
      dueDate: appClock.now().add(const Duration(days: 30)),
      isOverdue: false,
    ),
  ];

  @override
  Future<List<LedgerPayment>> fetchPayments({String? search}) async => payments;

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    TenderMethod method = TenderMethod.cash,
    String? officialReceiptNo,
  }) async {
    balance = (balance - amountPaid).clamp(0, double.infinity);
    payments = [
      LedgerPayment(
        id: 91,
        collectibleId: collectibleId,
        customerName: 'Dela Cruz Construction',
        projectName: 'Site A',
        transactionNo: 'OS-20261122-0007',
        amountPaid: amountPaid,
        paymentMethod: method.code,
        paymentDate: DateTime(2026, 11, 22, 14, 15),
        officialReceiptNo: 'PAY-0091',
        processedByName: 'Ana Cruz',
      ),
      ...payments,
    ];
  }
}

void main() {
  group('ESC/POS slip builders', () {
    test('buildReturnSlipEscPos outputs ASCII-safe Return Slip matching server figures', () {
      final bytes = buildReturnSlipEscPos(
        ReturnSlipData(
          returnNo: 'RTN-20261122-0001',
          transactionNo: 'OS-20261122-0007',
          customerName: 'Maria Santos',
          cashierName: 'Ana Cruz',
          reason: 'Cracked sacks',
          printedAt: DateTime(2026, 11, 22, 14, 0),
          lines: const [(name: 'Portland Cement - 40kg', uom: 'BAG', qty: 8)],
          returnValue: 800,
          debtReduced: 600,
          cashRefund: 200,
          refundMethod: 'CASH',
          ledgerId: 5,
          ledgerBalance: 0,
        ),
      );
      final text = latin1.decode(bytes);
      expect(text, contains('QUEEN BUILDERS'));
      expect(text, contains('RETURN SLIP'));
      expect(text, contains('RTN-20261122-0001'));
      expect(text, contains('OS-20261122-0007'));
      expect(text, contains('Maria Santos'));
      expect(text, contains('Portland Cement - 40kg'));
      expect(text, contains('PHP 800.00'));
      expect(text, contains('PHP 600.00'));
      expect(text, contains('PHP 200.00'));
      expect(text, contains('Not an Official Receipt'));
      expect(text, contains('Thank you!'));
      expect(text, isNot(contains('\u20b1')));
    });

    test('buildUtangPaymentSlipEscPos formats posted cash payment and pending cheque clearly', () {
      final paidBytes = buildUtangPaymentSlipEscPos(
        UtangPaymentSlipData(
          customerName: 'Dela Cruz Construction',
          projectName: 'Site A',
          transactionNo: 'OS-20261122-0007',
          paymentId: 91,
          referenceNo: 'PAY-0091',
          paymentMethod: 'CASH',
          amountPaid: 472,
          previousBalance: 472,
          remainingBalance: 0,
          recordedBy: 'Ana Cruz',
          paymentDate: DateTime(2026, 11, 22, 14, 15),
        ),
      );
      final paidText = latin1.decode(paidBytes);
      expect(paidText, contains('UTANG PAYMENT SLIP'));
      expect(paidText, contains('Dela Cruz Construction'));
      expect(paidText, contains('OS-20261122-0007'));
      expect(paidText, contains('Ref: PAY-0091'));
      expect(paidText, contains('PHP 472.00'));
      expect(paidText, contains('PHP 0.00 (PAID)'));
      expect(paidText, contains('Not an Official Receipt'));
      expect(paidText, isNot(contains('\u20b1')));

      final chequeBytes = buildUtangPaymentSlipEscPos(
        UtangPaymentSlipData(
          customerName: 'Dela Cruz Construction',
          transactionNo: 'OS-20261122-0007',
          paymentMethod: 'CHEQUE',
          amountPaid: 472,
          previousBalance: 472,
          remainingBalance: 472,
          paymentDate: DateTime(2026, 11, 22, 14, 15),
          isPendingCheque: true,
          chequeNumber: 'CHQ-1001',
          bank: 'BDO',
          chequeDate: DateTime(2026, 11, 30),
        ),
      );
      final chequeText = latin1.decode(chequeBytes);
      expect(chequeText, contains('CHEQUE RECEIPT SLIP'));
      expect(chequeText, contains('CHQ-1001'));
      expect(chequeText, contains('BDO'));
      expect(chequeText, contains('PENDING CLEARANCE'));
      expect(chequeText, contains('Balance stands'));
      expect(chequeText, isNot(contains('\u20b1')));
    });
  });

  testWidgets('PosReturnsPage prints the server-backed Return Slip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final printer = _RecordingReturnPrinter();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          home: PosReturnsPage(
            viewmodel: PosReturnsViewmodel(repository: _StubReturnsRepo()),
            shiftViewmodel: ShiftViewmodel(service: _StubShiftService()),
            returnSlipPrinter: printer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('returns-search-field')),
      'OS-20261122-0007',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search sale'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('One more').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cracked sacks');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm return'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('print-return-slip')));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    final slip = printer.printed.single;
    expect(slip.returnNo, 'RTN-20261122-0001');
    expect(slip.transactionNo, 'OS-20261122-0007');
    expect(slip.customerName, 'Maria Santos');
    expect(slip.returnValue, 800);
    expect(slip.debtReduced, 600);
    expect(slip.cashRefund, 200);
  });

  testWidgets('Utang payment shows confirmation slip and Payment History reprints it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = _StubLedgerRepo();
    final vm = SalesReceivablesViewmodel(repository: repo);
    final printer = _RecordingUtangPrinter();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm..load(),
        child: MaterialApp(
          home: Scaffold(body: SalesReceivablesContent(slipPrinter: printer)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    // Confirmation slip replaces the Record button and prints server-backed data.
    expect(find.text('Payment recorded'), findsOneWidget);
    expect(find.text('Record'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('print-utang-payment-slip')));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    expect(printer.printed.single.customerName, 'Dela Cruz Construction');
    expect(printer.printed.single.referenceNo, 'PAY-0091');
    expect(printer.printed.single.amountPaid, 472);
    expect(printer.printed.single.remainingBalance, 0);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Reprint from Payment history tab matches the same server record.
    await tester.tap(find.text('Payment history'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-payment-91')));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(2));
    expect(printer.printed.last.paymentId, 91);
    expect(printer.printed.last.recordedBy, 'Ana Cruz');
  });
}
