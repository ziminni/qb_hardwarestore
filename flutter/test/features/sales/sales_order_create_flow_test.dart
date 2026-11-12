// Phase 5 F3 follow-up: the sales orders page can CREATE an order.
//
// The owner authorised create-only entry, so this file pins both halves of that
// decision:
//   * "New sales order" exists, opens the form, and a created order refreshes the
//     list through the SAME `load()` the page already used (no second, divergent
//     reader);
//   * a refusal from the server leaves the form open with the sentence shown and
//     the list untouched — nothing is added to a list the server did not write.
//
// Quotations stay read-only: no create action is added there.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/widgets/sales_order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<SalesOrderRow> orders = const [];
  final List<SalesOrderDraft> created = [];

  /// Set to a sentence to make the server refuse the create.
  String? refusal;

  /// What a successful create adds to the list the server would answer with.
  SalesOrderRow? createdRow;

  int orderReads = 0;

  @override
  Future<List<QuotationRecord>> fetchQuotations() async => const [];

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async {
    orderReads++;
    return orders;
  }

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      const [];

  @override
  Future<SalesOrderRow> createSalesOrder(SalesOrderDraft draft) async {
    created.add(draft);
    final failure = refusal;
    if (failure != null) throw SalesServiceException(failure);
    final row = createdRow!;
    orders = [...orders, row];
    return row;
  }
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService() : super();

  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'REGULAR'),
  ];
}

SalesOrderRow _order({int id = 7, String number = 'SO-20261019-0001'}) =>
    SalesOrderRow(
      id: id,
      number: number,
      customerId: 3,
      quotationId: null,
      status: 'CONFIRMED',
      createdAt: '2026-11-12T08:00:00Z',
      items: const [OrderLineItem(variantUomId: 1, qty: 2, unitPrice: 250)],
    );

void main() {
  late _StubSalesService sales;

  setUp(() => sales = _StubSalesService());

  Future<InventoryViewmodel> inventory() async {
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

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: await inventory(),
          ),
          ChangeNotifierProvider<SalesModuleViewmodel>(
            create: (_) => SalesModuleViewmodel(
              service: sales,
              customerService: _StubCustomerService(),
            ),
          ),
        ],
        child: const MaterialApp(home: SalesOrdersPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('so-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('so-qty-0')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('so-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('the page offers "New sales order" and opens the form', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('New sales order'), findsOneWidget);
    await tester.tap(find.text('New sales order'));
    await tester.pumpAndSettle();

    expect(find.byType(SalesOrderFormDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('so-customer')), findsOneWidget);
  });

  testWidgets('a created order closes the form and refreshes the list', (
    tester,
  ) async {
    sales.createdRow = _order(id: 12, number: 'SO-20261112-0001');
    await pumpPage(tester);
    expect(find.text('SO-20261019-0001'), findsNothing);
    final readsBefore = sales.orderReads;

    await tester.tap(find.text('New sales order'));
    await tester.pumpAndSettle();
    await fillAndSubmit(tester);

    expect(find.byType(SalesOrderFormDialog), findsNothing);
    expect(sales.created, hasLength(1));
    // The same load() the page uses ran again, and the new row is on screen.
    expect(sales.orderReads, greaterThan(readsBefore));
    expect(find.text('SO-20261112-0001'), findsOneWidget);
    expect(find.text('Sales order created.'), findsOneWidget);
    // Create-only: the row still opens the read-only sheet and nothing else.
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('a refusal keeps the form open and adds nothing to the list', (
    tester,
  ) async {
    sales.refusal =
        'Cement 40kg, BAG: a whole unit takes a whole number of units.';
    await pumpPage(tester);
    final readsBefore = sales.orderReads;

    await tester.tap(find.text('New sales order'));
    await tester.pumpAndSettle();
    await fillAndSubmit(tester);

    expect(find.byType(SalesOrderFormDialog), findsOneWidget);
    expect(find.text(sales.refusal!), findsOneWidget);
    expect(
      find.text('SO-20261019-0001'),
      findsNothing,
      reason: 'the server refused, so no order exists to list',
    );
    expect(
      sales.orderReads,
      readsBefore,
      reason: 'a refused create reloads nothing: there is nothing new to read',
    );
  });
}
