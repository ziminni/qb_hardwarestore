import 'package:client/data/models/reports.dart';
import 'package:client/data/services/reports_service.dart';

/// Pass-through over [ReportsService], with no policy of its own.
///
/// It exists only to preserve the POS one-data-path invariant
/// (View -> ViewModel -> Repository -> Service -> ApiClient); the same shape as
/// [LedgerRepository].
class ReportsRepository {
  ReportsRepository({ReportsService? service})
    : _service = service ?? ReportsService();

  final ReportsService _service;

  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) =>
      _service.fetchSalesSummary(from: from, to: to);

  Future<InventoryValuation> fetchInventoryValuation() =>
      _service.fetchInventoryValuation();

  Future<StockMovements> fetchStockMovements({String? from, String? to}) =>
      _service.fetchStockMovements(from: from, to: to);

  Future<RequisitionHistory> fetchRequisitionHistory() =>
      _service.fetchRequisitionHistory();
}
