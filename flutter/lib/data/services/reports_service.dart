import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/reports.dart';
import 'package:dio/dio.dart';

/// Raised for anything the admin Reports screen must show to a human.
class ReportsServiceException implements Exception {
  const ReportsServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the four managerial aggregates behind the admin Reports screen.
///
/// Decision 16: ONE admin/manager screen over `/api/v1/reports/*`. Each report
/// loads on demand — one report at a time — so every fetch here is a separate
/// call the tab layer makes when its tab is first shown.
class ReportsService {
  ReportsService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String salesSummaryPath = '/api/v1/reports/sales-summary/';
  static const String vatSummaryPath = '/api/v1/reports/vat-summary/';
  static const String inventoryValuationPath =
      '/api/v1/reports/inventory-valuation/';
  static const String stockMovementsPath = '/api/v1/reports/stock-movements/';
  static const String requisitionHistoryPath =
      '/api/v1/reports/requisition-history/';
  static const String salesByItemPath = '/api/v1/reports/sales-by-item/';
  static const String salesByHourPath = '/api/v1/reports/sales-by-hour/';
  static const String salesByCashierPath = '/api/v1/reports/sales-by-cashier/';
  static const String billWisePath = '/api/v1/reports/bill-wise/';
  static const String returnsExchangesPath =
      '/api/v1/reports/returns-exchanges/';
  static const String discountsPath = '/api/v1/reports/discounts/';
  static const String voidsPath = '/api/v1/reports/voids/';

  /// Daily/weekly/monthly sales totals for the range; defaults to last 30 days.
  Future<SalesSummary> fetchSalesSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        salesSummaryPath,
        queryParameters: {'from': ?from, 'to': ?to, 'granularity': granularity},
      );
      return SalesSummary.fromJson(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, 'sales summary'));
    } on FormatException {
      // A body the client cannot parse is not "no sales" — saying so would show
      // a manager an empty, reassuring report over a server they cannot read.
      throw const ReportsServiceException(
        'The sales summary could not be read. Try again.',
      );
    }
  }

  /// Daily / weekly / monthly VAT summary split into OR-backed vs untagged OS.
  Future<VatReportSummary> fetchVatSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        vatSummaryPath,
        queryParameters: {'from': ?from, 'to': ?to, 'granularity': granularity},
      );
      return VatReportSummary.fromJson(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, 'VAT summary'));
    } on FormatException {
      throw const ReportsServiceException(
        'The VAT summary could not be read. Try again.',
      );
    }
  }

  /// Stock value at cost and at retail, grouped by category.
  Future<InventoryValuation> fetchInventoryValuation() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        inventoryValuationPath,
      );
      return InventoryValuation.fromJson(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, 'inventory valuation'));
    } on FormatException {
      throw const ReportsServiceException(
        'The inventory valuation could not be read. Try again.',
      );
    }
  }

  /// Stock IN vs OUT for the range; the server defaults to the last 30 days.
  Future<StockMovements> fetchStockMovements({String? from, String? to}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        stockMovementsPath,
        queryParameters: {'from': ?from, 'to': ?to},
      );
      return StockMovements.fromJson(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, 'stock movements'));
    } on FormatException {
      throw const ReportsServiceException(
        'The stock movements could not be read. Try again.',
      );
    }
  }

  /// Requisition counts per status plus the filtered listing.
  Future<RequisitionHistory> fetchRequisitionHistory() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        requisitionHistoryPath,
      );
      return RequisitionHistory.fromJson(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, 'requisition history'));
    } on FormatException {
      throw const ReportsServiceException(
        'The requisition history could not be read. Try again.',
      );
    }
  }

  /// Per selling unit: base-unit quantity, net merchandise, COGS and profit.
  Future<SalesByItemReport> fetchSalesByItem({String? from, String? to}) =>
      _paged(
        salesByItemPath,
        'item-wise sales',
        from,
        to,
        SalesByItemReport.fromJson,
      );

  /// Every store-local hour 0-23, zeros included.
  Future<SalesByHour> fetchSalesByHour({String? from, String? to}) =>
      _paged(salesByHourPath, 'hourly sales', from, to, SalesByHour.fromJson);

  /// Per cashier: transactions, invoice total and discounts given.
  Future<SalesByCashier> fetchSalesByCashier({String? from, String? to}) =>
      _paged(
        salesByCashierPath,
        'cashier sales',
        from,
        to,
        SalesByCashier.fromJson,
      );

  /// One row per completed bill, with its tenders and signed total.
  Future<BillWiseReport> fetchBillWise({String? from, String? to}) => _paged(
    billWisePath,
    'bill-wise sales',
    from,
    to,
    BillWiseReport.fromJson,
  );

  /// Only the RETURN / EXCHANGE rows, with the refunded money.
  Future<ReturnsExchangesReport> fetchReturnsExchanges({
    String? from,
    String? to,
  }) => _paged(
    returnsExchangesPath,
    'returns & exchanges',
    from,
    to,
    ReturnsExchangesReport.fromJson,
  );

  /// Discount pesos per type: LINE, CART and the APPROVAL behind a sale.
  Future<DiscountsReport> fetchDiscounts({String? from, String? to}) =>
      _paged(discountsPath, 'discounts', from, to, DiscountsReport.fromJson);

  /// VOID bills with the reason on file.
  Future<VoidsReport> fetchVoids({String? from, String? to}) =>
      _paged(voidsPath, 'voids', from, to, VoidsReport.fromJson);

  /// The shared shape of the seven paged sales reports: a dated GET whose body
  /// is the `_paged()` envelope (totals outside the 50-row page).
  Future<T> _paged<T>(
    String path,
    String report,
    String? from,
    String? to,
    T Function(Map<String, dynamic>) parse,
  ) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        path,
        queryParameters: {'from': ?from, 'to': ?to},
      );
      return parse(response.data!);
    } on DioException catch (error) {
      throw ReportsServiceException(_messageFor(error, report));
    } on FormatException {
      throw ReportsServiceException(
        'The $report could not be read. Try again.',
      );
    }
  }

  String _messageFor(DioException error, String report) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'You do not have access to reports.';
    return 'The $report could not be loaded.';
  }
}
