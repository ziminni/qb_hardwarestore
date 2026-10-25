import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:dio/dio.dart';

/// Raised when a catalog read or write fails. [message] is safe to show a clerk.
class CatalogueServiceException implements Exception {
  const CatalogueServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the three catalog lists the product form needs beyond the
/// products themselves: categories, brands and units of measure.
///
/// Why a service of its own (Phase 4 Task 4): the products screen used to derive
/// its category and brand choices from the products already loaded, and its base
/// unit from a hardcoded word list. Both were wrong the moment the client had to
/// CREATE something — a store with no products had no categories to file its
/// first product under, and `base_uom` is a foreign key, not a word.
///
/// Contracts (ENDPOINTS.md §3.3, Phase 4 Task 1):
/// * `CategorySerializer` — `id, name, is_active`
/// * `BrandSerializer` — `id, name`
/// * `UnitOfMeasureSerializer` — `id, code, name`
/// * Writes are Stock Manager / Store Manager / Admin; a refusal is a 4xx with a
///   `{code, detail}` body or a DRF field-error dict.
class CatalogueService {
  CatalogueService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const categoriesPath = '/api/v1/categories/';
  static const brandsPath = '/api/v1/brands/';
  static const unitsPath = '/api/v1/uoms/';

  Future<List<Category>> fetchCategories() => _guard(
    () => _client.getList<Category>(categoriesPath, Category.fromJson),
  ).then((page) => page.items);

  Future<List<Brand>> fetchBrands() => _guard(
    () => _client.getList<Brand>(brandsPath, Brand.fromJson),
  ).then((page) => page.items);

  Future<List<UnitOfMeasure>> fetchUnits() => _guard(
    () => _client.getList<UnitOfMeasure>(unitsPath, UnitOfMeasure.fromJson),
  ).then((page) => page.items);

  /// Creates a category and returns its server id.
  Future<int> createCategory(String name) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(
        categoriesPath,
        data: {'name': name},
      ),
    );
    return _idOf(response.data);
  }

  /// Renames and/or archives a category. There is no DELETE on this route (405).
  Future<void> patchCategory(int id, {String? name, bool? isActive}) async {
    await _write(
      () => _client.patch<Map<String, dynamic>>(
        '$categoriesPath$id/',
        data: {'name': ?name, 'is_active': ?isActive},
      ),
    );
  }

  int _idOf(Map<String, dynamic>? data) {
    final id = data?['id'];
    if (id is int) return id;
    throw const CatalogueServiceException(
      'The server did not return the saved row.',
    );
  }

  Future<T> _guard<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on DioException catch (error) {
      throw CatalogueServiceException(_message(error));
    }
  }

  Future<Response<Map<String, dynamic>>> _write(
    Future<Response<Map<String, dynamic>>> Function() write,
  ) async {
    try {
      return await write();
    } on DioException catch (error) {
      throw CatalogueServiceException(_message(error));
    }
  }

  /// One map of what the catalog routes can answer onto words a clerk reads.
  ///
  /// A refusal is never reported as a network problem: `DUPLICATE_CATEGORY` does
  /// not exist server-side, but "category with this name already exists" (the
  /// DRF unique validator's message) does, and it is the one a clerk can act on.
  String _message(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;

    if (data is Map<String, dynamic>) {
      final code = data['code'];
      final detail = data['detail'];
      final mapped = code is String ? _codes[code] : null;
      if (mapped != null) return mapped;
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
      403 => 'Only a stock manager can change the catalogue.',
      404 => 'That category no longer exists.',
      _ => 'Unable to save the category.',
    };
  }

  static const Map<String, String> _codes = {};

  /// DRF answers a duplicate name with `{"name": ["... already exists."]}`.
  String? _firstFieldError(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) return '${value.first}';
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
