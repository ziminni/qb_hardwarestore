// Phase 3 Task 4 / decision 05: the till's Returns tab as a CASHIER sees it.
//
// What a viewmodel test cannot see, and this file pins:
//
//  * the shift GATE comes first — no open shift, no search box, and the way out
//    is the Shifts tab (the same rule the till itself follows);
//  * a fully returned line is shown DISABLED (`onPressed: null`) rather than
//    silently absent, so the cashier can see the line came back;
//  * the confirm dialog states return value, debt reduced and the CASH estimate
//    BEFORE anything is posted;
//  * the posted refund summary is what the screen prints afterwards — the
//    server's numbers, not the till's arithmetic;
//  * a `NO_OPEN_SHIFT` refusal offers the Shifts tab instead of a dead end.

import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

TransactionRecord _sale() => TransactionRecord(
  id: 18,
  transactionNo: 'TRX-20261024-0007',
  transDate: DateTime(2026, 10, 24, 9),
  customerId: 2,
  customerName: 'Maria Santos',
  cashierName: 'Ana Cruz',
  source: 'CHARGE',
  originalTransactionId: null,
  status: 'COMPLETED',
  grandTotal: 1000,
  items: const [],
  payments: const [],
);

ReturnableSale _preflight({
  double openDebt = 600,
  bool returnable = true,
  String? reasonIfNot,
}) => ReturnableSale(
  transactionNo: 'TRX-20261024-0007',
  customer: 'Maria Santos',
  source: 'CHARGE',
  returnable: returnable,
  reasonIfNot: reasonIfNot,
  openDebt: openDebt,
  lines: const [
    ReturnableLine(
      variantUomId: 8,
      name: 'Portland Cement - 40kg',
      uom: 'BAG',
      soldQty: 10,
      returnedQty: 2,
      remainingQty: 8,
      unitPrice: 100,
    ),
    ReturnableLine(
      variantUomId: 9,
      name: 'Steel Bar 10mm',
      uom: 'PC',
      soldQty: 5,
      returnedQty: 5,
      remainingQty: 0,
      unitPrice: 250,
    ),
  ],
);

class _StubReturns extends ReturnsRepository {
  _StubReturns({this.found, this.preflight});

  TransactionRecord? found;
  ReturnableSale? preflight;
  Object? failPost;
  int posts = 0;

  @override
  Future<TransactionRecord?> findSale(String query) async => found;

  @override
  Future<ReturnableSale> fetchReturnable(int transactionId) async => preflight!;

  @override
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    posts++;
    if (failPost != null) throw failPost!;
    return const ReturnResult(
      returnNo: 'RTN-20261024-0001',
      refund: RefundSummary(
        returnValue: 800,
        debtReduced: 600,
        cashRefund: 200,
        refundMethod: 'CASH',
        ledgerId: 5,
        ledgerBalance: 0,
      ),
    );
  }
}

class _StubShifts extends ShiftService {
  _StubShifts(this.current);

  Shift? current;

  @override
  Future<Shift?> fetchCurrent() async => current;

  @override
  Future<List<Shift>> fetchAll() async => const [];
}

Shift _openShift() => Shift(
  id: 4,
  cashierName: 'Ana Cruz',
  status: Shift.openStatus,
  openingFloat: 5000,
  closingCount: null,
  openedAt: DateTime(2026, 10, 24, 8),
  closedAt: null,
  notes: '',
  zReading: null,
);

