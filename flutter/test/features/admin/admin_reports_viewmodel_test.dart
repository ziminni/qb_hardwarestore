import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  int salesCalls = 0;
  int valuationCalls = 0;
  int movementsCalls = 0;
  int historyCalls = 0;
  String? lastFrom;
  String? lastTo;
  String? salesFailure;
  Completer<void>? holdSales;

  SalesSummary summary = const SalesSummary(
    from: '', to: '', totalTransactions: 2, totalGross: 100,
    totalVat: 0, totalDiscounts: 0, days: [],
  );
  InventoryValuation valuation = const InventoryValuation(
    batchCount: 1, totalUnits: 5, totalCost: 50, totalRetail: 80,
    categories: [],
  );
  StockMovements movements = const StockMovements(
    from: '', to: '', totalIn: 10, totalOut: 3,
    receiptsByDay: [], adjustmentsByType: [],
  );
  RequisitionHistory history = const RequisitionHistory(
    from: '', to: '', statusFilter: null,
    countByStatus: {}, requisitions: [],
  );

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    salesCalls++;
    lastFrom = from;
    lastTo = to;
    final gate = holdSales;
    if (gate != null) await gate.future;
    final failure = salesFailure;
    if (failure != null) throw ReportsServiceException(failure);
    return summary;
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    valuationCalls++;
    return valuation;
  }

  @override
  Future<StockMovements> fetchStockMovements({String? from, String? to}) async {
    movementsCalls++;
    return movements;
  }

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async {
    historyCalls++;
    return history;
  }
}

void main() {
  late _StubReportsRepository repository;
  late AdminReportsViewmodel viewmodel;

  setUp(() {
    repository = _StubReportsRepository();
    viewmodel = AdminReportsViewmodel(repository: repository);
  });

  test('starts on the sales tab and loads it once', () async {
    expect(viewmodel.selectedTab, 0);

    await viewmodel.load();

    expect(repository.salesCalls, 1);
    expect(viewmodel.sales?.totalGross, 100);
    expect(viewmodel.errorFor(0), isNull);
  });

  test('selecting a tab loads it once and never reloads the first', () async {
    await viewmodel.load();

    await viewmodel.selectTab(1);

    expect(viewmodel.selectedTab, 1);
    expect(repository.valuationCalls, 1);
    expect(repository.salesCalls, 1);
    expect(viewmodel.valuation?.totalCost, 50);
  });

  test('a sales failure stays on its own tab', () async {
    repository.salesFailure = 'The sales summary could not be loaded.';
    await viewmodel.load();

    await viewmodel.selectTab(2);

    expect(viewmodel.errorFor(0), contains('sales summary'));
    expect(viewmodel.errorFor(2), isNull);
    expect(viewmodel.movements?.totalIn, 10);
  });

  test('a range change while loading reloads with the new bounds', () async {
    repository.holdSales = Completer<void>();
    final first = viewmodel.load();

    await viewmodel.setRange('2026-02-01', '2026-02-28');
    repository.holdSales!.complete();
    await first;

    expect(repository.salesCalls, 2);
    expect(repository.lastFrom, '2026-02-01');
    expect(viewmodel.sales?.totalGross, 100);
  });

  test('a range change reloads sales with the new bounds', () async {
    await viewmodel.load();

    await viewmodel.setRange('2026-01-01', '2026-01-31');

    expect(repository.salesCalls, 2);
    expect(repository.lastFrom, '2026-01-01');
    expect(repository.lastTo, '2026-01-31');
  });
}

