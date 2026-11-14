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
  static const String inventoryValuationPath =
      '/api/v1/reports/inventory-valuation/';
  static const String stockMovementsPath = '/api/v1/reports/stock-movements/';
  static const String requisitionHistoryPath =
      '/api/v1/reports/requisition-history/';

  /// Daily sales totals for the range; the server defaults to the last 30 days.
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        salesSummaryPath,
        queryParameters: {'from': ?from, 'to': ?to},
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
