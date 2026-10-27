// Task 19, the last page-level gap: SalesReceivablesPage had ZERO tests.
//
// The rule it holds was verified only by reading: when the load FAILS, the tiles render an em
// dash rather than a total. A failed load that renders "Outstanding P0.00 / 0 open invoices"
// states "this store is owed nothing" - a wrong number is far more persuasive than a wrong
// caption, and the caption was already carefully worded to avoid exactly that claim.
//
// The page builds its own viewmodel in production, so the seam added alongside this test is what
// makes the failed state renderable at all.

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// `SalesSkeletonLayout` reads the signed-in user to pick what to show, so every pump needs an
/// AuthViewmodel above it. No request is made - the viewmodel is only read.
Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository() : super();

  List<LedgerEntry> rows = const [];
  String? failureMessage;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    final failure = failureMessage;
    if (failure != null) throw LedgerServiceException(failure);
    return rows;
  }
}

LedgerEntry _entry({double balance = 472, bool isOverdue = false}) =>
    LedgerEntry(
      id: 1,
      customerId: 3,
      customerName: 'Dela Cruz Construction',
      transactionNo: 'TRX-20261016-0001',
      originalAmount: 5000,
      balanceDue: balance,
      dueDate: DateTime.now().add(const Duration(days: 30)),
      isOverdue: isOverdue,
    );

/// The skeleton layout is a full sidebar-plus-content shell, which overflows the default
/// 800x600 test surface. Sized here rather than tolerated, so an overflow cannot be mistaken for
/// a passing test.
void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester, {
  List<LedgerEntry> rows = const [],
  String? failure,
}) async {
  _sizeUp(tester);
  final repository = _StubLedgerRepository()
    ..rows = rows
    ..failureMessage = failure;
  await tester.pumpWidget(
    _app(
      SalesReceivablesPage(
        viewmodel: SalesReceivablesViewmodel(repository: repository),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a successful load renders the rows and totals what is owed', (
    tester,
  ) async {
    await _pump(tester, rows: [_entry(balance: 472)]);

    expect(find.text('Dela Cruz Construction'), findsOneWidget);
    expect(find.text('TRX-20261016-0001'), findsOneWidget);
    expect(find.text('₱472.00'), findsWidgets);
    expect(find.textContaining('1 open invoices'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  // Phase 5 Task 3: chips narrow the rows; the tiles stay store-wide.
  testWidgets('an overdue chip narrows the rows to late debts', (tester) async {
    await _pump(
      tester,
      rows: [_entry(balance: 472), _entry(balance: 100, isOverdue: true)],
    );
    expect(find.text('Dela Cruz Construction'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilterChip, 'Overdue'));
    await tester.pumpAndSettle();

    expect(find.text('Dela Cruz Construction'), findsOneWidget);
    expect(find.text('₱100.00'), findsWidgets);
    // Tiles still total the whole store, not the chip.
    expect(find.text('₱572.00'), findsWidgets);
  });

  testWidgets('a FAILED load shows the error and NEVER a total', (
    tester,
  ) async {
    await _pump(tester, failure: 'Cannot connect to the BuildPro server.');

    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // The claim a wrong number would make: "this store is owed nothing".
    expect(
      find.textContaining('₱0.00'),
      findsNothing,
      reason:
          'a number beside an error banner is more believable than any caption',
    );
    expect(
      find.text('Not loaded'),
      findsWidgets,
      reason: 'the tiles say what they do not know',
    );
  });

  testWidgets('a failed load does NOT read as "no receivables"', (
    tester,
  ) async {
    await _pump(tester, failure: 'The receivables could not be loaded.');

    expect(
      find.text('No receivables available.'),
      findsNothing,
      reason:
          'that would state the store is owed nothing, which this screen cannot know',
    );
    expect(find.text('Receivables could not be loaded.'), findsOneWidget);
  });

  testWidgets('a load that succeeds after a failure clears the error', (
    tester,
  ) async {
    _sizeUp(tester);
    final repository = _StubLedgerRepository()..failureMessage = 'Boom.';
    final viewmodel = SalesReceivablesViewmodel(repository: repository);

    await tester.pumpWidget(_app(SalesReceivablesPage(viewmodel: viewmodel)));
    await tester.pumpAndSettle();
    expect(find.text('Boom.'), findsOneWidget);

    repository
      ..failureMessage = null
      ..rows = [_entry()];
    await viewmodel.load();
    await tester.pumpAndSettle();

    expect(find.text('Boom.'), findsNothing);
    expect(find.text('Dela Cruz Construction'), findsOneWidget);
  });
}
