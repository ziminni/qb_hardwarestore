// Quotation -> sales order: the two writes the quotations screen was missing.
//
// Until this card the quotations screen was strictly read-only ("New quotation"
// had been removed as a dead control: no screen, no endpoint). The endpoints now
// exist, so this file pins the flow that closes the loop:
//   * "New quotation" opens a create form, POSTs the customer and its lines, and
//     reports the number the server generated;
//   * a quotation's sheet offers "Create sales order" to a manager, asks for a
//     confirmation that says the prices are the agreed ones and the cashier rings
//     it from Orders, and POSTs an order LINKED to the quotation.
//
// The status is never written from here: no accept endpoint exists, so a
// quotation stays DRAFT until it is ordered.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<QuotationRecord> quotations = const [];
  List<SalesOrderRow> orders = const [];

  final List<SalesOrderDraft> orderDrafts = [];
  final List<QuotationDraft> quotationDrafts = [];
  int quotationReads = 0;

  /// Set to a sentence to make the server refuse the write.
  String? quotationRefusal;
  String? orderRefusal;

  @override
  Future<List<QuotationRecord>> fetchQuotations() async {
    quotationReads++;
    return quotations;
  }

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async => orders;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      const [];

  @override
  Future<QuotationRecord> createQuotation(QuotationDraft draft) async {
    quotationDrafts.add(draft);
    final failure = quotationRefusal;
    if (failure != null) throw SalesServiceException(failure);
    final row = QuotationRecord(
      id: 9,
      number: 'QT-20261015-0009',
      customerId: draft.customerId,
      status: 'DRAFT',
      validUntil: null,
      createdAt: '2026-10-15T10:00:00Z',
      items: const [QuotationLineItem(variantUomId: 1, qty: 2, unitPrice: 250)],
    );
    quotations = [...quotations, row];
    return row;
  }

  @override
  Future<SalesOrderRow> createSalesOrder(SalesOrderDraft draft) async {
    orderDrafts.add(draft);
    final failure = orderRefusal;
    if (failure != null) throw SalesServiceException(failure);
    final row = SalesOrderRow(
      id: 11,
      number: 'SO-20261015-0011',
      customerId: draft.customerId,
      quotationId: draft.quotationId,
      status: 'CONFIRMED',
      createdAt: '2026-10-15T10:00:00Z',
      items: const [OrderLineItem(variantUomId: 1, qty: 2, unitPrice: 250)],
    );
    orders = [...orders, row];
    return row;
  }
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

const _quotation = QuotationRecord(
  id: 1,
  number: 'QT-20261019-0001',
  customerId: 3,
  status: 'DRAFT',
  validUntil: '2026-11-19',
  createdAt: '2026-10-19T08:00:00Z',
  items: [QuotationLineItem(variantUomId: 1, qty: 2, unitPrice: 250)],
);

/// The role CODE the server sends as `role.name`; the label is what a person
/// reads. A merged-style account is not built here — one held area is enough.
const _roleCodes = {'Store Manager': 'sales', 'Cashier': 'pos'};

AuthViewmodel _auth({String? role}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (role != null) {
    final code = _roleCodes[role]!;
    auth.user = User(
      id: 1,
      username: 'user',
      email: 'user@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 4, name: code, displayName: role),
    );
    auth.selectArea(code);
  }
  return auth;
}

Future<InventoryViewmodel> _inventory() async {
  final model = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Portland Cement',
          variants: [
            variant(
              id: 5,
              productId: 1,
              name: '40kg',
              baseUomCode: 'BAG',
              sellingUoms: [
                variantUom(
                  id: 1,
                  variantId: 5,
                  price: 250,
                  uomCode: 'BAG',
                  uomName: 'Bag',
                  isWhole: true,
                ),
              ],
            ),
          ],
        ),
      ],
      batches: [batch(id: 1, variantId: 5, qty: 100)],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await model.load();
  return model;
}

