import 'package:client/data/services/pos_service.dart';

/// The repository layer between the POS viewmodels and the checkout API.
///
/// Keeps the map's one-data-path invariant — `View → ViewModel → Repository →
/// Service → ApiClient` — so no viewmodel talks to Dio and swapping the transport
/// later touches this file rather than every caller.
///
/// A deliberate pass-through, like [ProductsRepository]: there is no client-side
/// policy to add here, because the server owns the sale entirely (one
/// `transaction.atomic()` doing FIFO deduction, payment allocation, receipt
/// generation and any collectibles posting). Adding logic here would be inventing a
/// second authority over money.
class PosRepository {
  PosRepository(this.service);

  final PosService service;

  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
  }) => service.checkout(
    customerId: customerId,
    items: items,
    payments: payments,
    source: source,
  );
}
