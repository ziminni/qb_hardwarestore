// Phase 3 Task 4: the returns wire contract, pinned against the shapes the
// backend actually sends.
//
// Two things are being pinned, and both were read out of backend_django rather
// than guessed:
//
//  * `returnable_payload` (apps/pos/services.py) is the pre-flight body —
//    one row per SELLING UNIT, every number a 2-decimal STRING, and
//    `reason_if_not` carrying the same stable code the POST would refuse with.
//  * `refund_summary` (`_settle_return_money`) is on the 201, with
//    `ledger_id`/`ledger_balance` NULL when the sale owed nothing.
//
// And the POST body: `{customer, source:'RETURN', original_transaction,
// reason, payment_method, items:[{variant_id, qty}]}` — `customer` is the
// ORIGINAL sale's customer, because a refund settles THAT customer's utang.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _transactionsPath = '/api/v1/transactions/';

/// One row of `GET /transactions/`, shaped like SalesTransactionSerializer.
Map<String, dynamic> _saleRow({int id = 18}) => {
  'id': id,
  'customer': 2,
  'customer_name': 'Maria Santos',
  'cashier': 1,
  'cashier_name': 'Ana Cruz',
  'transaction_no': 'TRX-20261024-0007',
  'trans_date': '2026-10-24T09:00:00+08:00',
  'vatable_sales': '1000.00',
  'vat_amount': '0.00',
  'discount_amount': '0.00',
  'grand_total': '1000.00',
  'source': 'CHARGE',
  'status': 'COMPLETED',
  'notes': '',
  'items': [
    {
      'id': 31,
      'transaction': id,
      'variant_uom': 8,
      'variant_uom_code': 'BAG',
      'qty': '10.00',
      'unit_price': '100.00',
      'subtotal': '1000.00',
    },
  ],
  'payments': [
    {
      'id': 12,
      'transaction': id,
      'method': 'CASH',
      'amount_tendered': '400.00',
      'reference_no': '',
      'timestamp': '2026-10-24T09:00:00+08:00',
    },
  ],
  'receipt': {
    'id': 9,
    'transaction': id,
    'or_number': 'OR-20261024-0007',
    'terminal_no': 'POS-01',
    'printed_at': '2026-10-24T09:00:00+08:00',
  },
};

/// `returnable_payload` verbatim: strings, one row per selling unit.
Map<String, dynamic> _returnable({String? reasonIfNot, String openDebt = '600.00'}) => {
  'transaction_no': 'TRX-20261024-0007',
  'customer': 'Maria Santos',
  'source': 'CHARGE',
  'returnable': reasonIfNot == null,
  'reason_if_not': reasonIfNot,
  'lines': [
    {
      'variant_uom': 8,
      'name': 'Portland Cement - 40kg',
      'uom': 'BAG',
      'sold_qty': '10.00',
      'returned_qty': '2.00',
      'remaining_qty': '8.00',
      'unit_price': '100.00',
    },
  ],
  'open_debt': openDebt,
};

/// `_settle_return_money` verbatim.
Map<String, dynamic> _postedReturn({
  String debtReduced = '600.00',
  String cashRefund = '200.00',
  int? ledgerId = 5,
  String? ledgerBalance = '0.00',
}) => {
  ..._saleRow(id: 44),
  'transaction_no': 'RTN-20261024-0001',
  'source': 'RETURN',
  'grand_total': '-800.00',
  'refund_summary': {
    'return_value': '800.00',
    'debt_reduced': debtReduced,
    'cash_refund': cashRefund,
    'refund_method': 'CASH',
    'ledger_id': ledgerId,
    'ledger_balance': ledgerBalance,
  },
};

