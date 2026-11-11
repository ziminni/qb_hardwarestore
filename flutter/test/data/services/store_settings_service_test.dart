// Phase 4 Task F3a: the client half of B1's store settings endpoints.
//
//   GET   /api/v1/store-settings/   any authenticated user
//   PATCH /api/v1/store-settings/   Admin only (403 otherwise), 400 field errors
//
// Every percent comes back as a STRING ("12.00") because DRF serializes Decimals
// that way, and goes back as a 2 dp string for the same reason: a double can
// serialize as 11.999999999999998 and store a rate nobody typed.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/services/store_settings_service.dart';
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
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _wire = {
  'vat_registered': true,
  'vat_rate': '12.00',
  'discount_cap_percent': '10.00',
  'updated_at': '2026-11-11T09:12:00Z',
};

void main() {
  late _FakeAdapter adapter;
  late StoreSettingsService service;
  RequestOptions? lastRequest;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    lastRequest = null;
    adapter = _FakeAdapter((options) {
      lastRequest = options;
      return _json(_wire);
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = StoreSettingsService();
  });

  test('fetch reads the singleton from the store settings path', () async {
    final settings = await service.fetch();

    expect(lastRequest?.method, 'GET');
    expect(lastRequest?.path, '/api/v1/store-settings/');
    expect(settings.vatRegistered, isTrue);
    expect(settings.vatRate, 12);
    expect(settings.discountCapPercent, 10);
  });

  test('save PATCHes the same path with 2 dp strings', () async {
    await service.save(
      const StoreSettings(
        vatRegistered: false,
        vatRate: 0,
        discountCapPercent: 15.5,
      ),
    );

    expect(lastRequest?.method, 'PATCH');
    expect(lastRequest?.path, '/api/v1/store-settings/');
    expect(lastRequest?.data, {
      'vat_registered': false,
      'vat_rate': '0.00',
      'discount_cap_percent': '15.50',
    });
  });

  test('save returns what the server stored', () async {
    adapter.respond = (_) => _json({
      'vat_registered': false,
      'vat_rate': '0.00',
      'discount_cap_percent': '20.00',
      'updated_at': '2026-11-11T10:00:00Z',
    });

    final saved = await service.save(
      const StoreSettings(
        vatRegistered: true,
        vatRate: 12,
        discountCapPercent: 10,
      ),
    );

    expect(saved.vatRegistered, isFalse);
    expect(saved.discountCapPercent, 20);
  });

  // The server owns the Admin boundary. A Store Manager who reaches the PATCH
  // must read a sentence that says what to do next, not a bare 403.
  test('a 403 names the admin boundary', () async {
    adapter.respond = (_) => _json({
      'detail': 'Only an Admin may change store settings.',
      'code': 'STORE_SETTINGS_FORBIDDEN',
    }, status: 403);

    await expectLater(
      service.save(
        const StoreSettings(
          vatRegistered: true,
          vatRate: 12,
          discountCapPercent: 10,
        ),
      ),
      throwsA(
        isA<StoreSettingsException>()
            .having(
              (error) => error.message,
              'message',
              contains('Only an Admin'),
            )
            .having((error) => error.isForbidden, 'isForbidden', isTrue),
      ),
    );
  });

  test('a 400 keeps the field sentence from the server', () async {
    adapter.respond = (_) => _json({
      'vat_rate': ['Ensure this value is less than or equal to 100.'],
    }, status: 400);

    await expectLater(
      service.save(
        const StoreSettings(
          vatRegistered: true,
          vatRate: 120,
          discountCapPercent: 10,
        ),
      ),
      throwsA(
        isA<StoreSettingsException>()
            .having(
              (error) => error.message,
              'message',
              contains('less than or equal to 100'),
            )
            .having(
              (error) => error.fieldErrors['vat_rate'],
              'vat_rate error',
              contains('less than or equal to 100'),
            ),
      ),
    );
  });

  test('a refused load says the server is unreachable', () async {
    adapter.respond = (_) => throw DioException.connectionError(
      requestOptions: RequestOptions(path: StoreSettingsService.path),
      reason: 'down',
    );

    await expectLater(
      service.fetch(),
      throwsA(
        isA<StoreSettingsException>().having(
          (error) => error.message,
          'message',
          'Cannot connect to the BuildPro server.',
        ),
      ),
    );
  });
}
