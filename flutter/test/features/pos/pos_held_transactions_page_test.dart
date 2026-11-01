import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/views/pos_held_transactions_page.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/routes/routes.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The held-transactions SCREEN.
///
/// What a viewmodel test cannot see: that a parked basket is actually readable at
/// the counter (customer, line count, WHAT IT IS WORTH, how long it has been
/// parked, the note), that the safe action (Resume) looks different from the one
/// that destroys the basket (Void), and that a load failure is VISIBLE with a
/// retry rather than an empty list that reads as "nothing is parked" — the
/// failure that would make a cashier re-ring a basket that is still held.
class _StubHeldCarts extends HeldCartService {
  int fetchCalls = 0;
  Object? failFetch;
  List<HeldCart> carts = const [];
  final List<int> voided = [];

  @override
  Future<List<HeldCart>> fetchAll() async {
    fetchCalls++;
    if (failFetch != null) throw failFetch!;
    return carts;
  }

  @override
  Future<void> voidCart(int cartId) async {
    voided.add(cartId);
  }
}

HeldCart _cart({
  required int id,
  String? customerName,
  String notes = '',
  int lines = 2,
  Duration heldFor = const Duration(minutes: 12),
  double unitPrice = 99.5,
}) {
  return HeldCart(
    id: id,
    customerId: customerName == null ? null : 10 + id,
    customerName: customerName,
    cashierName: 'Ana Cruz',
    notes: notes,
    items: [
      for (var i = 0; i < lines; i++)
        HeldCartItem(
          id: id * 10 + i,
          variantUom: 5 + i,
          qty: 1,
          unitPrice: unitPrice,
        ),
    ],
    createdAt: appClock.now().subtract(heldFor),
  );
}

