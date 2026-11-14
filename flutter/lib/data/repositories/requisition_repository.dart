import 'package:client/data/models/requisition.dart';
import 'package:client/data/services/requisition_service.dart';

/// Pass-through over [RequisitionService], with no policy of its own.
///
/// It exists only to preserve the POS one-data-path invariant
/// (View -> ViewModel -> Repository -> Service -> ApiClient); the same shape as [PosRepository],
/// [CustomerRepository] and [LedgerRepository].
class RequisitionRepository {
  RequisitionRepository({RequisitionService? service})
    : _service = service ?? RequisitionService();

  final RequisitionService _service;

  Future<List<Requisition>> fetchRequisitions({String? status}) =>
      _service.fetchRequisitions(status: status);

  Future<Requisition> fetchRequisition(int id) => _service.fetchRequisition(id);

  Future<int> waitingCount() => _service.waitingCount();

  Future<Requisition> accept(int id, List<RequisitionLineDecision> decisions) =>
      _service.accept(id, decisions);

  Future<Requisition> decline(int id, String reason) =>
      _service.decline(id, reason);

  Future<TokenVerification> verifyToken(String token) =>
      _service.verifyToken(token);

  Future<ReleaseResult> release(String token) => _service.release(token);
}
