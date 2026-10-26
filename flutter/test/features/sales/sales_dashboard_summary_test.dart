// Phase 5 Task 3: dashboard tiles read the server summary, never the client
// fold. With ZERO loaded transactions and a summary of 9000/40, the tiles
// must still show 9000 and 40 — a fold would show 0.

import 'package:client/data/models/reports.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      const [];
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

void main() {
  testWidgets('tiles show server totals even with no loaded rows', (
    tester,
  ) async {
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
          ChangeNotifierProvider<InventorySalesViewmodel>(
            create: (_) => InventorySalesViewmodel(
              service: _StubSalesService(),
              reports: _StubReportsRepository(),
            ),
          ),
        ],
        child: const MaterialApp(home: SalesDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('₱9000.00'), findsOneWidget);
    expect(find.text('40'), findsWidgets);
    expect(find.textContaining('Last 30 days · server'), findsWidgets);
    // The fold of zero rows would read 0 — that number must not appear.
    expect(find.text('₱0.00'), findsNothing);
  });
}