Future<void> _pump(WidgetTester tester, HeldCartViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: PosHeldTransactionsPage(viewmodel: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

/// The till route only exists so the empty state's link has somewhere to land:
/// "nothing is parked" is the moment the cashier needs the till back.
Future<void> _pumpWithRouter(WidgetTester tester, HeldCartViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.posHeld,
    routes: [
      GoRoute(
        path: AppRoutes.posHeld,
        builder: (_, _) => PosHeldTransactionsPage(viewmodel: vm),
      ),
      GoRoute(
        path: AppRoutes.posDashboard,
        builder: (_, _) => const Scaffold(body: Text('the till')),
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

void main() {
  group('PosHeldTransactionsPage', () {
    testWidgets('shows each parked basket with what the cashier needs', (
      tester,
    ) async {
      final service = _StubHeldCarts()
        ..carts = [
          _cart(
            id: 1,
            customerName: 'Dela Cruz Construction',
            notes: 'pay tomorrow',
          ),
          _cart(id: 2, lines: 1),
        ];
      await _pump(tester, HeldCartViewmodel(service: service));

      expect(find.text('Dela Cruz Construction'), findsOneWidget);
      expect(
        find.text('Walk-in'),
        findsOneWidget,
        reason: 'a cart with no customer must say so, not render blank',
      );
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);
      expect(find.text('pay tomorrow'), findsOneWidget);
      expect(find.textContaining('min ago'), findsNWidgets(2));
      expect(find.text('Resume'), findsNWidgets(2));
      expect(find.text('Void'), findsNWidgets(2));
    });

    testWidgets('each basket says what it is worth', (tester) async {
      final service = _StubHeldCarts()
        ..carts = [
          _cart(id: 1, customerName: 'Dela Cruz Construction'),
          _cart(id: 2, lines: 1, unitPrice: 1480.5),
        ];
      await _pump(tester, HeldCartViewmodel(service: service));

      // Two parked baskets for the same customer are told apart by the money on
      // them, not only by the name.
      expect(find.text(formatPeso(199)), findsOneWidget);
      expect(find.text(formatPeso(1480.5)), findsOneWidget);
    });

    testWidgets('Resume is the filled action, Void the quiet one', (
      tester,
    ) async {
      final service = _StubHeldCarts()
        ..carts = [_cart(id: 1, customerName: 'Dela Cruz Construction')];
      await _pump(tester, HeldCartViewmodel(service: service));

      expect(
        find.widgetWithText(FilledButton, 'Resume'),
        findsOneWidget,
        reason: 'picking a basket back up is the safe, expected move',
      );
      expect(find.widgetWithText(TextButton, 'Void'), findsOneWidget);
      final voidButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Void'),
      );
      expect(
        voidButton.style?.foregroundColor?.resolve(<WidgetState>{}),
        AppColors.errorText,
        reason: 'the destructive action reads red and quiet, not equal',
      );
    });

    testWidgets('the newest basket comes first', (tester) async {
      final service = _StubHeldCarts()
        ..carts = [
          _cart(
            id: 1,
            customerName: 'Older Basket',
            heldFor: const Duration(hours: 3),
          ),
          _cart(id: 2, customerName: 'Newer Basket'),
        ];
      await _pump(tester, HeldCartViewmodel(service: service));

      // Cards fill a row, so order is read left to right, then down.
      final newer = tester.getTopLeft(find.text('Newer Basket'));
      final older = tester.getTopLeft(find.text('Older Basket'));
      final newerFirst =
          newer.dy < older.dy || (newer.dy == older.dy && newer.dx < older.dx);
      expect(
        newerFirst,
        isTrue,
        reason: 'a cashier resumes the basket they parked a minute ago',
      );
    });

    testWidgets('a basket without a note shows no dash placeholder', (
      tester,
    ) async {
      final service = _StubHeldCarts()..carts = [_cart(id: 1)];
      await _pump(tester, HeldCartViewmodel(service: service));

      expect(find.text('—'), findsNothing);
    });

    testWidgets('a failed load is VISIBLE with a working retry', (
      tester,
    ) async {
      final service = _StubHeldCarts()
        ..failFetch = const HeldCartServiceException('Cannot connect.');
      await _pump(tester, HeldCartViewmodel(service: service));

      expect(find.text('Cannot connect.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.text('No held transactions.'),
        findsNothing,
        reason:
            'an empty list on failure reads as "nothing is parked", which is '
            'how a cashier re-rings a basket that is still held',
      );

      final callsBeforeRetry = service.fetchCalls;
      service
        ..failFetch = null
        ..carts = [_cart(id: 3, customerName: 'Maria Santos')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(service.fetchCalls, callsBeforeRetry + 1);
      expect(find.text('Maria Santos'), findsOneWidget);
    });

    testWidgets('voiding asks first, then drops the row', (tester) async {
      final service = _StubHeldCarts()
        ..carts = [_cart(id: 1, customerName: 'Dela Cruz Construction')];
      await _pump(tester, HeldCartViewmodel(service: service));

      await tester.tap(find.text('Void'));
      await tester.pumpAndSettle();
      expect(find.text('Void held transaction'), findsOneWidget);

      // Cancel keeps the basket: voiding is irreversible.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.voided, isEmpty);
      expect(find.text('Dela Cruz Construction'), findsOneWidget);

      await tester.tap(find.text('Void'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Void'),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.voided, [1]);
      expect(find.text('Dela Cruz Construction'), findsNothing);
      expect(find.text('No held transactions.'), findsOneWidget);
    });

    testWidgets('an empty queue offers the till', (tester) async {
      await _pumpWithRouter(
        tester,
        HeldCartViewmodel(service: _StubHeldCarts()),
      );

      expect(find.text('No held transactions.'), findsOneWidget);
      await tester.tap(find.text('Go to the till'));
      await tester.pumpAndSettle();

      expect(find.text('the till'), findsOneWidget);
    });
  });

  group('heldCartAgeLabel', () {
    final now = DateTime(2026, 10, 21, 12);
    test('coarsens to the unit a cashier actually needs', () {
      expect(heldCartAgeLabel(now, now: now), 'just now');
      expect(
        heldCartAgeLabel(now.subtract(const Duration(minutes: 12)), now: now),
        '12 min ago',
      );
      expect(
        heldCartAgeLabel(now.subtract(const Duration(hours: 3)), now: now),
        '3 hrs ago',
      );
      expect(
        heldCartAgeLabel(now.subtract(const Duration(days: 2)), now: now),
        '2 days ago',
      );
    });

    test('a clock running behind still reads as just now', () {
      expect(
        heldCartAgeLabel(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });
  });
}
