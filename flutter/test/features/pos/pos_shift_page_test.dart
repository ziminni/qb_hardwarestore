import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_shift_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The Z-reading SCREEN (tab 5).
///
/// What a viewmodel test cannot see: that the drawer numbers are actually
/// readable at the counter — especially the variance, which is the only line
/// that means "count again" — and that a failed load shows a retry instead of an
/// empty history that reads as "this cashier has never worked here".
class _StubShifts extends ShiftService {
  int currentCalls = 0;
  int listCalls = 0;
  Object? failCurrent;
  Object? failList;
  Shift? current;
  List<Shift> history = const [];

  @override
  Future<Shift?> fetchCurrent() async {
    currentCalls++;
    if (failCurrent != null) throw failCurrent!;
    return current;
  }

  @override
  Future<List<Shift>> fetchAll() async {
    listCalls++;
    if (failList != null) throw failList!;
    return history;
  }
}

const _z = ZReading(
  transactionCount: 12,
  grossSales: 8400,
  cashSales: 4400,
  cardSales: 2500,
  gcashSales: 1500,
  expectedDrawer: 9400,
  variance: -50,
);

Shift _shift({
  int id = 1,
  String status = Shift.openStatus,
  double openingFloat = 5000,
  double? closingCount,
  ZReading? zReading,
}) {
  return Shift(
    id: id,
    cashierName: 'Ana Cruz',
    status: status,
    openingFloat: openingFloat,
    closingCount: closingCount,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: status == Shift.closedStatus ? DateTime(2026, 10, 21, 17) : null,
    notes: '',
    zReading: zReading,
  );
}

Future<void> _pump(WidgetTester tester, ShiftViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: ChangeNotifierProvider<ShiftViewmodel>.value(
        value: vm,
        child: MaterialApp(home: PosShiftPage(viewmodel: vm)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PosShiftPage', () {
    testWidgets('an open shift is shown as open with its float', (
      tester,
    ) async {
      final service = _StubShifts()..current = _shift();
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('Shifts'), findsWidgets);
      expect(find.text('OPEN'), findsWidgets);
      expect(find.textContaining('₱5000.00'), findsWidgets);
      expect(
        find.text('Z-READING'),
        findsNothing,
        reason: 'an open shift has no Z-reading yet',
      );
    });

    testWidgets('a closed shift shows the Z-reading with its variance', (
      tester,
    ) async {
      final service = _StubShifts()
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            closingCount: 9350,
            zReading: _z,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('Z-READING'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('₱8400.00'), findsOneWidget);
      expect(find.text('₱4400.00'), findsOneWidget);
      expect(find.text('₱2500.00'), findsOneWidget);
      expect(find.text('₱1500.00'), findsOneWidget);
      expect(find.text('₱9400.00'), findsOneWidget);
      expect(
        find.text('₱-50.00'),
        findsNWidgets(2),
        reason:
            'a short drawer is the number the cashier must see — once in the '
            'Z-reading and once on the history row',
      );
      expect(find.text('Ana Cruz'), findsWidgets);
      expect(find.text('CLOSED'), findsWidgets);
    });

    testWidgets('a failed load is VISIBLE with a working retry', (
      tester,
    ) async {
      final service = _StubShifts()
        ..failCurrent = const ShiftServiceException('Cannot connect.');
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('Cannot connect.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      service.failCurrent = null;
      service.history = [_shift()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(service.currentCalls, greaterThan(1));
      expect(
        find.text('Cannot connect.'),
        findsNothing,
        reason: 'a successful retry must clear the banner',
      );
    });
  });
}