Future<void> _pump(
  WidgetTester tester, {
  required ReturnsRepository returns,
  bool openShift = true,
  List<String>? visits,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final returnsViewmodel = PosReturnsViewmodel(repository: returns);
  final shiftViewmodel = ShiftViewmodel(
    service: _StubShifts(openShift ? _openShift() : null),
  );

  final router = GoRouter(
    initialLocation: AppRoutes.posReturns,
    routes: [
      GoRoute(
        path: AppRoutes.posReturns,
        builder: (context, state) => PosReturnsPage(
          viewmodel: returnsViewmodel,
          shiftViewmodel: shiftViewmodel,
        ),
      ),
      GoRoute(
        path: AppRoutes.posShifts,
        builder: (context, state) {
          visits?.add(AppRoutes.posShifts);
          return const Scaffold(body: Text('SHIFTS PAGE'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// Search, then wait for the pre-flight.
Future<void> _search(WidgetTester tester, String number) async {
  await tester.enterText(find.byType(TextField).first, number);
  await tester.tap(find.widgetWithText(FilledButton, 'Search sale'));
  await tester.pumpAndSettle();
}

void main() {
  group('the shift gate comes first', () {
    testWidgets('no open shift: no search box, and the Shifts tab is offered', (
      tester,
    ) async {
      final visits = <String>[];
      await _pump(
        tester,
        returns: _StubReturns(),
        openShift: false,
        visits: visits,
      );

      expect(find.text('Open a shift before taking a return'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'a refund cannot be posted without a drawer to post it to',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Go to Shifts'));
      await tester.pumpAndSettle();

      expect(visits, [AppRoutes.posShifts]);
      expect(find.text('SHIFTS PAGE'), findsOneWidget);
    });
  });

  group('the full flow, with a shift open', () {
    testWidgets('search shows the sale, what is left, and the utang', (
      tester,
    ) async {
      await _pump(
        tester,
        returns: _StubReturns(found: _sale(), preflight: _preflight()),
      );

      await _search(tester, 'OR-20261024-0007');

      expect(find.text('TRX-20261024-0007'), findsOneWidget);
      expect(find.textContaining('Maria Santos'), findsOneWidget);
      expect(
        find.textContaining('still owes ₱600.00'),
        findsOneWidget,
        reason:
            'the debt is WHY a credit sale does not refund all cash, and the '
            'cashier must see it before choosing a quantity',
      );
      expect(find.textContaining('8.0 of 10.0 left'), findsOneWidget);
      expect(
        find.textContaining('All 5.0 already returned'),
        findsOneWidget,
        reason: 'a returned-out line is shown, disabled — not hidden',
      );
    });

    testWidgets('a fully returned line cannot be incremented', (tester) async {
      await _pump(
        tester,
        returns: _StubReturns(found: _sale(), preflight: _preflight()),
      );
      await _search(tester, 'OR-1');

      final plusButtons = find.widgetWithIcon(
        IconButton,
        Icons.add_circle_outline,
      );
      expect(plusButtons, findsNWidgets(2));
      final disabled = tester.widget<IconButton>(plusButtons.at(1));
      expect(
        disabled.onPressed,
        isNull,
        reason:
            'the stepper must be DISABLED with a reason on screen, not silently '
            'dead (no_dead_controls_test)',
      );
    });

    testWidgets('confirm is disabled until a quantity and a reason exist', (
      tester,
    ) async {
      final returns = _StubReturns(found: _sale(), preflight: _preflight());
      await _pump(tester, returns: returns);
      await _search(tester, 'OR-1');

      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm return'),
      );
      expect(confirm().onPressed, isNull);

      await tester.tap(find.byTooltip('One more').first);
      await tester.pumpAndSettle();
      expect(
        confirm().onPressed,
        isNull,
        reason: 'the reason is still missing',
      );

      await tester.enterText(find.byType(TextField).last, 'cracked sacks');
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets(
      'the confirm dialog states value, debt and cash before posting',
      (tester) async {
        final returns = _StubReturns(found: _sale(), preflight: _preflight());
        await _pump(tester, returns: returns);
        await _search(tester, 'OR-1');

        // Eight bags: 800 of value against 600 of utang.
        for (var i = 0; i < 8; i++) {
          await tester.tap(find.byTooltip('One more').first);
          await tester.pump();
        }
        await tester.enterText(find.byType(TextField).last, 'cracked sacks');
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(FilledButton, 'Confirm return'));
        await tester.pumpAndSettle();

        expect(find.text('Confirm the return'), findsOneWidget);
        expect(find.text('Return value ₱800.00'), findsOneWidget);
        expect(find.text('Settles utang ₱600.00'), findsOneWidget);
        expect(
          find.textContaining('Cash refund ₱200.00'),
          findsOneWidget,
          reason: 'only the EXCESS leaves the drawer (decision 05)',
        );
        expect(
          returns.posts,
          0,
          reason: 'nothing is posted before the cashier says so',
        );
      },
    );

    testWidgets('posting shows the server refund summary', (tester) async {
      final returns = _StubReturns(found: _sale(), preflight: _preflight());
      await _pump(tester, returns: returns);
      await _search(tester, 'OR-1');

      await tester.tap(find.byTooltip('One more').first);
      await tester.tap(find.byTooltip('One more').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'cracked sacks');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
      await tester.pumpAndSettle();

      expect(returns.posts, 1);
      expect(find.text('Return posted: RTN-20261024-0001'), findsOneWidget);
      expect(find.text('Utang reduced ₱600.00'), findsOneWidget);
      expect(find.text('Cash refunded ₱200.00 (CASH)'), findsOneWidget);
      expect(find.text('Ledger still owes ₱0.00'), findsOneWidget);
      // The next return starts from a clean screen, not the last customer's.
      expect(find.widgetWithText(OutlinedButton, 'New return'), findsOneWidget);
    });

    testWidgets('a NO_OPEN_SHIFT refusal offers the Shifts tab', (
      tester,
    ) async {
      final returns = _StubReturns(found: _sale(), preflight: _preflight())
        ..failPost = const ReturnsServiceException(
          'You have no open shift. Open a shift before posting a return.',
          code: 'NO_OPEN_SHIFT',
          needsOpenShift: true,
        );
      final visits = <String>[];
      await _pump(tester, returns: returns, visits: visits);
      await _search(tester, 'OR-1');

      await tester.tap(find.byTooltip('One more').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'unwanted');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm return'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Open a shift'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Go to Shifts'));
      await tester.pumpAndSettle();

      expect(visits, [AppRoutes.posShifts]);
    });
  });

  group('a document the server will not reverse', () {
    testWidgets('says which rule stopped it and offers no stepper', (
      tester,
    ) async {
      await _pump(
        tester,
        returns: _StubReturns(
          found: _sale(),
          preflight: _preflight(
            returnable: false,
            reasonIfNot: 'RELEASE_NOT_RETURNABLE',
          ),
        ),
      );

      await _search(tester, 'OR-1');

      expect(
        find.textContaining('material release, not a sale'),
        findsOneWidget,
      );
      expect(find.byTooltip('One more'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Confirm return'), findsNothing);
    });
  });

  group('a miss', () {
    testWidgets('states the miss instead of showing an empty form', (
      tester,
    ) async {
      await _pump(tester, returns: _StubReturns());

      await _search(tester, 'OR-nope');

      expect(
        find.textContaining('No sale of yours matches that number'),
        findsOneWidget,
      );
      expect(find.text('TRX-20261024-0007'), findsNothing);
    });
  });
}
