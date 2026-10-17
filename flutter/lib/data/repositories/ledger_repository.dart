import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/services/ledger_service.dart';

/// Pass-through over [LedgerService], with no policy of its own.
///
/// It exists only to preserve the POS one-data-path invariant
/// (View -> ViewModel -> Repository -> Service -> ApiClient); the same shape as
/// [PosRepository], [ProductsRepository] and [CustomerRepository].
class LedgerRepository {
  LedgerRepository({LedgerService? service}) : _service = service ?? LedgerService();

  final LedgerService _service;

  Future<List<LedgerEntry>> fetchLedgers() => _service.fetchLedgers();
}
