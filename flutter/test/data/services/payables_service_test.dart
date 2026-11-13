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
          'credited': '0.00',
          'unapplied_credit': '100.00',
          'issued_cheques': '0.00',
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

  // Phase 8 F1 (decision 20): returns, what a delivery can still give back, the
  // credit notes a return mints, and the two cheque decisions. The routes and
  // shapes come from ENDPOINTS.md (B1–B4), never guessed.
  group('supplier returns (Phase 8 F1)', () {
    test('the returnable report is a bare array, not a page', () async {
      adapter.respond = (_) => _json([
        {
          'receipt_line': 31,
          'variant': 7,
          'variant_name': 'Portland Cement 40 kg',
          'unit': 'BAG',
          'delivered': '40.00',
          'returned': '5.00',
          'returnable': '35.00',
        },
      ]);

      final line = (await service.fetchReturnable(9)).single;

      expect(line.receiptLineId, 31);
      expect(line.unit, 'BAG');
      expect(line.returnable, 35);
      expect(
        adapter.requests.last.path,
        '/api/v1/goods-receipts/9/returnable/',
      );
    });

    test(
      'a return posts the receipt, reason and per-line quantities',
      () async {
        adapter.respond = (_) => _json({
          'id': 5,
          'receipt': 9,
          'supplier': 2,
          'supplier_name': 'Cebu Steel Works',
          'purchase_order': 41,
          'bill': 4,
          'reason': 'Torn bags',
          'created_by': 3,
          'created_by_name': 'Maria Santos',
          'created_at': '2026-11-14T08:15:00Z',
          'credit_note_number': 'CN-20261114-0001',
          'credit_note_total': '500.00',
          'credit_note_remaining': '100.00',
          'lines': [],
        }, status: 201);

        final returned = await service.createReturn(
          receiptId: 9,
          reason: 'Torn bags',
          lines: [
            {'receipt_line': 31, 'qty': '2.00'},
          ],
        );

        expect(returned.creditNoteNumber, 'CN-20261114-0001');
        expect(returned.creditNoteRemaining, 100);
        expect(adapter.requests.last.path, '/api/v1/supplier-returns/');
        expect(adapter.requests.last.method, 'POST');
        expect(adapter.requests.last.data, {
          'receipt': 9,
          'reason': 'Torn bags',
          'lines': [
            {'receipt_line': 31, 'qty': '2.00'},
          ],
        });
      },
    );

    test('a refused return keeps the server sentence', () async {
      adapter.respond = (_) => _json({
        'code': 'RETURN_EXCEEDS_RECEIPT',
        'detail': 'Line 31 has 35.00 BAG returnable: 40.00 is more than that.',
      }, status: 400);

      await expectLater(
        service.createReturn(
          receiptId: 9,
          reason: 'Torn bags',
          lines: [
            {'receipt_line': 31, 'qty': '40.00'},
          ],
        ),
        throwsA(
          isA<PayablesServiceException>().having(
            (error) => error.message,
            'message',
            contains('35.00 BAG returnable'),
          ),
        ),
      );
    });
  });

  group('credit notes (Phase 8 F1)', () {
    test('open notes for one supplier are queried and decoded', () async {
      adapter.respond = (_) => _json(
        _envelope([
          {
            'id': 12,
            'number': 'CN-20261114-0001',
            'supplier': 2,
            'supplier_name': 'Cebu Steel Works',
            'supplier_return': 5,
            'source_bill': 4,
            'value': '500.00',
            'vat_rate': '12.00',
            'vat_inclusive': true,
            'vat_amount': '53.57',
            'total_amount': '500.00',
            'remaining_amount': '100.00',
            'applied_amount': '400.00',
            'created_at': '2026-11-14T08:15:00Z',
          },
        ]),
      );

      final note = (await service.fetchCreditNotes(
        supplierId: 2,
        openOnly: true,
      )).single;

      expect(note.remainingAmount, 100);
      expect(note.isOpen, isTrue);
      expect(adapter.requests.last.path, '/api/v1/supplier-credit-notes/');
      expect(adapter.requests.last.queryParameters, {
        'supplier': 2,
        'open': true,
        'page': 1,
      });
    });

    test('an unfiltered read sends no filter of its own', () async {
      await service.fetchCreditNotes();

      expect(adapter.requests.last.queryParameters, isNot(contains('open')));
      expect(
        adapter.requests.last.queryParameters,
        isNot(contains('supplier')),
      );
    });
  });

  group('supplier cheques (Phase 8 F1)', () {
    Map<String, dynamic> chequeJson({
      String status = 'ISSUED',
      Object? decisionReason = '',
    }) => {
      ...(_billJson()['payments'] as List).first as Map<String, dynamic>,
      'method': 'CHEQUE',
      'cheque_number': '000123',
      'cheque_bank': 'BDO',
      'cheque_date': '2026-10-20',
      'status': status,
      'decided_by': status == 'ISSUED' ? null : 5,
      'decided_by_name': status == 'ISSUED' ? null : 'Store Manager',
      'decided_at': status == 'ISSUED' ? null : '2026-11-14T09:00:00Z',
      'decision_reason': decisionReason,
      'credit_note': null,
    };

    test(
      'the cheque queue is read from supplier-payments with its filter',
      () async {
        adapter.respond = (_) => _json(_envelope([chequeJson()]));

        final payment = (await service.fetchCheques(
          supplierId: 2,
          status: SupplierPaymentStatus.issued,
        )).single;

        expect(payment.isIssued, isTrue);
        expect(payment.chequeNumber, '000123');
        expect(adapter.requests.last.path, '/api/v1/supplier-payments/');
        expect(adapter.requests.last.queryParameters, {
          'supplier': 2,
          'status': 'ISSUED',
          'page': 1,
        });
      },
    );

    test(
      'clear posts to the cheque route and returns the decided row',
      () async {
        adapter.respond = (_) => _json(chequeJson(status: 'CLEARED'));

        final payment = await service.clearCheque(7);

        expect(payment.status, SupplierPaymentStatus.cleared);
        expect(payment.decidedById, 5);
        expect(
          adapter.requests.last.path,
          '/api/v1/supplier-payments/7/clear/',
        );
        expect(adapter.requests.last.method, 'POST');
      },
    );

    test('bounce posts the reason and returns the bounced row', () async {
      adapter.respond = (_) => _json(
        chequeJson(status: 'BOUNCED', decisionReason: 'Account closed'),
      );

      final payment = await service.bounceCheque(7, 'Account closed');

      expect(payment.status, SupplierPaymentStatus.bounced);
      expect(payment.decisionReason, 'Account closed');
      expect(adapter.requests.last.path, '/api/v1/supplier-payments/7/bounce/');
      expect(adapter.requests.last.data, {'reason': 'Account closed'});
    });

    test(
      'a second decision is a 409 that says the cheque is already decided',
      () async {
        adapter.respond = (_) => _json({
          'code': 'CHEQUE_ALREADY_DECIDED',
          'detail':
              'Cheque 000123 is already cleared and cannot be decided again.',
          'status': 'CLEARED',
        }, status: 409);

        await expectLater(
          service.clearCheque(7),
          throwsA(
            isA<PayablesServiceException>()
                .having((error) => error.code, 'code', 'CHEQUE_ALREADY_DECIDED')
                .having(
                  (error) => error.alreadyDecided,
                  'alreadyDecided',
                  isTrue,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('already cleared'),
                ),
          ),
        );
      },
    );

    test('a bounce with no reason keeps the server refusal', () async {
      adapter.respond = (_) => _json({
        'code': 'CHEQUE_REASON_REQUIRED',
        'detail': 'Say why the bank refused the cheque.',
      }, status: 400);

      await expectLater(
        service.bounceCheque(7, '  '),
        throwsA(
          isA<PayablesServiceException>().having(
            (error) => error.message,
            'message',
            contains('Say why'),
          ),
        ),
      );
    });

    test('404 on a payment that is not a cheque is named as such', () async {
      adapter.respond = (_) => _json({'detail': 'Not found.'}, status: 404);

      await expectLater(
        service.clearCheque(8),
        throwsA(
          isA<PayablesServiceException>().having(
            (error) => error.message,
            'message',
            contains('no longer exists'),
          ),
        ),
      );
    });
  });
}
