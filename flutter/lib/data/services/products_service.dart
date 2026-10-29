import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:dio/dio.dart';

/// Raised when the catalogue cannot be loaded. [message] is safe to show a user.
class ProductsServiceException implements Exception {
  const ProductsServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One load of the products catalogue: the catalogue itself, plus the stock that
/// gives each row its quantity.
///
/// Stock is a separate list rather than a field on the product because a batch
/// is "a lot at a cost" (decision 02) and lives on its own endpoint.
class ProductsSnapshot {
  const ProductsSnapshot({required this.products, required this.batches});

  final List<Product> products;
  final List<InventoryBatch> batches;
}

/// Loads the products catalogue from the two list endpoints it needs.
///
/// Contract: `ENDPOINTS.md` §3.3 — `/api/v1/products/` nests each product's
/// variants and each variant's selling units, so one call carries the name, the
/// barcode and the price; `/api/v1/batches/` carries the quantities. Verified
/// against the live API on 2026-10-16 (count 6 and count 8).
class ProductsService {
  ProductsService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// What the screen says when the catalogue read fails for a reason other than
  /// a specific HTTP status. A contract break appends its parse detail to this.
  static const _loadFallback = 'The product catalogue could not be loaded.';

  static const productsPath = '/api/v1/products/';
  static const batchesPath = '/api/v1/batches/';

  /// Loads the catalogue and its stock together.
  ///
  /// Both envelopes are unwrapped by `parsePaged`, reached through
  /// [ApiClient.getList] — so the DRF `{count, next, previous, results}` shape is
  /// known in exactly one place (decision 03).
  ///
  /// This deliberately does **not** read `data['results']` by hand. The lost
  /// `PosService` (commit `22c7c26`) did, and that turns a contract break into a
  /// silently EMPTY catalogue: the screen reports "no products" when the truth is
  /// that the response was malformed. `parsePaged` throws instead, and there is a
  /// test pinning that.
  ///
  /// F1: that throw is turned into a [ProductsServiceException] here rather than
  /// escaping as a raw `FormatException`/`TypeError`. Neither was caught by
  /// `InventoryViewmodel.load()`, so a malformed envelope left `loadError` null
  /// and the screen painted "No products in the catalogue yet." over a fetch that
  /// had actually failed — with no banner and no Retry.
  ///
  /// The two requests run together because neither depends on the other.
  Future<ProductsSnapshot> fetchCatalogue() => _read(() async {
    // F5: `getList` reads ONE page (DRF `PAGE_SIZE` = 50). Product #51 was
    // unsearchable and unscannable, and batch #51's quantity was missing from
    // every stock figure. `getAll` walks the `next` links.
    // The two reads run one after the other, NOT in parallel: `Future.wait` (and
    // the record `.wait`) wraps a failure in ParallelWaitError, which is neither a
    // DioException nor a FormatException — the exact leak F1 fixed. A second
    // round trip is cheaper than a contract break reported as "no products".
    final products = await _client.getAll<Product>(
      productsPath,
      Product.fromJson,
    );
    final batches = await _client.getAll<InventoryBatch>(
      batchesPath,
      InventoryBatch.fromJson,
    );
    return ProductsSnapshot(products: products, batches: batches);
  });

  /// Resolves a scanned code to the selling unit that owns it (decision 13).
  ///
  /// The server compares the normalised code exactly (`Upper(barcode_qr) ==`),
  /// so this normalises first and a scanner's ` qb000013-0 ` finds
  /// `QB000013-0`. One page is enough: a code identifies at most one unit.
  ///
  /// Archived variants and products come back TOO — that row is how the till can
  /// say "that code belongs to X, which is archived" instead of "no such code".
  Future<List<VariantUom>> lookupByBarcode(String code) {
    final normalised = VariantUom.normalise(code);
    if (normalised.isEmpty) return Future.value(const <VariantUom>[]);
    return _read(
      () async => (await _client.getList<VariantUom>(
        variantUomsPath,
        VariantUom.fromJson,
        queryParameters: {'barcode': normalised},
      )).items,
    );
  }