void main() {
  late _StubSalesService sales;

  setUp(() {
    sales = _StubSalesService();
    sales.quotations = [_quotation];
  });

  Future<void> pumpPage(WidgetTester tester, {String? role}) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: _auth(role: role)),
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: await _inventory(),
          ),
          ChangeNotifierProvider<SalesModuleViewmodel>(
            create: (_) => SalesModuleViewmodel(
              service: sales,
              customerService: _StubCustomerService(),
            ),
          ),
        ],
        child: const MaterialApp(home: SalesQuotationsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openQuotationSheet(WidgetTester tester) async {
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
  }

  testWidgets('the page offers "New quotation" and opens the create form', (
    tester,
  ) async {
    await pumpPage(tester, role: 'Cashier');

    expect(find.text('New quotation'), findsOneWidget);
    await tester.tap(find.text('New quotation'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sq-customer')), findsOneWidget);
    expect(find.byKey(const ValueKey('sq-submit')), findsOneWidget);
  });

  testWidgets('creating a quotation posts the customer and its lines', (
    tester,
  ) async {
    await pumpPage(tester, role: 'Cashier');
    final readsBefore = sales.quotationReads;

    await tester.tap(find.text('New quotation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('sq-qty-0')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-submit')));
    await tester.pumpAndSettle();

    expect(sales.quotationDrafts, hasLength(1));
    // The payload the server is asked to write: a named customer, a selling unit
    // at the price the catalogue defaults to, and a validity date a month out
    // (the test clock is pinned to 15 October 2026).
    expect(sales.quotationDrafts.single.toJson(), {
      'customer': 3,
      'items': [
        {'variant_uom': 1, 'qty': 2.0, 'unit_price': '250.00'},
      ],
      'valid_until': '2026-11-14',
    });
    // The same load() the page already used re-read the list, and the number the
    // server generated is what the clerk is told.
    expect(sales.quotationReads, greaterThan(readsBefore));
    // The number the server generated is on the new row AND in the toast.
    expect(find.textContaining('QT-20261015-0009'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining('QT-20261015-0009'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sq-customer')), findsNothing);
  });

  testWidgets('a refused quotation keeps the form open and adds no row', (
    tester,
  ) async {
    sales.quotationRefusal =
        'Portland Cement 40kg, BAG: that unit is no longer sold.';
    await pumpPage(tester, role: 'Cashier');
    final readsBefore = sales.quotationReads;

    await tester.tap(find.text('New quotation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sq-submit')), findsOneWidget);
    expect(find.text(sales.quotationRefusal!), findsOneWidget);
    expect(
      sales.quotationReads,
      readsBefore,
      reason: 'a refused create reloads nothing: there is nothing new to read',
    );
  });

  testWidgets('a manager gets "Create sales order" on a quotation sheet', (
    tester,
  ) async {
    await pumpPage(tester, role: 'Store Manager');
    await openQuotationSheet(tester);

    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    expect(find.text('Create sales order'), findsOneWidget);

    await tester.tap(find.text('Create sales order'));
    await tester.pumpAndSettle();

    // The confirmation has to say what the order will cost and who rings it.
    expect(find.textContaining('Prices are the agreed prices'), findsOneWidget);
    expect(find.textContaining('cashier rings it from Orders'), findsOneWidget);
  });

  testWidgets('confirming posts one order and reports its number', (
    tester,
  ) async {
    await pumpPage(tester, role: 'Store Manager');
    await openQuotationSheet(tester);

    await tester.tap(find.text('Create sales order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-confirm-order')));
    await tester.pumpAndSettle();

    expect(sales.orderDrafts, hasLength(1));
    // The order is LINKED to the quotation and carries its customer and lines at
    // the agreed prices — nothing is re-typed or re-priced.
    expect(sales.orderDrafts.single.toJson(), {
      'customer': 3,
      'quotation': 1,
      'items': [
        {'variant_uom': 1, 'qty': 2.0, 'unit_price': '250.00'},
      ],
    });
    expect(find.textContaining('SO-20261015-0011'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation posts nothing', (tester) async {
    await pumpPage(tester, role: 'Store Manager');
    await openQuotationSheet(tester);

    await tester.tap(find.text('Create sales order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(sales.orderDrafts, isEmpty);
  });

  testWidgets('a refused conversion says why and adds no order', (
    tester,
  ) async {
    sales.orderRefusal = 'Portland Cement 40kg, BAG: no longer sold.';
    await pumpPage(tester, role: 'Store Manager');
    await openQuotationSheet(tester);

    await tester.tap(find.text('Create sales order'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sq-confirm-order')));
    await tester.pumpAndSettle();

    expect(find.textContaining('no longer sold'), findsOneWidget);
  });

  testWidgets('a cashier is offered no order conversion', (tester) async {
    await pumpPage(tester, role: 'Cashier');
    await openQuotationSheet(tester);

    expect(find.text('Create sales order'), findsNothing);
  });
}
