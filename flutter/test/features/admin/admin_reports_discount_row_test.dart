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
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:client/features/sales/views/sales_reports_page.dart';

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
          home: SalesReportsPage(
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
    expect(find.text('Payment fees'), findsNothing);
  });

  testWidgets('the sales report shows Payment fees tile and column when fees exist', (
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
          home: SalesReportsPage(
            viewmodel: AdminReportsViewmodel(
              repository: _FeeStubReportsRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment fees'), findsNWidgets(2));
    expect(find.text('₱35.00'), findsWidgets);
  });

  testWidgets('the sales report shows Operational Profit Breakdown and visual charts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          home: SalesReportsPage(
            viewmodel: AdminReportsViewmodel(
              repository: _ProfitStubReportsRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('profit-breakdown-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-daily-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('sales-category-chart')), findsOneWidget);
    expect(find.text('Operational Profit Breakdown'), findsOneWidget);
    expect(find.text('Margin 20.0%'), findsOneWidget);
    expect(find.text('Markup 25.0%'), findsOneWidget);
    expect(find.text('₱90.00'), findsWidgets);
  });
}

class _ProfitStubReportsRepository extends _StubReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    return const SalesSummary(
      from: '2026-11-01',
      to: '2026-11-21',
      totalTransactions: 2,
      totalGross: 619,
      totalVatableSales: 539.29,
      totalVat: 64.71,
      totalDiscounts: 56,
      totalPaymentFees: 15,
      totalDeliveryFees: 100,
      merchandiseGross: 560,
      merchandiseNetExVat: 450,
      totalCogs: 360,
      grossProfit: 90,
      grossMarginPercent: 20,
      effectiveMarkupPercent: 25,
      costCoverage: CostCoverage(
        costedDeductions: 2,
        missingCostDeductions: 0,
        complete: true,
      ),
      days: [
        SalesDay(
          day: '2026-11-21',
          transactions: 2,
          gross: 619,
          vat: 64.71,
          discounts: 56,
          paymentFees: 15,
          deliveryFees: 100,
          merchandiseNetExVat: 450,
          cogs: 360,
          grossProfit: 90,
        ),
      ],
      categories: [
        SalesCategoryBreakdown(
          categoryId: 1,
          categoryName: 'Cement',
          grossMerchandise: 560,
          discounts: 56,
          netMerchandise: 504,
          cogs: 360,
        ),
      ],
    );
  }
}

class _FeeStubReportsRepository extends _StubReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    return const SalesSummary(
      from: '2026-11-01',
      to: '2026-11-11',
      totalTransactions: 2,
      totalGross: 2035,
      totalVat: 180.00,
      totalDiscounts: 250,
      totalPaymentFees: 35.00,
      days: [
        SalesDay(
          day: '2026-11-11',
          transactions: 2,
          gross: 2035,
          vat: 180.00,
          discounts: 250,
          paymentFees: 35.00,
        ),
      ],
    );
  }
}
