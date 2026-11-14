// Phase 9 F3 (decision 21 §3, ENDPOINTS.md §3.3): the transfer WIRE contract.
//
// Pinned here:
//   * the list is walked over EVERY page — a move from last week is past row 50,
//     and one page would hide it;
//   * the body carries the SELLING unit and the amount, never a converted base
//     quantity (the server converts and refuses what stock cannot hold);
//   * a refusal arrives as the server's own sentence with its code and
//     shortfall, so the dialog can say why the shelves did not move;
//   * 403/405 read as rules, not as "try again".

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/services/stock_transfer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _path = '/api/v1/stock-transfers/';

Map<String, dynamic> _slipJson({
  int id = 1,
  String number = 'TR-20261113-0001',
  String remarks = '',
}) => {
  'id': id,
  'number': number,
  'from_location': 1,
  'from_location_name': 'Store',
  'to_location': 2,
  'to_location_name': 'Bodega',
  'user': 7,
  'user_name': 'Ana Lopez',
  'remarks': remarks,
  'created_at': '2026-11-13T09:15:00+08:00',
  'lines': [
    {
      'id': 11,
      'variant_uom': 4,
      'variant': 8,
      'variant_name': '20A 1-pole',
      'product_name': 'Circuit Breaker',
      'unit': 'BAG',
      'qty': '2.00',
      'base_qty': '24.00',
      // Two deliveries paid for one line: the slip says both.
      'moves': [
        {'id': 21, 'source_batch': 5, 'dest_batch': 9, 'qty': '12.00'},
        {'id': 22, 'source_batch': 6, 'dest_batch': 10, 'qty': '12.00'},
      ],
    },
  ],
};

Map<String, dynamic> _envelope(
  List<Map<String, dynamic>> results, {
  String? next,
  String? previous,
}) => {
  'count': results.length,
  'next': next,
  'previous': previous,
  'results': results,
};

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// Answers a LIST by page number (the way DRF does past PAGE_SIZE) and a POST
/// with [refusal] when a test set one.
class _TransfersAdapter implements HttpClientAdapter {
  _TransfersAdapter({this.pages = const []});

  final List<Object> pages;
  final List<String> requested = [];
  final List<Object?> sentBodies = [];
  Object? refusal;
  int refusalStatus = 400;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      final data = options.data;
      sentBodies.add(data is String ? jsonDecode(data) : data);
      final refused = refusal;
      if (refused != null) return _json(refused, status: refusalStatus);
      return _json(pages.first, status: 201);
    }
    final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requested.add('${options.path}?page=$page');
    if (page > pages.length) {
      return _json({'detail': 'invalid page'}, status: 404);
    }
    return _json(pages[page - 1]);
  }

  @override
  void close({bool force = false}) {}
}

/// Answers every request with one canned body — the status-only cases whose
/// prose is empty.
class _RefusingAdapter implements HttpClientAdapter {
  _RefusingAdapter(this.respond);

  final ResponseBody Function() respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond();

  @override
  void close({bool force = false}) {}
}

