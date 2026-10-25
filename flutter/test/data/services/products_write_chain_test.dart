// Phase 4 Task 4 — the product write chain, asserted at the WIRE.
//
// "Add product" is three POSTs (product → variant → factor-1 selling unit) and
// they only work if each one carries the id the previous response returned. A
// repository test with a stubbed repository cannot see that: it would pass even if
// the client posted `product: null`. So these tests drive the real
// `ProductsRepository` → `ProductsService` → `ApiClient` stack against a fake
// HTTP adapter and assert the ORDER of the requests, the BODIES, and the ids
// threaded between them.
//
// The refusals are asserted too, because each server code is mapped to a sentence
// a clerk can act on — a raw `{"code": "SELLING_UNIT_IN_USE"}` on screen is not.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request in order and answers by path.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.bodies = const {},
    this.statusCode = 201,
    this.statusCodes = const {},
  });

  /// path -> body. A missing path answers 404 with a `detail`.
  final Map<String, Object?> bodies;
  final int statusCode;

  /// path -> status, for when one step succeeds and the next is refused.
  final Map<String, int> statusCodes;

  final List<String> paths = [];
  final List<String> methods = [];
  final List<Map<String, dynamic>?> bodiesSent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    methods.add(options.method);
    bodiesSent.add(
      options.data is Map<String, dynamic>
          ? options.data as Map<String, dynamic>
          : null,
    );

    final body = bodies[options.path];
    if (body == null) {
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCodes[options.path] ?? statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

NewProductDraft _draft() => const NewProductDraft(
  categoryId: 4,
  brandId: 2,
  baseName: 'Portland Cement',
  description: 'General purpose',
  imageUrl: '',
  variantName: '40kg',
  baseUomId: 7,
  minStockThreshold: 5,
  maxStockLevel: 200,
  sellingPrice: 275.5,
  barcodeQr: 'QB-9001',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  // `init()` assigns a `late final dio`, so it is NOT idempotent — initialise the
  // singleton once and swap only its adapter (same harness as the catalogue test).
  setUpAll(() => client = ApiClient.instance..init());

  late _RecordingAdapter adapter;
  late ProductsRepository repository;

  void useAdapter(
    Map<String, Object?> bodies, {
    int statusCode = 201,
    Map<String, int> statusCodes = const {},
  }) {
    adapter = _RecordingAdapter(
      bodies: bodies,
      statusCode: statusCode,
      statusCodes: statusCodes,
    );
    client.dio.httpClientAdapter = adapter;
    repository = ProductsRepository(ProductsService(client: client));
  }

  group('createProductChain', () {
    test(
      'posts product → variant → selling unit and threads the server ids',
      () async {
        useAdapter({
          '/api/v1/products/': {'id': 11},
          '/api/v1/variants/': {'id': 22},
          '/api/v1/variant-uoms/': {'id': 33},
        });

        final created = await repository.createProductChain(_draft());

        expect(adapter.paths, [
          '/api/v1/products/',
          '/api/v1/variants/',
          '/api/v1/variant-uoms/',
        ]);
        expect(adapter.methods, ['POST', 'POST', 'POST']);

        // The product body names the catalog fields and NOTHING about stock: the
        // first stock arrives through a purchase order (user decision 2026-10-25).
        expect(adapter.bodiesSent[0], {
          'category': 4,
          'brand': 2,
          'base_name': 'Portland Cement',
          'description': 'General purpose',
          'image_url': '',
        });

        // The variant carries the id the product POST returned.
        expect(adapter.bodiesSent[1], {
          'product': 11,
          'variant_name': '40kg',
          'base_uom': 7,
          'min_stock_threshold': 5.0,
          'max_stock_level': 200.0,
        });

        // The selling unit carries the variant id, factor 1 and the price.
        expect(adapter.bodiesSent[2], {
          'variant': 22,
          'uom': 7,
          'conversion_factor': 1,
          'default_selling_price': 275.5,
          'barcode_qr': 'QB-9001',
        });

        expect(created.productId, 11);
        expect(created.variantId, 22);
        expect(created.sellingUnitId, 33);
      },
    );

    test('a failure at step 2 names the VARIANT and stops the chain', () async {
      useAdapter({
        // The variant POST is absent from the map → 404, which the service reports.
        '/api/v1/products/': {'id': 11},
      });

      await expectLater(
        repository.createProductChain(_draft()),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.variant)
              .having((e) => e.message, 'message', contains('not found')),
        ),
      );

      // Nothing was posted AFTER the failure: no selling unit for a variant that
      // does not exist.
      expect(adapter.paths, ['/api/v1/products/', '/api/v1/variants/']);
    });

    test('a refusal at step 3 names the SELLING UNIT', () async {
      useAdapter(
        {
          '/api/v1/products/': {'id': 11},
          '/api/v1/variants/': {'id': 22},
          '/api/v1/variant-uoms/': {
            'code': 'DUPLICATE_BASE_UNIT',
            'detail': 'Variant 22 already has a factor-1 unit.',
          },
        },
        statusCodes: {'/api/v1/variant-uoms/': 400},
      );

      await expectLater(
        repository.createProductChain(_draft()),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.sellingUnit)
              .having(
                (e) => e.message,
                'message',
                'This variant already has a base-unit selling unit.',
              ),
        ),
      );
    });
  });

  group('editProductChain', () {
    test('PATCHes only the rows that changed, with no frozen fields', () async {
      useAdapter({
        '/api/v1/products/11/': {'id': 11},
        '/api/v1/variants/22/': {'id': 22},
        '/api/v1/variant-uoms/33/': {'id': 33},
      }, statusCode: 200);

      await repository.editProductChain(
        const ProductEditDraft(
          productId: 11,
          variantId: 22,
          sellingUnitId: 33,
          baseName: 'Portland Cement Type 1',
          minStockThreshold: 8,
          sellingPrice: 290,
        ),
      );

      expect(adapter.paths, [
        '/api/v1/products/11/',
        '/api/v1/variants/22/',
        '/api/v1/variant-uoms/33/',
      ]);
      expect(adapter.methods, ['PATCH', 'PATCH', 'PATCH']);
      expect(adapter.bodiesSent[0], {'base_name': 'Portland Cement Type 1'});
      expect(adapter.bodiesSent[1], {'min_stock_threshold': 8.0});
      // `variant`, `uom` and `conversion_factor` are frozen once sold — sending
      // them would earn 400 SELLING_UNIT_IN_USE on a repriced unit.
      expect(adapter.bodiesSent[2], {'default_selling_price': 290.0});
    });

    test('a price edit alone touches ONLY the selling unit', () async {
      useAdapter({
        '/api/v1/variant-uoms/33/': {'id': 33},
      }, statusCode: 200);

      await repository.editProductChain(
        const ProductEditDraft(
          productId: 11,
          variantId: 22,
          sellingUnitId: 33,
          sellingPrice: 300,
        ),
      );

      expect(adapter.paths, ['/api/v1/variant-uoms/33/']);
      expect(adapter.bodiesSent.single, {'default_selling_price': 300.0});
    });
  });

  group('setProductActive', () {
    test('archives with PATCH is_active=false — never DELETE', () async {
      useAdapter({
        '/api/v1/products/11/': {'id': 11},
      }, statusCode: 200);

      await repository.setProductActive(11, false);

      expect(adapter.paths, ['/api/v1/products/11/']);
      expect(adapter.methods, ['PATCH']);
      expect(adapter.bodiesSent.single, {'is_active': false});
    });

    test('restores with PATCH is_active=true', () async {
      useAdapter({
        '/api/v1/products/11/': {'id': 11},
      }, statusCode: 200);

      await repository.setProductActive(11, true);

      expect(adapter.bodiesSent.single, {'is_active': true});
    });
  });
}
