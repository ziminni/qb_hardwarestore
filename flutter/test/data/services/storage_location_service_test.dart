// Phase 5 F4 (decision 18): the storage-location service and its refusals.
//
// The list is walked page by page, because a shop with more than fifty places
// would otherwise hide the rest from the product picker. A refusal is the
// SERVER's sentence when it names the place, and the fixed sentence only for the
// codes that carry no detail of their own.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/storage_location_service.dart';
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

Map<String, dynamic> _envelope(
  List<Map<String, dynamic>> results, {
  String? next,
}) => {
  'count': results.length,
  'next': next,
  'previous': null,
  'results': results,
};

Map<String, dynamic> _row({int id = 1, String name = 'Store'}) => {
  'id': id,
  'name': name,
  'is_active': true,
};

void main() {
  late _FakeAdapter adapter;
  late StorageLocationService service;

  setUpAll(() => ApiClient.instance.init());

  setUp(() {
    adapter = _FakeAdapter((_) => _json(_envelope(const [])));
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = StorageLocationService();
  });

  test('the list walks every page so a full shop still appears', () async {
    adapter.respond = (options) {
      final page = options.queryParameters['page'];
      return page == 1
          ? _json(
              _envelope([
                _row(id: 1, name: 'Bodega'),
              ], next: 'http://test/api/v1/storage-locations/?page=2'),
            )
          : _jsonEnvelopePageTwo();
    };

    final rows = await service.fetchAll();

    expect(rows.map((row) => row.name), ['Bodega', 'Store']);
    expect(
      adapter.requests.map((request) => request.queryParameters).toList(),
      [
        {'page': 1},
        {'page': 2},
      ],
    );
  });

  test('create POSTs the name only', () async {
    adapter.respond = (_) => _json(_row(id: 3, name: 'Yard'), status: 201);

    await service.create('Yard');

    expect(adapter.requests.single.path, '/api/v1/storage-locations/');
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.data, {'name': 'Yard'});
  });

  test('patch sends ONLY the field it is changing', () async {
    adapter.respond = (_) => _json(_row(id: 2, name: 'Bodega'));

    await service.patch(2, isActive: false);

    expect(adapter.requests.single.path, '/api/v1/storage-locations/2/');
    expect(adapter.requests.single.method, 'PATCH');
    expect(adapter.requests.single.data, {'is_active': false});
  });

  test('a rename leaves is_active out of the body', () async {
    adapter.respond = (_) => _json(_row(id: 2, name: 'Warehouse'));

    await service.patch(2, name: 'Warehouse');

    expect(adapter.requests.single.data, {'name': 'Warehouse'});
  });

  group('refusals', () {
    Future<String> refusal(int status, Object body) async {
      adapter.respond = (_) => _json(body, status: status);
      try {
        await service.create('Yard');
      } on StorageLocationServiceException catch (error) {
        return error.message;
      }
      fail('the refusal should have thrown');
    }

    test(
      'the server detail names the place on INVALID_STORAGE_LOCATION',
      () async {
        // The code map cannot know WHICH location the clerk chose; the server can.
        final message = await refusal(400, {
          'code': 'INVALID_STORAGE_LOCATION',
          'detail':
              '"Bodega" is not an active storage location: pick one that is in '
              'the list, or have an Admin restore it.',
        });

        expect(
          message,
          startsWith('"Bodega" is not an active storage location'),
        );
      },
    );

    test('the code alone still explains the assignment rule', () async {
      final message = await refusal(400, {'code': 'INVALID_STORAGE_LOCATION'});

      expect(message, contains('pick an active one'));
    });

    test('a duplicate name arrives as the DRF field sentence', () async {
      final message = await refusal(400, {
        'name': ['storage location with this name already exists.'],
      });

      expect(message, contains('already exists'));
    });

    test('403 says only an Admin may change the list', () async {
      final message = await refusal(403, {'detail': ''});

      expect(message, contains('Only an Admin'));
    });

    test('405 says deactivate rather than delete', () async {
      final message = await refusal(405, {'detail': ''});

      expect(message, contains('deactivate'));
    });

    test('404 says the row is gone and to reload', () async {
      final message = await refusal(404, {'detail': ''});

      expect(message, contains('no longer exists'));
    });
  });
}

ResponseBody _jsonEnvelopePageTwo() =>
    _json(_envelope([_row(id: 4, name: 'Store')]));
