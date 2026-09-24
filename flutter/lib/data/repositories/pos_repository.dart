import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/services/pos_service.dart';

class PosRepository {
  PosRepository(this.service);
  final PosService service;
  Future<List<PosCatalogItem>> loadCatalog() => service.fetchCatalog();
  Future<List<PosCustomer>> loadCustomers() => service.fetchCustomers();
  Future<PosCheckoutResult> checkout({required int customerId, required List<PosCartLine> lines, required String paymentMethod, required double amountPaid, required String referenceNumber}) => service.checkout(customerId: customerId, lines: lines, paymentMethod: paymentMethod, amountPaid: amountPaid, referenceNumber: referenceNumber);
}
