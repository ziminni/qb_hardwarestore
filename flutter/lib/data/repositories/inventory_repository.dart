import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/inventory_service.dart';

/// The repository layer between the inventory store and the inventory API.
///
/// Keeps the map's one-data-path invariant — `View → ViewModel → Repository →
/// Service → ApiClient` — so no viewmodel talks to Dio and swapping the
/// transport later touches this file rather than every caller.
class InventoryRepository {
  InventoryRepository(this.service);

  final InventoryService service;

  Future<List<SystemAlert>> loadAlerts() => service.fetchAlerts();

  Future<List<StockAdjustment>> loadAdjustments() => service.fetchAdjustments();

  /// Every goods receipt the server has recorded, newest first.
  Future<List<GoodsReceiptRecord>> loadGoodsReceipts() =>
      service.fetchGoodsReceipts();

  /// Resolves one alert on the server; the trail (who, when) is the server's.
  Future<SystemAlert> resolveAlert(int alertId) =>
      service.resolveAlert(alertId);

  Future<StockAdjustment> recordAdjustment({
    required int variantId,
    required StockAdjustmentType type,
    required double quantity,
    String remarks = '',
  }) => service.createAdjustment(
    variantId: variantId,
    type: type,
    quantity: quantity,
    remarks: remarks,
  );
}
