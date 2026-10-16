import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
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
  /// The two requests run together because neither depends on the other.
  Future<ProductsSnapshot> fetchCatalogue() async {
    try {
      final responses = await Future.wait([
        _client.getList<Product>(productsPath, Product.fromJson),
        _client.getList<InventoryBatch>(batchesPath, InventoryBatch.fromJson),
      ]);
      return ProductsSnapshot(
        products: (responses[0] as Paged<Product>).items,
        batches: (responses[1] as Paged<InventoryBatch>).items,
      );
    } on DioException catch (error) {
      throw ProductsServiceException(_message(error));
    }
  }

  String _message(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    return 'Unable to load the product catalogue.';
  }
}
