import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:flutter/foundation.dart';

/// Suppliers and their purchase orders, read from and written to the API
/// (decision D-02, Phase 4 Task 4).
///
/// Two rounds of removal are visible here. The first deleted the hardcoded
/// `_suppliers`/`_purchases` fixtures. The second (Phase 4) deleted
/// `_activeOverrides` — a session-local map that made the activate/deactivate
/// chip change without any server knowing, so a reload silently reverted it. A
/// supplier's active flag is now `PATCH {"is_active": …}` followed by a reload,
/// and a purchase order is created with its lines, placed and cancelled through
/// the server's own transitions.
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

  /// The supplier behind an id, for the PO dialogs. Null when the list has not
  /// loaded one — a picker must not crash over a missing name.
  Supplier? supplierById(int id) {
    for (final supplier in _suppliers) {
      if (supplier.id == id) return supplier;
    }
    return null;
  }

  /// Loads suppliers, then purchase orders.
  ///
  /// Suppliers first because each PO's `supplierName` is resolved from them:
  /// `PurchaseOrderSerializer` sends the supplier **id** only, and D-02 chose
  /// this join over a backend change. A PO whose supplier is not in the list
  /// (filtered by permission, or on another page) keeps an empty name rather
  /// than a guessed one.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final suppliers = await _repository.fetchSuppliers();
      final purchases = await _repository.fetchPurchaseOrders();
      _suppliers = suppliers;
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
  /// supplier was filtered out — and "No supplier" invented text would hide
  /// that.
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

  // ---------------------------------------------------------------------
  // Supplier writes
  // ---------------------------------------------------------------------

  /// Creates a supplier ([existing] null) or PATCHes one, then reloads.
  ///
  /// Returns `null` on success or the message to show. The reload is what makes
  /// the change survive closing the screen — the reason `_activeOverrides`
  /// existed was that nothing had been written down.
  Future<String?> saveSupplier(Supplier supplier) async {
    final body = {
      'company_name': supplier.companyName,
      'contact_person': supplier.contactPerson,
      'phone': supplier.phone,
      'email': supplier.email,
      'address': supplier.address,
    };
    try {
      if (supplier.id == 0) {
        await _repository.createSupplier(body);
      } else {
        await _repository.patchSupplier(supplier.id, body);
      }
    } on SupplierServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// Activates (`true`) or deactivates (`false`) a supplier on the server.
  ///
  /// `is_active` is the retirement path: `DELETE` answers 405 because purchase
  /// orders PROTECT-reference the row.
  Future<String?> setSupplierActive(Supplier supplier, bool isActive) async {
    if (supplier.id == 0) {
      return 'Save the supplier before changing its status.';
    }
    try {
      await _repository.patchSupplier(supplier.id, {'is_active': isActive});
    } on SupplierServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// Flips a supplier's active flag through the server.
  Future<String?> toggleSupplier(Supplier supplier) =>
      setSupplierActive(supplier, !supplier.isActive);

  // ---------------------------------------------------------------------
  // Purchase-order writes
  // ---------------------------------------------------------------------

  /// Creates a purchase order with its lines, optionally placing it at once.
  ///
  /// "Place order" is a SECOND call (`place/`), not a flag on the create: the
  /// server treats placing as an event with its own audit row and its own lock,
  /// so a create that failed to place is a DRAFT the screen shows as one.
  Future<String?> createPurchaseOrder(
    PurchaseOrderDraft draft, {
    bool place = false,
  }) async {
    if (draft.lines.isEmpty) return 'Add at least one line to the order.';
    final int id;
    try {
      id = await _repository.createPurchaseOrder(draft);
    } on SupplierServiceException catch (error) {
      return error.message;
    }
    String? placeError;
    if (place) {
      try {
        await _repository.placePurchaseOrder(id);
      } on SupplierServiceException catch (error) {
        // The draft exists — say so, because retrying the create would duplicate
        // the order. The list reload below shows it as DRAFT.
        placeError =
            'Purchase order #$id was saved as a draft but could not be '
            'placed: ${error.message}';
      }
    }
    await load();
    return placeError;
  }

  /// DRAFT → ORDERED.
  Future<String?> placeOrder(PurchaseOrder order) async {
    try {
      await _repository.placePurchaseOrder(order.id);
    } on SupplierServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }

  /// DRAFT or ORDERED-with-nothing-received → CANCELLED.
  Future<String?> cancelOrder(PurchaseOrder order) async {
    try {
      await _repository.cancelPurchaseOrder(order.id);
    } on SupplierServiceException catch (error) {
      return error.message;
    }
    await load();
    return null;
  }
}
