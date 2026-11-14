import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/services/supplier_service.dart';

/// Policy-free pass-through over [SupplierService], preserving the one data
/// path `View → ViewModel → Repository → Service → ApiClient`.
///
/// The supplier-name join lives in the viewmodel, not here: it is a read of two
/// lists this repository does not hold, and putting it here would make the
/// repository stateful or force it to fetch suppliers on every PO read.
class SupplierRepository {
  SupplierRepository({SupplierService? service})
    : _service = service ?? SupplierService();

  final SupplierService _service;

  Future<List<Supplier>> fetchSuppliers() => _service.fetchSuppliers();

  Future<List<PurchaseOrder>> fetchPurchaseOrders() =>
      _service.fetchPurchaseOrders();

  /// Creates a supplier and returns the server id.
  Future<int> createSupplier(Map<String, dynamic> body) =>
      _service.createSupplier(body);

  /// Edits a supplier, including `is_active` (the archive path — no DELETE).
  Future<void> patchSupplier(int id, Map<String, dynamic> body) =>
      _service.patchSupplier(id, body);

  /// Creates a purchase order with its lines nested in the same POST.
  Future<int> createPurchaseOrder(PurchaseOrderDraft draft) =>
      _service.createPurchaseOrder(draft.toJson());

  Future<void> placePurchaseOrder(int id) => _service.placePurchaseOrder(id);

  Future<void> cancelPurchaseOrder(int id) => _service.cancelPurchaseOrder(id);
}
