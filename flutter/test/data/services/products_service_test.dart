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

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.path);
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
        useBodies({
          _productsPath: {'count': 1, 'next': null, 'previous': null},
          _batchesPath: _envelope([_batch()]),
        });

        await expectLater(
          service().fetchCatalogue(),
          throwsA(isA<FormatException>()),
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
          throwsA(isA<FormatException>()),
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
  });
}
