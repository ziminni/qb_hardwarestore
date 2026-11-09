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
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/core/time/app_clock.dart';
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

LedgerEntry _entry({
  int id = 1,
  String customerName = 'Dela Cruz Construction',
  String transactionNo = 'TRX-20261016-0001',
  double originalAmount = 5000,
  double balance = 472,
  bool isOverdue = false,
  String? projectName,
}) => LedgerEntry(
  id: id,
  customerId: 3,
  customerName: customerName,
  transactionNo: transactionNo,
  originalAmount: originalAmount,
  balanceDue: balance,
  dueDate: appClock.now().add(const Duration(days: 30)),
  isOverdue: isOverdue,
  projectName: projectName,
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
  Size size = const Size(1600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

    await tester.tap(
      // Scoped to the bar: the row badge beside a due date says "Overdue" too,
      // and FilterBar draws its own chips (not a Material FilterChip).
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Overdue'),
      ),
    );
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

  testWidgets('a failed load shows ONE failure, never an empty state too', (
    tester,
  ) async {
    await _pump(tester, failure: 'The receivables could not be loaded.');

    // FX3: the failure is the banner, once, with its retry.
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('The receivables could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Repinned on purpose (wave-2 fix pass): the panel used to add a second
    // failure under the banner, white inbox icon and all, and an inbox icon
    // reads as "nothing owed" rather than "this did not load".
    expect(find.text('Receivables could not be loaded.'), findsNothing);
    expect(
      find.byType(EmptyState),
      findsNothing,
      reason: 'a failed read is the banner\'s job, not an empty-state card',
    );
    expect(
      find.text('No receivables available.'),
      findsNothing,
      reason:
          'that would state the store is owed nothing, which this screen cannot know',
    );
  });

  testWidgets('a failed RELOAD keeps the rows it already had', (tester) async {
    _sizeUp(tester);
    final repository = _StubLedgerRepository()..rows = [_entry()];
    final viewmodel = SalesReceivablesViewmodel(repository: repository);
    await tester.pumpWidget(_app(SalesReceivablesPage(viewmodel: viewmodel)));
    await tester.pumpAndSettle();
    expect(find.text('Dela Cruz Construction'), findsOneWidget);

    repository.failureMessage = 'The receivables could not be refreshed.';
    await viewmodel.load();
    await tester.pumpAndSettle();

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.text('The receivables could not be refreshed.'),
      findsOneWidget,
    );
    expect(
      find.text('Dela Cruz Construction'),
      findsOneWidget,
      reason: 'a failed refresh must not blank the rows on screen',
    );
    expect(find.byType(EmptyState), findsNothing);
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

  // ---- Card S2: one shared content, read here and on the cashier's page.

  testWidgets('at 760 the manager gets a search field and the status chips', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(760, 900),
      rows: [_entry(balance: 472), _entry(balance: 100, isOverdue: true)],
    );

    expect(find.byType(FilterBar), findsOneWidget);
    for (final chip in const ['All', 'Current', 'Due Soon', 'Overdue']) {
      expect(
        find.descendant(of: find.byType(FilterBar), matching: find.text(chip)),
        findsOneWidget,
        reason: 'chip "$chip" is missing from the filter bar',
      );
    }
  });

  testWidgets('a search narrows the list to the customer typed', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [
        _entry(balance: 472),
        _entry(
          id: 2,
          customerName: 'Reyes Trading',
          transactionNo: 'TRX-20261016-0002',
          balance: 100,
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'reyes');
    await tester.pumpAndSettle();

    expect(find.text('Reyes Trading'), findsOneWidget);
    expect(find.text('Dela Cruz Construction'), findsNothing);
    expect(
      find.text('No receivables match these filters.'),
      findsNothing,
      reason: 'one row still matches the search',
    );
  });

  testWidgets(
    'an empty search result is worded differently from an empty store',
    (tester) async {
      await _pump(tester, rows: [_entry()]);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.text('No receivables match these filters.'), findsOneWidget);
      expect(find.text('No receivables available.'), findsNothing);
    },
  );

  testWidgets('at 760 the rows are cards, not a sideways table', (
    tester,
  ) async {
    await _pump(tester, size: const Size(760, 900), rows: [_entry()]);

    expect(find.byType(DataPanel<LedgerEntry>), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Record payment'), findsOneWidget);
  });

  testWidgets('a failed load uses the shared ErrorBanner', (tester) async {
    await _pump(tester, failure: 'Cannot connect to the BuildPro server.');

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a 7 digit balance is grouped, not clipped', (tester) async {
    await _pump(
      tester,
      size: const Size(1100, 900),
      rows: [
        _entry(
          customerName:
              'Northern Mindanao Builders and Hardware Trading Corporation',
          originalAmount: 1148000,
          balance: 1148000,
        ),
      ],
    );

    expect(find.text('₱1,148,000.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // ---- Task 10 (decision 03): the utang says which project owes it.

  testWidgets('a release-made utang shows its project under the customer', (
    tester,
  ) async {
    await _pump(tester, rows: [_entry(projectName: '2-Storey House Mandaue')]);

    expect(
      find.text('2-Storey House Mandaue'),
      findsOneWidget,
      reason:
          'one contractor can owe on several jobs, and the payer alone does not '
          'say which one',
    );
  });

  testWidgets('a counter sale utang shows no project line at all', (
    tester,
  ) async {
    await _pump(tester, rows: [_entry()]);

    // The invoice number is the only caption under the customer name.
    expect(find.text('TRX-20261016-0001'), findsOneWidget);
    expect(
      // Scoped to the table: the sidebar carries a "Project requests" entry,
      // and an unscoped search would read the menu as a project caption.
      find.descendant(
        of: find.byType(DataPanel<LedgerEntry>),
        matching: find.textContaining('Project'),
      ),
      findsNothing,
      reason: 'a walk-in debt has no project, so there is nothing to caption',
    );
  });

  testWidgets('the search matches a project name, not only the customer', (
    tester,
  ) async {
    await _pump(
      tester,
      rows: [
        _entry(projectName: '2-Storey House Mandaue'),
        _entry(
          id: 2,
          customerName: 'Reyes Trading',
          transactionNo: 'TRX-20261016-0002',
          balance: 900,
          projectName: 'Warehouse Extension Phase 2',
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'warehouse');
    await tester.pumpAndSettle();

    expect(find.text('Reyes Trading'), findsOneWidget);
    expect(
      find.text('Dela Cruz Construction'),
      findsNothing,
      reason: 'the project is what the clerk is told at the counter',
    );
  });
}
