// Phase 1d Task 11 (decision 17): every real list screen names itself and says
// how many rows it is showing. The count is the rows ON SCREEN, after the
// filters and after the page's own slicing, never the server's total: a total
// beside a filtered table would outlive the filter and lie about it.

import 'package:client/data/models/audit_log.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/user.dart';
import 'package:client/features/admin/widgets/admin_audit_log_table.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_table.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:client/features/suppliers/widgets/purchases_table.dart';
import 'package:client/features/suppliers/widgets/suppliers_table.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/inventory_returns_fixtures.dart';
import '../support/phase4_fakes.dart';
import '../support/transactions_fixtures.dart';

void main() {
  const pill = ValueKey('DataPanel.count');

  /// The pill's number as the reader sees it.
  String pillText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(pill), matching: find.byType(Text)),
      )
      .data!;

  Future<void> pumpIn(
    WidgetTester tester,
    Widget child, {
    bool bounded = false,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: bounded ? child : SingleChildScrollView(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Supplier supplier(int id, String name) => Supplier(
    id: id,
    companyName: name,
    contactPerson: 'Ana Cruz',
    phone: '0917 000 0000',
    email: 'ana@example.ph',
    address: 'Cagayan de Oro',
  );

  PurchaseOrder order(int id, String supplierName) => PurchaseOrder(
    id: id,
    supplierId: id,
    supplierName: supplierName,
    orderDate: DateTime(2026, 10, 29),
    expectedDelivery: null,
    status: PurchaseStatus.ordered,
    createdBy: 'stocker',
    notes: '',
    items: const [],
  );

  User user(int id, String name) => User(
    id: id,
    username: name.toLowerCase(),
    email: '$name@qb.ph'.toLowerCase(),
    fullName: name,
    role: const Role(id: 2, name: 'admin', displayName: 'Admin'),
  );

  AuditLog log(int id) => AuditLog(
    id: id,
    userEmail: 'stocker@qb.ph',
    actionType: 'STOCK_ADJUST',
    description: 'Adjusted 5 bags',
    ipAddress: null,
    timestamp: DateTime(2026, 10, 29, 9),
  );

  /// The shared viewmodel turns the wire rows into the list's own model.
  Future<List<InventorySale>> saleRows() async {
    final viewmodel = InventorySalesViewmodel(
      service: StubSalesService(rows: transactionsFixture()),
    );
    await viewmodel.load();
    return viewmodel.sales;
  }

  testWidgets('a filtered transaction list counts what is shown', (
    tester,
  ) async {
    await pumpIn(
      tester,
      SalesTransactionsContent(
        role: SalesTransactionsRole.storeManager,
        sales: await saleRows(),
      ),
      bounded: true,
    );

    expect(find.text('Transactions'), findsOneWidget);
    expect(pillText(tester), '4');

    await tester.enterText(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.byType(TextField),
      ),
      'Northern',
    );
    await tester.pumpAndSettle();

    expect(
      pillText(tester),
      '1',
      reason: 'the pill follows the filter, not the four rows loaded',
    );
  });

  testWidgets('the suppliers list names itself and counts its rows', (
    tester,
  ) async {
    await pumpIn(
      tester,
      SuppliersTable(
        suppliers: [supplier(1, 'Holcim'), supplier(2, 'Neltex')],
        openOrderCount: (_) => 0,
        onEdit: (_) {},
        onToggle: (_) {},
        onNewOrder: (_) {},
        emptyMessage: 'No suppliers yet.',
      ),
    );

    expect(find.text('Suppliers'), findsOneWidget);
    expect(pillText(tester), '2');
  });

  testWidgets('the purchase-order list names itself and counts its rows', (
    tester,
  ) async {
    await pumpIn(
      tester,
      PurchasesTable(
        orders: [order(1, 'Holcim'), order(2, 'Neltex')],
        onView: (_) {},
        onPlace: (_) {},
        onCancel: (_) {},
        onReceive: (_) {},
        emptyMessage: 'No purchase orders yet.',
      ),
    );

    expect(find.text('Purchase orders'), findsOneWidget);
    expect(pillText(tester), '2');
  });

  testWidgets('the staff list names itself and counts its rows', (
    tester,
  ) async {
    await pumpIn(
      tester,
      AdminUserTable(
        users: [user(1, 'Ana'), user(2, 'Ben')],
        emptyMessage: 'No staff accounts yet.',
        onToggleActive: (_) {},
        onChangeRole: (_) {},
        isAdminViewer: true,
      ),
    );

    expect(find.text('Staff accounts'), findsOneWidget);
    expect(pillText(tester), '2');
  });

  testWidgets('the audit list counts the page it is showing', (tester) async {
    await pumpIn(
      tester,
      AdminAuditLogTable(
        logs: [log(1), log(2), log(3)],
        emptyMessage: 'No audit logs recorded.',
      ),
    );

    expect(find.text('Audit logs'), findsOneWidget);
    expect(pillText(tester), '3');
  });

  testWidgets('the returns list names itself and counts its rows', (
    tester,
  ) async {
    await pumpIn(
      tester,
      transactionsApp(
        child: const InventoryReturnsPage(),
        viewmodel: InventorySalesViewmodel(
          service: StubSalesService(rows: inventoryReturnsFixture()),
        ),
      ),
      bounded: true,
    );

    expect(
      find.descendant(
        of: find.byType(DataPanel<InventoryReturn>),
        matching: find.text('Returns'),
      ),
      findsOneWidget,
    );
    expect(pillText(tester), '4');
  });

  testWidgets('the stock list names itself and counts its records', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = seededInventory();
    await store.load();

    await pumpIn(
      tester,
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: const InventoryStockPage(),
      ),
      bounded: true,
    );

    expect(
      find.descendant(
        of: find.byType(DataPanel<InventoryStockRow>),
        matching: find.text('Stock'),
      ),
      findsOneWidget,
    );
    expect(pillText(tester), '2');
  });
}
