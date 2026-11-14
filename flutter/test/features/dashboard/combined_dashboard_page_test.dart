// Phase 2 F4: the merged account's landing page.
//
// Pinned here, one property per test:
//   * section headings render only for held areas, in Till/Sales/Stock/Admin
//     order, and each section's tiles show their own live counts;
//   * a failed section shows its own ErrorBanner with a retry, and does not
//     hide the counts the OTHER sections already loaded;
//   * a tile tap opens the screen it names.

import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/views/combined_dashboard_page.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_dashboard_alerts_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

const _sales = Role(id: 2, name: 'sales', displayName: 'Store Manager');
const _pos = Role(id: 4, name: 'pos', displayName: 'Cashier');

/// The combined-dashboard tile, not the merged sidebar's own nav item of the
/// same label.
final Finder _heldCartsTile = find.byKey(
  const ValueKey('combinedDashboard.needsYou.heldCarts'),
);
final Finder _shiftTile = find.byKey(
  const ValueKey('combinedDashboard.needsYou.shift'),
);
final Finder _receivablesTile = find.byKey(
  const ValueKey('combinedDashboard.needsYou.receivables'),
);

AuthViewmodel _mergedAuth() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = const User(
    id: 7,
    username: 'staff7',
    email: 'staff7@demo.ph',
    fullName: 'Staff Seven',
    role: _pos,
    roles: [_pos, _sales],
  );
  return auth;
}

class _FakeHeldCartService extends HeldCartService {
  _FakeHeldCartService({this.failure});

  final String? failure;

  @override
  Future<List<HeldCart>> fetchAll() async {
    if (failure != null) throw HeldCartServiceException(failure!);
    return [
      HeldCart(
        id: 1,
        customerId: null,
        customerName: null,
        cashierName: 'Cashy',
        notes: '',
        items: const [],
        createdAt: DateTime(2026, 11, 14),
      ),
    ];
  }
}

class _FakeShiftService extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => null;
}

class _FakeLedgerRepository extends LedgerRepository {
  _FakeLedgerRepository({this.failure});

  final String? failure;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    if (failure != null) {
      throw LedgerServiceException(failure!);
    }
    return [
      LedgerEntry(
        id: 1,
        customerId: 1,
        customerName: 'Dela Cruz',
        transactionNo: 'TRX-1',
        originalAmount: 100,
        balanceDue: 100,
        dueDate: DateTime(2020, 1, 1),
        isOverdue: true,
      ),
    ];
  }
}

Future<void> _pump(
  WidgetTester tester, {
  String? heldCartsFailure,
  String? receivablesFailure,
}) async {
  tester.view.physicalSize = const Size(1440, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: AppRoutes.combinedDashboard,
    routes: [
      GoRoute(
        path: AppRoutes.combinedDashboard,
        builder: (context, state) => CombinedDashboardPage(
          shiftViewmodel: ShiftViewmodel(service: _FakeShiftService()),
          salesAlertsViewmodel: SalesDashboardAlertsViewmodel(
            ledgers: _FakeLedgerRepository(failure: receivablesFailure),
          ),
        ),
      ),
      GoRoute(path: AppRoutes.posHeld, builder: (_, _) => const Text('HELD')),
      GoRoute(
        path: AppRoutes.salesReceivables,
        builder: (_, _) => const Text('RECEIVABLES'),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>.value(value: _mergedAuth()),
        ChangeNotifierProvider<InventoryViewmodel>.value(
          value: InventoryViewmodel(),
        ),
        ChangeNotifierProvider<SuppliersPurchasesViewmodel>.value(
          value: SuppliersPurchasesViewmodel(),
        ),
        ChangeNotifierProvider<HeldCartViewmodel>.value(
          value: HeldCartViewmodel(
            service: _FakeHeldCartService(failure: heldCartsFailure),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a merged account sees only its held areas, in order', (
    tester,
  ) async {
    await _pump(tester);

    final headings = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((text) => text == 'Till' || text == 'Sales')
        .toList();
    expect(headings, ['Till', 'Sales'], reason: 'Till renders above Sales');
    expect(find.text('Stock'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('the Till tile shows the real held-cart count', (tester) async {
    await _pump(tester);

    expect(_heldCartsTile, findsOneWidget);
    expect(
      find.descendant(of: _heldCartsTile, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _shiftTile, matching: find.text('No open shift')),
      findsOneWidget,
    );
  });

  testWidgets('the Sales tile shows the real overdue-receivables count', (
    tester,
  ) async {
    await _pump(tester);

    expect(_receivablesTile, findsOneWidget);
    expect(
      find.descendant(of: _receivablesTile, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a failed Sales read shows its own banner, and Till keeps its count',
    (tester) async {
      await _pump(tester, receivablesFailure: 'Cannot connect.');

      expect(find.text('Cannot connect.'), findsOneWidget);
      expect(
        find.descendant(
          of: _receivablesTile,
          matching: find.text('Not loaded'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _heldCartsTile, matching: find.text('1')),
        findsOneWidget,
        reason: "a failed Sales read must not hide Till's real count",
      );
    },
  );

  testWidgets(
    'a failed Till read shows its own banner, and Sales keeps its count',
    (tester) async {
      await _pump(tester, heldCartsFailure: 'Cannot connect.');

      expect(find.text('Cannot connect.'), findsOneWidget);
      expect(
        find.descendant(of: _receivablesTile, matching: find.text('1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping Held transactions opens the held-transactions screen', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(_heldCartsTile);
    await tester.pumpAndSettle();

    expect(find.text('HELD'), findsOneWidget);
  });

  testWidgets('tapping Overdue receivables opens the receivables screen', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(_receivablesTile);
    await tester.pumpAndSettle();

    expect(find.text('RECEIVABLES'), findsOneWidget);
  });
}
