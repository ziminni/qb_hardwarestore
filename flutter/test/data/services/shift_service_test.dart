import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shift WIRE contract (decision 06).
///
/// The one behaviour that must not drift: **404 means "no open shift" and every
/// other failure is an error.** The POS shell keys its gate off that difference,
/// so folding a 500 into null would tell a cashier with a live shift that they
/// have none.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  HttpClientAdapter? replaced;

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
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _shiftJson({
  int id = 1,
  String status = 'OPEN',
  String openingFloat = '5000.00',
  String? closingCount,
  Map<String, dynamic>? zReading,
}) => {
  'id': id,
  'cashier': 3,
  'cashier_name': 'Ana Cruz',
  'status': status,
  'opening_float': openingFloat,
  'closing_count': closingCount,
  'opened_at': '2026-10-21T08:00:00Z',
  'closed_at': status == 'CLOSED' ? '2026-10-21T17:00:00Z' : null,
  'notes': '',
  'z_reading': zReading,
};

void main() {
  late ApiClient client;
  late _FakeAdapter adapter;

  // init() is NOT idempotent - dio is `late final`, so a second call throws.
  // setUpAll initialises once and each test swaps only the adapter.
  setUpAll(() {
    client = ApiClient.instance..init();
  });

  void serve(ResponseBody Function(RequestOptions options) respond) {
    adapter = _FakeAdapter(respond);
    adapter.replaced = client.dio.httpClientAdapter;
    client.dio.httpClientAdapter = adapter;
  }

  tearDown(() {
    if (adapter.replaced != null) {
      client.dio.httpClientAdapter = adapter.replaced!;
    }
  });

  test('an open shift is parsed with its float', () async {
    serve((_) => _json(_shiftJson()));

    final shift = await ShiftService(client: client).fetchCurrent();

    expect(shift?.id, 1);
    expect(shift?.cashierName, 'Ana Cruz');
    expect(shift?.openingFloat, 5000);
    expect(shift?.isOpen, isTrue);
    expect(shift?.closingCount, isNull);
    expect(shift?.zReading, isNull);
  });

  test('404 is null, not an error', () async {
    serve((_) => _json({'detail': 'No open shift for this cashier.'}, status: 404));

    final shift = await ShiftService(client: client).fetchCurrent();

    expect(shift, isNull);
  });

  test('a 500 is an error, never null', () async {
    serve((_) => _json({'detail': 'boom'}, status: 500));

    await expectLater(
      ShiftService(client: client).fetchCurrent(),
      throwsA(isA<ShiftServiceException>()),
    );
  });

  test('opening posts the float as money', () async {
    Object? sentBody;
    String? sentPath;
    serve((options) {
      sentPath = options.path;
      // Dio may hand the adapter either the encoded JSON or the map.
      final data = options.data;
      sentBody = data is String ? jsonDecode(data) : data;
      return _json(_shiftJson(), status: 201);
    });

    await ShiftService(client: client).openShift(5000);

    expect(sentPath, '/api/v1/shifts/open/');
    expect(
      (sentBody as Map)['opening_float'],
      '5000.00',
      reason: 'money goes as a two-decimal STRING, never a float',
    );
  });

  test('closing posts the count to the shift id and reads the Z-reading', () async {
    String? sentPath;
    serve((options) {
      sentPath = options.path;
      return _json(
        _shiftJson(
          status: 'CLOSED',
          closingCount: '9350.00',
          zReading: {
            'shift_id': 1,
            'opening_float': '5000.00',
            'closing_count': '9350.00',
            'transaction_count': 12,
            'gross_sales': '8400.00',
            'vat': '0.00',
            'discounts': '0.00',
            'cash_sales': '4400.00',
            'card_sales': '2500.00',
            'gcash_sales': '1500.00',
            'bank_sales': '0.00',
            'cash_refunds': '0.00',
            'expected_drawer': '9400.00',
            'variance': '-50.00',
          },
        ),
      );
    });

    final closed = await ShiftService(client: client).closeShift(1, 9350);

    expect(sentPath, '/api/v1/shifts/1/close/');
    final reading = closed.zReading;
    expect(reading, isNotNull);
    expect(reading!.transactionCount, 12);
    expect(reading.grossSales, 8400);
    expect(reading.cashSales, 4400);
    expect(reading.cardSales, 2500);
    expect(reading.gcashSales, 1500);
    expect(reading.expectedDrawer, 9400);
    expect(reading.variance, -50);
    expect(closed.isOpen, isFalse);
  });

  test('an open shift\'s z_reading parses with a null variance', () async {
    serve(
      (_) => _json(
        _shiftJson(
          zReading: {
            'shift_id': 1,
            'opening_float': '5000.00',
            'closing_count': null,
            'transaction_count': 0,
            'gross_sales': '0.00',
            'vat': '0.00',
            'discounts': '0.00',
            'cash_sales': '0.00',
            'card_sales': '0.00',
            'gcash_sales': '0.00',
            'bank_sales': '0.00',
            'cash_refunds': '0.00',
            'expected_drawer': '5000.00',
            'variance': null,
          },
        ),
      ),
    );

    final shift = await ShiftService(client: client).fetchCurrent();

    expect(shift?.zReading?.variance, isNull);
    expect(shift?.zReading?.expectedDrawer, 5000);
  });

  test('the history follows the pages', () async {
    var pages = <String>[];
    serve((options) {
      pages.add('${options.queryParameters['page']}');
      final page = options.queryParameters['page'];
      return _json({
        'count': 2,
        'next': page == 1 ? 'http://x/api/v1/shifts/?page=2' : null,
        'results': [
          page == 1
              ? _shiftJson(id: 1, status: 'CLOSED')
              : _shiftJson(id: 2),
        ],
      });
    });

    final shifts = await ShiftService(client: client).fetchAll();

    expect(shifts.map((shift) => shift.id), [1, 2]);
    expect(pages, ['1', '2']);
  });

  test('a shift with no cashier_name fails loudly instead of rendering blank', () {
    expect(
      () => Shift.fromJson({..._shiftJson()}..remove('cashier_name')),
      throwsA(isA<FormatException>()),
    );
  });
}
