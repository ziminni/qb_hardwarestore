import 'package:client/data/models/bodega.dart';
import 'package:client/data/services/bodega_service.dart';

/// Policy-free pass-through over [BodegaService], keeping the one data path
/// `View → ViewModel → Repository → Service → ApiClient`.
class BodegaRepository {
  BodegaRepository({BodegaService? service})
    : _service = service ?? BodegaService();

  final BodegaService _service;

  Future<List<BodegaStockRow>> fetchStock() => _service.fetchStock();

  Future<List<BodegaClaim>> fetchClaims({
    bool openOnly = true,
    String query = '',
  }) => _service.fetchClaims(openOnly: openOnly, query: query);

  Future<BodegaClaim> lookupClaim(String receipt) =>
      _service.lookupClaim(receipt);

  Future<BodegaRelease> release(BodegaReleaseRequest request) =>
      _service.release(request);

  Future<List<BodegaRelease>> fetchReleases() => _service.fetchReleases();

  Future<List<BodegaDelivery>> fetchDeliveries({String status = ''}) =>
      _service.fetchDeliveries(status: status);

  Future<BodegaDelivery> confirmDelivery(
    int id,
    BodegaDeliveryConfirmation confirmation,
  ) => _service.confirmDelivery(id, confirmation);

  Future<BodegaDelivery> uploadLinePhoto(
    int deliveryId,
    int lineId,
    List<int> bytes, {
    String filename = 'item.jpg',
  }) => _service.uploadLinePhoto(deliveryId, lineId, bytes, filename: filename);
}
