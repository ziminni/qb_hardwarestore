// Phase 3 Task F2: the preview call.
//
// The wire is fixed by B1 (`POST /api/v1/catalogue-import/preview/` with
// `{rows: [...]}`, answering creates, changes, unchanged, errors and a
// fingerprint) and by `catalogue_import.COLUMNS` on the server, so the request
// path, the body key and the answer's shape are pinned here against a payload
// trimmed from the real response.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/catalogue_import_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned body, recording what was asked.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200, this.failure});

  final Object body;
  final int statusCode;

  /// Set to fail the way the transport does, before any response exists.
  final DioExceptionType? failure;
  RequestOptions? lastRequest;
  HttpClientAdapter? replaced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (failure case final type?) {
      throw DioException(requestOptions: options, type: type);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> previewBody() => {
  'creates': {'products': 1, 'variants': 2, 'units': 3},
  'changes': [
    {'row': 2, 'field': 'Price', 'before': '315.00', 'after': '320.00'},
    {'row': 4, 'field': 'Barcode', 'before': 'QB1', 'after': 'QB2'},
  ],
  'unchanged': 7,
  'errors': [
    {
      'row': 5,
      'column': 'Category',
      'code': 'UNKNOWN_CATEGORY',
      'message': 'Category "Limitless" is not on the list.',
    },
  ],
  'fingerprint': 'a1b2c3',
};

void main() {
  late ApiClient client;
  late CatalogueImportService service;
  _FakeAdapter? adapter;

  setUpAll(() {
    // The house pattern: `init()` is not idempotent, so it runs exactly once.
    client = ApiClient.instance..init();
  });

  setUp(() {
    service = CatalogueImportService(client: client);
  });

  tearDown(() {
    final previous = adapter?.replaced;
    if (previous != null) client.dio.httpClientAdapter = previous;
  });

  void serve(Object body, {int status = 200, DioExceptionType? failure}) {
    final fake = _FakeAdapter(body, statusCode: status, failure: failure)
      ..replaced = client.dio.httpClientAdapter;
    adapter = fake;
    client.dio.httpClientAdapter = fake;
  }

  test('posts the rows to the preview endpoint', () async {
    serve(previewBody());

    await service.preview([
      {'product_id': '6', 'price': '315', 'barcode': '0012345678905'},
      {'product_id': '', 'product_name': '=SUM(A1)'},
    ]);

    final request = adapter!.lastRequest!;
    expect(request.path, '/api/v1/catalogue-import/preview/');
    expect(request.method, 'POST');
    expect(request.data, {
      'rows': [
        {'product_id': '6', 'price': '315', 'barcode': '0012345678905'},
        {'product_id': '', 'product_name': '=SUM(A1)'},
      ],
    });
  });

  test('reads the whole answer back', () async {
    serve(previewBody());

    final preview = await service.preview(const []);

    expect(preview.creates.products, 1);
    expect(preview.creates.variants, 2);
    expect(preview.creates.units, 3);
    expect(preview.unchanged, 7);
    expect(preview.fingerprint, 'a1b2c3');
    expect(preview.changes, hasLength(2));
    expect(preview.changes.first.row, 2);
    expect(preview.changes.first.field, 'Price');
    expect(preview.changes.first.before, '315.00');
    expect(preview.changes.first.after, '320.00');
    expect(preview.errors.single.row, 5);
    expect(preview.errors.single.column, 'Category');
    expect(preview.errors.single.code, 'UNKNOWN_CATEGORY');
    expect(preview.hasErrors, isTrue);
  });

  test('a clean preview has no errors and can be applied', () async {
    serve({...previewBody(), 'errors': const []});

    final preview = await service.preview(const []);

    expect(preview.hasErrors, isFalse);
    expect(preview.changes, hasLength(2));
  });

  test('a stale preview says to run it again', () async {
    serve({
      'code': 'CATALOGUE_PREVIEW_STALE',
      'detail': 'The catalogue changed since the preview.',
    }, status: 409);

    await expectLater(
      service.preview(const []),
      throwsA(
        isA<CatalogueImportServiceException>().having(
          (failure) => failure.message,
          'message',
          'Run the preview again',
        ),
      ),
    );
  });

  test(
    'the too-large refusal keeps the server wording, which says what to do',
    () async {
      serve({
        'code': 'CATALOGUE_IMPORT_TOO_LARGE',
        'detail':
            '2,500 rows is more than the 2,000 rows one import accepts: split the '
            'sheet into files of at most 2,000 rows and import them one at a time.',
      }, status: 400);

      await expectLater(
        service.preview(const []),
        throwsA(
          isA<CatalogueImportServiceException>().having(
            (failure) => failure.message,
            'message',
            contains('split the sheet'),
          ),
        ),
      );
    },
  );

  test('an unknown code still shows the server detail', () async {
    serve({
      'code': 'SOMETHING_NEW',
      'detail': 'The Unit code column must hold an existing code.',
    }, status: 400);

    await expectLater(
      service.preview(const []),
      throwsA(
        isA<CatalogueImportServiceException>().having(
          (failure) => failure.message,
          'message',
          'The Unit code column must hold an existing code.',
        ),
      ),
    );
  });

  test('a refused role is worded for the clerk', () async {
    serve({'detail': 'You do not have permission.'}, status: 403);

    await expectLater(
      service.preview(const []),
      throwsA(
        isA<CatalogueImportServiceException>().having(
          (failure) => failure.message,
          'message',
          contains('stock manager'),
        ),
      ),
    );
  });

  // -------------------------------------------------------------------
  // The apply (B2): `{rows, fingerprint}` in, the counts it wrote out.
  // -------------------------------------------------------------------

  Map<String, dynamic> appliedBody() => {
    'creates': {'products': 1, 'variants': 0, 'units': 1},
    'updates': {'products': 0, 'variants': 1, 'units': 2},
    'unchanged': 3,
    'summary':
        'Catalogue import applied: 1 product and 1 selling unit created; 1 '
        'variant and 2 selling units updated; 3 rows unchanged.',
  };

  test('the apply posts the rows and the preview fingerprint', () async {
    serve(appliedBody());

    await service.apply(const [
      {'product_id': '6', 'price': '315'},
    ], 'a1b2c3');

    final request = adapter!.lastRequest!;
    expect(request.path, '/api/v1/catalogue-import/apply/');
    expect(request.method, 'POST');
    expect(request.data, {
      'rows': [
        {'product_id': '6', 'price': '315'},
      ],
      'fingerprint': 'a1b2c3',
    });
  });

  test('the apply reads the counts and the summary back', () async {
    serve(appliedBody());

    final applied = await service.apply(const [], 'a1b2c3');

    expect(applied.creates.products, 1);
    expect(applied.creates.units, 1);
    expect(applied.updates.variants, 1);
    expect(applied.updates.units, 2);
    expect(applied.unchanged, 3);
    expect(
      applied.summary,
      startsWith('Catalogue import applied: 1 product and 1 selling unit'),
    );
  });

  test(
    'a catalogue that moved under the apply is stale, not unknown',
    () async {
      serve({
        'code': 'CATALOGUE_PREVIEW_STALE',
        'detail': 'Run the preview again',
      }, status: 409);

      await expectLater(
        service.apply(const [], 'a1b2c3'),
        throwsA(
          isA<CatalogueImportServiceException>()
              .having((failure) => failure.isStale, 'isStale', isTrue)
              .having(
                (failure) => failure.message,
                'message',
                CatalogueImportService.staleMessage,
              ),
        ),
      );
    },
  );

  test('row errors from the apply come back in the preview shape', () async {
    serve({
      'code': 'CATALOGUE_IMPORT_ROW_ERRORS',
      'detail':
          'The catalogue import was not applied: 1 row still has an '
          'error.',
      'errors': [
        {
          'row': 2,
          'column': 'Barcode',
          'code': 'BARCODE_TAKEN',
          'message': 'Barcode "QB000013-0" is already on another selling unit.',
        },
      ],
    }, status: 400);

    await expectLater(
      service.apply(const [], 'a1b2c3'),
      throwsA(
        isA<CatalogueImportServiceException>()
            .having((failure) => failure.isStale, 'isStale', isFalse)
            .having((failure) => failure.errors, 'errors', hasLength(1))
            .having((failure) => failure.errors.single.row, 'row', 2)
            .having(
              (failure) => failure.errors.single.column,
              'column',
              'Barcode',
            )
            .having(
              (failure) => failure.errors.single.code,
              'code',
              'BARCODE_TAKEN',
            ),
      ),
    );
  });

  test('a barcode taken after the preview shows the server detail', () async {
    serve({
      'code': 'BARCODE_TAKEN',
      'detail':
          'Another selling unit already carries this barcode: choose a '
          'different code for row 2.',
    }, status: 400);

    await expectLater(
      service.apply(const [], 'a1b2c3'),
      throwsA(
        isA<CatalogueImportServiceException>()
            .having((failure) => failure.errors, 'errors', isEmpty)
            .having(
              (failure) => failure.message,
              'message',
              contains('Another selling unit already carries this barcode'),
            ),
      ),
    );
  });

  test(
    'a network failure during the apply says so, and claims nothing',
    () async {
      serve(const {}, failure: DioExceptionType.connectionError);

      await expectLater(
        service.apply(const [], 'a1b2c3'),
        throwsA(
          isA<CatalogueImportServiceException>()
              .having((failure) => failure.isStale, 'isStale', isFalse)
              .having((failure) => failure.errors, 'errors', isEmpty)
              .having(
                (failure) => failure.message,
                'message',
                contains('Cannot connect to the BuildPro server'),
              ),
        ),
      );
    },
  );
}
