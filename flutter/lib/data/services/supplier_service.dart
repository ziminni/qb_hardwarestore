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

/// Reads AND WRITES suppliers and purchase orders (decision D-02, Phase 4
/// Task 4).
///
/// Both viewsets inherit `_CatalogBaseViewSet`: read is `IsAuthenticated`,
/// write is `IsInventoryRole` (Stock Manager / Store Manager / Admin). Phase 4
/// added the writes the screens need — supplier create/edit/archive, purchase
/// order create (nested lines), `place/` and `cancel/`. There is still no DELETE:
/// the routes answer **405**, so everything retires through `is_active` or a PO
/// status transition.
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

  // ---------------------------------------------------------------------
  // Writes (Phase 4 Task 4)
  // ---------------------------------------------------------------------

  /// Creates a supplier and returns its server id.
  Future<int> createSupplier(Map<String, dynamic> body) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(suppliersPath, data: body),
    );
    return _idOf(response.data);
  }

  /// Edits a supplier — including `is_active`, which is how one is retired.
  Future<void> patchSupplier(int id, Map<String, dynamic> body) async {
    if (body.isEmpty) return;
    await _write(
      () =>
          _client.patch<Map<String, dynamic>>('$suppliersPath$id/', data: body),
    );
  }

  /// Creates a purchase order WITH its lines as one nested write.
  ///
  /// There is no `/po-items/` endpoint: `items: [{variant, ordered_qty,
  /// unit_cost}]` is the only way a line exists. `created_by` and `status` are
  /// read-only server-side, so the body deliberately carries neither.
  Future<int> createPurchaseOrder(Map<String, dynamic> body) async {
    final response = await _write(
      () => _client.post<Map<String, dynamic>>(purchaseOrdersPath, data: body),
    );
    return _idOf(response.data);
  }

  /// DRAFT → ORDERED. Any other state answers 400 `INVALID_PO_STATE`.
  Future<void> placePurchaseOrder(int id) => _write(
    () => _client.post<Map<String, dynamic>>(
      '$purchaseOrdersPath$id/place/',
      data: const <String, dynamic>{},
    ),
  );

  /// DRAFT or ORDERED-with-nothing-received → CANCELLED.
  Future<void> cancelPurchaseOrder(int id) => _write(
    () => _client.post<Map<String, dynamic>>(
      '$purchaseOrdersPath$id/cancel/',
      data: const <String, dynamic>{},
    ),
  );

  int _idOf(Map<String, dynamic>? data) {
    final id = data?['id'];
    if (id is int) return id;
    throw const SupplierServiceException(
      'The server did not return the saved row.',
    );
  }

  Future<Response<Map<String, dynamic>>> _write(
    Future<Response<Map<String, dynamic>>> Function() write,
  ) async {
    try {
      return await write();
    } on DioException catch (error) {
      throw SupplierServiceException(
        _message(error, 'The change was refused.'),
      );
    }
  }

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
      final code = data['code'];
      if (code is String) {
        final mapped = _codes[code];
        if (mapped != null) return mapped;
      }
      final detail = data['detail'];
      if (detail is String) return detail;
      // A field-error dict (`{"company_name": ["..."]}`) is still a refusal a
      // clerk can act on, so it is read out rather than flattened to `fallback`.
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return '${value.first}';
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return fallback;
  }

  /// Every refusal code the supplier and purchase-order routes answer with
  /// (ENDPOINTS.md §3.3), in words a clerk can act on.
  static const Map<String, String> _codes = {
    'SUPPLIER_INACTIVE':
        'That supplier is inactive. Reactivate it before ordering from it.',
    'INVALID_PO':
        'A purchase order needs at least one line, a quantity above zero, a '
        'cost that is not negative, and only one line per variant.',
    'PO_LOCKED':
        'This order has already been placed, so it can no longer be edited.',
    'PO_HAS_RECEIPTS':
        'Goods have already been received against this order, so it cannot be '
        'cancelled.',
    'INVALID_PO_STATE': 'That action is not allowed in this order status.',
  };
}
