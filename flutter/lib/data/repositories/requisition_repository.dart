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

  Future<List<Requisition>> fetchRequisitions() => _service.fetchRequisitions();

  Future<TokenVerification> verifyToken(String token) => _service.verifyToken(token);

  Future<ReleaseResult> release(String token) => _service.release(token);
}
