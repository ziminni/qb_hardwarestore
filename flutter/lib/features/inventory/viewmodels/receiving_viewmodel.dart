import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the receiving screen: purchase orders in, goods receipts recorded,
/// receipts processed into FIFO batches, and the deliveries already received.
///
/// Screen-scoped like every other viewmodel (decision 11): it lives as long as
/// the receiving page and no longer. Amounts entered per PO line travel to the
/// server as `items: [{po_item, qty}]`, which is what `process/` turns into
/// batches — the screen never invents stock itself.
///
/// Phase 4 added two things the server allows and the screen did not show:
///
///  * the list is filtered to **ORDERED / PARTIAL** orders, the only ones that
///    can be received (`PO_NOT_ORDERED`, `PO_NOT_RECEIVABLE` elsewhere), and
///  * **received deliveries** from `GET /goods-receipts/`, so a delivery can be
///    looked up after the fact instead of only at the moment it was booked.
class ReceivingViewmodel extends ChangeNotifier {
  ReceivingViewmodel({InventoryService? service})
    : _service = service ?? InventoryService();

  final InventoryService _service;

  List<PurchaseOrderRecord> _orders = const [];
  bool _isLoading = false;
  String? _loadError;

  List<GoodsReceiptRecord> _receipts = const [];
  bool _isLoadingReceipts = false;
  String? _receiptsError;

  PurchaseOrderRecord? _selected;
  final Map<int, double> _quantities = {};
  String? _actionError;
  bool _isActing = false;
  int? _lastReceiptId;
  List<InventoryBatch> _lastBatches = const [];

  /// Only the orders that can actually be received.
  List<PurchaseOrderRecord> get orders => List.unmodifiable(_orders);
  bool get isLoading => _isLoading;
  bool get hasOrders => _orders.isNotEmpty;
  String? get loadError => _loadError;

  /// Deliveries already booked into stock, newest first.
  List<GoodsReceiptRecord> get receipts => List.unmodifiable(_receipts);
  bool get isLoadingReceipts => _isLoadingReceipts;
  String? get receiptsError => _receiptsError;

  PurchaseOrderRecord? get selected => _selected;

  /// Entered received quantity for a PO line; unset means nothing entered yet.
  double? qtyFor(int poItemId) => _quantities[poItemId];

  String? get actionError => _actionError;
  bool get isActing => _isActing;
  int? get lastReceiptId => _lastReceiptId;
  List<InventoryBatch> get lastBatches => List.unmodifiable(_lastBatches);

  /// True once a receipt has been processed: the Process button must go away,
  /// because process/ has no receipt-level guard against a second run client-side.
  bool get isProcessed => _lastReceiptId != null && _lastBatches.isNotEmpty;

  /// Loads the orders that can be received. A failed load keeps the rows already
  /// shown: emptying the table would read as "nothing on order".
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final orders = await _service.fetchPurchaseOrders();
      _orders = orders
          .where((order) => order.isReceivable)
          .toList(growable: false);
      _loadError = null;
    } on InventoryServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Loads the goods-receipt history.
  Future<void> loadReceipts() async {
    _isLoadingReceipts = true;
    _receiptsError = null;
    notifyListeners();
    try {
      _receipts = await _service.fetchGoodsReceipts();
      _receiptsError = null;
    } on InventoryServiceException catch (error) {
      _receiptsError = error.message;
    } finally {
      _isLoadingReceipts = false;
      notifyListeners();
    }
  }

  /// Selects the order being received; clears any quantities from the last one.
  void select(PurchaseOrderRecord order) {
    _selected = order;
    _quantities.clear();
    _actionError = null;
    _lastReceiptId = null;
    _lastBatches = const [];
    notifyListeners();
  }

  void setQty(int poItemId, double qty) {
    _quantities[poItemId] = qty;
    notifyListeners();
  }

  /// Withdraws a line: clearing a field must not post the value it used to hold.
  void clearQty(int poItemId) {
    _quantities.remove(poItemId);
    notifyListeners();
  }

  /// Records the receipt with one line per order item that has a quantity.
  Future<bool> recordReceipt({String deliveryReceiptNo = ''}) async {
    final order = _selected;
    if (order == null) {
      _actionError = 'Select a purchase order first.';
      notifyListeners();
      return false;
    }
    final lines = [
      for (final item in order.items)
        if (_quantities.containsKey(item.id))
          ReceiptLine(poItemId: item.id, qty: _quantities[item.id]!),
    ];
    if (lines.isEmpty) {
      _actionError = 'Enter a received quantity for at least one line.';
      notifyListeners();
      return false;
    }
    _isActing = true;
    _actionError = null;
    notifyListeners();
    try {
      final receipt = await _service.createReceipt(
        poId: order.id,
        items: lines,
        deliveryReceiptNo: deliveryReceiptNo,
      );
      _lastReceiptId = receipt.id;
      // The delivery is now part of the history, and the order's received
      // quantity moved: reload both so the screen agrees with the server.
      await load();
      await loadReceipts();
      return true;
    } on InventoryServiceException catch (error) {
      _actionError = error.message;
      return false;
    } finally {
      _isActing = false;
      notifyListeners();
    }
  }

  /// Processes the recorded receipt into FIFO batches.
  Future<bool> processReceipt() async {
    final receiptId = _lastReceiptId;
    if (receiptId == null) {
      _actionError = 'Record a receipt before processing it.';
      notifyListeners();
      return false;
    }
    _isActing = true;
    _actionError = null;
    notifyListeners();
    try {
      _lastBatches = await _service.processReceipt(receiptId);
      await loadReceipts();
      return _lastBatches.isNotEmpty;
    } on InventoryServiceException catch (error) {
      _actionError = error.message;
      return false;
    } finally {
      _isActing = false;
      notifyListeners();
    }
  }
}
