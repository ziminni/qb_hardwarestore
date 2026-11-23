// Reports suite P1 stage 1: the catalogue home + one shared viewer.
//
// The catalogue is the Reports area's front door: cards grouped SALES /
// INVENTORY / KPIs. The five reports that have an endpoint behind them are
// live; the P1 sales reports that have no endpoint yet are shown DISABLED with
// a "P1" tag, because a card that opens an empty screen is the dead control the
// tree-wide guard bans.
//
// Decision 02-role-visibility: an inventory-role-only account (the stocker) sees
// the INVENTORY section only — Sales, VAT and KPI cards are manager-only, and
// the server answers 403 to those endpoints for that account.
//
// The pages are built in three pieces so both facts are testable without a
// server or a shell: `ReportsCatalogueView` and `ReportViewerView` are the
// bodies, `ReportsCataloguePage` / `ReportViewerPage` wrap them in each area's
// skeleton (decision D-01: the same body in the admin, sales and stock shells).

import 'package:client/core/constants/app_areas.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/features/reports/reports_catalogue_page.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Answers the sales summary without a server; anything else is a failure of the
/// test's own setup, not of the screen.
class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  String? lastFrom;
  String? lastTo;
  int salesCalls = 0;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    salesCalls++;
    lastFrom = from;
    lastTo = to;
    return const SalesSummary(
      from: '2026-10-01',
      to: '2026-10-30',
      totalTransactions: 3,
      totalGross: 1500,
      totalVat: 180,
      totalDiscounts: 50,
      days: [
        SalesDay(
          day: '2026-10-29',
          transactions: 2,
          gross: 1000,
          vat: 120,
          discounts: 50,
        ),
        SalesDay(
          day: '2026-10-30',
          transactions: 1,
          gross: 500,
          vat: 60,
          discounts: 0,
        ),
      ],
    );
  }
}

void main() {
  group('catalogue home', () {
    testWidgets('renders the three sections with their cards', (tester) async {
      await tester.pumpWidget(_host(const ReportsCatalogueView()));

      expect(find.text('SALES'), findsOneWidget);
      expect(find.text('INVENTORY'), findsOneWidget);
      expect(find.text('KPIs'), findsOneWidget);

      // One live card per existing endpoint.
      expect(find.text('Sales summary'), findsOneWidget);
      expect(find.text('VAT & OR summary'), findsOneWidget);
      expect(find.text('Inventory valuation'), findsOneWidget);
      expect(find.text('Stock movements'), findsOneWidget);
      expect(find.text('Requisition history'), findsOneWidget);
    });

    testWidgets('every P1 card is tagged and opens nothing', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(_host(ReportsCatalogueView(onOpen: opened.add)));

      final planned = reportCatalogue.where((report) => !report.available);
      expect(
        planned,
        isNotEmpty,
        reason:
            'the P1 cards are the point of the tag: without them this is a '
            'vacuous check',
      );
      expect(find.text('P1'), findsNWidgets(planned.length));

      for (final report in planned) {
        await tester.tap(find.text(report.title));
        await tester.pumpAndSettle();
      }
      expect(opened, isEmpty, reason: 'a P1 card has no viewer behind it yet');
    });

    testWidgets('a live card opens the shared viewer with its report id', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(_host(ReportsCatalogueView(onOpen: opened.add)));

      await tester.tap(find.text('Sales summary'));
      await tester.pumpAndSettle();

      expect(opened, ['sales-summary']);
    });
  });

  group('role visibility (decision 02-role-visibility)', () {
    testWidgets('an inventory-only account sees Inventory and no Sales', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ReportsCatalogueView(areas: {AppAreas.inventory})),
      );

      expect(find.text('INVENTORY'), findsOneWidget);
      expect(find.text('Inventory valuation'), findsOneWidget);
      expect(find.text('SALES'), findsNothing);
      expect(find.text('Sales summary'), findsNothing);
      expect(
        find.text('KPIs'),
        findsNothing,
        reason: 'ABV / ASP / markdown are sales KPIs; the stocker is 403 there',
      );
    });

    testWidgets('a manager sees Sales, Inventory and KPIs', (tester) async {
      await tester.pumpWidget(
        _host(const ReportsCatalogueView(areas: {AppAreas.sales})),
      );

      expect(find.text('SALES'), findsOneWidget);
      expect(find.text('INVENTORY'), findsOneWidget);
      expect(find.text('KPIs'), findsOneWidget);
    });

    test('the visibility rule names the manager areas', () {
      expect(reportSectionsFor({AppAreas.inventory}), {
        ReportSection.inventory,
      });
      expect(reportSectionsFor({AppAreas.admin}), ReportSection.values.toSet());
      expect(reportSectionsFor({AppAreas.sales}), ReportSection.values.toSet());
      // A merged stocker + manager keeps the manager's sections.
      expect(
        reportSectionsFor({AppAreas.inventory, AppAreas.sales}),
        ReportSection.values.toSet(),
      );
    });
  });

  group('shared viewer', () {
    testWidgets('shows the sales-summary KPIs and rows', (tester) async {
      final repository = _StubReportsRepository();
      await tester.pumpWidget(
        _host(
          ReportViewerView(
            report: reportById('sales-summary')!,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.salesCalls, 1);
      // The viewer always sends the two days it shows, as the server's own
      // `YYYY-MM-DD`.
      expect(repository.lastFrom, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(repository.lastTo, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

      // KPI tiles (matched on the tile itself, so the table's column heading of
      // the same name cannot satisfy the check).
      expect(find.widgetWithText(MetricTile, 'Transactions'), findsOneWidget);
      expect(find.widgetWithText(MetricTile, 'Invoice total'), findsOneWidget);
      expect(find.text('₱1,500.00'), findsWidgets);

      // Table rows: one per reported day, plus the total row.
      expect(find.text('Oct 29, 2026'), findsOneWidget);
      expect(find.text('Oct 30, 2026'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('offers Excel export and a disabled PDF export', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ReportViewerView(
            report: reportById('sales-summary')!,
            repository: _StubReportsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final excel = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Export Excel'),
      );
      expect(excel.onPressed, isNotNull, reason: 'buildSalesReportXlsx exists');

      final pdf = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Export PDF'),
      );
      expect(
        pdf.onPressed,
        isNull,
        reason:
            'the letterhead PDF builder is P3, so the button is disabled '
            'rather than silently doing nothing',
      );

      // The date range filter sits above the report.
      expect(find.byKey(const ValueKey('report-viewer-range')), findsOneWidget);
    });

    testWidgets('a failed load says so instead of showing empty figures', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ReportViewerView(
            report: reportById('sales-summary')!,
            repository: _FailingReportsRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The sales summary could not be loaded.'),
        findsOneWidget,
      );
    });
  });
}

class _FailingReportsRepository extends ReportsRepository {
  _FailingReportsRepository() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    throw const ReportsServiceException(
      'The sales summary could not be loaded.',
    );
  }
}
