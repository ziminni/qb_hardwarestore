// Phase 5 F2 (decision 18): the payables service puts the server's own words in
// front of the clerk.
//
// The bill, payment and summary endpoints are read through `getAll`, the list
// walk that lives next to the pagination envelope (decision 03). A refusal is
// the SERVER's `detail` sentence: it names the bill, what is left to pay and
// what was typed, which no canned sentence can. A canned sentence is only the
// fallback for a code that arrives without one.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _billJson({String status = 'PARTIAL'}) => {
  'id': 4,
  'receipt': 9,
  'purchase_order': 41,
  'supplier': 2,
  'supplier_name': 'Cebu Steel Works',
  'received_date': '2026-10-01',
  'terms_days': 30,
  'due_date': '2026-10-31',
  'gross_amount': '1000.00',
  'discount_amount': '100.00',
  'net_amount': '900.00',
  'vatable_amount': '803.57',
  'vat_amount': '96.43',
  'vat_rate': '12.00',
  'total_amount': '900.00',
  'balance_amount': '400.00',
  'paid_amount': '500.00',
  'status': status,
  'is_overdue': true,
  'payments': [
    {
      'id': 7,
      'bill': 4,
      'amount': '500.00',
      'method': 'CASH',
      'reference': '',
      'cheque_number': null,
      'cheque_bank': null,
      'cheque_date': null,
      'paid_by': 3,
      'paid_by_name': 'Maria Santos',
      'paid_on': '2026-10-20T09:30:00Z',
    },
  ],
};

Map<String, dynamic> _envelope(List<Map<String, dynamic>> results) => {
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

void main() {
  late _FakeAdapter adapter;
  late PayablesService service;

  setUpAll(() => ApiClient.instance.init());

  setUp(() {
    adapter = _FakeAdapter((_) => _json(_envelope(const [])));
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = PayablesService();
  });

  test(
    'bills are read from the supplier-bills route with their history',
    () async {
      adapter.respond = (_) => _json(_envelope([_billJson()]));

      final bill = (await service.fetchBills()).single;

      expect(bill.supplierName, 'Cebu Steel Works');
      expect(bill.balanceAmount, 400);
      expect(bill.payments.single.paidByName, 'Maria Santos');
      expect(adapter.requests.last.path, '/api/v1/supplier-bills/');
    },
  );

  test('the filters travel as query parameters', () async {
    await service.fetchBills(
      supplierId: 2,
      status: SupplierBillStatus.partial,
      overdueOnly: true,
    );

    expect(adapter.requests.last.path, '/api/v1/supplier-bills/');
    // `page` rides along because the walk owns it, not the caller.
    expect(adapter.requests.last.queryParameters, {
      'supplier': 2,
      'status': 'PARTIAL',
      'overdue': true,
      'page': 1,
    });
  });

  test('an unfiltered read sends no query of its own', () async {
    await service.fetchBills();

    expect(adapter.requests.last.queryParameters, isNot(contains('status')));
    expect(adapter.requests.last.queryParameters, isNot(contains('overdue')));
  });

  test('one bill is read by id', () async {
    adapter.respond = (_) => _json(_billJson());

    final bill = await service.fetchBill(4);

    expect(bill.id, 4);
    expect(adapter.requests.last.path, '/api/v1/supplier-bills/4/');
  });

  test('the per-supplier summary is read from suppliers/payables', () async {
    adapter.respond = (_) => _json(
      _envelope([
        {
          'supplier': 2,
          'supplier_name': 'Cebu Steel Works',
          'bills': 3,
          'original': '3000.00',
          'paid': '1000.00',
          'balance': '2000.00',
          'overdue': '500.00',
        },
      ]),
    );

    final row = (await service.fetchSummary()).single;

    expect(row.balance, 2000);
    expect(adapter.requests.last.path, '/api/v1/suppliers/payables/');
  });

  test('a payment posts the bill, amount and method', () async {
    adapter.respond = (_) => _json({
      'id': 12,
      'bill': 4,
      'amount': '400.00',
      'method': 'CASH',
      'reference': '',
      'cheque_number': null,
      'cheque_bank': null,
      'cheque_date': null,
      'paid_by': 3,
      'paid_by_name': 'Maria Santos',
      'paid_on': '2026-10-20T09:30:00Z',
    }, status: 201);

    await service.createPayment({
      'bill': 4,
      'amount': '400.00',
      'method': 'CASH',
    });

    expect(adapter.requests.last.path, '/api/v1/supplier-payments/');
    expect(adapter.requests.last.method, 'POST');
  });

  group('refusals', () {
    Future<String> refusal(int status, Map<String, dynamic> body) async {
      adapter.respond = (_) => _json(body, status: status);
      try {
        await service.createPayment({
          'bill': 4,
          'amount': '999.00',
          'method': 'CASH',
        });
      } on PayablesServiceException catch (error) {
        return error.message;
      }
      fail('a refused payment must throw');
    }

    test('OVERPAYMENT shows the server detail sentence', () async {
      const sentence =
          'Bill #4 has 400.00 left to pay: 999.00 is more than that.';
      expect(
        await refusal(400, {'code': 'OVERPAYMENT', 'detail': sentence}),
        sentence,
      );
    });

    test('BILL_PAID shows the server detail sentence', () async {
      const sentence = 'Bill #4 is already paid in full.';
      expect(
        await refusal(400, {'code': 'BILL_PAID', 'detail': sentence}),
        sentence,
      );
    });

    test('INVALID_SUPPLIER_PAYMENT shows the server detail sentence', () async {
      const sentence = 'A cheque payment needs a cheque number, bank and date.';
      expect(
        await refusal(400, {
          'code': 'INVALID_SUPPLIER_PAYMENT',
          'detail': sentence,
        }),
        sentence,
      );
    });

    test('an unknown code still refuses and still shows its detail', () async {
      const sentence = 'Something the client has never heard of.';
      expect(
        await refusal(400, {'code': 'SOME_NEW_CODE', 'detail': sentence}),
        sentence,
      );
    });

    test(
      'a known code without a detail falls back to its own sentence',
      () async {
        final message = await refusal(400, {'code': 'BILL_PAID'});
        expect(message, contains('already paid'));
      },
    );

    test('a field-error body is read out, not flattened', () async {
      expect(
        await refusal(400, {
          'cheque_number': ['A cheque needs its number.'],
        }),
        'A cheque needs its number.',
      );
    });
  });

  test('403 says the account may not record payments', () async {
    adapter.respond = (_) => _json({'detail': 'refused'}, status: 403);

    await expectLater(
      service.createPayment({'bill': 4, 'amount': '1.00', 'method': 'CASH'}),
      throwsA(
        isA<PayablesServiceException>().having(
          (error) => error.message,
          'message',
          contains('No permission'),
        ),
      ),
    );
  });
}
