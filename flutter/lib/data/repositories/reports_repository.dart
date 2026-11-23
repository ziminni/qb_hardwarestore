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
}
