// Phase 4 Task F4 (decision 18): the Discounts figure is BACK in reports.
//
// D12 removed it because checkout hard-zeroed every discount, so the tile could only
// ever read ₱0.00. The till takes a capped discount again (B1 server, F4 screen), so
// the tile and the per-day column are a real number and must be visible again.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubReportsRepository extends ReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    return const SalesSummary(
      from: '2026-11-01',
      to: '2026-11-11',
      totalTransactions: 2,
      totalGross: 2000,
      totalVat: 180.00,
      totalDiscounts: 250,
      days: [
        SalesDay(
          day: '2026-11-11',
          transactions: 2,
          gross: 2000,
          vat: 180.00,
          discounts: 250,
        ),
      ],
    );
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async =>
      const InventoryValuation(
        batchCount: 0,
        totalUnits: 0,
        totalCost: 0,
        totalRetail: 0,
        categories: [],
      );

  @override
  Future<StockMovements> fetchStockMovements({
    String? from,
    String? to,
  }) async => const StockMovements(
    from: '',
    to: '',
    totalIn: 0,
    totalOut: 0,
    receiptsByDay: [],
    adjustmentsByType: [],
  );

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async =>
      const RequisitionHistory(
        from: '',
        to: '',
        statusFilter: null,
        countByStatus: {},
        requisitions: [],
      );
}

void main() {
  testWidgets('the sales report shows a Discounts tile with the real figure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          home: ReportsPage(
            viewmodel: AdminReportsViewmodel(
              repository: _StubReportsRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Discounts'), findsWidgets);
    // ₱250 for the period, and the same figure in the Total row of the table.
    expect(find.text('₱250.00'), findsWidgets);
    expect(find.text('₱0.00'), findsNothing);
  });
}
