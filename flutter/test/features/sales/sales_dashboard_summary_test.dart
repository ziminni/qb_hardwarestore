// Phase 5 Task 3: dashboard tiles read the server summary, never the client
// fold. With ZERO loaded transactions and a summary of 9000/40, the tiles
// must still show 9000 and 40 — a fold would show 0.
//
// Card M1 (ui-refresh): the dashboard also leads with what needs the manager
// NOW — requisitions waiting, overdue receivables, today's returns — each a
// link into the screen that handles it, and each count taken from a read that
// actually answered. The page's own heading is gone: the shell already says
// "Sales Dashboard", and two headings before any number is one too many.

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_dashboard_alerts_viewmodel.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubSalesService extends SalesService {
  _StubSalesService({this.transactions = const []}) : super();

  final List<TransactionRecord> transactions;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      transactions;
}

class _FailingSalesService extends SalesService {
  _FailingSalesService() : super();

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      throw const SalesServiceException(
        'The sales list could not be loaded. Try again.',
      );
}

class _FailingReportsRepository extends ReportsRepository {
  _FailingReportsRepository() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      throw const ReportsServiceException('Summary unavailable.');
}

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      const SalesSummary(
        from: '2026-09-26',
        to: '2026-10-25',
        totalTransactions: 40,
        totalGross: 9000,
        totalVat: 0,
        totalDiscounts: 0,
        days: [],
      );
}

class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions({this.rows = const []}) : super();

  final List<Requisition> rows;

  @override
  Future<List<Requisition>> fetchRequisitions() async => rows;
}

class _FailingRequisitions extends RequisitionRepository {
  _FailingRequisitions() : super();

  @override
  Future<List<Requisition>> fetchRequisitions() async =>
      throw const RequisitionServiceException(
        'The requisition list could not be loaded. Try again.',
      );
}

class _StubLedgers extends LedgerRepository {
  _StubLedgers({this.rows = const []}) : super();

  final List<LedgerEntry> rows;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => rows;
}

class _FailingLedgers extends LedgerRepository {
  _FailingLedgers() : super();

  @override
  Future<List<LedgerEntry>> fetchLedgers() async =>
      throw const LedgerServiceException(
        'The receivables list could not be loaded. Try again.',
      );
}

Requisition _requisition({
  required int id,
  required RequisitionStatus status,
}) => Requisition(
  id: id,
  reqNumber: 'REQ-20261019-000$id',
  rawStatus: status.apiValue,
  projectName: 'Dela Cruz Residence',
  projectCustomerName: 'Dela Cruz Construction',
  requestedByName: 'Eng. Reyes',
  items: const [
    RequisitionItem(
      id: 1,
      variantId: 1,
      variantName: 'Cement 40kg',
      quantity: 20,
      releasedQty: 0,
    ),
  ],
);

LedgerEntry _ledger({
  required int id,
  required String customer,
  required bool overdue,
}) => LedgerEntry(
  id: id,
  customerId: id,
  customerName: customer,
  transactionNo: 'TRX-20261019-000$id',
  originalAmount: 48000,
  balanceDue: 24000,
  dueDate: overdue ? DateTime(2026, 9, 30) : DateTime(2030, 1, 1),
  isOverdue: overdue,
);

TransactionRecord _transaction({
  required int id,
  required String no,
  required String source,
  required DateTime date,
  double total = 100,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: date,
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: source,
  originalTransactionId: source == 'RETURN' ? 1 : null,
  status: source == 'RETURN' ? 'REFUNDED' : 'COMPLETED',
  grandTotal: total,
  items: const [],
  payments: const [],
);

/// A sales viewmodel with nothing loaded, for the tests that only care about
/// the queue counts.
InventorySalesViewmodel _emptySales() => InventorySalesViewmodel(
  service: _StubSalesService(),
  reports: _StubReportsRepository(),
);

Widget _app(
  Widget child, {
  required InventorySalesViewmodel sales,
  InventoryViewmodel? inventory,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
    ),
    ChangeNotifierProvider<InventorySalesViewmodel>.value(value: sales),
    if (inventory != null)
      ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
  ],
  child: child,
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _tile(String name) =>
    find.byKey(ValueKey('salesDashboard.needsYou.$name'));

Finder _tileValue(String name, String text) =>
    find.descendant(of: _tile(name), matching: find.text(text));

/// The dashboard inside a real router, so a tapped tile can be seen to land on
/// another screen instead of merely looking tappable.
Future<GoRouter> _pumpRouted(WidgetTester tester) async {
  _sizeUp(tester);
  final router = GoRouter(
    initialLocation: AppRoutes.salesDashboard,
    routes: [
      GoRoute(
        path: AppRoutes.salesDashboard,
        builder: (context, state) =>
            SalesDashboardPage(viewmodel: _alerts(awaiting: 3, overdue: 2)),
      ),
      for (final path in [
        AppRoutes.salesRequisitions,
        AppRoutes.salesReceivables,
        AppRoutes.salesReturns,
      ])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(body: Text('page:$path')),
        ),
    ],
  );
  await tester.pumpWidget(
    _app(MaterialApp.router(routerConfig: router), sales: _emptySales()),
  );
  await tester.pumpAndSettle();
  return router;
}

SalesDashboardAlertsViewmodel _alerts({int? awaiting, int? overdue}) =>
    SalesDashboardAlertsViewmodel(
      requisitions: _StubRequisitions(
        rows: [
          for (var i = 1; i <= (awaiting ?? 0); i++)
            _requisition(id: i, status: RequisitionStatus.submitted),
        ],
      ),
      ledgers: _StubLedgers(
        rows: [
          for (var i = 1; i <= (overdue ?? 0); i++)
            _ledger(id: i, customer: 'Customer $i', overdue: true),
        ],
      ),
    );

