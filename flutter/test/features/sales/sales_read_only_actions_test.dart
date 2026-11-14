// Phase 3 Task 0 (U) — dead controls on the Store Manager's sales screens.
//
// What was there (2026-10-24 report): buttons that looked live and did nothing.
//
//   Sales Quotations  "New quotation"      — no create screen, no endpoint
//   Sales Orders      "New sales order"    — same, until Phase 5 F3's follow-up
//                                             (see below) built a create-only form
//   Sales Returns     "New customer return"— cashiers return from the till
//                                             (Phase 3 Task 4); the manager's
//                                             unlinked-return screen is Phase 5
//   Sales Returns row "View"               — swallowed the tap
//   Sales Dashboard   "This month"         — filtered nothing
//
// The quotation and return create buttons are REMOVED (those views are read-only
// by decision). "New sales order" is BACK as a form: the owner authorised it in
// the Phase 5 F3 follow-up. Phase 7 F1 supersedes the ORDER half of these pins —
// a Store Manager/Admin now gets Edit and Cancel on an unfulfilled order (decision
// 19 #4) — and keeps the rest: DELETE is still gone (cancellation replaces it),
// a cashier is offered neither action, and the QUOTATION pins are untouched.
// "View" opens the real read-only details sheet — the same document sheet the
// transactions page uses. "This month" becomes a label that states what the
// dashboard actually shows: every recorded transaction, with no period filter.

import 'package:client/data/models/reports.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';
import 'package:provider/provider.dart';

/// Phase 5 Task 3: the dashboard tiles read the summary, so the dead-label
/// test pins the fallback — a refused summary keeps honest row-folded tiles
/// that say where they came from, never a crash on an uninitialized client.
class _FailingReportsRepository extends ReportsRepository {
  _FailingReportsRepository() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    throw const ReportsServiceException('Summary unavailable.');
  }
}

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<QuotationRecord> quotations = const [];
  List<SalesOrderRow> orders = const [];
  List<TransactionRecord> transactions = const [];

  @override
  Future<List<QuotationRecord>> fetchQuotations() async => quotations;

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async => orders;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      transactions;
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService() : super();

  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(
      id: 3,
      name: 'Dela Cruz Construction',
      customerType: 'CONSTRUCTION_FIRM',
    ),
  ];
}

QuotationRecord _quotation() => const QuotationRecord(
  id: 1,
  number: 'QT-20261019-0001',
  customerId: 3,
  status: 'SENT',
  validUntil: '2026-11-19',
  createdAt: '2026-10-19T08:00:00Z',
  items: [],
);

SalesOrderRow _order() => const SalesOrderRow(
  id: 7,
  number: 'SO-20261019-0001',
  customerId: 3,
  quotationId: 1,
  status: 'CONFIRMED',
  createdAt: '2026-10-19T08:00:00Z',
  items: [],
);

TransactionRecord _row({
  required int id,
  required String no,
  required String source,
  int? original,
  double total = 100,
  List<TransactionLineItem> items = const [],
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: DateTime(2026, 10, 19, 8),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: source,
  originalTransactionId: original,
  status: 'COMPLETED',
  grandTotal: total,
  items: items,
  payments: const [],
);

const _returnItems = [
  TransactionLineItem(
    variantUomId: 1,
    variantUomCode: 'BAG',
    qty: 2,
    unitPrice: 50,
    subtotal: 100,
  ),
  TransactionLineItem(
    variantUomId: 2,
    variantUomCode: 'TILE',
    qty: 1,
    unitPrice: 30,
    subtotal: 30,
  ),
];

/// A catalogue the return lines resolve names against. The wire carries only
/// `variant_uom` codes/ids, so a name has to come from the app-scoped catalogue.
///
/// Phase 4 Task 4: seeded through the repository + `load()`, because the
/// in-memory `addProduct` that used to build it is gone.
Future<InventoryViewmodel> _inventory() async {
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Cement Bag',
          categoryName: 'Hardware',
          brandName: 'BuildPro',
          variants: [
            variant(
              id: 5,
              productId: 1,
              name: '40kg',
              threshold: 1,
              maxStockLevel: 100,
              sellingUoms: [
                variantUom(id: 1, variantId: 5, price: 50, uomCode: 'BAG'),
              ],
            ),
          ],
        ),
      ],
      batches: [batch(id: 1, variantId: 5, qty: 10)],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();
  return inventory;
}