/// A path-aware fake: this service talks to three different routes.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.searchBody,
    this.returnableBody,
    this.postBody,
    this.returnableStatus = 200,
    this.postStatus = 201,
  });

  /// The LIST envelope answered by `GET /transactions/?q=`.
  Map<String, dynamic>? searchBody;

  /// The pre-flight body, or a `{status, body}` failure.
  Map<String, dynamic>? returnableBody;

  /// The POST answer, or a failure.
  Map<String, dynamic>? postBody;

  int returnableStatus;
  int postStatus;

  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.path;
    if (path.contains('/returnable/')) {
      return _reply(
        returnableBody ?? const {'detail': 'not found'},
        returnableStatus,
      );
    }
    if (options.method == 'POST') {
      return _reply(postBody ?? const {'detail': 'refused'}, postStatus);
    }
    return _reply(
      searchBody ?? {'count': 0, 'next': null, 'previous': null, 'results': []},
      200,
    );
  }

  ResponseBody _reply(Map<String, dynamic> body, int status) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeAdapter adapter;
  late ApiClient client;
  late HttpClientAdapter originalAdapter;

  // `ApiClient.init()` assigns a `late final dio`, so it runs once for the file.
  setUpAll(() => client = ApiClient.instance..init());

  setUp(() {
    originalAdapter = client.dio.httpClientAdapter;
  });

  tearDown(() => client.dio.httpClientAdapter = originalAdapter);

  ReturnsService serviceWith(_FakeAdapter fake) {
    adapter = fake;
    client.dio.httpClientAdapter = fake;
    return ReturnsService(client: client);
  }

  group('search', () {
    test('asks ?q= and returns the matched sale', () async {
      final service = serviceWith(
        _FakeAdapter(
          searchBody: {
            'count': 1,
            'next': null,
            'previous': null,
            'results': [_saleRow()],
          },
        ),
      );

      final found = await service.findSale(' OR-20261024-0007 ');

      expect(
        adapter.requests.single.queryParameters['q'],
        'OR-20261024-0007',
        reason:
            'the search is an EXACT match server-side; sending the raw text '
            'with spaces would answer an empty page',
      );
      expect(found?.id, 18);
      expect(found?.customerId, 2, reason: 'the POST needs the customer id');
    });

    test('an empty page is a MISS, not an exception', () async {
      final service = serviceWith(_FakeAdapter());

      expect(await service.findSale('nothing'), isNull);
    });

    test('an empty query never reaches the server', () async {
      final service = serviceWith(_FakeAdapter());

      expect(await service.findSale('   '), isNull);
      expect(adapter.requests, isEmpty);
    });
  });

  group('pre-flight', () {
    test('reads the payload the server sends', () async {
      final service = serviceWith(
        _FakeAdapter(returnableBody: _returnable()),
      );

      final preflight = await service.fetchReturnable(18);

      expect(adapter.requests.single.path, '${_transactionsPath}18/returnable/');
      expect(preflight.transactionNo, 'TRX-20261024-0007');
      expect(preflight.customer, 'Maria Santos');
      expect(preflight.returnable, isTrue);
      expect(preflight.reasonIfNot, isNull);
      expect(preflight.openDebt, 600);
      expect(preflight.lines.single.variantUomId, 8);
      expect(preflight.lines.single.remainingQty, 8);
      expect(preflight.lines.single.unitPrice, 100);
    });

    test('reason_if_not becomes a clerk-readable refusal', () async {
      final service = serviceWith(
        _FakeAdapter(returnableBody: _returnable(reasonIfNot: 'RETURN_OF_RETURN')),
      );

      final preflight = await service.fetchReturnable(18);

      expect(preflight.returnable, isFalse);
      expect(preflight.reasonIfNot, 'RETURN_OF_RETURN');
      expect(
        preflight.notReturnableMessage,
        contains('cannot reverse another return'),
      );
    });

    test("another cashier's sale reads as not found", () async {
      final service = serviceWith(
        _FakeAdapter(
          returnableBody: const {'detail': 'Not found.'},
          returnableStatus: 404,
        ),
      );

      final failure = await service
          .fetchReturnable(99)
          .then<Object?>((_) => null, onError: (error) => error);

      expect(failure, isA<ReturnsServiceException>());
      expect(failure.toString(), contains('No sale of yours matches'));
    });
  });

  group('posting the return', () {
    test('sends the body the serializer expects, with the ORIGINAL customer', () async {
      final service = serviceWith(_FakeAdapter(postBody: _postedReturn()));

      await service.postReturn(
        customerId: 2,
        originalTransactionId: 18,
        reason: '  cracked sacks  ',
        paymentMethod: 'CASH',
        lines: const [ReturnRequestLine(variantUomId: 8, qty: 8)],
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, _transactionsPath);
      final sent = request.data as Map<String, dynamic>;
      expect(sent['customer'], 2);
      expect(
        sent['source'],
        'RETURN',
        reason: 'a return IS a transaction with source RETURN (decision 05)',
      );
      expect(sent['original_transaction'], 18);
      expect(sent['reason'], 'cracked sacks');
      expect(sent['payment_method'], 'CASH');
      expect(
        sent['items'],
        [
          {'variant_id': 8, 'qty': 8.0},
        ],
        reason: 'the server prices the lines; a client price would be forgeable',
      );
      expect(sent.containsKey('cashier'), isFalse);
    });

    test('reads refund_summary, the server\'s own arithmetic', () async {
      final service = serviceWith(_FakeAdapter(postBody: _postedReturn()));

      final result = await service.postReturn(
        customerId: 2,
        originalTransactionId: 18,
        reason: 'cracked sacks',
        paymentMethod: 'CASH',
        lines: const [ReturnRequestLine(variantUomId: 8, qty: 8)],
      );

      expect(result.returnNo, 'RTN-20261024-0001');
      expect(result.refund.returnValue, 800);
      expect(result.refund.debtReduced, 600);
      expect(result.refund.cashRefund, 200);
      expect(result.refund.refundMethod, 'CASH');
      expect(result.refund.ledgerId, 5);
      expect(result.refund.ledgerBalance, 0);
    });

    test('a sale that owed nothing reports a null ledger, not a zero one', () async {
      final service = serviceWith(
        _FakeAdapter(
          postBody: _postedReturn(
            debtReduced: '0.00',
            cashRefund: '800.00',
            ledgerId: null,
            ledgerBalance: null,
          ),
        ),
      );

      final result = await service.postReturn(
        customerId: 2,
        originalTransactionId: 18,
        reason: 'unwanted',
        paymentMethod: 'CASH',
        lines: const [ReturnRequestLine(variantUomId: 8, qty: 8)],
      );

      expect(result.refund.debtReduced, 0);
      expect(result.refund.cashRefund, 800);
      expect(result.refund.ledgerId, isNull);
      expect(result.refund.ledgerBalance, isNull);
    });
  });

  group('every server code becomes words a cashier can act on', () {
    Future<ReturnsServiceException> refusal(
      Map<String, dynamic> body,
      int status,
    ) async {
      final service = serviceWith(
        _FakeAdapter(postBody: body, postStatus: status),
      );
      final failure = await service
          .postReturn(
            customerId: 2,
            originalTransactionId: 18,
            reason: 'x',
            paymentMethod: 'CASH',
            lines: const [ReturnRequestLine(variantUomId: 8, qty: 1)],
          )
          .then<Object?>((_) => null, onError: (error) => error);
      return failure! as ReturnsServiceException;
    }

    test('NO_OPEN_SHIFT is flagged as fixable', () async {
      final failure = await refusal(
        const {
          'code': 'NO_OPEN_SHIFT',
          'detail': 'You have no open shift.',
        },
        400,
      );

      expect(failure.needsOpenShift, isTrue);
      expect(failure.message, contains('Open a shift'));
    });

    test('RETURN_QTY_EXCEEDED names the four numbers', () async {
      final failure = await refusal(
        {
          'code': 'RETURN_QTY_EXCEEDED',
          'detail': 'Selling unit 8 sold 10.00 on this sale.',
          'variant_uom': 8,
          'sold': '10.00',
          'already_returned': '2.00',
          'requested': '9.00',
        },
        400,
      );

      expect(failure.code, 'RETURN_QTY_EXCEEDED');
      expect(failure.message, contains('sold 10.00'));
      expect(failure.message, contains('2.00 already returned'));
      expect(failure.message, contains('9.00 is being asked for'));
      expect(
        failure.needsOpenShift,
        isFalse,
        reason: 'a quantity mistake is not fixed by opening a shift',
      );
    });

    test('RETURN_REASON_REQUIRED, RELEASE_NOT_RETURNABLE, RETURN_OF_RETURN, '
        'ORIGINAL_NOT_COMPLETED, UNLINKED_RETURN_FORBIDDEN each explain '
        'themselves', () async {
      const expected = {
        'RETURN_REASON_REQUIRED': 'needs a reason',
        'RELEASE_NOT_RETURNABLE': 'material release, not a sale',
        'RETURN_OF_RETURN': 'cannot reverse another return',
        'ORIGINAL_NOT_COMPLETED': 'Only a completed sale',
        'UNLINKED_RETURN_FORBIDDEN': 'Store Manager',
      };

      for (final entry in expected.entries) {
        final failure = await refusal(
          {'code': entry.key, 'detail': 'server prose'},
          entry.key == 'UNLINKED_RETURN_FORBIDDEN' ? 403 : 400,
        );
        expect(
          failure.message,
          contains(entry.value),
          reason:
              '${entry.key} must reach the counter as an instruction, not as '
              '"the return could not be completed"',
        );
        expect(failure.code, entry.key);
      }
    });
  });
}
