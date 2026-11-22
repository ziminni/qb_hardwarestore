import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_shift_cash_movement_dialog.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeShiftService extends ShiftService {
  Map<String, int>? lastDenominations;
  double? lastClosingCount;
  String? lastCategory;

  Shift _openShift() => Shift(
    id: 1,
    cashierName: 'Ana',
    status: Shift.openStatus,
    openingFloat: 1000,
    closingCount: null,
    openedAt: DateTime(2026, 11, 22, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );

  @override
  Future<Shift?> fetchCurrent() async => _openShift();

  @override
  Future<Shift> closeShift(
    int shiftId,
    double closingCount, {
    double? cashLeft,
    Map<String, int>? denominations,
  }) async {
    lastClosingCount = closingCount;
    lastDenominations = denominations;
    return Shift(
      id: shiftId,
      cashierName: 'Ana',
      status: Shift.closedStatus,
      openingFloat: 1000,
      closingCount: closingCount,
      openedAt: DateTime(2026, 11, 22, 8),
      closedAt: DateTime(2026, 11, 22, 17),
      notes: '',
      zReading: null,
    );
  }

  @override
  Future<Shift> recordCashMovement(
    int shiftId, {
    required String kind,
    required double amount,
    required String reason,
    String category = ShiftCashMovement.otherCategory,
  }) async {
    lastCategory = category;
    return _openShift();
  }
}

void main() {
  testWidgets('close shift dialog sums PHP denominations into closing count', (
    tester,
  ) async {
    final service = _FakeShiftService();
    final vm = ShiftViewmodel(service: service);
    await vm.loadCurrent();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showShiftCloseDialog(context, vm),
              child: const Text('Open close'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('shift-close-denoms-toggle')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('denom-1000')), '2');
    await tester.enterText(find.byKey(const ValueKey('denom-500')), '1');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
    await tester.pumpAndSettle();

    expect(service.lastClosingCount, 2500.0);
    expect(service.lastDenominations, {'1000': 2, '500': 1});
  });

  testWidgets('cash movement dialog sends selected cash-out category', (
    tester,
  ) async {
    final service = _FakeShiftService();
    final vm = ShiftViewmodel(service: service);
    await vm.loadCurrent();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showShiftCashMovementDialog(context, vm),
              child: const Text('Open cash out'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open cash out'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cash-movement-cat-FUEL')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('cash-movement-amount')),
      '250',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cash-movement-reason')),
      'Delivery diesel',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save movement'));
    await tester.pumpAndSettle();

    expect(service.lastCategory, ShiftCashMovement.fuelCategory);
  });

  testWidgets('cash movement dialog allows typing a custom category', (
    tester,
  ) async {
    final service = _FakeShiftService();
    final vm = ShiftViewmodel(service: service);
    await vm.loadCurrent();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showShiftCashMovementDialog(context, vm),
              child: const Text('Open cash out'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open cash out'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('cash-movement-amount')),
      '120',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cash-movement-category-input')),
      'Parking',
    );
    await tester.enterText(
      find.byKey(const ValueKey('cash-movement-reason')),
      'Hardware delivery parking',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save movement'));
    await tester.pumpAndSettle();

    expect(service.lastCategory, 'Parking');
  });

  testWidgets(
    'Z-reading summary displays cash-out categories and PHP denomination breakdown',
    (tester) async {
      final reading = ZReading(
        transactionCount: 4,
        grossSales: 3000,
        cashSales: 2000,
        cardSales: 500,
        gcashSales: 500,
        expectedDrawer: 2750,
        variance: 0,
        cashOut: 250,
        denominationCounts: const {'1000': 2, '500': 1, '50': 5},
        cashOutByCategory: const {'FUEL': 180, 'Parking': 70},
      );
      final movements = [
        ShiftCashMovement(
          id: 1,
          kind: ShiftCashMovement.cashOutKind,
          category: 'FUEL',
          amount: 180,
          reason: 'Delivery diesel',
          recordedByName: 'Ana',
          createdAt: DateTime(2026, 11, 22, 12),
        ),
        ShiftCashMovement(
          id: 2,
          kind: ShiftCashMovement.cashOutKind,
          category: 'Parking',
          amount: 70,
          reason: 'Hardware delivery parking',
          recordedByName: 'Ana',
          createdAt: DateTime(2026, 11, 22, 14),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PosZReadingSummary(
                reading: reading,
                closingCount: 2750,
                cashMovements: movements,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Fuel'), findsOneWidget);
      expect(find.text('Parking'), findsOneWidget);
      expect(find.text('Counted PHP bills & coins'), findsOneWidget);
      expect(find.byKey(const ValueKey('z-reading-denominations')), findsOneWidget);
    },
  );
}