void main() {
  late ApiClient client;
  late HttpClientAdapter original;
  late _TransfersAdapter adapter;

  setUpAll(() {
    // init() is NOT idempotent (dio is `late final`): once, then swap adapters.
    client = ApiClient.instance..init();
  });

  setUp(() => original = client.dio.httpClientAdapter);

  tearDown(() => client.dio.httpClientAdapter = original);

  _TransfersAdapter serve(List<Object> pages) {
    adapter = _TransfersAdapter(pages: pages);
    client.dio.httpClientAdapter = adapter;
    return adapter;
  }

  group('fetchAll', () {
    test('walks every page and reads the slip with its moves', () async {
      serve([
        _envelope([_slipJson(id: 1)], next: 'http://api.test$_path?page=2'),
        _envelope([_slipJson(id: 2, number: 'TR-20261112-0001')]),
      ]);

      final transfers = await StockTransferService(client: client).fetchAll();

      expect(adapter.requested, [
        '$_path?page=1',
        '$_path?page=2',
      ], reason: 'a transfer past row 50 must still be reachable');
      expect(transfers.map((row) => row.number), [
        'TR-20261113-0001',
        'TR-20261112-0001',
      ]);
      final line = transfers.first.lines.single;
      expect(line.unit, 'BAG');
      expect(line.qty, 2);
      expect(line.baseQty, 24);
      expect(line.label, 'Circuit Breaker · 20A 1-pole');
      expect(line.moves, hasLength(2));
      expect(line.moves.first.sourceBatchId, 5);
      expect(line.moves.last.destBatchId, 10);
      expect(transfers.first.routeLabel, 'Store → Bodega');
      expect(transfers.first.movedBaseQty, 24);
    });

    test('the server sentence is shown as sent', () async {
      client.dio.httpClientAdapter = _RefusingAdapter(
        () => _json({'detail': 'Forbidden.'}, status: 403),
      );

      await expectLater(
        StockTransferService(client: client).fetchAll(),
        throwsA(
          isA<StockTransferServiceException>().having(
            (error) => error.message,
            'message',
            'Forbidden.',
          ),
        ),
      );
    });

    test('a 403 with no prose still says who may move stock', () async {
      client.dio.httpClientAdapter = _RefusingAdapter(
        () => _json({'detail': ''}, status: 403),
      );

      await expectLater(
        StockTransferService(client: client).fetchAll(),
        throwsA(
          isA<StockTransferServiceException>().having(
            (error) => error.message,
            'message',
            contains('Only a Stock Manager, Store Manager or Admin'),
          ),
        ),
      );
    });
  });

  group('create', () {
    test('posts the selling unit and the typed amount', () async {
      serve([_slipJson(remarks: 'Shelf refill')]);

      final slip = await StockTransferService(client: client).create(
        const StockTransferRequest(
          fromLocationId: 1,
          toLocationId: 2,
          remarks: ' Shelf refill ',
          lines: [(variantUomId: 4, qty: 2)],
        ),
      );

      expect(slip.number, 'TR-20261113-0001');
      expect(adapter.sentBodies.single, {
        'from_location': 1,
        'to_location': 2,
        'remarks': 'Shelf refill',
        'lines': [
          {'variant_uom': 4, 'qty': 2.0},
        ],
      }, reason: 'the server converts; posting base units would convert twice');
    });

    test('a short shelf is the server sentence, code and shortfall', () async {
      serve([_slipJson()]);
      adapter.refusal = {
        'code': 'INSUFFICIENT_STOCK',
        'detail':
            'Not enough Portland cement at Store: 3.00 BAG short of the 5 BAG '
            'this line moves.',
        'shortfall': '3.00',
        'variant_id': 8,
      };

      await expectLater(
        StockTransferService(client: client).create(
          const StockTransferRequest(
            fromLocationId: 1,
            toLocationId: 2,
            lines: [(variantUomId: 4, qty: 5)],
          ),
        ),
        throwsA(
          isA<StockTransferServiceException>()
              .having((error) => error.code, 'code', 'INSUFFICIENT_STOCK')
              .having((error) => error.shortfall, 'shortfall', 3)
              .having(
                (error) => error.message,
                'message',
                contains('at Store'),
              ),
        ),
      );
    });

    test('a whole-unit refusal keeps its own code', () async {
      serve([_slipJson()]);
      adapter.refusal = {
        'code': 'WHOLE_UNIT_QUANTITY',
        'detail': '2.5 × BAG of Portland cement is not a whole BAG.',
      };

      await expectLater(
        StockTransferService(client: client).create(
          const StockTransferRequest(
            fromLocationId: 1,
            toLocationId: 2,
            lines: [(variantUomId: 4, qty: 2.5)],
          ),
        ),
        throwsA(
          isA<StockTransferServiceException>()
              .having((error) => error.code, 'code', 'WHOLE_UNIT_QUANTITY')
              .having(
                (error) => error.message,
                'message',
                contains('not a whole BAG'),
              ),
        ),
      );
    });

    test('a 405 says the slip is append-only', () async {
      client.dio.httpClientAdapter = _RefusingAdapter(
        () => _json({'detail': ''}, status: 405),
      );

      await expectLater(
        StockTransferService(client: client).create(
          const StockTransferRequest(
            fromLocationId: 1,
            toLocationId: 2,
            lines: [(variantUomId: 4, qty: 1)],
          ),
        ),
        throwsA(
          isA<StockTransferServiceException>().having(
            (error) => error.message,
            'message',
            contains('cannot be changed'),
          ),
        ),
      );
    });
  });
}
