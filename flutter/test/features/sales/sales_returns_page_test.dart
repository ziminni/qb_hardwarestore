import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(
  Widget child,
  InventorySalesViewmodel viewmodel, {
  String? roleCode,
  String? roleLabel,
}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (roleCode != null) {
    auth.user = User(
      id: 1,
      username: 'u',
      email: 'u@demo.ph',
      fullName: 'U',
      role: Role(id: 1, name: roleCode, displayName: roleLabel ?? roleCode),
    );
  }
  return ChangeNotifierProvider<AuthViewmodel>.value(
    value: auth,
    child: ChangeNotifierProvider<InventorySalesViewmodel>.value(
      value: viewmodel,
      child: MaterialApp(home: child),
    ),
  );
}

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<TransactionRecord> rows = const [];

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async => rows;

  @override
  Future<List<QuotationRecord>> fetchQuotations() =>
      throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() => throw UnimplementedError();
}

TransactionRecord _row({
  required int id,
  required String no,
  required String source,
  int? original,
  double total = 100,
}) => TransactionRecord(
  id: id, transactionNo: no, transDate: DateTime(2026, 10, 19, 8),
  customerId: 3, customerName: 'Dela Cruz Construction', cashierName: 'Cashy Ir',
  source: source, originalTransactionId: original, status: 'COMPLETED',
  grandTotal: total,
  items: const [TransactionLineItem(variantUomId: 1, variantUomCode: 'BAG', qty: 2, unitPrice: 50, subtotal: 100)],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 100)],
);

void main() {
  testWidgets('returns page lists RETURN rows with the reversed receipt', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()
      ..rows = [
        _row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN'),
        _row(id: 10, no: 'TRX-20261019-0002', source: 'RETURN', original: 9, total: -50),
      ];
    await tester.pumpWidget(
      _app(const SalesReturnsPage(), InventorySalesViewmodel(service: service)..load()),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261019-0002'), findsOneWidget);
    // The original sale's number appears exactly once — as the linked receipt,
    // not as its own row.
    expect(find.text('TRX-20261019-0001'), findsOneWidget);
    expect(find.text('No customer returns available.'), findsNothing);
  });

  testWidgets('an empty returns list states it plainly', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()..rows = [_row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN')];
    await tester.pumpWidget(
      _app(const SalesReturnsPage(), InventorySalesViewmodel(service: service)..load()),
    );
    await tester.pumpAndSettle();

    expect(find.text('No customer returns available.'), findsOneWidget);
  });

  // Phase 5 Task 3: the unlinked correction lives on this page for the Store
  // Manager (and Admin) only — a cashier's POST would 403 server-side, so the
  // button is not offered. Compared by role CODE, never label.
  testWidgets('a store manager is offered the unlinked return', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()..rows = const [];
    await tester.pumpWidget(
      _app(
        const SalesReturnsPage(),
        InventorySalesViewmodel(service: service)..load(),
        roleCode: 'sales',
        roleLabel: 'Store Manager',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlinked return'), findsOneWidget);
  });

  testWidgets('a cashier is not offered the unlinked return', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()..rows = const [];
    await tester.pumpWidget(
      _app(
        const SalesReturnsPage(),
        InventorySalesViewmodel(service: service)..load(),
        roleCode: 'pos',
        roleLabel: 'Cashier',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unlinked return'), findsNothing);
  });
}
