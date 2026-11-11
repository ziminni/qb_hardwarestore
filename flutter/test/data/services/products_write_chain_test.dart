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
    this.replies = const {},
  });

  /// path -> body. A missing path answers 404 with a `detail`.
  final Map<String, Object?> bodies;
  final int statusCode;

  /// path -> status, for when one step succeeds and the next is refused.
  final Map<String, int> statusCodes;

  /// Call index (0-based) -> (status, body), for a chain where the failing step
  /// is one of several POSTs to the SAME path (the extra selling units).
  final Map<int, (int, Map<String, dynamic>)> replies;

  final List<String> paths = [];
  final List<String> methods = [];
  final List<Map<String, dynamic>?> bodiesSent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final callIndex = paths.length;
    paths.add(options.path);
    methods.add(options.method);
    bodiesSent.add(
      options.data is Map<String, dynamic>
          ? options.data as Map<String, dynamic>
          : null,
    );

    final reply = replies[callIndex];
    if (reply != null) {
      return ResponseBody.fromString(
        jsonEncode(reply.$2),
        reply.$1,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

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

/// The same product, sold by the base unit and by a 40 kg bag and a 4-piece
/// box (Phase 1d decision 15: "Bag = 40 kg at ₱270").
NewProductDraft _draftWithExtras() => const NewProductDraft(
  categoryId: 4,
  brandId: 2,
  baseName: 'Portland Cement',
  description: 'General purpose',
  imageUrl: '',
  variantName: '40kg',
  baseUomId: 7,
  minStockThreshold: 5,
  maxStockLevel: 200,
  sellingPrice: 6.75,
  extraSellingUnits: [
    NewSellingUnit(
      uomId: 9,
      uomCode: 'BAG',
      conversionFactor: 40,
      sellingPrice: 270,
    ),
    NewSellingUnit(
      uomId: 10,
      uomCode: 'BOX',
      conversionFactor: 4,
      sellingPrice: 30,
      barcodeQr: 'BOX-9001',
    ),
  ],
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
    Map<int, (int, Map<String, dynamic>)> replies = const {},
  }) {
    adapter = _RecordingAdapter(
      bodies: bodies,
      statusCode: statusCode,
      statusCodes: statusCodes,
      replies: replies,
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

  group('createProductChain with extra selling units', () {
    test('posts each extra unit AFTER the base unit, in form order', () async {
      useAdapter({
        '/api/v1/products/': {'id': 11},
        '/api/v1/variants/': {'id': 22},
        '/api/v1/variant-uoms/': {'id': 33},
      });

      final created = await repository.createProductChain(_draftWithExtras());

      expect(adapter.paths, [
        '/api/v1/products/',
        '/api/v1/variants/',
        '/api/v1/variant-uoms/',
        '/api/v1/variant-uoms/',
        '/api/v1/variant-uoms/',
      ]);
      expect(adapter.methods, List.filled(5, 'POST'));

      // FACTOR 1 first: the base unit the variant is counted in (the server
      // refuses any other factor-1 unit afterwards with DUPLICATE_BASE_UNIT).
      expect(adapter.bodiesSent[2], {
        'variant': 22,
        'uom': 7,
        'conversion_factor': 1,
        'default_selling_price': 6.75,
        'barcode_qr': '',
      });
      expect(adapter.bodiesSent[3], {
        'variant': 22,
        'uom': 9,
        'conversion_factor': 40.0,
        'default_selling_price': 270.0,
        'barcode_qr': '',
      });
      expect(adapter.bodiesSent[4], {
        'variant': 22,
        'uom': 10,
        'conversion_factor': 4.0,
        'default_selling_price': 30.0,
        'barcode_qr': 'BOX-9001',
      });

      expect(
        created.sellingUnitId,
        33,
        reason: 'the returned id is still the BASE unit the form prices',
      );
    });

    test(
      'a refused extra unit says WHICH one, and that the product exists',
      () async {
        useAdapter(
          {
            '/api/v1/products/': {'id': 11},
            '/api/v1/variants/': {'id': 22},
            '/api/v1/variant-uoms/': {'id': 33},
          },
          // Calls 0-2 are product, variant and base unit; 3 is the BAG and 4 the
          // BOX: the refusal lands on one of three POSTs to the SAME path, which a
          // per-path status map cannot express.
          replies: {
            3: (201, {'id': 44}),
            4: (
              400,
              {
                'code': 'INVALID_SELLING_UNIT',
                'detail':
                    'One selling unit always holds at least one base unit.',
              },
            ),
          },
        );

        final failure = await repository
            .createProductChain(_draftWithExtras())
            .then<Object?>((_) => null, onError: (error) => error);

        expect(failure, isA<PartialCreateException>());
        // Both halves matter: WHICH unit to re-add, and the fact that the catalog
        // row exists — a clerk who retries "Add product" makes a duplicate.
        final partial = failure! as PartialCreateException;
        expect(
          partial.unit,
          'BOX',
          reason:
              'the message must name the unit that was NOT saved, or the clerk '
              're-adds the one that was',
        );
        expect(
          partial.created.productId,
          11,
          reason:
              'the product EXISTS on the server: a retry would duplicate it',
        );
        expect(partial.created.variantId, 22);
        expect(partial.created.sellingUnitId, 33);
        expect(partial.message, contains('selling price'));
        expect(
          adapter.paths,
          hasLength(5),
          reason:
              'the chain stops at the refused unit, saving nothing after it',
        );
      },
    );
  });

  group('createSellingUnit on an existing variant', () {
    test('POSTs the same unit body the create chain posts', () async {
      useAdapter({
        '/api/v1/variant-uoms/': {'id': 44},
      });

      await repository.createSellingUnit(
        8,
        const NewSellingUnit(
          uomId: 2,
          uomCode: 'BAG',
          conversionFactor: 40,
          sellingPrice: 270,
        ),
      );

      expect(adapter.paths, ['/api/v1/variant-uoms/']);
      expect(adapter.methods, ['POST']);
      expect(adapter.bodiesSent.single, {
        'variant': 8,
        'uom': 2,
        'conversion_factor': 40.0,
        'default_selling_price': 270.0,
        'barcode_qr': '',
      });
    });

    test('a refused unit names the selling unit step', () async {
      useAdapter({
        '/api/v1/variant-uoms/': {
          'code': 'INVALID_SELLING_UNIT',
          'detail': 'A selling unit always holds at least one base unit.',
        },
      }, statusCode: 400);

      await expectLater(
        repository.createSellingUnit(
          8,
          const NewSellingUnit(
            uomId: 2,
            uomCode: 'BAG',
            conversionFactor: 1,
            sellingPrice: 270,
          ),
        ),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.sellingUnit)
              .having((e) => e.message, 'message', contains('at least one')),
        ),
      );
    });
  });

  group('deleteSellingUnit', () {
    test('DELETEs the row: the one catalog DELETE the API answers', () async {
      useAdapter({'/api/v1/variant-uoms/33/': {}}, statusCode: 204);

      await repository.deleteSellingUnit(33);

      expect(adapter.paths, ['/api/v1/variant-uoms/33/']);
      expect(adapter.methods, [
        'DELETE',
      ], reason: 'removal is a DELETE; a PATCH would only archive nothing');
    });

    test('the base unit is refused as a base unit', () async {
      useAdapter({
        '/api/v1/variant-uoms/33/': {
          'code': 'BASE_UNIT_REQUIRED',
          'detail': 'Selling unit 33 is the base unit.',
        },
      }, statusCode: 400);

      await expectLater(
        repository.deleteSellingUnit(33),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.sellingUnit)
              .having((e) => e.message, 'message', contains('base unit')),
        ),
      );
    });

    test('a used unit is refused in words about REMOVING it', () async {
      useAdapter({
        '/api/v1/variant-uoms/33/': {
          'code': 'SELLING_UNIT_IN_USE',
          'detail': 'Selling unit 33 is referenced by a sale.',
        },
      }, statusCode: 400);

      final failure = await repository
          .deleteSellingUnit(33)
          .then<Object?>((_) => null, onError: (error) => error);

      expect(failure, isA<ProductWriteException>());
      expect(
        (failure! as ProductWriteException).message,
        contains('cannot be removed'),
        reason:
            'the same code also refuses an EDIT, so the shared PATCH sentence '
            '("frozen, the price is still editable") would be about the wrong '
            'action here',
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
