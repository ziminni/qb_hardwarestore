import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';

class PosTransactionViewmodel extends ChangeNotifier {
  PosTransactionViewmodel(
    this._inventory,
    this._tracking, {
    PosRepository? pos,
  }) : _pos = pos ?? PosRepository(PosService()) {
    _inventory.addListener(_inventoryChanged);
    _tracking.addListener(_inventoryChanged);
  }

  final InventoryViewmodel _inventory;
  final ProductTrackingViewmodel _tracking;
  final PosRepository _pos;
  final List<PosCartLine> _lines = [];
  final List<PosReceipt> _receipts = [];
  String _query = '';
  bool _isSubmitting = false;
  String? _submitError;
  int? _walkInCustomerId;

  List<PosCartLine> get lines => List.unmodifiable(_lines);
  List<PosReceipt> get receipts => List.unmodifiable(_receipts);
  double get subtotal => _lines.fold(0, (sum, line) => sum + line.total);
  double get total => subtotal;
  int get itemCount => _lines.length;

  /// True while a sale is in flight. The submit action must be disabled, because the
  /// sale is one atomic server operation and a double submit would be two sales.
  bool get isSubmitting => _isSubmitting;

  /// The last submit failure, safe to show a cashier. Null after a success.
  String? get submitError => _submitError;

  List<PosCatalogItem> get _catalog {
    final items = <PosCatalogItem>[];
    for (final record in _inventory.stockRecords) {
      if (!record.product.isActive ||
          !record.variant.isActive ||
          _inventory.stockOnHandFor(record.variant.id) <= 0) {
        continue;
      }
      final tracking = _tracking.configurationFor(record.product.baseName);
      final usesTracking =
          tracking != null &&
          tracking.baseUnit.toLowerCase() ==
              record.variant.baseUomCode.toLowerCase();
      // Decision 06 section 2: the rows are built from the variant's REAL selling
      // units, because that is both what the catalogue can actually sell and the
      // only source of a valid `variantUomId` for the payload. Tracking supplies the
      // conversion factor and package price for whichever units it recognises; it can
      // no longer add a unit the catalogue does not sell, because such a row has no
      // id to submit.
      //
      // Building from tracking's labels instead produced DUPLICATE ids: variant 19 is
      // tracked with two sale units ('kg', 'g') but carries a single selling unit, so
      // both rows resolved to id 19. That silently merged two cart lines in `addLine`
      // (which de-duplicates on `variantUomId`) and made `complete()` price and deduct
      // a 'g' line as 'kg' (it takes the FIRST row matching the id).
      final sellableUnits = <String, VariantUom>{};
      for (final uom in record.variant.sellingUoms) {
        final code = uom.uomCode.trim();
        if (code.isEmpty) continue;
        sellableUnits.putIfAbsent(code.toLowerCase(), () => uom);
      }
      for (final uom in sellableUnits.values) {
        final unit = uom.uomCode;
        final factor = usesTracking ? _conversionFactor(tracking, unit) : 1.0;
        final configuredPackagePrice =
            usesTracking &&
                unit.toLowerCase() == tracking.packageType.toLowerCase()
            ? tracking.packageSellingPrice
            : 0.0;
        items.add(
          PosCatalogItem(
            variantUomId: uom.id,
            variantId: record.variant.id,
            productName: record.product.baseName,
            variantName: record.variant.variantName,
            unit: unit,
            barcode: record.variant.barcode,
            conversionFactor: factor,
            unitPrice: configuredPackagePrice > 0
                ? configuredPackagePrice
                : (_inventory.priceFor(record.variant.id) ?? 0) * factor,
            availableBaseStock: _inventory.stockOnHandFor(record.variant.id),
          ),
        );
      }
    }
    return items;
  }

  List<PosCatalogItem> get filteredProducts {
    final matched = _query.isEmpty
        ? _catalog
        : _catalog
              .where(
                (item) =>
                    item.productName.toLowerCase().contains(_query) ||
                    item.variantName.toLowerCase().contains(_query) ||
                    item.barcode.toLowerCase().contains(_query) ||
                    item.unit.toLowerCase().contains(_query),
              )
              .toList(growable: false);
    final variants = <int, PosCatalogItem>{};
    for (final item in matched) {
      variants.putIfAbsent(item.variantId, () => item);
    }
    return variants.values.toList(growable: false);
  }

  List<PosCatalogItem> saleOptionsFor(PosCatalogItem product) => _catalog
      .where((item) => item.variantId == product.variantId)
      .toList(growable: false);

  PosCatalogItem? findByBarcode(String value) {
    final barcode = value.trim().toLowerCase();
    if (barcode.isEmpty) return null;
    for (final item in _catalog) {
      if (item.barcode.trim().toLowerCase() == barcode) return item;
    }
    return null;
  }

  void setQuery(String value) {
    _query = value.trim().toLowerCase();
    notifyListeners();
  }

  void _inventoryChanged() => notifyListeners();

  @override
  void dispose() {
    _inventory.removeListener(_inventoryChanged);
    _tracking.removeListener(_inventoryChanged);
    super.dispose();
  }

