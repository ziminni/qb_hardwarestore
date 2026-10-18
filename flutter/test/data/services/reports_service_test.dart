import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

void main() {
  late _FakeAdapter adapter;
  late ReportsService service;
  RequestOptions? lastRequest;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    lastRequest = null;
    adapter = _FakeAdapter((options) {
      lastRequest = options;
      return _json({});
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = ReportsService();
  });

  test('sales summary parses totals and daily rows', () async {
    adapter.respond = (_) => _json({
      'from': '2026-09-19',
      'to': '2026-10-19',
      'totals': {'transactions': 3, 'gross_sales': '1500.00', 'vat': '0.00', 'discounts': '50.00'},
      'by_day': [
        {'day': '2026-10-19', 'transactions': 3, 'gross_sales': '1500.00', 'vat': '0.00', 'discounts': '50.00'},
      ],
    });

    final summary = await service.fetchSalesSummary();

    expect(summary.totalTransactions, 3);
    expect(summary.totalGross, 1500.0);
    expect(summary.totalDiscounts, 50.0);
    expect(summary.days, hasLength(1));
    expect(summary.days.single.day, '2026-10-19');
  });

  test('an empty range reads as zeros, not a parse crash', () async {
    adapter.respond = (_) => _json({
      'from': '2026-09-19',
      'to': '2026-10-19',
      'totals': {'transactions': 0, 'gross_sales': null, 'vat': null, 'discounts': null},
      'by_day': [],
    });

    final summary = await service.fetchSalesSummary();

    expect(summary.totalGross, 0.0);
    expect(summary.days, isEmpty);
  });

  test('valuation parses grand totals and categories', () async {
    adapter.respond = (_) => _json({
      'totals': {'batch_count': 2, 'total_units': '10', 'total_cost_value': '500.00', 'total_retail_value': '800.00'},
      'by_category': [
        {'variant__product__category__id': 1, 'variant__product__category__name': 'Cement', 'batch_count': 2, 'total_units': '10', 'cost_value': '500.00', 'retail_value': '800.00'},
      ],
    });

    final valuation = await service.fetchInventoryValuation();

    expect(valuation.totalCost, 500.0);
    expect(valuation.categories.single.name, 'Cement');
  });

  test('movements parse receipts, adjustments and totals', () async {
    adapter.respond = (_) => _json({
      'from': '2026-09-19',
      'to': '2026-10-19',
      'total_qty_in': 100,
      'total_qty_out': 30,
      'receipts_by_day': [
        {'receive_date': '2026-10-19', 'receipts': 1, 'qty_in': '100.00'},
      ],
      'adjustments_by_type': [
        {'adjustment_type': 'DAMAGE', 'movements': 2, 'qty_out': '30.00'},
      ],
    });

    final movements = await service.fetchStockMovements();

    expect(movements.totalIn, 100);
    expect(movements.totalOut, 30);
    expect(movements.adjustmentsByType.single.type, 'DAMAGE');
  });

  test('requisition history parses counts and rows', () async {
    adapter.respond = (_) => _json({
      'from': '2026-09-19',
      'to': '2026-10-19',
      'status_filter': null,
      'count_by_status': [
        {'status': 'APPROVED', 'count': 1},
      ],
      'requisitions': [
        {'id': 3, 'req_number': 'REQ-001', 'status': 'APPROVED', 'project': 'House', 'requested_by': 'Foreman', 'approved_by': 'Manager', 'created_at': '2026-10-19T08:00:00Z'},
      ],
    });

    final history = await service.fetchRequisitionHistory();

    expect(history.countByStatus['APPROVED'], 1);
    expect(history.requisitions.single.reqNumber, 'REQ-001');
    expect(history.requisitions.single.approvedBy, 'Manager');
  });

  test('from and to ride along as query parameters', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({'from': '2026-01-01', 'to': '2026-01-31', 'totals': {'transactions': 0, 'gross_sales': null, 'vat': null, 'discounts': null}, 'by_day': []});
    };

    await service.fetchSalesSummary(from: '2026-01-01', to: '2026-01-31');

    expect(lastRequest?.path, '/api/v1/reports/sales-summary/');
    expect(lastRequest?.queryParameters['from'], '2026-01-01');
    expect(lastRequest?.queryParameters['to'], '2026-01-31');
  });
}
