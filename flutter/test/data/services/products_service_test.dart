// Phase 1 (decision 12): the products catalogue's live data comes from exactly
// two list endpoints, and the DRF envelope is unwrapped by `parsePaged` ONLY
// (decision 03). The lost `PosService` (commit 22c7c26) hand-rolled
// `data['results']`; that must NOT come back, and one test below exists purely
// to prove it has not.
//
// The payloads are trimmed copies of REAL responses captured from the live API
// on 2026-10-16 (`/api/v1/products/` count 6, `/api/v1/batches/` count 8), so
// this file fails if the client and the server ever disagree about the shape.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/products_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _productsPath = '/api/v1/products/';
const _batchesPath = '/api/v1/batches/';

Map<String, dynamic> _variant({int id = 8, String price = '315.00'}) => {
  'id': id,
  'product': 6,
  'variant_name': '20A 1-pole',
  'base_uom': 2,
  'base_uom_code': 'PC',
  'min_stock_threshold': '5.00',
  'max_stock_level': '0.00',
  'is_active': true,
  'selling_uoms': [
    {
      'id': 8,
      'variant': id,
      'uom': 2,
      'uom_code': 'PC',
      'uom_name': 'Piece',
      'barcode_qr': '',
      'conversion_factor': '1.00',
      'default_selling_price': price,
    },
  ],
  'created_at': '2026-09-25T16:24:33.630104+08:00',
  'updated_at': '2026-09-25T16:24:33.630104+08:00',
};

Map<String, dynamic> _product({
  int id = 6,
  List<Map<String, dynamic>>? variants,
}) => {
  'id': id,
  'category': 1,
  'category_name': 'Electrical',
  'brand': 1,
  'brand_name': 'Omni',
  'base_name': 'Circuit Breaker',
  'description': '',
  'image_url': '',
  'is_active': true,
  'variants': variants ?? [_variant()],
  'created_at': '2026-09-25T16:24:33.630104+08:00',
  'updated_at': '2026-09-25T16:24:33.630104+08:00',
};

Map<String, dynamic> _batch({
  int variantId = 8,
  String currentQty = '100.00',
}) => {
  'id': 6,
  'variant': variantId,
  'receipt': 6,
  'initial_qty': '100.00',
  'current_qty': currentQty,
  'unit_cost_landed': '180.00',
  'markup_percentage': '0.00',
  'batch_selling_price': '180.00',
  'expiration_date': null,
  'created_at': '2026-09-25T16:24:33.630104+08:00',
};

const _variantUomsPath = '/api/v1/variant-uoms/';

/// One `GET /variant-uoms/?barcode=` row, shaped exactly like
/// `VariantUOMSerializer` (verified against the committed backend).
Map<String, dynamic> _variantUomRow({
  bool variantIsActive = false,
  bool productIsActive = true,
}) => {
  'id': 13,
  'variant': 8,
  'uom': 2,
  'uom_code': 'PC',
  'uom_name': 'Piece',
  'product_name': 'Circuit Breaker',
  'variant_name': '20A 1-pole',
  'product_is_active': productIsActive,
  'variant_is_active': variantIsActive,
  'barcode_qr': 'QB000013-0',
  'conversion_factor': '1.00',
  'default_selling_price': '315.00',
};

