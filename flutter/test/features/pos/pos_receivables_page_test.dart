// Card S2: the cashier's Record payment screen is a SHELL around the same
// receivables content the Store Manager reads.
//
// What the old screen could not do, and what these tests hold it to:
//  * no search and no status chips, so a cashier with many customers hunted for
//    one name down a table that scrolled sideways under 1100 px;
//  * "Record payment" lived in the eighth column of a raw DataTable, off screen
//    on a 760 px till;
//  * the load failure was a hand-built red box, styled unlike every other page.
//
// Narrow (760) first: every defect this refresh has found showed up there.

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/views/pos_receivables_page.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// [DashboardShell] reads the signed-in user, so every pump needs an
/// `AuthViewmodel` above it. No request is made - it is only read.
Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

/// Answers from memory; nothing here touches a server.
class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository() : super();

  List<LedgerEntry> rows = const [];
  String? failureMessage;
  int fetchCalls = 0;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    fetchCalls++;
    final failure = failureMessage;
    if (failure != null) throw LedgerServiceException(failure);
    return rows;
  }

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    TenderMethod method = TenderMethod.cash,
    String? officialReceiptNo,
  }) async {}
}

LedgerEntry _entry({
  int id = 1,
  String customer = 'Dela Cruz Construction',
  String transactionNo = 'TRX-20261016-0001',
  double original = 5000,
  double balance = 472,
  bool isOverdue = false,
  DateTime? dueDate,
}) => LedgerEntry(
  id: id,
  customerId: 3,
  customerName: customer,
  transactionNo: transactionNo,
  originalAmount: original,
  balanceDue: balance,
  dueDate: dueDate ?? DateTime.now().add(const Duration(days: 30)),
  isOverdue: isOverdue,
);

Future<SalesReceivablesViewmodel> _pump(
  WidgetTester tester, {
  Size size = const Size(760, 900),
  List<LedgerEntry> rows = const [],
  String? failure,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repository = _StubLedgerRepository()
    ..rows = rows
    ..failureMessage = failure;
  final viewmodel = SalesReceivablesViewmodel(repository: repository);
  await tester.pumpWidget(_app(PosReceivablesPage(viewmodel: viewmodel)));
  await tester.pumpAndSettle();
  return viewmodel;
}

void main() {
  testWidgets('at 760 the cashier gets a search field and the status chips', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [
        _entry(balance: 472),
        _entry(id: 2, balance: 100, isOverdue: true),
      ],
    );

    expect(find.byType(FilterBar), findsOneWidget);
    // Scoped to the bar: a row badge says "Overdue" too.
    for (final chip in const ['All', 'Current', 'Due Soon', 'Overdue']) {
      expect(
        find.descendant(of: find.byType(FilterBar), matching: find.text(chip)),
        findsOneWidget,
        reason: 'chip "$chip" is missing from the filter bar',
      );
    }
  });

  testWidgets('an overdue chip narrows the cards but not the totals', (
    tester,
  ) async {
    final viewmodel = await _pump(
      tester,
      rows: [
        _entry(balance: 472),
        _entry(id: 2, balance: 100, isOverdue: true),
      ],
    );
    expect(find.text('Dela Cruz Construction'), findsNWidgets(2));

    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Overdue'),
      ),
    );
    await tester.pumpAndSettle();

    expect(viewmodel.filteredEntries, hasLength(1));
    expect(find.text('Dela Cruz Construction'), findsOneWidget);
    // Tiles stay store-wide: the chip narrows the list, not the money.
    expect(find.text('₱572.00'), findsWidgets);
  });

  testWidgets('a search narrows the cards and says when nothing matches', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [
        _entry(balance: 472),
        _entry(
          id: 2,
          customer: 'Reyes Trading',
          transactionNo: 'TRX-20261016-0002',
          balance: 100,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'reyes');
    await tester.pumpAndSettle();
    expect(find.text('Reyes Trading'), findsOneWidget);
    expect(find.text('Dela Cruz Construction'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No receivables match these filters.'), findsOneWidget);
    expect(
      find.text('No receivables available.'),
      findsNothing,
      reason: 'an empty search is not an empty store',
    );
  });

  testWidgets('a failed load shows the shared error banner, never a total', (
    tester,
  ) async {
    await _pump(tester, failure: 'Cannot connect to the BuildPro server.');

    expect(
      find.byType(ErrorBanner),
      findsOneWidget,
      reason: 'the hand-built red box is gone; every page uses ErrorBanner',
    );
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Not loaded'), findsWidgets);
    expect(find.textContaining('₱0.00'), findsNothing);
  });

  testWidgets('at 760 Record payment sits on the card and opens the dialog', (
    tester,
  ) async {
    await _pump(tester, rows: [_entry(balance: 472)]);

    expect(
      find.byType(DataPanel<LedgerEntry>),
      findsOneWidget,
      reason: 'below 720 px of content the table becomes cards',
    );
    expect(find.byType(DataTable), findsNothing);

    final action = find.text('Record payment');
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    // Prefilled with the whole balance, as before.
    expect(find.widgetWithText(TextField, '472.00'), findsOneWidget);
  });

  testWidgets('a 7 digit balance keeps its thousands separators', (
    tester,
  ) async {
    await _pump(tester, rows: [_entry(original: 1148000, balance: 1148000)]);

    expect(find.text('₱1,148,000.00'), findsWidgets);
  });
}
