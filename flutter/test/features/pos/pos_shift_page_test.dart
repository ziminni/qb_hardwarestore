import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_shift_page.dart';
import 'package:client/features/pos/widgets/pos_z_reading_summary.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  Future<ShiftOpeningSuggestion> fetchOpeningSuggestion() async =>
      const ShiftOpeningSuggestion();

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

  @override
  Future<Shift> recordCashMovement(
    int shiftId, {
    required String kind,
    required double amount,
    required String reason,
    String category = ShiftCashMovement.otherCategory,
  }) async {
    final existing = current ?? _shift(id: shiftId);
    final movement = ShiftCashMovement(
      id: existing.cashMovements.length + 1,
      kind: kind,
      amount: amount,
      reason: reason,
      recordedByName: 'Ana Cruz',
      createdAt: DateTime(2026, 10, 21, 11),
    );
    final movements = [...existing.cashMovements, movement];
    final cashOut = movements
        .where((m) => m.isCashOut)
        .fold<double>(0, (sum, m) => sum + m.amount);
    final cashIn = movements
        .where((m) => !m.isCashOut)
        .fold<double>(0, (sum, m) => sum + m.amount);
    final updated = Shift(
      id: existing.id,
      cashierName: existing.cashierName,
      status: existing.status,
      openingFloat: existing.openingFloat,
      closingCount: existing.closingCount,
      openedAt: existing.openedAt,
      closedAt: existing.closedAt,
      notes: existing.notes,
      zReading: ZReading(
        transactionCount: existing.zReading?.transactionCount ?? 1,
        grossSales: existing.zReading?.grossSales ?? 315,
        cashSales: existing.zReading?.cashSales ?? 315,
        cardSales: existing.zReading?.cardSales ?? 0,
        gcashSales: existing.zReading?.gcashSales ?? 0,
        expectedDrawer:
            existing.openingFloat +
            (existing.zReading?.cashSales ?? 315) +
            cashIn -
            cashOut,
        variance: null,
        cashIn: cashIn,
        cashOut: cashOut,
      ),
      cashMovements: movements,
    );
    current = updated;
    history = [updated, ...history.where((s) => s.id != updated.id)];
    return updated;
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

/// The same shift counted correctly, counted one cent short, and counted over.
/// Three readings because variance has three meanings and the screen must not
/// paint two of them the same (card C6).
const _short = ZReading(
  transactionCount: 12,
  grossSales: 8400,
  cashSales: 4400,
  cardSales: 2500,
  gcashSales: 1500,
  expectedDrawer: 9400,
  variance: -50,
);

const _over = ZReading(
  transactionCount: 12,
  grossSales: 8400,
  cashSales: 4400,
  cardSales: 2500,
  gcashSales: 1500,
  expectedDrawer: 9400,
  variance: 25.5,
);

const _exact = ZReading(
  transactionCount: 12,
  grossSales: 8400,
  cashSales: 4400,
  cardSales: 2500,
  gcashSales: 1500,
  expectedDrawer: 9400,
  variance: 0,
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

/// Mirrors `lib/main.dart`: the auth viewmodel is app-scoped and therefore an
/// ANCESTOR of the Navigator, while [ShiftViewmodel] is NOT — it is created by
/// [PosShiftPage] itself and provided inside the page.
///
/// The old harness provided [ShiftViewmodel] above `MaterialApp` too, which put
/// it above the Navigator and hid a live-QA break: the open-shift DIALOG pushes
/// a route above the page, so `context.read<ShiftViewmodel>()` inside the dialog
/// looked for a provider the real app does not have and threw
/// ProviderNotFoundException into an async callback (swallowed — nothing
/// happened on screen). Anything the dialog needs must now be passed in, so a
/// test that pumps this harness fails if that regresses.
Future<void> _pumpPage(WidgetTester tester, ShiftViewmodel vm) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: PosShiftPage(viewmodel: vm)),
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
      // Card C6 replaced the 300 px card whose big value was the raw word OPEN
      // with the same green chip the till header shows.
      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Shift open'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('₱5,000.00'), findsWidgets);
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
      expect(
        find.text('Last closed shift (Oct 21, 2026, 8:00 AM)'),
        findsOneWidget,
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('₱8,400.00'), findsWidgets);
      expect(find.text('₱4,400.00'), findsOneWidget);
      expect(find.text('₱2,500.00'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsOneWidget);
      expect(find.text('₱9,400.00'), findsOneWidget);
      expect(
        find.text('-₱50.00'),
        findsNWidgets(2),
        reason:
            'a short drawer is the number the cashier must see — once in the '
            'Z-reading and once on the history row',
      );
      expect(find.text('Ana Cruz'), findsWidgets);
      // Z1 (C6): the history badge is sentence case, like every other
      // StatusBadge in the app.
      expect(find.text('Closed'), findsWidgets);
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

    testWidgets('the open-shift DIALOG carries the viewmodel above the page', (
      tester,
    ) async {
      // The dialog route sits ABOVE PosShiftPage's own provider, exactly like the
      // real app (see _pumpPage). The form inside it reads ShiftViewmodel, so the
      // dialog must re-provide the one it was handed.
      final service = _StubShifts();
      await _pump(tester, ShiftViewmodel(service: service));

      await tester.tap(find.widgetWithText(FilledButton, 'Open shift'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), '500');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Open shift'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        service.openCalls,
        1,
        reason:
            'the dialog\'s form must reach the viewmodel — a route above the '
            'page cannot read a page-scoped provider',
      );
      expect(service.openedWith, 500);
      expect(find.text('Open'), findsWidgets);
    });

    testWidgets('with no open shift the tab OPENS one instead of dead-ending', (
      tester,
    ) async {
      final service = _StubShifts();
      await _pump(tester, ShiftViewmodel(service: service));

      // Card C6: the absence of a shift is words a cashier can act on, not the
      // word CLOSED printed as the page's biggest number.
      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('No shift open'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('No shift open. Open one to start selling.'),
        findsOneWidget,
      );
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
        find.text('Open'),
        findsWidgets,
        reason: 'the opened shift is shown on the page that opened it',
      );
      expect(find.textContaining('₱1,500.00'), findsWidgets);
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
      expect(
        find.descendant(
          of: find.byType(PosZReadingSummary),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('₱315.00'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(PosZReadingSummary),
          matching: find.text('₱500.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Last closed shift (Oct 21, 2026, 8:00 AM)'),
        findsNothing,
        reason: 'a live drawer must not be read off the previous shift',
      );
      expect(
        find.text('₱9,400.00'),
        findsNothing,
        reason: 'the previous shift\'s expected drawer is stale on an open one',
      );
      expect(find.text('12'), findsNothing);
    });

    testWidgets('Open and Closed are status badges, not bare words', (
      tester,
    ) async {
      final service = _StubShifts()
        ..current = _shift(id: 1)
        ..history = [
          _shift(id: 3, status: Shift.closedStatus, closingCount: 9350),
          _shift(id: 1),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Shift open'),
        ),
        findsOneWidget,
        reason: 'the live shift is a green chip, the same one the till shows',
      );
      // Z1 (C6): the row state reads as the same sentence case every other
      // StatusBadge uses. The wire code stays OPEN; only the label changed.
      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Open'),
        ),
        findsOneWidget,
        reason: 'the history row state is a badge reading "Open"',
      );
      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Closed'),
        ),
        findsOneWidget,
        reason: 'the history row state is a badge reading "Closed"',
      );
    });

    testWidgets('a short drawer is red with a minus sign', (tester) async {
      final service = _StubShifts()
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            closingCount: 9350,
            zReading: _short,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      final inReading = tester.widget<Text>(
        find.descendant(
          of: find.byType(PosZReadingSummary),
          matching: find.text('-₱50.00'),
        ),
      );
      expect(
        inReading.style?.color,
        AppColors.errorText,
        reason: 'a short drawer is the one number that means count again',
      );

      final inHistory = tester.widget<Text>(
        find.descendant(
          of: find.byType(DataPanel<Shift>),
          matching: find.text('-₱50.00'),
        ),
      );
      expect(inHistory.style?.color, AppColors.errorText);
    });

    testWidgets('an over drawer is green with a plus sign', (tester) async {
      final service = _StubShifts()
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            closingCount: 9425.5,
            zReading: _over,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      final inReading = tester.widget<Text>(
        find.descendant(
          of: find.byType(PosZReadingSummary),
          matching: find.text('+₱25.50'),
        ),
      );
      expect(
        inReading.style?.color,
        AppColors.successText,
        reason: 'over has to read differently from short at a glance',
      );

      final inHistory = tester.widget<Text>(
        find.descendant(
          of: find.byType(DataPanel<Shift>),
          matching: find.text('+₱25.50'),
        ),
      );
      expect(inHistory.style?.color, AppColors.successText);
    });

    testWidgets('a drawer that counts exactly is neither red nor green', (
      tester,
    ) async {
      final service = _StubShifts()
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            closingCount: 9400,
            zReading: _exact,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      final inHistory = tester.widget<Text>(
        find.descendant(
          of: find.byType(DataPanel<Shift>),
          matching: find.text(formatPeso(0)),
        ),
      );
      expect(
        inHistory.style?.color,
        AppColors.textSecondary,
        reason: 'zero is not a warning and not a win',
      );
      expect(
        find.text('+₱0.00'),
        findsNothing,
        reason: 'an exact drawer has no direction to point in',
      );
      expect(find.text('Matches expected cash'), findsOneWidget);
    });

    testWidgets('the reading is a metric row and the opened date is a date', (
      tester,
    ) async {
      final service = _StubShifts()
        ..history = [
          _shift(
            id: 2,
            status: Shift.closedStatus,
            closingCount: 9350,
            zReading: _short,
          ),
        ];
      await _pump(tester, ShiftViewmodel(service: service));

      expect(
        find.descendant(
          of: find.byType(PosZReadingSummary),
          matching: find.byType(MetricTile),
        ),
        findsNWidgets(6),
        reason: 'transactions, gross, cash, card, GCash, expected drawer',
      );
      expect(
        find.textContaining(formatDate(DateTime(2026, 10, 21))),
        findsWidgets,
        reason: 'the Opened column is a date, not a raw server timestamp',
      );
    });

    testWidgets('a shift nobody counted yet says so in words, not a dash', (
      tester,
    ) async {
      final service = _StubShifts()
        ..current = _shift(id: 1)
        ..history = [_shift(id: 1)];
      await _pump(tester, ShiftViewmodel(service: service));

      expect(
        find.text('Not counted yet'),
        findsNWidgets(2),
        reason: 'closing count and variance are both unset on an open row',
      );
      expect(find.text('—'), findsNothing, reason: 'no dashes in copy (D18)');
    });

    testWidgets('a shift that could not be checked offers no guess', (
      tester,
    ) async {
      final service = _StubShifts()
        ..failCurrent = const ShiftServiceException('Cannot connect.');
      await _pump(tester, ShiftViewmodel(service: service));

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Shift not known'),
        ),
        findsOneWidget,
        reason: '"could not ask" must not be printed as "no shift open"',
      );
      expect(
        find.text('No shift open. Open one to start selling.'),
        findsNothing,
        reason: 'the failed read says nothing about whether a drawer is open',
      );
    });

    // The cashier at the drawer does not know the word "variance". The one
    // number that means "count the drawer again" is written as the difference
    // between the cash in hand and the cash the shift should hold, with the two
    // amounts it came from, so it can be checked without asking anybody.
    group('the drawer difference is written in plain words', () {
      testWidgets('the history names the counted cash and its difference', (
        tester,
      ) async {
        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9350,
              zReading: _short,
            ),
          ];
        await _pump(tester, ShiftViewmodel(service: service));

        expect(
          find.text('Variance'),
          findsNothing,
          reason: '"variance" is accounting jargon, not counter language',
        );
        expect(
          find.descendant(
            of: find.byType(DataPanel<Shift>),
            matching: find.text('Cash difference'),
          ),
          findsOneWidget,
          reason: 'the column that holds the difference must say what it is',
        );
        expect(
          find.text('Closing count'),
          findsNothing,
          reason: 'the same fact the close dialog asks for is "cash counted"',
        );
        expect(
          find.descendant(
            of: find.byType(DataPanel<Shift>),
            matching: find.text('Cash counted'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('a short drawer names the two amounts it compares', (
        tester,
      ) async {
        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9350,
              zReading: _short,
            ),
          ];
        await _pump(tester, ShiftViewmodel(service: service));

        final reading = find.byType(PosZReadingSummary);
        expect(
          find.descendant(of: reading, matching: find.text('Cash difference')),
          findsOneWidget,
          reason: 'the callout label must be the plain name, not "Variance"',
        );
        expect(
          find.descendant(
            of: reading,
            matching: find.text('Short of expected cash'),
          ),
          findsOneWidget,
          reason: 'the direction is a word, never the colour alone',
        );
        expect(
          find.descendant(
            of: reading,
            matching: find.text(
              'Cash counted ${formatPeso(9350)} minus expected '
              '${formatPeso(9400)}.',
            ),
          ),
          findsOneWidget,
          reason: 'the difference has to be checkable without asking anyone',
        );
        expect(find.text('Expected cash'), findsOneWidget);
      });

      testWidgets('an over drawer says "over expected cash"', (tester) async {
        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9425.5,
              zReading: _over,
            ),
          ];
        await _pump(tester, ShiftViewmodel(service: service));

        expect(find.text('Over expected cash'), findsOneWidget);
        expect(
          find.textContaining('minus expected'),
          findsOneWidget,
          reason: 'the two amounts are always named, in every direction',
        );
      });

      testWidgets('an exact drawer says it matches, not just "Exact"', (
        tester,
      ) async {
        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9400,
              zReading: _exact,
            ),
          ];
        await _pump(tester, ShiftViewmodel(service: service));

        expect(
          find.descendant(
            of: find.byType(PosZReadingSummary),
            matching: find.text('Matches expected cash'),
          ),
          findsOneWidget,
        );
      });

      // The sweep's window and root font (D-03): the drawer line is the one
      // sentence a cashier reads under stress, so it must survive a raised text
      // scale instead of overflowing the panel that holds it.
      testWidgets('the difference reads whole at 1.3x text', (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9350,
              zReading: _short,
            ),
          ];
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
            child: MaterialApp(
              home: PosShiftPage(viewmodel: ShiftViewmodel(service: service)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Short of expected cash'), findsOneWidget);
        expect(find.textContaining('minus expected'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the difference must not overflow at a raised text scale',
        );
      });

      // End to end at the counter's own narrow window: the card layout's fixed
      // 110 px label column is what cut "Cash difference" at 1.3x text.
      testWidgets('the difference label reads whole in a card at 760 px', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(760, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final service = _StubShifts()
          ..history = [
            _shift(
              id: 2,
              status: Shift.closedStatus,
              closingCount: 9350,
              zReading: _short,
            ),
          ];
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
            child: MaterialApp(
              home: PosShiftPage(viewmodel: ShiftViewmodel(service: service)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The card's own label line, not the callout and not a header label.
        final cardLabel = find.descendant(
          of: find.byKey(const ValueKey('DataPanel.cards')),
          matching: find.text('Cash difference'),
        );
        expect(cardLabel, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: cardLabel, matching: find.byType(RichText)),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'the label must wrap whole, never "Cash differe..."',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('an open shift invents no difference at all', (tester) async {
        // The running reading carries every total and NO variance: there is no
        // closing count yet, so there is nothing to compare and nothing to
        // claim. The one honest sentence is that nobody has counted.
        final service = _StubShifts()
          ..current = _shift(id: 3, openingFloat: 185, zReading: _running)
          ..history = [_shift(id: 3, openingFloat: 185)];
        await _pump(tester, ShiftViewmodel(service: service));

        final reading = find.byType(PosZReadingSummary);
        expect(reading, findsOneWidget);
        expect(
          find.descendant(of: reading, matching: find.text('Cash difference')),
          findsNothing,
          reason: 'an uncounted drawer has no difference to show',
        );
        expect(find.text('Short of expected cash'), findsNothing);
        expect(find.text('Over expected cash'), findsNothing);
        expect(find.text('Matches expected cash'), findsNothing);
        expect(
          find.textContaining('minus expected'),
          findsNothing,
          reason: 'a missing count must not read as a zero difference',
        );
        expect(
          find.text('Not counted yet'),
          findsNWidgets(2),
          reason:
              'the open row still says in words that nobody counted, once for '
              'the cash and once for the difference',
        );
      });
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
      expect(
        find.text('Last closed shift (Oct 21, 2026, 8:00 AM)'),
        findsOneWidget,
      );
    });

    testWidgets(
      'records mid-shift cash withdrawal with reason and updates expected cash',
      (tester) async {
        final service = _StubShifts()
          ..current = _shift(id: 5, openingFloat: 5000, zReading: _running)
          ..history = [_shift(id: 5, openingFloat: 5000, zReading: _running)];
        await _pump(tester, ShiftViewmodel(service: service));

        expect(find.text('Record Cash Out'), findsOneWidget);
        await tester.tap(find.text('Record Cash Out'));
        await tester.pumpAndSettle();

        expect(find.text('Record drawer cash in / out'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Amount'),
          '1200',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason (required)'),
          'Owner safe drop for bank deposit',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save movement'));
        await tester.pumpAndSettle();

        expect(find.text('Cash taken out'), findsOneWidget);
        expect(
          find.text('Cash out · Owner safe drop for bank deposit'),
          findsOneWidget,
        );
        expect(find.text('-₱1,200.00'), findsWidgets);
        // 5000 float + 315 cash sales - 1200 cash out = 4115 expected cash.
        expect(find.text('₱4,115.00'), findsWidgets);
      },
    );
  });
}
