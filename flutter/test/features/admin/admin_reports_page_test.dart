// Decision 16 (as amended): ONE admin Reports screen, four tabs, one report at
// a time. Decision D12 drops the Discounts figure (discounts are not built, so
// it was always ₱0.00) and D13 replaces the typed From/To fields with a period
// choice plus a date range picker.
//
// The two tests that typed `YYYY-MM-DD` into two text fields are GONE on
// purpose, and so is the "Enter dates as YYYY-MM-DD." they pinned: a reader can
// no longer mistype a date, so there is no format rule left to read. What they
// guarded (a chosen range reaching the server as `YYYY-MM-DD`, and a refresher
// with the new bounds) is now asserted through the picker and the period menu.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  int salesCalls = 0;
  int valuationCalls = 0;
  String? lastFrom;
  String? lastTo;
  bool failSales = false;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    salesCalls++;
    lastFrom = from;
    lastTo = to;
    if (failSales) {
      throw const ReportsServiceException(
        'The sales summary could not be loaded.',
      );
    }
    return const SalesSummary(
      from: '2026-10-01',
      to: '2026-10-30',
      totalTransactions: 3,
      totalGross: 1500,
      totalVat: 0,
      totalDiscounts: 50,
      days: [
        SalesDay(
          day: '2026-10-29',
          transactions: 2,
          gross: 1000,
          vat: 0,
          discounts: 50,
        ),
        SalesDay(
          day: '2026-10-30',
          transactions: 1,
          gross: 500,
          vat: 0,
          discounts: 0,
        ),
      ],
    );
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    valuationCalls++;
    return const InventoryValuation(
      batchCount: 2,
      totalUnits: 10,
      totalCost: 500,
      totalRetail: 800,
      categories: [],
    );
  }

  @override
  Future<StockMovements> fetchStockMovements({String? from, String? to}) async {
    lastFrom = from;
    lastTo = to;
    return const StockMovements(
      from: '',
      to: '',
      totalIn: 100,
      totalOut: 30,
      receiptsByDay: [],
      adjustmentsByType: [
        MovementType(type: 'DAMAGE', movements: 2, qtyOut: 5),
      ],
    );
  }

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async {
    return const RequisitionHistory(
      from: '',
      to: '',
      statusFilter: null,
      countByStatus: {},
      requisitions: [],
    );
  }
}

