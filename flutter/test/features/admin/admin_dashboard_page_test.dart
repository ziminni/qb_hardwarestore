// Owner 2026-11-18: Admin → Dashboard, five tabs of the Admin's own figures,
// built to the owner's card / state / token spec.

import 'dart:async';

import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/admin_dashboard_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/admin_dashboard_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _sections() => {
  'system': {
    'users_total': 10,
    'users_active': 9,
    'users_inactive': 1,
    'users_by_role': {'admin': 2, 'bodega': 1},
    'logins_today': 22,
    'failed_logins_7d': 2,
    'events_today': 33,
    'recent_events': [
      {
        'when': '2026-11-18T09:00:00+08:00',
        'user': 'stocker',
        'action': 'Login',
        'description': 'Signed in',
      },
    ],
    'locations': [
      {'name': 'Bodega', 'is_bodega': true, 'is_active': true},
    ],
    'vat_registered': true,
    'vat_rate': '12.00',
    'discount_cap_percent': '10.00',
  },
  'sales': {
    'today_total': '30871.40',
    'today_transactions': 5,
    'month_total': '42327.00',
    'month_transactions': 11,
    'month_returns_total': '0.00',
    'month_returns_count': 0,
    'open_shifts': 2,
    'stale_shifts': <Map<String, dynamic>>[],
    'last_7_days': [
      {'date': '2026-11-18', 'total': '30871.40', 'transactions': 5},
    ],
    'top_products_month': [
      {'name': 'Gravel — 3/4 inch', 'qty': '9.00', 'total': '12150.00'},
    ],
    'by_cashier_today': <Map<String, dynamic>>[],
  },
  'inventory': {
    'products_active': 10,
    'products_archived': 0,
    'stock_cost': '418334.00',
    'stock_retail': '418334.00',
    'by_location': [
      {'name': 'Store', 'cost': '300000.00', 'retail': '300000.00'},
      {'name': 'Bodega', 'cost': '150000.00', 'retail': '150000.00'},
    ],
    'open_alerts': 2,
    'out_of_stock': 1,
    'low_stock': 1,
    'expiring': 0,
    'alerts': <Map<String, dynamic>>[],
    'open_purchase_orders': 0,
    'draft_purchase_orders': 0,
    'adjustments_7d': 0,
    'transfers_7d': 0,
  },
  'bodega': {
    'open_pickups': 0,
    'pending_deliveries': 0,
    'pending_delivery_list': <Map<String, dynamic>>[],
    'releases_today': 4,
    'deliveries_checked_month': 1,
    'write_offs_month': 0,
    'recent_releases': <Map<String, dynamic>>[],
  },
  'finance': {
    'receivables_total': '5372.00',
    'receivables_count': 2,
    'receivables_overdue': '0.00',
    'receivables_overdue_count': 0,
    'overdue_receivables': <Map<String, dynamic>>[],
    'payables_total': '157250.00',
    'payables_count': 2,
    'payables_overdue': '7250.00',
    'payables_overdue_count': 1,
    'payables_due_7d': '150000.00',
    'payables_by_supplier': [
      {'supplier': 'Holcim', 'balance': '157250.00', 'bills': 2},
    ],
    'open_bills': [
      {
        'supplier': 'Holcim',
        'reference': 'DR-118',
        'received_date': '2026-10-01',
        'due_date': '2026-10-31',
        'total': '7250.00',
        'balance': '7250.00',
        'overdue': true,
      },
    ],
    'customer_cheques_pending': 0,
    'supplier_cheques_issued': 0,
    'collections_month': '0.00',
    'supplier_payments_month': '0.00',
  },
};

class _FakeService extends AdminDashboardService {
  _FakeService({this.failing = const {}, this.gate});

  /// Sections that throw.
  final Set<String> failing;

  /// When given, every read waits for it.
  final Completer<void>? gate;

  final List<String> reads = [];

  @override
  Future<DashboardSectionRead> fetchSection(String name) async {
    reads.add(name);
    if (gate != null) await gate!.future;
    if (failing.contains(name)) {
      throw const AdminDashboardException('Cannot connect to the server.');
    }
    return DashboardSectionRead(
      asOf: DateTime.parse('2026-11-18T10:00:00+08:00'),
      section: DashboardSection(_sections()[name] as Map<String, dynamic>),
    );
  }
}

class _NoAuth extends AuthRepository {
  _NoAuth() : super(AuthService());
}

