// Decision D-02 (sales-manager-workflow): View on quotations, orders and
// transactions was `TextButton(onPressed: () {}, child: Text('View'))` — a
// button that pressed nothing, three times over. Every test below taps the
// real button and demands a real document.
//
// The three pages read different viewmodels (quotations/orders: the module
// viewmodel; transactions: the inventory sales viewmodel), so each is pumped
// with stubs of its own service. Nothing here touches a server.
//
// The read-only invariant is pinned too: no TextField inside the sheet, because
// D-02 rejected write scope explicitly and an accidental form field would be
// the first step back into it.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';
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

/// A catalogue entry the quotation/order lines can be resolved against. The
/// wire only carries `variant_uom` as an id; the name has to come from the
/// app-scoped inventory viewmodel (decision D-02).
///
/// Phase 4 Task 4: the store no longer carries an in-memory `addProduct`, so the
/// fixture arrives through the repository and `load()` — the same path production
/// uses.
Future<InventoryViewmodel> _inventory() async {
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Circuit Breaker',
          categoryName: 'Electrical',
          brandName: 'BuildPro',
          variants: [
            variant(
              id: 5,
              productId: 1,
              name: '20A 1-pole',
              threshold: 1,
              maxStockLevel: 100,
              sellingUoms: [variantUom(id: 42, variantId: 5, price: 250)],
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

QuotationRecord _quotation({
  int id = 1,
  String number = 'QT-20261019-0001',
  String status = 'SENT',
  String validUntil = '2026-11-19',
  List<QuotationLineItem> items = const [],
}) => QuotationRecord(
  id: id,
  number: number,
  customerId: 3,
  status: status,
  validUntil: validUntil,
  createdAt: '2026-10-19T08:00:00Z',
  items: items,
);

SalesOrderRow _order({
  int id = 7,
  String number = 'SO-20261019-0001',
  String status = 'CONFIRMED',
  List<OrderLineItem> items = const [],
}) => SalesOrderRow(
  id: id,
  number: number,
  customerId: 3,
  quotationId: 1,
  status: status,
  createdAt: '2026-10-19T08:00:00Z',
  items: items,
);

TransactionRecord _transaction() => TransactionRecord(
  id: 11,
  transactionNo: 'TRX-20261019-0001',
  transDate: DateTime(2026, 10, 19),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Ana Reyes',
  source: 'WALK_IN',
  originalTransactionId: null,
  status: 'COMPLETED',
  grandTotal: 500,
  items: const [
    TransactionLineItem(
      variantUomId: 42,
      variantUomCode: 'PC',
      qty: 2,
      unitPrice: 250,
      subtotal: 500,
    ),
  ],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 500)],
);

Widget _app(Widget child, {InventoryViewmodel? inventory}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
      ),
      if (inventory != null)
        ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
    ],
    child: MaterialApp(home: child),
  );
}

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Taps the one View button on the table and settles the sheet.
Future<void> _tapView(WidgetTester tester) async {
  final view = find.text('View');
  expect(
    view,
    findsOneWidget,
    reason: 'the row must carry exactly one View action',
  );
  await tester.ensureVisible(view);
  await tester.tap(view);
  await tester.pumpAndSettle();
}

Finder _inSheet(String text) => find.descendant(
  of: find.byType(SalesDocumentSheet),
  matching: find.textContaining(text),
);

