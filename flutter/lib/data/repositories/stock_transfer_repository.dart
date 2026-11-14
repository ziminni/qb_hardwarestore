import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/services/stock_transfer_service.dart';

/// Policy-free pass-through over [StockTransferService], keeping the one data
/// path `View → ViewModel → Repository → Service → ApiClient` (Phase 9 F3).
///
/// No ordering, filtering or conversion lives here: "active shelves only" and
/// "newest slip first" are decisions a screen test can read, and hiding them in
/// a pass-through would put them where nobody looks.
class StockTransferRepository {
  StockTransferRepository({StockTransferService? service})
    : _service = service ?? StockTransferService();

  final StockTransferService _service;

  Future<List<StockTransfer>> fetchAll() => _service.fetchAll();

  Future<StockTransfer> create(StockTransferRequest request) =>
      _service.create(request);
}
