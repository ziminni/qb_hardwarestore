// Decision 19 page half: the receivables row button must open a real payment dialog,
// not sit disabled beside a stale "Admin-only" comment.

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubPayingRepository extends LedgerRepository {
  _StubPayingRepository() : super();

  List<LedgerEntry> rows = const [];
  int recordCalls = 0;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => rows;

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    TenderMethod method = TenderMethod.cash,
    String? officialReceiptNo,
  }) async {
    recordCalls++;
  }
}

LedgerEntry _entry({double balance = 472}) => LedgerEntry(
  id: 1,
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  transactionNo: 'TRX-20261016-0001',
  originalAmount: 5000,
  balanceDue: balance,
  dueDate: DateTime.now().add(const Duration(days: 30)),
  isOverdue: false,
);

void main() {
  testWidgets('Record payment opens an amount dialog prefilled with the balance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _StubPayingRepository()..rows = [_entry()];
    await tester.pumpWidget(
      _app(SalesReceivablesPage(viewmodel: SalesReceivablesViewmodel(repository: repository))),
    );
    await tester.pumpAndSettle();

    // The records table scrolls horizontally and the Action column starts off-screen
    // at this surface size — scroll it into view before tapping, or the tap misses.
    await tester.ensureVisible(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();

    // A TextField renders its content as an EditableText, not a Text widget.
    expect(find.widgetWithText(TextField, '472.00'), findsOneWidget);
    expect(repository.recordCalls, 0);
  });

  testWidgets('an amount above the balance is refused without posting', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _StubPayingRepository()..rows = [_entry()];
    await tester.pumpWidget(
      _app(SalesReceivablesPage(viewmodel: SalesReceivablesViewmodel(repository: repository))),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '500');
    await tester.tap(find.text('Record', skipOffstage: false).last);
    await tester.pumpAndSettle();

    expect(find.textContaining('more than'), findsOneWidget);
    expect(repository.recordCalls, 0);
  });
}
