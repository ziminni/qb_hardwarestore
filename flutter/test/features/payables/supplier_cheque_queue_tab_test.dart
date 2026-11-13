// Phase 8 F3 (decision 20 #3/#4): the supplier cheque queue tab.
//
// Pinned here:
//   * only CHEQUES appear — the payments route also answers cash and credit
//     rows, and an ordinary tender has no bank decision;
//   * the status chip narrows the queue without another read;
//   * Clear and Bounce are the manager's acts: a Stock Manager only reads, and
//     a bounce REFUSES to send without a reason (the server would 400);
//   * a decided cheque shows who decided it, when, and why it bounced.

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/features/payables/widgets/supplier_cheque_queue_tab.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

SupplierPayment _cheque({
  int id = 7,
  int billId = 4,
  double amount = 400,
  String number = '000123',
  SupplierPaymentStatus status = SupplierPaymentStatus.issued,
  DateTime? chequeDate,
  String decisionReason = '',
}) => SupplierPayment(
  id: id,
  billId: billId,
  amount: amount,
  method: SupplierPaymentMethod.cheque,
  methodCode: 'CHEQUE',
  reference: '',
  chequeNumber: number,
  chequeBank: 'BDO',
  chequeDate: chequeDate ?? DateTime(2026, 10, 20),
  paidByName: 'Maria Santos',
  paidOn: DateTime(2026, 10, 21),
  status: status,
  statusCode: status.code,
  decidedByName: status == SupplierPaymentStatus.issued ? null : 'Ana Cruz',
  decidedAt: status == SupplierPaymentStatus.issued
      ? null
      : DateTime(2026, 11, 1),
  decisionReason: decisionReason,
);

SupplierPayment _cash({int id = 9}) => SupplierPayment(
  id: id,
  billId: 4,
  amount: 100,
  method: SupplierPaymentMethod.cash,
  methodCode: 'CASH',
  reference: 'CV-11',
  chequeNumber: null,
  chequeBank: null,
  chequeDate: null,
  paidByName: 'Maria Santos',
  paidOn: DateTime(2026, 10, 22),
  status: SupplierPaymentStatus.cleared,
  statusCode: 'CLEARED',
);

class _StubRepository extends PayablesRepository {
  _StubRepository({List<SupplierPayment>? rows})
    : paymentRows = rows ?? [_cheque(), _cash()];

  List<SupplierPayment> paymentRows;
  final List<int> cleared = [];
  final List<(int, String)> bounced = [];
  String? decisionFailure;

  @override
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) async => const [];

  @override
  Future<List<SupplierPayable>> fetchSummary() async => const [];

  @override
  Future<List<SupplierPayment>> fetchCheques({
    int? supplierId,
    SupplierPaymentStatus? status,
  }) async => paymentRows;

  @override
  Future<SupplierPayment> clearCheque(int paymentId) async {
    if (decisionFailure != null) {
      throw PayablesServiceException(decisionFailure!);
    }
    cleared.add(paymentId);
    return _cheque(status: SupplierPaymentStatus.cleared);
  }

  @override
  Future<SupplierPayment> bounceCheque(int paymentId, String reason) async {
    if (decisionFailure != null) {
      throw PayablesServiceException(decisionFailure!);
    }
    bounced.add((paymentId, reason));
    return _cheque(
      status: SupplierPaymentStatus.bounced,
      decisionReason: reason,
    );
  }
}

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

Future<PayablesViewmodel> _pump(
  WidgetTester tester,
  _StubRepository repository, {
  bool canDecide = true,
  Size size = const Size(1400, 900),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final viewmodel = PayablesViewmodel(repository: repository);
  await tester.pumpWidget(
    ChangeNotifierProvider<PayablesViewmodel>.value(
      value: viewmodel,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SupplierChequeQueueTab(canDecide: canDecide)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return viewmodel;
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('only cheques are listed, with their bank and bill', (
    tester,
  ) async {
    await _pump(tester, _StubRepository());

    expect(find.textContaining('000123'), findsWidgets);
    expect(
      find.textContaining('CV-11'),
      findsNothing,
      reason: 'a cash payment has no bank decision to make',
    );
  });

  testWidgets('the status chip narrows the queue', (tester) async {
    await _pump(
      tester,
      _StubRepository(
        rows: [
          _cheque(),
          _cheque(
            id: 8,
            number: '000456',
            status: SupplierPaymentStatus.cleared,
          ),
        ],
      ),
    );

    expect(find.textContaining('000123'), findsWidgets);
    expect(find.textContaining('000456'), findsWidgets);

    await tester.tap(
      // The chip, not the status badge a cleared row already shows.
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Cleared'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('000456'), findsWidgets);
    expect(find.textContaining('000123'), findsNothing);
  });

  testWidgets('Clear asks once and stamps the row', (tester) async {
    final repository = _StubRepository();
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Clear cheque'));
    await tester.pumpAndSettle();

    expect(repository.cleared, [7]);
    expect(find.text('Cleared'), findsWidgets);
  });

  testWidgets('Bounce refuses to send without a reason, then sends it', (
    tester,
  ) async {
    final repository = _StubRepository();
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(TextButton, 'Bounce'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Mark bounced');
    expect(
      tester.widget<FilledButton>(confirm).onPressed,
      isNull,
      reason: 'the server 400s a bounce with no reason',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Why did the bank refuse it?'),
      'Insufficient funds',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(repository.bounced.single, (7, 'Insufficient funds'));
    expect(find.textContaining('Insufficient funds'), findsWidgets);
  });

  testWidgets('a refused decision stays on screen in the server sentence', (
    tester,
  ) async {
    final repository = _StubRepository()
      ..decisionFailure = 'Cheque 000123 is already cleared.';
    await _pump(tester, repository);

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cheque'));
    await tester.pumpAndSettle();

    expect(find.text(repository.decisionFailure!), findsWidgets);
  });

  testWidgets('a Stock Manager reads the queue and decides nothing', (
    tester,
  ) async {
    await _pump(tester, _StubRepository(), canDecide: false);

    expect(find.widgetWithText(TextButton, 'Clear'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Bounce'), findsNothing);
    expect(find.textContaining('Read only'), findsWidgets);
  });

  testWidgets('760 px at 1.3x text, the queue and its dialogs render whole', (
    tester,
  ) async {
    final repository = _StubRepository();
    await _pump(tester, repository, size: const Size(760, 900), scale: 1.3);

    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Bounce'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Mark bounced').hitTestable(),
      findsOneWidget,
    );
  });
}
