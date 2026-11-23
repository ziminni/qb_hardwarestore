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

  Future<VatReportSummary> fetchVatSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) => _service.fetchVatSummary(from: from, to: to, granularity: granularity);

  Future<SalesByItemReport> fetchSalesByItem({String? from, String? to}) =>
      _service.fetchSalesByItem(from: from, to: to);

  Future<SalesByHour> fetchSalesByHour({String? from, String? to}) =>
      _service.fetchSalesByHour(from: from, to: to);

  Future<SalesByCashier> fetchSalesByCashier({String? from, String? to}) =>
      _service.fetchSalesByCashier(from: from, to: to);

  Future<BillWiseReport> fetchBillWise({String? from, String? to}) =>
      _service.fetchBillWise(from: from, to: to);

  Future<ReturnsExchangesReport> fetchReturnsExchanges({
    String? from,
    String? to,
  }) => _service.fetchReturnsExchanges(from: from, to: to);

  Future<DiscountsReport> fetchDiscounts({String? from, String? to}) =>
      _service.fetchDiscounts(from: from, to: to);

  Future<VoidsReport> fetchVoids({String? from, String? to}) =>
      _service.fetchVoids(from: from, to: to);

  Future<GrnReport> fetchGrn({String? from, String? to}) =>
      _service.fetchGrn(from: from, to: to);

  Future<StnReport> fetchStn({String? from, String? to}) =>
      _service.fetchStn(from: from, to: to);

  Future<BatchAgeReport> fetchBatchAge() => _service.fetchBatchAge();

  Future<ShrinkageReport> fetchShrinkage({String? from, String? to}) =>
      _service.fetchShrinkage(from: from, to: to);

  Future<AdjustmentsReport> fetchAdjustments({String? from, String? to}) =>
      _service.fetchAdjustments(from: from, to: to);

  Future<ReorderReport> fetchReorder() => _service.fetchReorder();

  Future<DeadStockReport> fetchDeadStock() => _service.fetchDeadStock();

  Future<FastSlowReport> fetchFastSlow({String? from, String? to}) =>
      _service.fetchFastSlow(from: from, to: to);

  Future<CycleCountReport> fetchCycleCount({String? from, String? to}) =>
      _service.fetchCycleCount(from: from, to: to);

  Future<ExpiryReport> fetchExpiry() => _service.fetchExpiry();
}