/// The role CODE the server sends as `role.name`, keyed by the label a person
/// reads (the Phase 4 fixture trap: putting the label in both fields passed a
/// test the live server would fail).
const _roleCodes = {
  'Store Manager': 'sales',
  'Cashier': 'pos',
  'Stock Manager': 'inventory',
};

AuthViewmodel _auth({String? role, List<String> roles = const []}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (role != null) {
    auth.user = User(
      id: 1,
      username: 'manager',
      email: 'manager@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 4, name: _roleCodes[role]!, displayName: role),
    );
    auth.selectArea(_roleCodes[role]!);
  }
  if (roles.isNotEmpty) {
    // Phase 2 F3: a merged account has no active area at all, so only the
    // areas it holds can answer an action gate.
    auth.user = User(
      id: 2,
      username: 'merged',
      email: 'merged@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 1, name: roles.first, displayName: roles.first),
      roles: [
        for (final (index, code) in roles.indexed)
          Role(id: index + 1, name: code, displayName: code),
      ],
    );
  }
  return auth;
}

Widget _app(
  Widget child, {
  InventoryViewmodel? inventory,
  String? role,
  List<String> roles = const [],
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: _auth(role: role, roles: roles),
    ),
    if (inventory != null)
      ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
  ],
  child: MaterialApp(home: child),
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _inSheet(String text) => find.descendant(
  of: find.byType(SalesDocumentSheet),
  matching: find.textContaining(text),
);

