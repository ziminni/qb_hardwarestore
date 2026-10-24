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
///
/// Two live-QA defects are pinned here:
///
/// * the tab was a DEAD END with no open shift (Release and Returns both send the
///   cashier here), so it must offer the same open-shift flow as the till;
/// * while a shift was OPEN the tab printed the PREVIOUS closed shift's
///   Z-reading, unlabelled — stale money on a live drawer.
class _StubShifts extends ShiftService {
  int currentCalls = 0;
  int listCalls = 0;
  int openCalls = 0;
  double? openedWith;
  Object? failCurrent;
  Object? failList;
  Object? failOpen;
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

  @override
  Future<Shift> openShift(double openingFloat) async {
    openCalls++;
    openedWith = openingFloat;
    if (failOpen != null) throw failOpen!;
    final opened = _shift(openingFloat: openingFloat);
    current = opened;
    return opened;
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

/// The RUNNING reading `GET /shifts/current/` carries for an open shift: the
/// same arithmetic with no closing count yet, so no variance.
const _running = ZReading(
  transactionCount: 1,
  grossSales: 315,
  cashSales: 315,
  cardSales: 0,
  gcashSales: 0,
  expectedDrawer: 500,
  variance: null,
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

Future<void> _pumpPage(WidgetTester tester, ShiftViewmodel vm) async {
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

Future<void> _pump(WidgetTester tester, ShiftViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await _pumpPage(tester, vm);
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
      expect(
        find.text('This shift so far'),
        findsNothing,
        reason: 'a reading the server did not send must not be invented',
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

      // The heading names WHICH shift the figures belong to: on this tab the
      // reading is the last closed one, and an unlabelled Z-reading was the
      // second QA defect (stale money read as the live drawer).
      expect(find.text('Last closed shift (2026-10-21 08:00)'), findsOneWidget);
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

    testWidgets('a failed current-shift check offers NO open-shift button', (
      tester,
    ) async {
      // "Could not ask" is not "no shift": a second shift opened on top of a
      // live drawer is exactly what the server refuses.
      final service = _StubShifts()
        ..failCurrent = const ShiftServiceException(
          'The shift could not be read.',
        );
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('The shift could not be read.'), findsOneWidget);
      expect(find.text('Retry'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Open shift'),
        findsNothing,
        reason: 'unknown state must not offer to open a shift',
      );
    });

    testWidgets('with no open shift the tab OPENS one instead of dead-ending', (
      tester,
    ) async {
      final service = _StubShifts();
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('CLOSED'), findsWidgets);
      final openButton = find.widgetWithText(FilledButton, 'Open shift');
      expect(openButton, findsOneWidget);

      await tester.tap(openButton);
      await tester.pumpAndSettle();

      // The SAME flow as the till gate: count the drawer, no negative float.
      // Scoped to the dialog: the page's own button carries the same label.
      final dialogButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Open shift'),
      );
      await tester.enterText(find.byType(TextField), '-20');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(dialogButton).onPressed,
        isNull,
        reason: 'money that cannot be in a drawer is a typo, not a float',
      );

      await tester.enterText(find.byType(TextField), '1500');
      await tester.pumpAndSettle();
      await tester.tap(dialogButton);
      await tester.pumpAndSettle();

      expect(service.openCalls, 1);
      expect(service.openedWith, 1500);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'the dialog closes once the server accepted the shift',
      );
      expect(
        find.text('OPEN'),
        findsWidgets,
        reason: 'the opened shift is shown on the page that opened it',
      );
      expect(find.textContaining('₱1500.00'), findsWidgets);
      expect(
        find.widgetWithText(FilledButton, 'Open shift'),
        findsNothing,
        reason: 'a shift is open — there is nothing left to open',
      );
    });

    testWidgets('an OPEN shift shows THIS shift so far, never the last one', (
      tester,
    ) async {
      final service = _StubShifts()
        ..current = _shift(id: 3, openingFloat: 185, zReading: _running)
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            openingFloat: 5000,
            closingCount: 4977,
            zReading: _z,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      expect(find.text('This shift so far'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('₱315.00'), findsWidgets);
      expect(find.text('₱500.00'), findsOneWidget);
      expect(
        find.text('Last closed shift (2026-10-21 08:00)'),
        findsNothing,
        reason: 'a live drawer must not be read off the previous shift',
      );
      expect(
        find.text('₱9400.00'),
        findsNothing,
        reason: 'the previous shift\'s expected drawer is stale on an open one',
      );
      expect(find.text('12'), findsNothing);
    });

    testWidgets('revisiting the tab re-reads the current shift and history', (
      tester,
    ) async {
      final service = _StubShifts();
      await _pump(tester, ShiftViewmodel(service: service));
      expect(service.currentCalls, 1);
      expect(service.listCalls, 1);

      // Leave the tab (go_router disposes the page) and come back after a sale.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      service.history = [
        _shift(
          id: 2,
          status: Shift.closedStatus,
          closingCount: 9350,
          zReading: _z,
        ),
      ];
      await _pumpPage(tester, ShiftViewmodel(service: service));

      expect(
        service.currentCalls,
        2,
        reason:
            'a cached "closed" answer would hide a shift opened at the till',
      );
      expect(service.listCalls, 2);
      expect(find.text('Last closed shift (2026-10-21 08:00)'), findsOneWidget);
    });
  });
}