/// A real DRF list envelope.
Map<String, dynamic> _envelope(List<Map<String, dynamic>> results) => {
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

/// Answers each path with its own body and records what was asked for.
class _PathFakeAdapter implements HttpClientAdapter {
  _PathFakeAdapter(this.bodies, {this.statusCode = 200});

  /// path -> json-encodable body. A missing path answers 404.
  final Map<String, Object?> bodies;
  final int statusCode;
  final List<String> requested = [];

  /// The query string of every request, so a test can assert that a filtered
  /// call really asked the server to filter.
  final List<Map<String, dynamic>> requestedQueries = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);
    requestedQueries.add(options.queryParameters);
    if (!bodies.containsKey(options.path)) {
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(bodies[options.path]),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Answers each path with a LIST of page bodies, chosen by the `page` query
/// parameter — the shape DRF produces when a list is longer than `PAGE_SIZE`.
class _PagedFakeAdapter implements HttpClientAdapter {
  _PagedFakeAdapter(this.pages);

  /// path -> page bodies, in order (index 0 is page 1).
  final Map<String, List<Map<String, dynamic>>> pages;
  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = int.tryParse('${options.queryParameters['page'] ?? 1}') ?? 1;
    requested.add('${options.path}?page=$page');
    final bodies = pages[options.path];
    if (bodies == null || page > bodies.length) {
      return ResponseBody.fromString(
        '{"detail":"invalid page"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(bodies[page - 1]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An envelope whose `next` link is set (or not) — the ONLY signal
/// `parsePaged` uses to decide another page follows.
Map<String, dynamic> _page(
  List<Map<String, dynamic>> results, {
  required int count,
  required bool hasNext,
}) => {
  'count': count,
  'next': hasNext ? 'http://test/api?page=2' : null,
  'previous': null,
  'results': results,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  // `ApiClient.init()` assigns a `late final dio`, so it is NOT idempotent —
  // initialise the singleton once and swap only its adapter.
  setUpAll(() => client = ApiClient.instance..init());

  late _PathFakeAdapter adapter;

  void useBodies(Map<String, Object?> bodies, {int statusCode = 200}) {
    adapter = _PathFakeAdapter(bodies, statusCode: statusCode);
    client.dio.httpClientAdapter = adapter;
  }

  ProductsService service() => ProductsService(client: client);

  group('ProductsService.fetchCatalogue', () {
    test('loads products and batches from their two list endpoints', () async {
      useBodies({
        _productsPath: _envelope([_product()]),
        _batchesPath: _envelope([_batch()]),
      });

      final snapshot = await service().fetchCatalogue();

      expect(snapshot.products, hasLength(1));
      expect(snapshot.products.single.baseName, 'Circuit Breaker');
      // The nested variant and its selling unit must survive the parse, because
      // the catalogue's price and barcode come from them (decisions 08 and 10).
      expect(snapshot.products.single.variants, hasLength(1));
      expect(
        snapshot
            .products
            .single
            .variants
            .single
            .sellingUoms
            .single
            .defaultSellingPrice,
        315.0,
      );

      expect(snapshot.batches, hasLength(1));
      expect(snapshot.batches.single.currentQty, 100.0);
      expect(snapshot.batches.single.variantId, 8);

      expect(adapter.requested, containsAll([_productsPath, _batchesPath]));
    });

    test(
      'uses parsePaged, so a body with no results list fails loudly',
      () async {
        // This is the anti-regression test for decision 03. The lost PosService
        // read `data['results']` by hand, which turns a contract break into a
        // silently EMPTY catalogue. `parsePaged` throws instead, and that is the
        // behaviour worth protecting.
        //
        // What the throw reaches the screen AS changed with F1: it is a
        // ProductsServiceException carrying the parse message, not a raw
        // FormatException the viewmodel never caught (which left `loadError`
        // null and the empty catalogue rendering as "no products yet").
        useBodies({
          _productsPath: {'count': 1, 'next': null, 'previous': null},
          _batchesPath: _envelope([_batch()]),
        });

        await expectLater(
          service().fetchCatalogue(),
          throwsA(
            isA<ProductsServiceException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('could not be loaded'),
                contains('results'),
                isNot(contains('FormatException')),
              ),
            ),
          ),
        );
      },
    );

    test(
      'rejects a count that is not numeric rather than guessing it',
      () async {
        useBodies({
          _productsPath: {
            'count': 'six',
            'next': null,
            'previous': null,
            'results': [_product()],
          },
          _batchesPath: _envelope([_batch()]),
        });

        await expectLater(
          service().fetchCatalogue(),
          throwsA(isA<ProductsServiceException>()),
        );
      },
    );

    test(
      'a row that does not match its model is an error, not a short list',
      () async {
        // `Product.fromJson` casts `id` with `as int`; a drifted row throws a
        // TypeError. Nothing used to catch it, so the fetch crashed past the
        // service and the screen showed an empty catalogue with no retry.
        useBodies({
          _productsPath: _envelope([
            {'base_name': 'Circuit Breaker', 'variants': const []},
          ]),
          _batchesPath: _envelope([_batch()]),
        });

        await expectLater(
          service().fetchCatalogue(),
          throwsA(
            isA<ProductsServiceException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('could not be loaded'),
                isNot(contains('TypeError')),
              ),
            ),
          ),
        );
      },
    );

    test('reports a failed request as ProductsServiceException', () async {
      useBodies({}, statusCode: 500);

      await expectLater(
        service().fetchCatalogue(),
        throwsA(isA<ProductsServiceException>()),
      );
    });

    test('walks every page, so product and batch #51 load', () async {
      // F5: one page is PAGE_SIZE (50) rows. Reading only the first page made
      // product #51 unsearchable and unscannable at the till, and batch #51's
      // quantity simply missing from every stock figure. The stub below answers
      // exactly like DRF: `next` set on page 1, null on page 2.
      final pageOneProducts = [
        for (var id = 1; id <= 50; id++) _product(id: id),
      ];
      final pageOneBatches = [
        for (var id = 1; id <= 50; id++) _batch(variantId: id),
      ];
      final adapter = _PagedFakeAdapter({
        _productsPath: [
          _page(pageOneProducts, count: 51, hasNext: true),
          _page([_product(id: 51)], count: 51, hasNext: false),
        ],
        _batchesPath: [
          _page(pageOneBatches, count: 51, hasNext: true),
          _page([_batch(variantId: 51)], count: 51, hasNext: false),
        ],
      });
      client.dio.httpClientAdapter = adapter;

      final snapshot = await service().fetchCatalogue();

      expect(snapshot.products, hasLength(51));
      expect(snapshot.products.last.id, 51);
      expect(snapshot.batches, hasLength(51));
      expect(snapshot.batches.last.variantId, 51);
      expect(adapter.requested, contains('$_productsPath?page=2'));
      expect(adapter.requested, contains('$_batchesPath?page=2'));
    });
  });

  group('ProductsService.lookupByBarcode', () {
    test('asks for the normalised code on the selling-unit endpoint', () async {
      // Decision 13: the server compares `Upper(barcode_qr)`, so the client must
      // send the same normalised text — a scanner's ` qb000013-0 ` has to find
      // the stored `QB000013-0`.
      useBodies({_variantUomsPath: _envelope([_variantUomRow()])});

      await service().lookupByBarcode('  qb000013-0 ');

      expect(adapter.requested, [_variantUomsPath]);
      expect(adapter.requestedQueries.single['barcode'], 'QB000013-0');
    });

    test('returns the unit plus why the server thinks it is unsellable', () async {
      useBodies({_variantUomsPath: _envelope([_variantUomRow()])});

      final rows = await service().lookupByBarcode('QB000013-0');

      final row = rows.single;
      expect(row.id, 13);
      expect(row.barcodeQr, 'QB000013-0');
      expect(row.productName, 'Circuit Breaker');
      expect(row.variantName, '20A 1-pole');
      expect(row.variantIsActive, isFalse);
      expect(row.productIsActive, isTrue);
    });

    test('an unknown code is an empty list, not a failure', () async {
      useBodies({_variantUomsPath: _envelope(const [])});

      expect(await service().lookupByBarcode('QB999999-9'), isEmpty);
    });

    test('a failed lookup is a ProductsServiceException', () async {
      useBodies({}, statusCode: 500);

      await expectLater(
        service().lookupByBarcode('QB000013-0'),
        throwsA(isA<ProductsServiceException>()),
      );
    });
  });
}
