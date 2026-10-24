// Phase 3 Task 4 (decision 06 record-and-warn / Phase 3 Task 3 advisory): the
// shift close tells the cashier that carts are still parked, and the Z-reading
// carries the count.
//
// WHY THIS IS ADVISORY AND NOT A BLOCK: decision 06 makes a held cart a PARKED
// basket — nothing deducted, no money taken — and the carts are never deleted by
// a close. So closing with carts parked is legal and must still be possible; what
// it must not be is SILENT, or a cashier finds out tomorrow that the customer's
// basket is still sitting there.
//
// The field is read-only on the wire (`held_cart_count` is a SerializerMethodField
// on `ShiftSerializer`), so the client parses it and never sends it.

import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A shift body exactly as `ShiftSerializer` sends it, plus `held_cart_count`.
Map<String, dynamic> _shiftJson({int heldCarts = 2}) => {
  'id': 4,
  'cashier': 3,
  'cashier_name': 'Ana Cruz',
  'status': 'OPEN',
  'opening_float': '5000.00',
  'closing_count': null,
  'opened_at': '2026-10-24T08:00:00+08:00',
  'closed_at': null,
  'notes': '',
  'z_reading': {
    'shift_id': 4,
    'opening_float': '5000.00',
    'closing_count': null,
    'transaction_count': 3,
    'gross_sales': '1200.00',
    'vat': '0.00',
    'discounts': '0.00',
    'cash_sales': '1200.00',
    'card_sales': '0.00',
    'gcash_sales': '0.00',
    'bank_sales': '0.00',
    'cash_refunds': '0.00',
    'expected_drawer': '6200.00',
    'variance': null,
    'held_cart_count': heldCarts,
  },
  'held_cart_count': heldCarts,
};

class _StubShifts extends ShiftService {
  _StubShifts(this.current);

  Shift? current;
  int closeCalls = 0;
  double? closingCount;

  @override
  Future<Shift?> fetchCurrent() async => current;

  @override
  Future<List<Shift>> fetchAll() async => [?current];

  @override
  Future<Shift> closeShift(int shiftId, double closingCount) async {
    closeCalls++;
    this.closingCount = closingCount;
    final closed = _closedShift(heldCarts: current?.heldCartCount ?? 0);
    current = null;
    return closed;
  }
}

Shift _closedShift({int heldCarts = 0}) => Shift(
  id: 4,
  cashierName: 'Ana Cruz',
  status: Shift.closedStatus,
  openingFloat: 5000,
  closingCount: 7000,
  openedAt: DateTime(2026, 10, 24, 8),
  closedAt: DateTime(2026, 10, 24, 17),
  notes: '',
  heldCartCount: heldCarts,
  zReading: ZReading(
    transactionCount: 3,
    grossSales: 1200,
    cashSales: 1200,
    cardSales: 0,
    gcashSales: 0,
    expectedDrawer: 6200,
    variance: 800,
    heldCartCount: heldCarts,
  ),
);

Shift _openShift({int heldCarts = 2}) => Shift(
  id: 4,
  cashierName: 'Ana Cruz',
  status: Shift.openStatus,
  openingFloat: 5000,
  closingCount: null,
  openedAt: DateTime(2026, 10, 24, 8),
  closedAt: null,
  notes: '',
  heldCartCount: heldCarts,
  zReading: null,
);

/// The stub the last [_openCloseDialog] wired, so a test can assert on what the
/// page actually called without reaching into the viewmodel's private state.
late _StubShifts _stub;

/// Opens the real close dialog through the same function the till and the
/// Shifts tab call, so the test pins the shipped wording, not a copy of it.
Future<ShiftViewmodel> _openCloseDialog(
  WidgetTester tester, {
  required int heldCarts,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final stub = _StubShifts(_openShift(heldCarts: heldCarts));
  _stub = stub;
  final viewmodel = ShiftViewmodel(service: stub);
  await viewmodel.loadCurrent();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShiftCloseDialog(context, viewmodel),
            child: const Text('close the shift'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('close the shift'));
  await tester.pumpAndSettle();
  return viewmodel;
}

void main() {
  group('the wire carries the parked-cart count', () {
    test('a shift parses held_cart_count instead of defaulting it to 0', () {
      final shift = Shift.fromJson(_shiftJson(heldCarts: 2));

      expect(
        shift.heldCartCount,
        2,
        reason:
            'the server sends held_cart_count on current, list and close; a '
            'client that dropped it could not warn about parked carts',
      );
    });

    test('the Z-reading body carries its own count', () {
      final shift = Shift.fromJson(_shiftJson(heldCarts: 3));

      expect(shift.zReading?.heldCartCount, 3);
    });

    test('a body without the field still parses, as zero', () {
      // Older fixtures and any proxy that trims unknown keys must not break the
      // Shifts tab; "no carts" is the honest reading of an absent count.
      final json = _shiftJson()..remove('held_cart_count');
      (json['z_reading'] as Map<String, dynamic>).remove('held_cart_count');

      final shift = Shift.fromJson(json);

      expect(shift.heldCartCount, 0);
      expect(shift.zReading?.heldCartCount, 0);
    });
  });

  group('the close dialog warns while it still allows the close', () {
    testWidgets('2 held carts are named in the dialog', (tester) async {
      await _openCloseDialog(tester, heldCarts: 2);

      expect(
        find.textContaining('2 held cart'),
        findsOneWidget,
        reason:
            'a cashier closing the drawer must be told the carts are still '
            'parked — silently is how they are forgotten',
      );
      expect(
        find.textContaining('resumed later'),
        findsOneWidget,
        reason: 'the warning must also say the carts survive the close',
      );
    });

    testWidgets('the close is still allowed with carts parked', (tester) async {
      final viewmodel = await _openCloseDialog(tester, heldCarts: 2);

      await tester.enterText(find.byType(TextField), '7000');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close shift'));
      await tester.pumpAndSettle();

      expect(
        _stub.closeCalls,
        1,
        reason:
            'decision 06 is record-and-warn, NOT block: the close must go '
            'through and report the count',
      );
      expect(viewmodel.currentShift, isNull);
      // The Z-reading dialog that follows carries the advisory too.
      expect(find.text('Held carts'), findsOneWidget);
    });

    testWidgets('no warning when nothing is parked', (tester) async {
      await _openCloseDialog(tester, heldCarts: 0);

      expect(
        find.textContaining('held cart'),
        findsNothing,
        reason: 'a warning on every close is a warning nobody reads',
      );
    });
  });

  group('the Z-reading view shows the count', () {
    testWidgets('a closed shift with parked carts names the count', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosZReadingSummary(
              reading: _closedShift(heldCarts: 2).zReading!,
            ),
          ),
        ),
      );

      expect(find.text('Held carts'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('and stays quiet when there are none', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosZReadingSummary(
              reading: _closedShift(heldCarts: 0).zReading!,
            ),
          ),
        ),
      );

      expect(find.text('Held carts'), findsNothing);
    });
  });
}