Future<void> _pump(
  WidgetTester tester,
  AdminDashboardService service, {
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1440, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => AuthViewmodel(_NoAuth()),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdminDashboardPage(service: service),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String tab) async {
  // Inside the tab bar: the sidebar also has an "Inventory" entry.
  final target = find.descendant(
    of: find.byKey(const ValueKey('admin-dashboard-tabs')),
    matching: find.text(tab),
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _inAttention(String text) => find.descendant(
  of: find.byKey(const ValueKey('needs-attention')),
  matching: find.text(text),
);

void main() {
  testWidgets('the System tab opens first and only System is read', (
    tester,
  ) async {
    final service = _FakeService();
    await _pump(tester, service);

    expect(find.byKey(const ValueKey('tab-system')), findsOneWidget);
    expect(find.text('Active accounts'), findsOneWidget);
    expect(find.text('Bodega Checker'), findsOneWidget);
    expect(find.text('Registered, 12.00%'), findsOneWidget);
    expect(service.reads, ['system']);
  });

  testWidgets('a tab is read the first time it opens and kept after', (
    tester,
  ) async {
    final service = _FakeService();
    await _pump(tester, service);

    await _open(tester, 'Sales');
    await _open(tester, 'System');
    await _open(tester, 'Sales');

    expect(service.reads, ['system', 'sales']);
  });

  testWidgets('Refresh re-reads only the open tab', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await _open(tester, 'Finance');

    await tester.tap(find.byKey(const ValueKey('dashboard-refresh')));
    await tester.pumpAndSettle();

    expect(service.reads, ['system', 'finance', 'finance']);
  });

  testWidgets('first load shows placeholder blocks, not a spinner', (
    tester,
  ) async {
    final gate = Completer<void>();
    await _pump(tester, _FakeService(gate: gate), settle: false);
    await tester.pump();

    expect(find.byKey(const ValueKey('dashboard-placeholder')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('dashboard-placeholder')), findsNothing);
  });

  testWidgets('a failed tab says why and Try again reads it again', (
    tester,
  ) async {
    final service = _FakeService(failing: {'system'});
    await _pump(tester, service);

    expect(find.text('Cannot connect to the server.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-system')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(service.reads, ['system', 'system']);
  });

  testWidgets('one failing tab does not block the others', (tester) async {
    await _pump(tester, _FakeService(failing: {'system'}));

    await _open(tester, 'Sales');

    expect(find.byKey(const ValueKey('tab-sales')), findsOneWidget);
  });

  testWidgets('stat tiles show whole pesos', (tester) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Sales');

    expect(find.text(formatPesoWhole(30871.40)), findsWidgets);
    expect(find.text('₱30,871'), findsWidgets);
  });

  testWidgets('urgent attention rows come before warnings', (tester) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Finance');

    final urgent = tester.getTopLeft(
      _inAttention('1 supplier bill overdue · ₱7,250'),
    );
    final warning = tester.getTopLeft(
      _inAttention('₱150,000 in bills due this week'),
    );
    expect(urgent.dy, lessThan(warning.dy));
  });

  testWidgets('nothing wrong shows one All clear row', (tester) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Bodega');

    expect(_inAttention('All clear'), findsOneWidget);
    expect(
      _inAttention('Every Bodega delivery has been checked.'),
      findsOneWidget,
    );
  });

  testWidgets('read-only tabs say who records the data; System does not', (
    tester,
  ) async {
    await _pump(tester, _FakeService());
    expect(find.byKey(const ValueKey('read-only-banner')), findsNothing);

    await _open(tester, 'Sales');
    expect(find.byKey(const ValueKey('read-only-banner')), findsOneWidget);
    expect(find.textContaining('Cashiers record sales'), findsOneWidget);

    // Owner 2026-11-18: the Admin sees everything and acts on nothing, so
    // Finance is read-only too.
    await _open(tester, 'Finance');
    expect(find.byKey(const ValueKey('read-only-banner')), findsOneWidget);
    expect(find.textContaining('Store Manager pays'), findsOneWidget);
  });

  testWidgets('daily admin sales show count and exact pesos', (tester) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Sales');

    expect(find.textContaining('· 5 transactions'), findsOneWidget);
    expect(find.text('₱30,871.40'), findsOneWidget);
  });

  testWidgets('breakdown bars are sized against the largest row', (
    tester,
  ) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Inventory');

    final store = tester.getSize(find.byKey(const ValueKey('bar-Store')));
    final bodega = tester.getSize(find.byKey(const ValueKey('bar-Bodega')));
    expect(bodega.width, closeTo(store.width / 2, 1));
  });

  testWidgets('an item row expands to show its facts; overdue reads red', (
    tester,
  ) async {
    await _pump(tester, _FakeService());
    await _open(tester, 'Finance');

    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('DR-118'), findsNothing);

    final status = find.textContaining('Overdue since');
    expect(tester.widget<Text>(status).style?.color, const Color(0xFF991B1B));

    await tester.ensureVisible(status);
    await tester.tap(status);
    await tester.pumpAndSettle();
    expect(find.text('DR-118'), findsOneWidget);
    expect(find.text('Bill total'), findsOneWidget);
  });

  testWidgets('the menu says Dashboard and has no Reports or requests', (
    tester,
  ) async {
    await _pump(tester, _FakeService());
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Project requests'), findsNothing);
  });

  test('the Admin menu keeps only the Admin\'s own jobs', () {
    final labels = AdminSkeletonLayout.navigationSections
        .expand((section) => section.destinations)
        .map((destination) => destination.label);
    for (final kept in ['User management', 'Settings', 'Audit logs']) {
      expect(labels, contains(kept));
    }
    for (final gone in [
      'Sales & POS',
      'Payables',
      'Deliveries',
      'Transfers',
      'Storage locations',
    ]) {
      expect(labels, isNot(contains(gone)));
    }
  });

  testWidgets('the tabs are underlined tabs with the open one marked', (
    tester,
  ) async {
    await _pump(tester, _FakeService());
    final bar = find.byKey(const ValueKey('admin-dashboard-tabs'));
    expect(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.point_of_sale_outlined),
      ),
      findsOneWidget,
    );
    FontWeight? weight(String tab) => tester
        .widget<Text>(find.descendant(of: bar, matching: find.text(tab)))
        .style
        ?.fontWeight;
    expect(weight('System'), FontWeight.w700);
    expect(weight('Sales'), FontWeight.w500);
  });
}
