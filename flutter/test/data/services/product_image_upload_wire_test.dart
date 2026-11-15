// Product image lane (usability follow-up 2): the photo travels on the EXISTING
// product POST/PATCH as `multipart/form-data`, and only when the clerk picked a
// file.
//
// Why the wire is asserted here rather than through a stubbed repository: the
// root bug was a DEVICE PATH sent as `image_url`, which no repository double can
// catch — it looked like a normal string field. These tests drive the real
// `ProductsRepository` → `ProductsService` → `ApiClient` stack against a fake
// adapter and assert the actual body: a `FormData` with string fields plus one
// `image` file part, or the untouched JSON map when nothing was picked.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/product_image_upload.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request and answers by path.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.bodies});

  /// path -> (status, body).
  final Map<String, (int, Map<String, dynamic>)> bodies;

  final List<String> paths = [];
  final List<String> methods = [];

  /// The raw `data` of every request: a `Map` (JSON) or a `FormData` (multipart).
  final List<Object?> payloads = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    methods.add(options.method);
    payloads.add(options.data);

    final reply = bodies[options.path];
    if (reply == null) {
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(reply.$2),
      reply.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _productsPath = '/api/v1/products/';
const _variantsPath = '/api/v1/variants/';
const _unitsPath = '/api/v1/variant-uoms/';

final _bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

ProductImageUpload _upload({String filename = 'cement.png'}) =>
    ProductImageUpload(bytes: _bytes, filename: filename);

NewProductDraft _draft({ProductImageUpload? image}) => NewProductDraft(
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
  storedAtId: 9,
  image: image,
);

ProductEditDraft _edit({ProductImageUpload? image}) => ProductEditDraft(
  productId: 11,
  variantId: 22,
  sellingUnitId: 33,
  baseName: 'Portland Cement',
  image: image,
);

/// The `image` file part of a multipart body, or null.
MapEntry<String, MultipartFile>? _imageFile(Object? payload) {
  if (payload is! FormData) return null;
  for (final file in payload.files) {
    if (file.key == 'image') return file;
  }
  return null;
}

Map<String, String> _fields(Object? payload) => payload is FormData
    ? {for (final field in payload.fields) field.key: field.value}
    : const {};

void main() {
  late ApiClient client;
  setUpAll(() => client = ApiClient.instance..init());

  late _RecordingAdapter adapter;
  late ProductsRepository repository;

  void useAdapter(Map<String, (int, Map<String, dynamic>)> bodies) {
    adapter = _RecordingAdapter(bodies: bodies);
    client.dio.httpClientAdapter = adapter;
    repository = ProductsRepository(ProductsService(client: client));
  }

  group('create with a photo', () {
    test('sends the product POST as multipart with string fields + image', () async {
      useAdapter({
        _productsPath: (201, {'id': 11}),
        _variantsPath: (201, {'id': 22}),
        _unitsPath: (201, {'id': 33}),
      });

      await repository.createProductChain(_draft(image: _upload()));

      final product = adapter.payloads[0];
      expect(product, isA<FormData>(), reason: 'a photo forces multipart');
      expect(_fields(product), {
        'category': '4',
        'brand': '2',
        'base_name': 'Portland Cement',
        'description': 'General purpose',
        'image_url': '',
        'stored_at': '9',
      });
      final file = _imageFile(product);
      expect(file, isNotNull, reason: 'the picked photo is the `image` part');
      expect(file!.value.filename, 'cement.png');
      // The part carries the picked bytes; the length is the whole assertion
      // `MultipartFile` allows after dio has finalized it for the request.
      expect(file.value.length, _bytes.length);

      // The rest of the chain stays JSON: only the product row carries a file.
      expect(adapter.payloads[1], isA<Map<String, dynamic>>());
      expect(adapter.payloads[2], isA<Map<String, dynamic>>());
      expect(adapter.paths, [_productsPath, _variantsPath, _unitsPath]);
    });

    test('never puts a device path anywhere in the product payload', () async {
      useAdapter({
        _productsPath: (201, {'id': 11}),
        _variantsPath: (201, {'id': 22}),
        _unitsPath: (201, {'id': 33}),
      });

      await repository.createProductChain(_draft(image: _upload()));

      final fields = _fields(adapter.payloads[0]);
      expect(fields['image_url'], '');
      for (final value in fields.values) {
        expect(value, isNot(contains('cement.png')));
        expect(value, isNot(contains('C:\\')));
        expect(value, isNot(contains('/tmp/')));
        expect(value, isNot(startsWith('blob:')));
      }
    });
  });

  group('no photo', () {
    test('create stays plain JSON, exactly as before', () async {
      useAdapter({
        _productsPath: (201, {'id': 11}),
        _variantsPath: (201, {'id': 22}),
        _unitsPath: (201, {'id': 33}),
      });

      await repository.createProductChain(_draft());

      expect(adapter.payloads[0], {
        'category': 4,
        'brand': 2,
        'base_name': 'Portland Cement',
        'description': 'General purpose',
        'image_url': '',
        'stored_at': 9,
      });
    });

    test('an unrelated edit sends no image, so the server keeps the old one', () async {
      useAdapter({
        '${_productsPath}11/': (200, {'id': 11}),
        '${_variantsPath}22/': (200, {'id': 22}),
        '${_unitsPath}33/': (200, {'id': 33}),
      });

      await repository.editProductChain(_edit());

      final product = adapter.payloads[0];
      expect(product, isA<Map<String, dynamic>>());
      expect(product, {'base_name': 'Portland Cement'});
      expect((product as Map).containsKey('image'), isFalse);
      expect(product.containsKey('image_url'), isFalse);
    });
  });

  group('edit with a new photo', () {
    test('PATCHes the product row as multipart with the replacement', () async {
      useAdapter({
        '${_productsPath}11/': (200, {'id': 11}),
        '${_variantsPath}22/': (200, {'id': 22}),
        '${_unitsPath}33/': (200, {'id': 33}),
      });

      await repository.editProductChain(
        _edit(image: _upload(filename: 'replacement.webp')),
      );

      final product = adapter.payloads[0];
      expect(product, isA<FormData>());
      expect(_fields(product), {'base_name': 'Portland Cement'});
      final file = _imageFile(product);
      expect(file, isNotNull);
      expect(file!.value.filename, 'replacement.webp');
      expect(adapter.methods[0], 'PATCH');

      // This draft touched no variant or unit field, so nothing else is sent:
      // the photo alone did not drag an empty PATCH along.
      expect(adapter.payloads, hasLength(1));
    });

    test('a photo-only edit still PATCHes instead of skipping an empty body', () async {
      useAdapter({
        '${_productsPath}11/': (200, {'id': 11}),
      });

      await repository.editProductChain(
        ProductEditDraft(
          productId: 11,
          variantId: 0,
          sellingUnitId: 0,
          image: _upload(),
        ),
      );

      expect(adapter.paths, ['${_productsPath}11/']);
      expect(_imageFile(adapter.payloads[0]), isNotNull);
    });
  });

  group('server refusals', () {
    test('INVALID_PRODUCT_IMAGE reaches the caller as a product-step message', () async {
      useAdapter({
        _productsPath: (
          400,
          {
            'code': 'INVALID_PRODUCT_IMAGE',
            'detail': 'Upload a JPEG, PNG or WebP image.',
          },
        ),
      });

      await expectLater(
        repository.createProductChain(_draft(image: _upload())),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.product)
              .having(
                (e) => e.message,
                'message',
                contains('JPEG, PNG or WebP'),
              ),
        ),
      );
    });

    test('PRODUCT_IMAGE_TOO_LARGE reaches the caller as a product-step message', () async {
      useAdapter({
        _productsPath: (
          400,
          {
            'code': 'PRODUCT_IMAGE_TOO_LARGE',
            'detail': 'The image must be smaller than 5 MB.',
          },
        ),
      });

      await expectLater(
        repository.createProductChain(_draft(image: _upload())),
        throwsA(
          isA<ProductWriteException>()
              .having((e) => e.step, 'step', ProductWriteStep.product)
              .having((e) => e.message, 'message', contains('5 MB')),
        ),
      );
    });
  });
}
