import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/supplier.dart';
import 'package:dio/dio.dart';

/// Raised when suppliers or purchase orders cannot be read. [message] is safe
/// to show.
class SupplierServiceException implements Exception {
  const SupplierServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads suppliers and purchase orders (decision D-02).
///
/// Both viewsets inherit `_CatalogBaseViewSet`: read is `IsAuthenticated`,
/// write is `IsInventoryRole`. This service only reads — creating or editing a
/// supplier/PO is out of scope for this pass, so no write method exists here to
/// be wired to a button that does nothing.
///
/// Contracts verified 2026-10-22:
/// * `SupplierSerializer` — `id, company_name, contact_person, phone, email,
///   address, is_active`
/// * `PurchaseOrderSerializer` — `id, supplier, created_by, created_by_name,
///   order_date, expected_delivery, status, notes, items`
///
/// `GET /api/v1/purchase-orders/` is also read by `InventoryService` for
/// receiving; that model is a different, narrower shape (decision 17) and is
/// left alone.
class SupplierService {
  SupplierService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const suppliersPath = '/api/v1/suppliers/';
  static const purchaseOrdersPath = '/api/v1/purchase-orders/';

  /// How many pages to read before giving up. 40 x DRF's `PAGE_SIZE` (50) =
  /// 2000 rows, far past any supplier book; hitting it means the API is
  /// misbehaving, and failing loudly beats a silently truncated list the user
  /// would read as complete.
  static const _maxPages = 40;

  /// Every supplier, both active and inactive.
  ///
  /// Inactive suppliers are kept deliberately: a PO may reference one, and the
  /// screen shows an Active/Inactive chip rather than hiding half the book.
  Future<List<Supplier>> fetchSuppliers() => _readAll(
    suppliersPath,
    Supplier.fromJson,
    'The supplier list could not be loaded.',
  );

  /// Every purchase order, newest first (the backend orders `-order_date`).
  ///
  /// `supplierName` is empty on each row — the serializer sends only the
  /// supplier id. The viewmodel joins it against the suppliers it loaded.
  Future<List<PurchaseOrder>> fetchPurchaseOrders() => _readAll(
    purchaseOrdersPath,
    PurchaseOrder.fromJson,
    'The purchase orders could not be loaded.',
  );

  /// Walks every page of a list endpoint and returns the flattened rows.
  Future<List<T>> _readAll<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
    String fallback,
  ) async {
    try {
      final all = <T>[];
      var page = 1;
      while (true) {
        final result = await _client.getList<T>(
          path,
          fromJson,
          queryParameters: {'page': page},
        );
        all.addAll(result.items);
        if (!result.hasMore) return all;
        page++;
        if (page > _maxPages) {
          throw const FormatException('The list did not end.');
        }
      }
    } on DioException catch (error) {
      throw SupplierServiceException(_message(error, fallback));
    } on FormatException catch (error) {
      // A malformed row is a contract break, not a network problem — but it
      // still has to reach the screen as a retryable message instead of a raw
      // crash that leaves the table blank with no explanation.
      throw SupplierServiceException('$fallback (${error.message})');
    }
  }

  String _message(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    if (error.response?.statusCode == 403) {
      return 'No permission to view suppliers.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
    }
    return fallback;
  }
}