void main() {
  testWidgets('tiles show server totals even with no loaded rows', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(const MaterialApp(home: SalesDashboardPage()), sales: _emptySales()),
    );
    await tester.pumpAndSettle();

    expect(find.text('₱9,000.00'), findsOneWidget);
    expect(find.text('40'), findsWidgets);
    expect(find.textContaining('Last 30 days'), findsWidgets);
    // The fold of zero rows would read 0 — that number must not appear.
    expect(find.text('₱0.00'), findsNothing);
  });

  testWidgets('the dashboard reads the catalogue the product names live in', (
    tester,
  ) async {
    // FX4: the sales wire carries the selling unit's id and code only, so the
    // top-products panel can only name a product once the app-scoped catalogue
    // has been read. One shared read, guarded like the products screen.
    _sizeUp(tester);
    final products = FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Cement Bag',
          variants: [
            variant(
              id: 5,
              productId: 1,
              name: '40 kg',
              sellingUoms: [variantUom(id: 8, variantId: 5)],
            ),
          ],
        ),
      ],
      batches: [batch(id: 1, variantId: 5, qty: 100)],
    );
    final inventory = InventoryViewmodel(
      products: products,
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );

    await tester.pumpWidget(
      _app(
        const MaterialApp(home: SalesDashboardPage()),
        sales: _emptySales(),
        inventory: inventory,
      ),
    );
    await tester.pumpAndSettle();

    expect(products.loadCount, 1);
  });

  testWidgets('the page repeats no heading above its numbers', (tester) async {
    await _pumpRouted(tester);

    // The shell title is "Sales Dashboard"; a second heading before any number
    // is one heading too many.
    expect(find.text('Sales overview'), findsNothing);
    expect(find.text('Live sales activity'), findsNothing);
    expect(find.text('Needs you'), findsOneWidget);
  });

  testWidgets('"Needs you" tiles lead to Approvals, Receivables and Returns', (
    tester,
  ) async {
    final router = await _pumpRouted(tester);

    const links = [
      ('approvals', AppRoutes.salesRequisitions),
      ('receivables', AppRoutes.salesReceivables),
      ('returns', AppRoutes.salesReturns),
    ];
    for (final link in links) {
      expect(_tile(link.$1), findsOneWidget);
      await tester.tap(_tile(link.$1));
      await tester.pumpAndSettle();
      expect(find.text('page:${link.$2}'), findsOneWidget);

      router.go(AppRoutes.salesDashboard);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('the outstanding queues show the count their read answered', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        MaterialApp(
          home: SalesDashboardPage(viewmodel: _alerts(awaiting: 3, overdue: 2)),
        ),
        sales: _emptySales(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_tileValue('approvals', '3'), findsOneWidget);
    expect(_tileValue('receivables', '2'), findsOneWidget);
    // A read that answered is not a failure: no banner.
    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('a failed queue read says Not loaded instead of a zero', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        MaterialApp(
          home: SalesDashboardPage(
            viewmodel: SalesDashboardAlertsViewmodel(
              requisitions: _FailingRequisitions(),
              ledgers: _FailingLedgers(),
            ),
          ),
        ),
        sales: _emptySales(),
      ),
    );
    await tester.pumpAndSettle();

    expect(_tileValue('approvals', 'Not loaded'), findsOneWidget);
    expect(_tileValue('receivables', 'Not loaded'), findsOneWidget);
    // The first failure is named; nothing invents a count.
    expect(
      find.text('The requisition list could not be loaded. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed first load says Not loaded instead of a zero', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        MaterialApp(
          home: SalesDashboardPage(viewmodel: _alerts(awaiting: 0, overdue: 0)),
        ),
        sales: InventorySalesViewmodel(
          service: _FailingSalesService(),
          reports: _FailingReportsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // One failure per read, each naming itself and offering its own retry.
    expect(
      find.text('The sales list could not be loaded. Try again.'),
      findsOneWidget,
    );
    // A list that never arrived is not an empty list: no panel below the
    // banner may claim "no sales transactions".
    expect(find.text('No sales transactions yet.'), findsNothing);
    // Nor is an unanswered read a zero: the three sales tiles say so, while
    // the queue tiles still show the zeroes their own reads did answer with.
    expect(find.text('₱0.00'), findsNothing);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Transactions'),
          matching: find.byType(MetricTile),
        ),
        matching: find.text('Not loaded'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('returns today counts only the loaded rows dated today', (
    tester,
  ) async {
    _sizeUp(tester);
    final today = DateTime.now();
    await tester.pumpWidget(
      _app(
        MaterialApp(
          home: SalesDashboardPage(viewmodel: _alerts(awaiting: 0, overdue: 0)),
        ),
        sales: InventorySalesViewmodel(
          service: _StubSalesService(
            transactions: [
              _transaction(
                id: 1,
                no: 'TRX-20261019-0001',
                source: 'WALK_IN',
                date: today,
              ),
              // Two returns today and one yesterday: the tile counts 2.
              _transaction(
                id: 2,
                no: 'TRX-20261019-0002',
                source: 'RETURN',
                date: today,
                total: -100,
              ),
              _transaction(
                id: 3,
                no: 'TRX-20261019-0003',
                source: 'RETURN',
                date: today,
                total: -50,
              ),
              _transaction(
                id: 4,
                no: 'TRX-20261019-0004',
                source: 'RETURN',
                date: today.subtract(const Duration(days: 1)),
                total: -30,
              ),
            ],
          ),
          reports: _StubReportsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_tileValue('returns', '2'), findsOneWidget);
  });
}
