import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/returns_service.dart';

/// The repository layer between the returns viewmodel and the returns API.
///
/// Keeps the map's one-data-path invariant — `View -> ViewModel -> Repository ->
/// Service -> ApiClient` — so no viewmodel talks to Dio, and a transport change
/// touches this file and not five screens.
///
/// A deliberate pass-through, like [PosRepository]: there is no client-side
/// refund policy to add here. `process_return` prices the lines, restocks the
/// batches, settles the utang first and decides what the drawer pays out, all
/// inside one transaction. A second authority over that arithmetic is exactly
/// how the shop ends up refunding money nobody agreed to.
class ReturnsRepository {
  ReturnsRepository({ReturnsService? service})
    : _service = service ?? ReturnsService();

  final ReturnsService _service;

  Future<TransactionRecord?> findSale(String query) => _service.findSale(query);

  Future<ReturnableSale> fetchReturnable(int transactionId) =>
      _service.fetchReturnable(transactionId);

  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) => _service.postReturn(
    customerId: customerId,
    originalTransactionId: originalTransactionId,
    reason: reason,
    paymentMethod: paymentMethod,
    lines: lines,
  );
}
