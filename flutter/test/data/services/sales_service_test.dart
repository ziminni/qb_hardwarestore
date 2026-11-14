import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/sales_service.dart';
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

Map<String, dynamic> _txn({String source = 'WALK_IN', String no = 'TRX-20261019-0001'}) => {
  'id': 9,
  'customer': 3,
  'customer_name': 'Dela Cruz Construction',
  'cashier_name': 'Cashy Ir',
  'transaction_no': no,
  'trans_date': '2026-10-19T08:00:00Z',
  'vatable_sales': '100.00',
  'vat_amount': '0.00',
  'discount_amount': '0.00',
  'grand_total': '100.00',
  'source': source,
  'original_transaction': null,
  'status': 'COMPLETED',
  'notes': '',
  'items': [
    {'id': 4, 'transaction': 9, 'variant_uom': 1, 'variant_uom_code': 'BAG', 'qty': '2.00', 'unit_price': '50.00', 'subtotal': '100.00'},
  ],
  'payments': [
    {'id': 5, 'transaction': 9, 'method': 'CASH', 'amount_tendered': '100.00', 'reference_no': '', 'timestamp': '2026-10-19T08:00:00Z'},
  ],
  'receipt': {'id': 6, 'transaction': 9, 'or_number': 'OR-1', 'terminal_no': 'POS-01', 'printed_at': '2026-10-19T08:00:00Z'},
  'created_at': '2026-10-19T08:00:00Z',
  'updated_at': '2026-10-19T08:00:00Z',
};

void main() {
  late _FakeAdapter adapter;
  late SalesService service;
  RequestOptions? lastRequest;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    lastRequest = null;
    adapter = _FakeAdapter((options) {
      lastRequest = options;
      return _json({'count': 0, 'next': null, 'previous': null, 'results': []});
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = SalesService();
  });

  test('transactions parse rows with nested items and payments', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({'count': 1, 'next': null, 'previous': null, 'results': [_txn()]});
    };

    final rows = await service.fetchTransactions();

    expect(rows, hasLength(1));
    expect(rows.single.transactionNo, 'TRX-20261019-0001');
    expect(rows.single.customerName, 'Dela Cruz Construction');
    expect(rows.single.items.single.variantUomCode, 'BAG');
    expect(rows.single.payments.single.method, 'CASH');
  });

  test('a source filter rides along as a query parameter', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({'count': 1, 'next': null, 'previous': null, 'results': [_txn(source: 'RETURN')]});
    };

    final rows = await service.fetchTransactions(source: 'RETURN');

    expect(lastRequest?.queryParameters['source'], 'RETURN');
    expect(rows.single.source, 'RETURN');
  });

  test('quotations parse with items and status vocabulary', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({'count': 1, 'next': null, 'previous': null, 'results': [
        {'id': 1, 'quotation_no': 'QT-20261019-0001', 'customer': 3, 'status': 'SENT', 'valid_until': '2026-11-19', 'notes': '', 'items': [
          {'id': 2, 'quotation': 1, 'variant_uom': 1, 'qty': '4.00', 'unit_price': '50.00'},
        ], 'created_at': '2026-10-19T08:00:00Z', 'updated_at': '2026-10-19T08:00:00Z'},
      ]});
    };

    final rows = await service.fetchQuotations();

    expect(lastRequest?.path, '/api/v1/quotations/');
    expect(rows.single.number, 'QT-20261019-0001');
    expect(rows.single.status, 'SENT');
    expect(rows.single.items.single.qty, 4.0);
  });

  test('orders parse with an optional quotation link', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({'count': 1, 'next': null, 'previous': null, 'results': [
        {'id': 7, 'order_no': 'SO-20261019-0001', 'customer': 3, 'quotation': 1, 'status': 'CONFIRMED', 'notes': '', 'items': [], 'created_at': '2026-10-19T08:00:00Z', 'updated_at': '2026-10-19T08:00:00Z'},
      ]});
    };

    final rows = await service.fetchSalesOrders();

    expect(rows.single.number, 'SO-20261019-0001');
    expect(rows.single.quotationId, 1);
  });

  test('an unauthenticated read reports sign-in', () async {
    adapter.respond = (_) => _json({'detail': 'Authentication required.'}, status: 401);

    expect(
      service.fetchTransactions(),
      throwsA(isA<SalesServiceException>().having(
        (e) => e.message, 'message', 'Your session has expired. Sign in again.')),
    );
  });
}