  String? addLine(PosCatalogItem item, double quantity) {
    if (quantity <= 0) return 'Enter a quantity greater than zero.';
    final index = _lines.indexWhere(
      (line) => line.variantUomId == item.variantUomId,
    );
    final cartQuantity = index < 0 ? 0.0 : _lines[index].quantity;
    final reservedBaseStock = _lines
        .where((line) {
          final option = _catalog.firstWhere(
            (catalogItem) => catalogItem.variantUomId == line.variantUomId,
          );
          return option.variantId == item.variantId;
        })
        .fold<double>(0, (sum, line) {
          final option = _catalog.firstWhere(
            (catalogItem) => catalogItem.variantUomId == line.variantUomId,
          );
          return sum + line.quantity * option.conversionFactor;
        });
    final requestedBaseStock = quantity * item.conversionFactor;
    if (reservedBaseStock + requestedBaseStock > item.availableBaseStock) {
      return 'Only ${_quantity(item.availableSaleQuantity)} ${item.unit} available.';
    }
    if (index < 0) {
      _lines.add(
        PosCartLine(
          variantUomId: item.variantUomId,
          productName: item.productName,
          variantName: item.variantName,
          quantity: quantity,
          unit: item.unit,
          unitPrice: item.unitPrice,
          availableQuantity: item.availableSaleQuantity,
        ),
      );
    } else {
      _lines[index] = _lines[index].copyWith(quantity: cartQuantity + quantity);
    }
    notifyListeners();
    return null;
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  String? validate() {
    if (_lines.isEmpty) return 'Add at least one product to the transaction.';
    final requestedByVariant = <int, double>{};
    for (final line in _lines) {
      final item = _catalog.firstWhere(
        (catalogItem) => catalogItem.variantUomId == line.variantUomId,
      );
      requestedByVariant[item.variantId] =
          (requestedByVariant[item.variantId] ?? 0) +
          line.quantity * item.conversionFactor;
      if (requestedByVariant[item.variantId]! > item.availableBaseStock) {
        return '${line.productName}: the combined units exceed available stock.';
      }
    }
    return null;
  }

  /// Completes the sale ON THE SERVER, then clears the cart.
  ///
  /// Decision 06 sections 3 and 5. Three rules are load-bearing here:
  ///
  /// * The cart is cleared **only** after a successful sale. `process_sale` runs in one
  ///   `transaction.atomic()`, so a failure rolls back wholesale - the server state is
  ///   unchanged, and the cashier's basket must survive so it can be corrected and
  ///   retried. Clearing optimistically would lose a real order.
  /// * An empty cart is never submitted. The server has no guard on an empty `items`
  ///   list, so an empty sale would **succeed** and mint a zero-value receipt.
  /// * Insufficient stock and a server failure both keep the cart, but they are
  ///   different messages. The distinction comes from the server's code, never from
  ///   the status alone.
  ///
  /// Returns whether the sale was confirmed, so a caller cannot announce success
  /// unconditionally.
  Future<bool> submit({
    int? customerId,
    required String paymentMethod,
    required double amountPaid,
  }) async {
    if (_lines.isEmpty) return false;

    _isSubmitting = true;
    _submitError = null;
    notifyListeners();

    try {
      // A walk-in sale cannot omit the customer (decision 06 section 2), so resolve
      // the seed's Walk-in Customer once and reuse it.
      final buyer =
          customerId ?? (_walkInCustomerId ??= await _pos.walkInCustomerId());
      // Snapshot the lines being sold: the receipt must describe THIS sale, not
      // whatever the cart holds when the response lands.
      final sold = List<PosCartLine>.of(_lines);
      final result = await _pos.checkout(
        customerId: buyer,
        items: [
          for (final line in sold)
            PosCheckoutItem(
              variantUomId: line.variantUomId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
        ],
        payments: [
          PosCheckoutPayment(method: paymentMethod, amountTendered: amountPaid),
        ],
      );

      // The receipt's numbers are the SERVER's, not the cart's arithmetic: decision
      // 06 section 1 says the response is the finished transaction.
      _receipts.insert(
        0,
        PosReceipt(
          reference: result.transactionNo,
          officialReceiptNumber: result.orNumber,
          createdAt: result.transDate,
          lines: List.unmodifiable(sold),
          paymentMethod: paymentMethod,
          amountPaid: amountPaid,
          total: result.grandTotal,
        ),
      );
      _lines.clear();
      return true;
    } on PosServiceException catch (error) {
      _submitError = error.message;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  double _conversionFactor(ProductTrackingConfiguration tracking, String unit) {
    if (unit.toLowerCase() == tracking.packageType.toLowerCase()) {
      return tracking.stockForm == ProductStockForm.standardLengths
          ? tracking.standardLength
          : tracking.packageSize;
    }
    const factors = {
      'g': .001,
      'kg': 1.0,
      'mm': .001,
      'cm': .01,
      'meter': 1.0,
      'm': 1.0,
      'inch': .0254,
      'foot': .3048,
      'ml': .001,
      'l': 1.0,
      'piece': 1.0,
    };
    final from = factors[unit.toLowerCase()] ?? 1;
    final base = factors[tracking.baseUnit.toLowerCase()] ?? 1;
    return from / base;
  }
}