Future<_StubReportsRepository> _pump(
  WidgetTester tester, {
  bool failSales = false,
  Size size = const Size(1600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _StubReportsRepository()..failSales = failSales;
  await tester.pumpWidget(
    _app(ReportsPage(viewmodel: AdminReportsViewmodel(repository: repository))),
  );
  await tester.pumpAndSettle();
  return repository;
}

/// `2026-10-30`: the one shape the server's `from`/`to` query takes.
String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Opens the period menu and chooses [label].
Future<void> _pickPeriod(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('reports-period')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The tab is named in the TabBar and may also be a row word; the tab is the one
/// inside the bar.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('four tabs render and the sales totals show', (tester) async {
    await _pump(tester);

    // Scoped to the TabBar: the admin sidebar itself carries an exact
    // "Requisitions" entry, so an unscoped finder matches twice.
    final tabBar = find.byType(TabBar);
    for (final tab in ['Sales', 'Valuation', 'Movements', 'Requisitions']) {
      expect(
        find.descendant(of: tabBar, matching: find.text(tab)),
        findsOneWidget,
      );
    }
    expect(find.textContaining('1,500'), findsWidgets);
  });

  testWidgets('the Sales tab shows no Discounts figure or column', (
    tester,
  ) async {
    await _pump(tester);

    // D12: a discount is not built (checkout hard-zeroes it), so the tile could
    // only ever read ₱0.00 and the column ₱0.00 all the way down. The finder is
    // by WORD, so it catches both the tile and the column heading.
    expect(find.text('Discounts'), findsNothing);
    expect(find.text('Gross sales'), findsOneWidget);
  });

  testWidgets('a failed first load is one banner with a retry, no zero tiles', (
    tester,
  ) async {
    await _pump(tester, failSales: true);

    expect(find.text('The sales summary could not be loaded.'), findsOneWidget);
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // A month nobody sold anything in and a month that never loaded look the
    // same once a row of ₱0.00 tiles is on screen.
    expect(find.byType(MetricTile), findsNothing);
    expect(find.text('No sales in this range.'), findsNothing);
  });

  testWidgets('selecting valuation loads it once', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.text('Valuation'));
    await tester.pumpAndSettle();

    expect(repository.valuationCalls, 1);
    expect(find.textContaining('500'), findsWidgets);
  });

  testWidgets('a failed sales tab names the failure and keeps the other tabs', (
    tester,
  ) async {
    await _pump(tester, failSales: true);

    expect(find.textContaining('could not be loaded'), findsOneWidget);

    await _openTab(tester, 'Movements');

    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets(
    'the Movements tab counts adjustments and says what is left out',
    (tester) async {
      await _pump(tester);

      await _openTab(tester, 'Movements');

      // The server's "out" total is adjustments only: sales and releases never
      // reach it (the same gap the Stock adjustments screen names).
      expect(find.text('Units out'), findsNothing);
      expect(find.text('Adjustments'), findsWidgets);
      expect(
        find.text('Sales and releases are not included.'),
        findsOneWidget,
        reason: 'an unlabelled total reads as the whole stock movement',
      );
      expect(find.text('Damaged'), findsOneWidget);
    },
  );

  testWidgets('a period choice refetches with that period as YYYY-MM-DD', (
    tester,
  ) async {
    final repository = await _pump(tester);
    final today = DateTime.now();

    await _pickPeriod(tester, 'Today');
    expect(repository.lastFrom, _iso(today));
    expect(repository.lastTo, _iso(today));
    expect(repository.salesCalls, 2);

    await _pickPeriod(tester, 'This month');
    expect(repository.lastFrom, _iso(DateTime(today.year, today.month)));
    expect(repository.lastTo, _iso(today));
    expect(repository.salesCalls, 3);
  });

  // FX8 (QA wave 3b): the browser at 1440 x 900 showed a period menu of Today /
  // This week / This month / Last 30 days and a clipped, faded sliver where
  // Custom range should be, so the date range picker could not be opened on a
  // laptop window. The cause is the open animation, not the layout: the menu's
  // Material reveals itself through `Align(heightFactor:)`
  // (`popup_menu.dart`, `_PopupMenuState.build`), so until the 300 ms animation
  // ends the panel is shorter than its own item list and the last item is
  // clipped out of it. `_PeriodControl` therefore opens without that grow.
  for (final size in const [Size(1440, 900), Size(1100, 900), Size(760, 900)]) {
    testWidgets('Custom range is in the menu the moment it opens at '
        '${size.width.toInt()} x ${size.height.toInt()}', (tester) async {
      await _pump(tester, size: size);

      await tester.tap(find.byKey(const Key('reports-period')));
      // A glance's worth of frames, not the whole animation: a menu that
      // reveals itself item by item is a menu whose last choice cannot be
      // pressed until it finishes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.text('Custom range').hitTestable(),
        findsOneWidget,
        reason: 'every one of the five periods must be tappable at once',
      );

      await tester.tap(find.text('Custom range'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
    });
  }

  testWidgets('Custom range opens the picker and sends the days it returns', (
    tester,
  ) async {
    final repository = await _pump(tester);
    final today = DateTime.now();
    // The picker opens on the period already applied, which is Last 30 days:
    // the server's own default window (`to` minus 30 days).
    final applied = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 30));

    await tester.tap(find.byKey(const Key('reports-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();

    expect(find.byType(DateRangePickerDialog), findsOneWidget);

    // The picker opens on the range already applied, so Save with no further
    // taps is the shortest honest path through it.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(repository.lastFrom, _iso(applied));
    expect(repository.lastTo, _iso(today));
    // The chosen range is on screen: "Custom" alone would hide which two days
    // the numbers below cover.
    expect(
      find.text('${formatDate(applied)} to ${formatDate(today)}'),
      findsOneWidget,
    );
  });
}
