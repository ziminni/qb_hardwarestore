import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:dio/dio.dart';

/// Raised when inventory state cannot be read or written. [message] is safe to show.
class InventoryServiceException implements Exception {
  const InventoryServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and writes the two inventory endpoints that are the **server's**
/// authority over inventory state (decision 13).
///
/// Decision 13 settled that the client stops deciding these things for itself:
/// low stock is whatever the server has alerted, and movement history is
/// whatever the server has recorded. The client's job is to read and to report.
///
/// Both reads go through [ApiClient.getList], so the DRF envelope is unwrapped by
/// `parsePaged` in exactly one place (decision 03). Verified contracts
/// (2026-10-16):
///
/// * `SystemAlertSerializer` — `id, alert_type, variant, message, is_resolved, created_at`
/// * `StockAdjustmentSerializer` — `id, variant, user, adjustment_type, qty_adjusted, remarks, timestamp`
class InventoryService {
  InventoryService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const alertsPath = '/api/v1/alerts/';
  static const adjustmentsPath = '/api/v1/adjustments/';
  static const purchaseOrdersPath = '/api/v1/purchase-orders/';
  static const goodsReceiptsPath = '/api/v1/goods-receipts/';

  /// Alerts the backend has raised — low stock, out of stock, expiring.
  ///
  /// Note the consequence decision 13 accepted: this is a list of **events the
  /// server generated**, not a live view. A variant that drops below its
  /// threshold without going through an alerted path will not appear here until
  /// an alert exists. That is the price of one authority.
  Future<List<SystemAlert>> fetchAlerts() async {
    final page = await _guard(
      () => _client.getList<SystemAlert>(alertsPath, SystemAlert.fromJson),
    );
    return page.items;
  }

  /// Recorded stock adjustments, newest first (the backend orders by
  /// `-timestamp`).
  Future<List<StockAdjustment>> fetchAdjustments() async {
    final page = await _guard(
      () => _client.getList<StockAdjustment>(
        adjustmentsPath,
        StockAdjustment.fromJson,
      ),
    );
    return page.items;
  }

  /// Records an adjustment on the server and returns the stored row.
  ///
  /// Returns the server's row rather than the caller's input, so the screen can
  /// show what was actually stored (ids, the authoritative timestamp) instead of
  /// what it hoped was stored.
  Future<StockAdjustment> createAdjustment({
    required int variantId,
    required StockAdjustmentType type,
    required double quantity,
    String remarks = '',
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        adjustmentsPath,
        data: {
          'variant': variantId,
          'adjustment_type': type.apiValue,
          'qty_adjusted': quantity,
          'remarks': remarks,
        },
      );
      final data = response.data;
      if (data == null) {
        throw const InventoryServiceException(
          'The server did not return the saved adjustment.',
        );
      }
      return StockAdjustment.fromJson(data);
    } on DioException catch (error) {
      throw InventoryServiceException(_message(error));
    }
  }

  /// Open purchase orders with their lines, for the receiving screen.
  ///
  /// Decision 17: a PO can be created through the UI and then never received —
  /// this list is where receiving starts.
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async {
    final page = await _guard(
      () => _client.getList<PurchaseOrderRecord>(
        purchaseOrdersPath,
        PurchaseOrderRecord.fromJson,
      ),
    );
    return page.items;
  }

  /// Records a goods receipt, carrying the received quantities.
  ///
  /// The `items` payload sets POItem.received_qty server-side, which is what a
  /// later process/ turns into FIFO batches. Returns the server's row.
  /// Resolves one alert on the server and returns the stored row.
  ///
  /// Decision 06: resolving is a named act with a trail — the server stamps
  /// `resolved_by` and `resolved_at`, so the screen can show WHO cleared it and
  /// WHEN. The client never guesses either.
  Future<SystemAlert> resolveAlert(int alertId) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$alertsPath$alertId/resolve/',
        data: const <String, dynamic>{},
      );
      final data = response.data;
      if (data == null) {
        throw const InventoryServiceException(
          'The server did not return the resolved alert.',
        );
      }
      return SystemAlert.fromJson(data);
    } on DioException catch (error) {
      throw InventoryServiceException(_message(error));
    }
  }

  /// Every goods receipt the server has recorded, for the receiving history.
  ///
  /// `GoodsReceiptSerializer` carries `received_by_name`, `receive_date`, the
  /// delivered `lines` and `processed_at`, so one call describes a delivery
  /// without a request per line.
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts() async {
    final page = await _guard(
      () => _client.getList<GoodsReceiptRecord>(
        goodsReceiptsPath,
        GoodsReceiptRecord.fromJson,
      ),
    );
    return page.items;
  }

  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        goodsReceiptsPath,
        data: {
          'po': poId,
          'delivery_receipt_no': deliveryReceiptNo,
          'items': [for (final line in items) line.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const InventoryServiceException(
          'The server did not return the saved receipt.',
        );
      }
      return GoodsReceiptRecord.fromJson(data);
    } on DioException catch (error) {
      throw InventoryServiceException(_message(error));
    }
  }

  /// Processes a receipt into FIFO batches and returns the minted rows.
  ///
  /// The process endpoint answers with a bare list, not a paginated envelope —
  /// there is exactly one receipt being processed, so paging it would be absurd.
  Future<List<InventoryBatch>> processReceipt(int receiptId) async {
    try {
      final response = await _client.post<List<dynamic>>(
        '$goodsReceiptsPath$receiptId/process/',
        data: {},
      );
      final data = response.data;
      if (data == null) {
        throw const InventoryServiceException(
          'The server did not return the minted batches.',
        );
      }
      return data
          .map((b) => InventoryBatch.fromJson(b as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw InventoryServiceException(_message(error));
    }
  }

  /// Runs a read, converting a transport failure into a message worth showing.
  ///
  /// Deliberately does NOT catch `FormatException`: a malformed body is a
  /// contract break and must fail loudly rather than be reported as a network
  /// problem the user could retry their way out of.
  Future<T> _guard<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on DioException catch (error) {
      throw InventoryServiceException(_message(error));
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
    return 'Unable to load inventory data.';
  }
}