void main() {
  late _StubSalesService sales;

  setUp(() => sales = _StubSalesService());

  testWidgets('quotations: the dead "New quotation" button is gone', (
    tester,
  ) async {
    _sizeUp(tester);
    sales.quotations = [_quotation()];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<SalesModuleViewmodel>(
          create: (_) => SalesModuleViewmodel(
            service: sales,
            customerService: _StubCustomerService(),
          ),
          child: const SalesQuotationsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New quotation'), findsNothing);
    // The page still works: the row is there, and View still opens the document.
    expect(find.text('QT-20261019-0001'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('orders: a manager may edit or cancel, never delete', (
    tester,
  ) async {
    _sizeUp(tester);
    sales.orders = [_order()];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<SalesModuleViewmodel>(
          create: (_) => SalesModuleViewmodel(
            service: sales,
            customerService: _StubCustomerService(),
          ),
          child: const SalesOrdersPage(),
        ),
        role: 'Store Manager',
      ),
    );
    await tester.pumpAndSettle();

    // Phase 5 F3 follow-up made creating real; Phase 7 F1 adds the two lifecycle
    // actions decision 19 #4 grants a manager, and NOT a delete: a cancellation
    // with a reason replaces it (decision 19, "DELETE removed for orders").
    expect(find.text('New sales order'), findsOneWidget);
    expect(find.text('New quotation'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('SO-20261019-0001'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    expect(_inSheet('Edit'), findsOneWidget);
    expect(_inSheet('Cancel'), findsOneWidget);
    expect(_inSheet('Delete'), findsNothing);
    // The sheet itself still edits nothing: the actions close it and the page
    // opens the dialog that writes.
    expect(
      find.descendant(
        of: find.byType(SalesDocumentSheet),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
  });

  testWidgets('orders: a cashier is offered neither action', (tester) async {
    _sizeUp(tester);
    sales.orders = [_order()];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<SalesModuleViewmodel>(
          create: (_) => SalesModuleViewmodel(
            service: sales,
            customerService: _StubCustomerService(),
          ),
          child: const SalesOrdersPage(),
        ),
        role: 'Cashier',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    expect(_inSheet('Edit'), findsNothing);
    // 'Cancelled' is not on this sheet, so 'Cancel' can only be the action.
    expect(_inSheet('Cancel'), findsNothing);
    expect(_inSheet('Delete'), findsNothing);
  });

  // Phase 2 F3 (decision 24): a merged account has no active area, so an
  // action gate asks what the account HOLDS. Store Manager + Cashier keeps the
  // manager actions; Stock Manager + Cashier still gets neither.
  testWidgets('orders: a merged manager keeps edit and cancel', (tester) async {
    _sizeUp(tester);
    sales.orders = [_order()];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<SalesModuleViewmodel>(
          create: (_) => SalesModuleViewmodel(
            service: sales,
            customerService: _StubCustomerService(),
          ),
          child: const SalesOrdersPage(),
        ),
        roles: const ['sales', 'pos'],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    expect(_inSheet('Edit'), findsOneWidget);
    expect(_inSheet('Cancel'), findsOneWidget);
  });

  testWidgets('orders: a merged non-manager is offered neither action', (
    tester,
  ) async {
    _sizeUp(tester);
    sales.orders = [_order()];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<SalesModuleViewmodel>(
          create: (_) => SalesModuleViewmodel(
            service: sales,
            customerService: _StubCustomerService(),
          ),
          child: const SalesOrdersPage(),
        ),
        roles: const ['inventory', 'pos'],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(_inSheet('Edit'), findsNothing);
    expect(_inSheet('Cancel'), findsNothing);
  });

  testWidgets('returns: the dead "New customer return" button is gone', (
    tester,
  ) async {
    _sizeUp(tester);
    sales.transactions = [
      _row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN'),
      _row(
        id: 10,
        no: 'TRX-20261019-0002',
        source: 'RETURN',
        original: 9,
        total: -130,
        items: _returnItems,
      ),
    ];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<InventorySalesViewmodel>(
          create: (_) => InventorySalesViewmodel(service: sales),
          child: const SalesReturnsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New customer return'), findsNothing);
  });

  testWidgets(
    'returns: View opens the read-only details sheet with the return data',
    (tester) async {
      _sizeUp(tester);
      sales.transactions = [
        _row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN'),
        _row(
          id: 10,
          no: 'TRX-20261019-0002',
          source: 'RETURN',
          original: 9,
          total: -130,
          items: _returnItems,
        ),
      ];
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<InventorySalesViewmodel>(
            create: (_) => InventorySalesViewmodel(service: sales),
            child: const SalesReturnsPage(),
          ),
          inventory: await _inventory(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalesDocumentSheet), findsNothing);
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      // Reference is the sheet title.
      expect(_inSheet('TRX-20261019-0002'), findsWidgets);
      // Original sale, cashier, reason and the refund are all on the document.
      expect(_inSheet('TRX-20261019-0001'), findsOneWidget);
      expect(_inSheet('Cashy Ir'), findsOneWidget);
      expect(_inSheet('Customer return'), findsWidgets);
      expect(_inSheet('-₱130.00'), findsWidgets);
      // Every line, with its quantity — not a collapsed total.
      expect(_inSheet('2 × ₱50.00'), findsOneWidget);
      expect(_inSheet('1 × ₱30.00'), findsOneWidget);
      // Read-only: the sheet never edits a posted return.
      expect(
        find.descendant(
          of: find.byType(SalesDocumentSheet),
          matching: find.byType(TextField),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('dashboard: "This month" is replaced by a truthful label', (
    tester,
  ) async {
    _sizeUp(tester);
    sales.transactions = [
      _row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN'),
    ];
    await tester.pumpWidget(
      _app(
        ChangeNotifierProvider<InventorySalesViewmodel>(
          create: (_) => InventorySalesViewmodel(
            service: sales,
            reports: _FailingReportsRepository(),
          ),
          child: const SalesDashboardPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This month'),
      findsNothing,
      reason: 'it filtered nothing; keeping it would be a lie with a border',
    );
    // The refused summary falls back to the loaded rows and says so.
    expect(find.text('Loaded transactions'), findsWidgets);
    expect(find.text('Summary unavailable.'), findsOneWidget);

    final label = find.text('All recorded transactions');
    expect(label, findsOneWidget);
    expect(
      find.ancestor(of: label, matching: find.byType(OutlinedButton)),
      findsNothing,
      reason: 'it is a statement of scope, not a control',
    );
    expect(
      find.ancestor(of: label, matching: find.byType(InkWell)),
      findsNothing,
      reason: 'nothing to tap, nothing to tap into',
    );
  });
}
