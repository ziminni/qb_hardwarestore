// Phase 3 Task 0 (U) — dead controls on the Store Manager's sales screens.
//
// What was there (2026-10-24 report): buttons that looked live and did nothing.
//
//   Sales Quotations  "New quotation"      — no create screen, no endpoint
//   Sales Orders      "New sales order"    — same
//   Sales Returns     "New customer return"— cashiers return from the till
//                                             (Phase 3 Task 4); the manager's
//                                             unlinked-return screen is Phase 5
//   Sales Returns row "View"               — swallowed the tap
//   Sales Dashboard   "This month"         — filtered nothing
//
// The three create buttons are REMOVED (the views are read-only by decision).
// "View" opens the real read-only details sheet — the same document sheet the
// transactions page uses. "This month" becomes a label that states what the
// dashboard actually shows: every recorded transaction, with no period filter.

import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
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
import 'package:provider/provider.dart';

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
InventoryViewmodel _inventory() {
  final inventory = InventoryViewmodel(
    products: ProductsRepository(ProductsService()),
    inventory: InventoryRepository(InventoryService()),
  );
  inventory.addProduct(
    const Product(
      id: 0,
      categoryId: 1,
      categoryName: 'Hardware',
      brandId: 1,
      brandName: 'BuildPro',
      baseName: 'Cement Bag',
      description: '',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: 5,
          productId: 0,
          baseUomId: 1,
          minStockThreshold: 1,
          maxStockLevel: 100,
          sellingUoms: [
            VariantUom(
              id: 1,
              variantId: 5,
              uomId: 1,
              uomCode: 'BAG',
              uomName: 'per bag',
              barcodeQr: '',
              conversionFactor: 1,
              defaultSellingPrice: 50,
            ),
          ],
          variantName: '40kg',
          baseUomCode: 'BAG',
          isActive: true,
        ),
      ],
    ),
  );
  return inventory;
}

Widget _app(Widget child, {InventoryViewmodel? inventory}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
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

  testWidgets('orders: the dead "New sales order" button is gone', (
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New sales order'), findsNothing);
    expect(find.text('SO-20261019-0001'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
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
          inventory: _inventory(),
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
      expect(_inSheet('₱-130.00'), findsWidgets);
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
          create: (_) => InventorySalesViewmodel(service: sales),
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
