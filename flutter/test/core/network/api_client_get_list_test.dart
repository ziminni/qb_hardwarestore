// `ApiClient.getList<T>` is the thin call that puts `parsePaged` on the wire.
//
// It is deliberately thin — the envelope logic lives in the pure `parsePaged`,
// which has its own tests — so these tests only prove the wiring: that the
// response goes through the decoder, that query parameters survive, and that a
// malformed envelope surfaces rather than being swallowed by the client.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class Category {
  const Category({required this.id, required this.name});
  final int id;
  final String name;
  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as int, name: json['name'] as String);
}

/// A Dio adapter that answers every request with a canned body and records the
/// requests it saw, so the test needs no server and no mocking package.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200});

  final String body;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String envelopeBody({
  int count = 2,
  List<Map<String, dynamic>>? results,
  String? next,
}) => jsonEncode({
  'count': count,
  'next': next,
  'previous': null,
      'results':
          results ??
          [
            {'id': 1, 'name': 'Cement'},
            {'id': 2, 'name': 'Electrical'},
          ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  late _FakeAdapter adapter;

  // `ApiClient.init()` assigns a `late final Dio dio`, so it is NOT idempotent —
  // calling it once per test throws `LateInitializationError` on the second
  // call. Initialise the singleton once here and swap only the adapter below.
  setUpAll(() {
    client = ApiClient.instance..init();
  });

  void useBody(String body, {int statusCode = 200}) {
    adapter = _FakeAdapter(body, statusCode: statusCode);
    client.dio.httpClientAdapter = adapter;
  }

  group('ApiClient.getList', () {
    test('returns the unwrapped page for a list endpoint', () async {
      useBody(envelopeBody());

      final page = await client.getList<Category>(
        '/api/v1/categories/',
        Category.fromJson,
      );

      expect(page.items, hasLength(2));
      expect(page.items.first.name, 'Cement');
      expect(page.total, 2);
      expect(adapter.requests.single.path, '/api/v1/categories/');
    });

    test('carries the page total through, not just the page size', () async {
      useBody(
        envelopeBody(
          count: 137,
          // A NON-final page: DRF sets `next` whenever another page exists,
          // and that link — not the row count — is what `hasMore` reports.
          next: 'http://example.test/api/v1/products/?page=2',
          results: [
            {'id': 1, 'name': 'Cement'},
          ],
        ),
      );

      final page = await client.getList<Category>(
        '/api/v1/products/',
        Category.fromJson,
      );

      expect(page.items, hasLength(1));
      expect(page.total, 137);
      expect(page.hasMore, isTrue);
    });

    test('passes query parameters to the endpoint', () async {
      useBody(envelopeBody());

      await client.getList<Category>(
        '/api/v1/products/',
        Category.fromJson,
        queryParameters: {'page': 2, 'search': 'cement'},
      );

      expect(adapter.requests.single.queryParameters, {
        'page': 2,
        'search': 'cement',
      });
    });

    test(
      'surfaces a malformed envelope instead of returning an empty list',
      () async {
        // A 200 carrying the wrong shape must not read as "no results".
        useBody(jsonEncode({'count': 2}));

        expect(
          () =>
              client.getList<Category>('/api/v1/products/', Category.fromJson),
          throwsFormatException,
        );
      },
    );

    test('a non-list body (a detail endpoint) is a loud failure', () async {
      useBody(jsonEncode({'id': 1, 'name': 'Cement'}));

      expect(
        () => client.getList<Category>(
          '/api/v1/categories/1/',
          Category.fromJson,
        ),
        throwsFormatException,
      );
    });
  });
}
