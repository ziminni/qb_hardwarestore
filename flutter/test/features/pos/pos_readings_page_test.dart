import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_readings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubShiftService extends ShiftService {
  _StubShiftService({this.current, this.history = const []});

  final Shift? current;
  final List<Shift> history;

  @override
  Future<Shift?> fetchCurrent() async => current;

  @override
  Future<List<Shift>> fetchAll() async => history;
}

Shift _openShift({int id = 42, String cashier = 'Ana Cruz'}) => Shift(
  id: id,
  cashierName: cashier,
  status: Shift.openStatus,
  openingFloat: 2000,
  closingCount: null,
  openedAt: DateTime(2026, 11, 23, 8, 0),
  closedAt: null,
  notes: '',
  zReading: const ZReading(
    transactionCount: 14,
    grossSales: 12500,
    cashSales: 8000,
    cardSales: 2000,
    gcashSales: 2500,
    expectedDrawer: 9500,
    variance: null,
    cashIn: 0,
    cashOut: 500,
  ),
);

Shift _closedShift({
  required int id,
  required String cashier,
  required DateTime closedAt,
  required double grossSales,
  required double variance,
  Map<String, int> denoms = const {},
}) {
  final expected = 2000 + grossSales;
  return Shift(
    id: id,
    cashierName: cashier,
    status: Shift.closedStatus,
    openingFloat: 2000,
    closingCount: expected + variance,
    openedAt: closedAt.subtract(const Duration(hours: 8)),
    closedAt: closedAt,
    notes: '',
    zReading: ZReading(
      transactionCount: 10,
      grossSales: grossSales,
      cashSales: grossSales,
      cardSales: 0,
      gcashSales: 0,
      expectedDrawer: expected,
      variance: variance,
      denominationCounts: denoms,
    ),
  );
}

Future<void> _pumpPage(WidgetTester tester, ShiftViewmodel vm) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: PosReadingsPage(viewmodel: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'sidebar_collapsed': false});
  });

  testWidgets('renders all 4 sub-tabs and Monthly Summary KPIs', (
    tester,
  ) async {
    final vm = ShiftViewmodel(
      service: _StubShiftService(
        current: _openShift(),
        history: [
          _openShift(),
          _closedShift(
            id: 41,
            cashier: 'Ana Cruz',
            closedAt: DateTime(2026, 11, 22, 17, 0),
            grossSales: 10000,
            variance: 0,
          ),
          _closedShift(
            id: 40,
            cashier: 'Ben Reyes',
            closedAt: DateTime(2026, 11, 21, 17, 0),
            grossSales: 8000,
            variance: -50,
          ),
        ],
      ),
    );
    await _pumpPage(tester, vm);

    // Tab 1: All Readings
    expect(find.text('Daily X/Z-Reading & Sales Summary'), findsOneWidget);
    expect(find.text('Reading Ledger'), findsOneWidget);
    expect(find.text('#Z-41'), findsOneWidget);
    expect(find.text('#Z-40'), findsOneWidget);

    // Tab 2: Today's X-Readings
    await tester.tap(find.byKey(const ValueKey('readings-tab-x')));
    await tester.pumpAndSettle();
    expect(find.text('Live Open Shift · Shift #42'), findsOneWidget);
    expect(find.text('Take Mid-Shift X-Reading'), findsOneWidget);

    // Tab 3: Daily Z-Readings (EOD)
    await tester.tap(find.byKey(const ValueKey('readings-tab-z')));
    await tester.pumpAndSettle();
    expect(find.text('Closed Shifts Z-Reading Ledger'), findsOneWidget);
    expect(find.text('Open Shifts to Close'), findsOneWidget);

    // Tab 4: Monthly Summary
    await tester.tap(find.byKey(const ValueKey('readings-tab-monthly')));
    await tester.pumpAndSettle();
    expect(find.text('MTD Gross Sales'), findsOneWidget);
    expect(find.text('Top Revenue Days'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget); // 1 of 2 closed shifts balanced
  });

  testWidgets(
    'taking an instant X-reading adds snapshot to Today\'s X-Readings and All Readings',
    (tester) async {
      final vm = ShiftViewmodel(
        service: _StubShiftService(
          current: _openShift(),
          history: [_openShift()],
        ),
      );
      await _pumpPage(tester, vm);

      await tester.tap(find.byKey(const ValueKey('readings-generate-x')));
      await tester.pumpAndSettle();

      expect(find.text('#X-1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('readings-tab-x')));
      await tester.pumpAndSettle();
      expect(find.text('#X-1'), findsOneWidget);
    },
  );

  testWidgets('opens 80mm thermal slip dialog and copies monospace text', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final vm = ShiftViewmodel(
      service: _StubShiftService(
        current: null,
        history: [
          _closedShift(
            id: 55,
            cashier: 'Ana Cruz',
            closedAt: DateTime(2026, 11, 22, 18, 0),
            grossSales: 5600,
            variance: 0,
            denoms: const {'1000': 5, '500': 5, '100': 1},
          ),
        ],
      ),
    );
    await _pumpPage(tester, vm);

    final slipBtn = find.byKey(const ValueKey('reading-slip-btn-Z-55'));
    await tester.ensureVisible(slipBtn);
    await tester.pumpAndSettle();
    await tester.tap(slipBtn);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('thermal-slip-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('thermal-slip-text')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('slip-copy-btn')));
    await tester.pumpAndSettle();

    expect(copiedText, isNotNull);
    expect(copiedText, contains('QB HARDWARE POS'));
    expect(copiedText, contains('Z-55'));
    expect(copiedText, contains('DENOMINATION SUMMARY'));
    expect(copiedText!.toUpperCase(), isNot(contains('BIR')));
    expect(find.text('Reading slip copied to clipboard.'), findsOneWidget);
  });

  testWidgets('filters All / Balanced / Variance and paginates with page size picker', (
    tester,
  ) async {
    final shifts = [
      for (var i = 1; i <= 12; i++)
        _closedShift(
          id: 100 + i,
          cashier: i.isEven ? 'Ana Cruz' : 'Ben Reyes',
          closedAt: DateTime(2026, 11, i, 17, 0),
          grossSales: 1000.0 * i,
          variance: i.isEven ? 0 : -25,
        ),
    ];
    final vm = ShiftViewmodel(
      service: _StubShiftService(current: null, history: shifts),
    );
    await _pumpPage(tester, vm);

    // Page size picker is visible
    final pageSizeBtn = find.byKey(const ValueKey('DataPanel.pageSize'));
    expect(pageSizeBtn, findsOneWidget);
    expect(find.text('1 to 12 of 12'), findsOneWidget);

    // Switch page size to 10 per page
    await tester.ensureVisible(pageSizeBtn);
    await tester.pumpAndSettle();
    await tester.tap(pageSizeBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 per page'));
    await tester.pumpAndSettle();
    expect(find.text('1 to 10 of 12'), findsOneWidget);

    // Filter Balanced (6 even shifts)
    final balancedPill = find.byKey(const ValueKey('readings-filter-balanced'));
    await tester.ensureVisible(balancedPill);
    await tester.pumpAndSettle();
    await tester.tap(balancedPill);
    await tester.pumpAndSettle();
    expect(find.text('1 to 6 of 6'), findsOneWidget);

    // Filter Variance (6 odd shifts)
    await tester.tap(find.byKey(const ValueKey('readings-filter-variance')));
    await tester.pumpAndSettle();
    expect(find.text('1 to 6 of 6'), findsOneWidget);

    // Filter All (back to 12)
    await tester.tap(find.byKey(const ValueKey('readings-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('1 to 10 of 12'), findsOneWidget);
  });
}
