import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/services/payables_service.dart';

/// Policy-free pass-through over [PayablesService], preserving the one data
/// path `View → ViewModel → Repository → Service → ApiClient`.
///
/// No sorting, filtering or refreshing lives here: an overdue-first order is a
/// decision the viewmodel owns and a test can read, and hiding it in a
/// pass-through would put it where nobody looks.
class PayablesRepository {
  PayablesRepository({PayablesService? service})
    : _service = service ?? PayablesService();

  final PayablesService _service;

  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) => _service.fetchBills(
    supplierId: supplierId,
    status: status,
    overdueOnly: overdueOnly,
  );

  Future<SupplierBill> fetchBill(int id) => _service.fetchBill(id);

  Future<List<SupplierPayable>> fetchSummary() => _service.fetchSummary();

  Future<void> createPayment(Map<String, dynamic> body) =>
      _service.createPayment(body);
}
