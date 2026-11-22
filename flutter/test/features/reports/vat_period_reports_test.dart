import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubVatReportsRepository extends ReportsRepository {
  String lastGranularity = 'day';

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      const SalesSummary(
        from: '2026-11-01',
        to: '2026-11-22',
        totalTransactions: 7,
        totalGross: 784,
        totalVat: 84,
        totalDiscounts: 0,
        days: [],
        orVatBreakdown: OrVatSplit(
          orBacked: VatBucketTotals(
            transactions: 2,
            grossSales: 224,
            vatableSales: 200,
            vat: 24,
          ),
          untaggedOs: VatBucketTotals(
            transactions: 5,
            grossSales: 560,
            vatableSales: 500,
            vat: 60,
          ),
          combined: VatBucketTotals(
            transactions: 7,
            grossSales: 784,
            vatableSales: 700,
            vat: 84,
          ),
        ),
      );

  @override
  Future<VatReportSummary> fetchVatSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) async {
    lastGranularity = granularity;
    return VatReportSummary(
      from: '2026-11-01',
      to: '2026-11-22',
      granularity: granularity,
      totals: const OrVatSplit(
        orBacked: VatBucketTotals(
          transactions: 2,
          grossSales: 224,
          vatableSales: 200,
          vat: 24,
        ),
        untaggedOs: VatBucketTotals(
          transactions: 5,
          grossSales: 560,
          vatableSales: 500,
          vat: 60,
        ),
        combined: VatBucketTotals(
          transactions: 7,
          grossSales: 784,
          vatableSales: 700,
          vat: 84,
        ),
      ),
      periods: const [
        VatPeriodRow(
          period: '2026-11',
          transactions: 7,
          grossSales: 784,
          vat: 84,
          orBackedTransactions: 2,
          orBackedSales: 224,
          orBackedVatable: 200,
          orBackedVat: 24,
          untaggedTransactions: 5,
          untaggedSales: 560,
          untaggedVatable: 500,
          untaggedVat: 60,
        ),
      ],
    );
  }
}

void main() {
  test('VatReportSummary parses OR-backed vs untagged OS VAT breakdown and periods', () {
    final report = VatReportSummary.fromJson({
      'from': '2026-11-01',
      'to': '2026-11-22',
      'granularity': 'month',
      'totals': {
        'or_backed': {
          'transactions': 2,
          'gross_sales': '224.00',
          'vatable_sales': '200.00',
          'vat': '24.00',
        },
        'untagged_os': {
          'transactions': 5,
          'gross_sales': '560.00',
          'vatable_sales': '500.00',
          'vat': '60.00',
        },
        'combined': {
          'transactions': 7,
          'gross_sales': '784.00',
          'vatable_sales': '700.00',
          'vat': '84.00',
        },
      },
      'by_period': [
        {
          'period': '2026-11',
          'transactions': 7,
          'gross_sales': '784.00',
          'vat': '84.00',
          'or_backed_transactions': 2,
          'or_backed_sales': '224.00',
          'or_backed_vatable': '200.00',
          'or_backed_vat': '24.00',
          'untagged_transactions': 5,
          'untagged_sales': '560.00',
          'untagged_vatable': '500.00',
          'untagged_vat': '60.00',
        },
      ],
    });

    expect(report.granularity, 'month');
    expect(report.totals.orBacked.vat, 24.0);
    expect(report.totals.untaggedOs.vat, 60.0);
    expect(report.totals.combined.vat, 84.0);
    expect(report.periods.single.period, '2026-11');
    expect(report.periods.single.orBackedVat, 24.0);
  });

  testWidgets(
    'ReportsContent shows Whole VAT vs BIR OR split and switches VAT & OR granularity',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _StubVatReportsRepository();
      final vm = AdminReportsViewmodel(repository: repo);
      await vm.load();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChangeNotifierProvider<AdminReportsViewmodel>.value(
                value: vm,
                child: const ReportsContent(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sales tab surfaces the Whole VAT vs BIR OR comparison panel.
      expect(
        find.byKey(const ValueKey('or-vat-comparison-panel')),
        findsOneWidget,
      );
      expect(find.text('BIR OR Only (Official Receipt)'), findsOneWidget);

      // Jump to the dedicated VAT & OR tab.
      await tester.tap(find.byKey(const ValueKey('open-vat-or-tab-button')));
      await tester.pumpAndSettle();

      expect(find.text('Whole VAT vs. BIR OR-Only VAT'), findsOneWidget);
      expect(repo.lastGranularity, 'day');

      // Switch grouping to Monthly.
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();

      expect(repo.lastGranularity, 'month');
    },
  );
}
