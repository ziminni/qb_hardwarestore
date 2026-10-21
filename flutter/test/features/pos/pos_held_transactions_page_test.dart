import 'package:client/data/models/held_cart.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/views/pos_held_transactions_page.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The held-transactions SCREEN.
///
/// What a viewmodel test cannot see: that a parked basket is actually readable at
/// the counter (customer, line count, how long it has been parked, the note), and
/// that a load failure is VISIBLE with a retry rather than an empty table that
/// reads as "nothing is parked" — the failure that would make a cashier re-ring a
/// basket that is still held.
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
          unitPrice: 99.5,
        ),
    ],
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
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
      expect(find.textContaining('m ago'), findsNWidgets(2));
      expect(find.text('Resume'), findsNWidgets(2));
      expect(find.text('Void'), findsNWidgets(2));
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
            'an empty table on failure reads as "nothing is parked", which is '
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
  });

  group('heldCartAgeLabel', () {
    final now = DateTime(2026, 10, 21, 12);
    test('coarsens to the unit a cashier actually needs', () {
      expect(heldCartAgeLabel(now, now: now), 'Just now');
      expect(
        heldCartAgeLabel(now.subtract(const Duration(minutes: 12)), now: now),
        '12m ago',
      );
      expect(
        heldCartAgeLabel(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        heldCartAgeLabel(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
    });

    test('a clock running behind still reads as just now', () {
      expect(
        heldCartAgeLabel(now.add(const Duration(minutes: 5)), now: now),
        'Just now',
      );
    });
  });
}