  /// Runs a read, turning every way it can fail into a [ProductsServiceException]
  /// the screen can show. The three failures deserve three messages: a transport
  /// refusal, a malformed envelope, and a row of the wrong TYPE.
  Future<T> _read<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on DioException catch (error) {
      throw ProductsServiceException(_message(error));
    } on FormatException catch (error) {
      // A malformed envelope or row: a contract break, reported as a message the
      // screen can show, with the parse detail kept for whoever debugs it.
      throw ProductsServiceException('$_loadFallback (${error.message})');
    } on TypeError {
      // A row whose field is the wrong TYPE throws from its `fromJson` cast. The
      // raw message is a Dart type name, so the clerk gets the plain sentence.
      throw const ProductsServiceException(
        '$_loadFallback (a row was not the shape this app expects)',
      );
    }
  }

  static const variantsPath = '/api/v1/variants/';
  static const variantUomsPath = '/api/v1/variant-uoms/';

  /// POSTs one product row and returns the server id.
  Future<int> createProduct(Map<String, dynamic> body) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(productsPath, data: body),
    );
    return _idOf(response.data);
  }

  /// POSTs one variant row and returns the server id.
  Future<int> createVariant(Map<String, dynamic> body) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(variantsPath, data: body),
    );
    return _idOf(response.data);
  }

  /// POSTs one selling unit and returns the server id.
  Future<int> createSellingUnit(Map<String, dynamic> body) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(variantUomsPath, data: body),
    );
    return _idOf(response.data);
  }

  Future<void> patchProduct(int id, Map<String, dynamic> body) async {
    if (body.isEmpty) return;
    await _write(
      () =>
          _client.patch<Map<String, dynamic>>('$productsPath$id/', data: body),
    );
  }

  Future<void> patchVariant(int id, Map<String, dynamic> body) async {
    if (body.isEmpty) return;
    await _write(
      () =>
          _client.patch<Map<String, dynamic>>('$variantsPath$id/', data: body),
    );
  }

  Future<void> patchSellingUnit(int id, Map<String, dynamic> body) async {
    if (body.isEmpty) return;
    await _write(
      () => _client.patch<Map<String, dynamic>>(
        '$variantUomsPath$id/',
        data: body,
      ),
    );
  }

  int _idOf(Map<String, dynamic>? data) {
    final id = data?['id'];
    if (id is int) return id;
    throw const ProductsServiceException(
      'The server did not return the saved row.',
    );
  }

  Future<Response<Map<String, dynamic>>> _write(
    Future<Response<Map<String, dynamic>>> Function() write,
  ) async {
    try {
      return await write();
    } on DioException catch (error) {
      throw ProductsServiceException(_message(error));
    }
  }

  String _message(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is String) {
        final mapped = _codes[code];
        if (mapped != null) return mapped;
      }
      final detail = data['detail'];
      if (detail is String) return detail;
      final fieldError = _firstFieldError(data);
      if (fieldError != null) return fieldError;
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    return switch (status) {
      401 => 'Your session has expired. Sign in again.',
      403 => 'Only a stock manager can change the product catalogue.',
      404 => 'That product no longer exists. Reload and try again.',
      405 => 'Products cannot be deleted: archive the product instead.',
      _ => 'Unable to load the product catalogue.',
    };
  }

  /// The refusal codes this service can be answered with (ENDPOINTS.md §3.3),
  /// each turned into something a clerk can act on.
  static const Map<String, String> _codes = {
    'INVALID_VARIANT':
        'A stock level cannot be negative. Correct the reorder level and save '
        'again.',
    'INVALID_SELLING_UNIT':
        'The selling price cannot be negative, and one selling unit always '
        'holds at least one base unit.',
    'DUPLICATE_BASE_UNIT': 'This variant already has a base-unit selling unit.',
    'SELLING_UNIT_IN_USE':
        'This selling unit has already been sold, so its unit and factor are '
        'frozen. The price is still editable.',
  };

  String? _firstFieldError(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) return '${value.first}';
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
