import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:flutter/foundation.dart';

/// Suppliers and their purchase orders, read from the API (decision D-02).
///
/// Replaces the hardcoded `_suppliers`/`_purchases` fixtures this class used to
/// hold. Those fixtures were the reason the Stocker Purchasing tabs showed six
/// vendors no server had ever heard of.
///
/// Deliberately NOT present any more: `saveSupplier` and `addPurchase`. Both
/// mutated local lists that no server knew about, behind dialogs whose Save
/// button therefore lied. D-02 scoped this pass to reads only; when writes are
/// specified they will go through [SupplierRepository] and re-load, not through
/// a memory-only mutation.
class SuppliersPurchasesViewmodel extends ChangeNotifier {
  SuppliersPurchasesViewmodel({SupplierRepository? repository})
    : _repository = repository ?? SupplierRepository();

  final SupplierRepository _repository;

  List<Supplier> _suppliers = const [];
  List<PurchaseOrder> _purchases = const [];
  bool _isLoading = false;
  String? _loadError;

  List<Supplier> get suppliers => List.unmodifiable(_suppliers);
  List<PurchaseOrder> get purchases => List.unmodifiable(_purchases);

  /// A load is in flight. The pages show a spinner rather than an empty table:
  /// "no suppliers" and "not loaded yet" are different things, and a purchasing
  /// screen that reads as empty is a screen someone orders against wrongly.
  bool get isLoading => _isLoading;

  /// The last load's failure, or null. Set means the lists are as the last
  /// successful load left them — never cleared by a failed refresh.
  String? get loadError => _loadError;

  int get activeSuppliers => _suppliers.where((item) => item.isActive).length;

  double get openPurchaseValue => _purchases
      .where(
        (item) =>
            item.status == PurchaseStatus.draft ||
            item.status == PurchaseStatus.ordered ||
            item.status == PurchaseStatus.partial,
      )
      .fold(0, (sum, item) => sum + item.total);

  /// Purchases matching a PO/supplier [query] and an optional [status].
  ///
  /// Kept as a viewmodel helper (rather than inline in the page) so the same
  /// filtering rule is testable without a widget tree.
  List<PurchaseOrder> filteredPurchases({
    String query = '',
    PurchaseStatus? status,
  }) {
    final needle = query.toLowerCase();
    return _purchases
        .where(
          (item) =>
              ('PO-${item.id} ${item.supplierName}').toLowerCase().contains(
                needle,
              ) &&
              (status == null || item.status == status),
        )
        .toList();
  }

  /// Suppliers whose company, contact person or email match [query].
  List<Supplier> filteredSuppliers({String query = ''}) {
    final needle = query.toLowerCase();
    return _suppliers
        .where(
          (item) => '${item.companyName} ${item.contactPerson} ${item.email}'
              .toLowerCase()
              .contains(needle),
        )
        .toList();
  }

  /// Loads suppliers, then purchase orders.
  ///
  /// Suppliers first because each PO's `supplierName` is resolved from them:
  /// `PurchaseOrderSerializer` sends the supplier **id** only, and D-02 chose
  /// this join over a backend change. A PO whose supplier is not in the list
  /// (deleted upstream, or a permission-filtered row) keeps an empty name
  /// rather than a guessed one.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final suppliers = await _repository.fetchSuppliers();
      final purchases = await _repository.fetchPurchaseOrders();
      _suppliers = [
        for (final s in suppliers)
          _activeOverrides.containsKey(s.id)
              ? s.copyWith(isActive: _activeOverrides[s.id]!)
              : s,
      ];
      _purchases = _withSupplierNames(purchases, suppliers);
    } on SupplierServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Attaches each PO's supplier name, looked up by id in [suppliers].
  ///
  /// An id with no match keeps `''` rather than a placeholder: D-02 chose the
  /// client-side join over a backend change, so an unmatched id means the
  /// supplier was deleted or filtered — and "No supplier" invented text would
  /// hide that.
  List<PurchaseOrder> _withSupplierNames(
    List<PurchaseOrder> purchases,
    List<Supplier> suppliers,
  ) {
    final names = {
      for (final supplier in suppliers) supplier.id: supplier.companyName,
    };
    return [
      for (final purchase in purchases)
        purchase.withSupplierName(names[purchase.supplierId] ?? ''),
    ];
  }

  /// Session-local active-flag overrides, keyed by supplier id.
  ///
  /// Re-applied after every load so a toggle survives tab switches: without
  /// this, each page open re-runs load() and silently reverts the switch.
  /// Memory-only — PATCH wiring is Fog of War.
  final Map<int, bool> _activeOverrides = {};

  /// Flips a supplier's active flag **locally**.
  void toggleSupplier(Supplier supplier) {
    final index = _suppliers.indexWhere((item) => item.id == supplier.id);
    if (index < 0) return;
    final next = !supplier.isActive;
    _activeOverrides[supplier.id] = next;
    _suppliers = [
      ..._suppliers.sublist(0, index),
      _suppliers[index].copyWith(isActive: next),
      ..._suppliers.sublist(index + 1),
    ];
    notifyListeners();
  }
}