void main() {
  late _StubSalesService sales;

  setUp(() => sales = _StubSalesService());

  group('quotations', () {
    Future<void> pump(
      WidgetTester tester, {
      InventoryViewmodel? inventory,
      List<QuotationRecord>? quotations,
      DateTime Function()? now,
      List<QuotationLineItem> items = const [
        QuotationLineItem(variantUomId: 42, qty: 2, unitPrice: 250),
      ],
    }) async {
      _sizeUp(tester);
      sales.quotations = quotations ?? [_quotation(items: items)];
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<SalesModuleViewmodel>(
            create: (_) => SalesModuleViewmodel(
              service: sales,
              customerService: _StubCustomerService(),
            ),
            child: SalesQuotationsPage(now: now ?? DateTime.now),
          ),
          inventory: inventory,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('View opens the quotation with its lines and total', (
      tester,
    ) async {
      await pump(tester, inventory: await _inventory());

      expect(find.byType(SalesDocumentSheet), findsNothing);
      await _tapView(tester);

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(_inSheet('QT-20261019-0001'), findsOneWidget);
      expect(_inSheet('Dela Cruz Construction'), findsOneWidget);
      expect(
        _inSheet('Sent'),
        findsWidgets,
        reason: 'the status reads as the badge does, not as the wire constant',
      );
      expect(
        _inSheet('Circuit Breaker 20A 1-pole'),
        findsOneWidget,
        reason: 'the line name is resolved from the catalogue, not the id',
      );
      expect(_inSheet('₱500.00'), findsWidgets);
    });

    testWidgets('the sheet is strictly read-only', (tester) async {
      await pump(tester, inventory: await _inventory());
      await _tapView(tester);

      expect(
        find.descendant(
          of: find.byType(SalesDocumentSheet),
          matching: find.byType(TextField),
        ),
        findsNothing,
        reason: 'D-02 rejected write scope; a field is the first step back in',
      );
      expect(
        find.descendant(
          of: find.byType(SalesDocumentSheet),
          matching: find.byType(TextButton),
        ),
        findsNothing,
        reason: 'no submit, no save — there is nothing to write',
      );
    });

    testWidgets('a line with no catalogue entry shows its id, never crashes', (
      tester,
    ) async {
      await pump(tester);

      await _tapView(tester);

      expect(
        _inSheet('Variant unit #42'),
        findsOneWidget,
        reason:
            'a manager who opened the sheet before the catalogue loaded '
            'must still see what was ordered',
      );
    });

    testWidgets('a quotation with no items says so', (tester) async {
      await pump(tester, inventory: await _inventory(), items: const []);
      await _tapView(tester);

      expect(_inSheet('No items'), findsOneWidget);
    });

    testWidgets('a quotation past its valid date reads Expired, not Sent', (
      tester,
    ) async {
      await pump(
        tester,
        quotations: [_quotation(validUntil: '2020-12-31', status: 'SENT')],
      );

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Expired'),
        ),
        findsOneWidget,
        reason: 'a quote nobody can order from must not look like a live one',
      );
      expect(
        // Scoped to the badge: the FilterBar has a "Sent" chip of its own.
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Sent'),
        ),
        findsNothing,
      );
    });

    testWidgets('a quotation inside its valid date keeps its status', (
      tester,
    ) async {
      await pump(
        tester,
        quotations: [_quotation(validUntil: '2060-01-01', status: 'SENT')],
      );

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Sent'),
        ),
        findsOneWidget,
      );
      expect(
        // Scoped to the badge: the FilterBar has an "Expired" chip of its own.
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Expired'),
        ),
        findsNothing,
      );
      expect(
        find.text('Jan 1, 2060'),
        findsOneWidget,
        reason: 'the reader checks the date the expiry rule judged',
      );
    });

    testWidgets('an expired quotation says Expired on its document too', (
      tester,
    ) async {
      await pump(
        tester,
        quotations: [_quotation(validUntil: '2020-12-31', status: 'SENT')],
      );
      await _tapView(tester);

      expect(_inSheet('Expired'), findsWidgets);
    });

    testWidgets('the expiry rule reads the clock the page is given', (
      tester,
    ) async {
      // Well inside its valid date by the wall clock, past it by the given one:
      // only an injected clock can make this read Expired.
      await pump(
        tester,
        quotations: [_quotation(validUntil: '2060-01-01', status: 'SENT')],
        now: () => DateTime(2061, 1, 1),
      );

      expect(
        find.descendant(
          of: find.byType(StatusBadge),
          matching: find.text('Expired'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the list can be searched by number', (tester) async {
      await pump(
        tester,
        quotations: [
          _quotation(),
          _quotation(id: 2, number: 'QT-20261020-0002'),
        ],
      );

      expect(
        find.byType(FilterBar),
        findsOneWidget,
        reason: 'a list of quotations the reader cannot narrow is the defect',
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.byType(TextField),
        ),
        'QT-20261020',
      );
      await tester.pumpAndSettle();

      expect(find.text('QT-20261020-0002'), findsOneWidget);
      expect(find.text('QT-20261019-0001'), findsNothing);
    });

    testWidgets('a search that matches nothing says so, and says which', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.byType(TextField),
        ),
        'nothing is called this',
      );
      await tester.pumpAndSettle();

      expect(find.text('No quotations match these filters.'), findsOneWidget);
      expect(
        find.text('No quotations available.'),
        findsNothing,
        reason: 'the system has quotations; the search hid them',
      );
    });

    testWidgets('the row itself opens the document, like its View action', (
      tester,
    ) async {
      await pump(tester, inventory: await _inventory());

      await tester.tap(find.text('QT-20261019-0001'));
      await tester.pumpAndSettle();

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(_inSheet('Dela Cruz Construction'), findsOneWidget);
    });
  });

  group('sales orders', () {
    testWidgets('View opens the order with its lines and total', (
      tester,
    ) async {
      _sizeUp(tester);
      sales.orders = [
        _order(
          items: const [
            OrderLineItem(variantUomId: 42, qty: 4, unitPrice: 250),
          ],
        ),
      ];
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<SalesModuleViewmodel>(
            create: (_) => SalesModuleViewmodel(
              service: sales,
              customerService: _StubCustomerService(),
            ),
            child: const SalesOrdersPage(),
          ),
          inventory: await _inventory(),
        ),
      );
      await tester.pumpAndSettle();

      await _tapView(tester);

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(_inSheet('SO-20261019-0001'), findsOneWidget);
      expect(_inSheet('Circuit Breaker 20A 1-pole'), findsOneWidget);
      expect(_inSheet('₱1,000.00'), findsWidgets);
    });

    testWidgets('the list can be filtered by status chip', (tester) async {
      _sizeUp(tester);
      sales.orders = [
        _order(),
        _order(id: 8, number: 'SO-20261020-0002', status: 'COMPLETED'),
      ];
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

      // Scoped to the bar: a row badge carries the same word as its chip.
      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Completed'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SO-20261020-0002'), findsOneWidget);
      expect(find.text('SO-20261019-0001'), findsNothing);
      expect(
        find.text('View'),
        findsOneWidget,
        reason: 'the surviving order still opens its document',
      );
    });

    testWidgets('an empty result says which kind of empty it is', (
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

      // Phase 7 F1: 'Ready' is gone from the chips (the server reads a legacy
      // READY order as Confirmed), so an empty result is asked for with a chip
      // that exists: nothing on this list is cancelled.
      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Cancelled'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No sales orders match these filters.'), findsOneWidget);
      expect(find.text('No sales orders available.'), findsNothing);
    });
  });

  group('transactions', () {
    Future<void> pump(WidgetTester tester) async {
      _sizeUp(tester);
      sales.transactions = [_transaction()];
      await tester.pumpWidget(
        _app(
          ChangeNotifierProvider<InventorySalesViewmodel>(
            create: (_) => InventorySalesViewmodel(service: sales),
            child: const SalesTransactionsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('View opens the transaction with its lines and payment', (
      tester,
    ) async {
      await pump(tester);

      await _tapView(tester);

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(_inSheet('TRX-20261019-0001'), findsOneWidget);
      expect(_inSheet('Dela Cruz Construction'), findsOneWidget);
      expect(_inSheet('2 × ₱250.00'), findsOneWidget);
      expect(
        // The sheet shows the LABEL; the wire code is what the row carries (C1).
        // ('Cashier' also contains 'Cash', so the line is matched in full.)
        _inSheet('Payment (Cash)'),
        findsOneWidget,
        reason: 'how it was paid is part of the document',
      );
    });
  });
}
